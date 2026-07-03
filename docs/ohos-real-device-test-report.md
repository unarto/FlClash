# FlClash HarmonyOS real-device test report (Mate 80 Pro)

Automated functional verification of FlClash on a connected HarmonyOS NEXT real
device. The whole suite is one command and is meant to be re-run after any change
as a regression gate.

- Device: Huawei Mate 80 Pro, HDC `5JV0225B14001088`
- Build: `dist/FlClash-0.8.93-ohos-arm64.hap` (branch `feat/ohos-support`)
- Date: 2026-06-28

## How to run

```bash
# screen stays awake automatically; pass --install to (re)flash first
bash scripts/ohos/verify_all.sh                          # test current install
bash scripts/ohos/verify_all.sh --install dist/FlClash-0.8.93-ohos-arm64.hap
```

Exit code is `0` only if every **hard** check passes. Known-limitation probes are
reported but never fail the suite, so a green run means "no regression in the
features that work today". When a limitation is fixed its probe flips to
`now WORKS`, which is the signal to promote it to a hard check.

The suite drives the app through `scripts/ohos/ui.sh` (uitest `dumpLayout`
find-text / tap-text assertions) and probes proxy connectivity through the
loopback mixed listener (`hdc fport 7890`) and the VPN tun byte counters.

## Result summary

**22 / 22 PASS** (exit code 0)

### Checks

| Area | Check | Result |
|------|-------|--------|
| Install/core | install HAP | ✅ |
| Core | core healthy (7890 + 1053 listening) | ✅ |
| VPN | tun up | ✅ |
| Proxy | youtube `/generate_204` via 7890 → 204 | ✅ |
| Proxy | foreign egress node (loc≠CN) | ✅ |
| Browser | Chrome renders YouTube through VPN | ✅ |
| Browser | Huawei native browser renders YouTube through VPN | ✅ |
| Dashboard | widgets render (网络速度/流量统计/网络检测/出站模式) | ✅ |
| Dashboard | all three outbound modes selectable in UI | ✅ |
| Proxy tab | proxy groups / nodes listed | ✅ |
| Config | profile / subscription listed | ✅ |
| Tools | 连接 page opens | ✅ |
| Tools | 请求 page opens | ✅ |
| Tools | 日志 page opens | ✅ |
| Settings | 主题 opens | ✅ |
| Settings | 语言 opens | ✅ |
| Settings | 基本配置 opens | ✅ |
| Settings | 进阶配置 opens | ✅ |
| Settings | 应用程序 opens | ✅ |
| Tools | 备份与恢复 opens | ✅ |
| Live | outbound-mode switch reaches the running core (直连 egress ≠ node) | ✅ |
| Live | connections page lists real-time traffic via the node | ✅ |

## Live UI ↔ running-core link (fixed in this pass)

Initially the last two "Live" checks failed: the main app UI had no live channel
to the core that serves traffic, so the dashboard stuck at "连接中…", 流量统计 read
0, the 连接 page stayed "暂无连接", and live outbound-mode/node switches didn't take
effect.

Root cause: the Go core is the socket *client* (`startServer` → `dial`) and Dart's
`CoreService` is the *server* (`ServerSocket.bind(unixSocketPath)`). When the VPN
is on, the proxy core runs in the `com.follow.clash:vpn` process but nothing made
it dial the main app's socket, and the OHOS-VPN path used
`_handleStart(syncCoreState: false)` (no subscribe/poll).

Fix: thread the main app's `unixSocketPath` through `startVpn`
(`lib/plugins/app.dart`, `lib/manager/vpn_manager.dart`, `lib/state.dart`) →
`AppPlugin.ets` → `FlClashVpnAbility.ets`, which after `startTun` calls
`nativeBridge.startEmbeddedCore(coreSocketPath, filesDir)`. That dlopens the same
`libclash.so` and runs `startServerProcessDetached` → `dial(socketPath)`, so the
in-process VPN core connects back to the main app's listening socket — the same
core that runs the tun now answers UI queries and pushes events. The two OHOS-VPN
`_handleStart(syncCoreState: false)` calls in `lib/providers/action.dart` are
flipped to `_handleStart()` so the UI subscribes/polls once connected.

Verified device-side: the socket shows LISTENING + CONNECTED; 网络速度 updates,
流量统计 is non-zero, the 连接 page lists live YouTube connections via the HK node,
and switching to 直连 moves the 7890 egress off the node.

## Coverage notes

- UI assertions use accessibility text from `uitest dumpLayout`; web content
  (YouTube) is asserted via the in-page "YouTube" node plus tun RX byte growth.
- WebDAV backup is checked only to the point of the page opening (no live server).
- Delay-test latency values are not asserted numerically (proxy-tab node presence
  is asserted instead).
