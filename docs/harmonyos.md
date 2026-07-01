# HarmonyOS NEXT packaging notes

This repository now contains an `ohos/` host project and the minimum local plugin skeletons required to produce a signed HarmonyOS `.hap` artifact for migration work.

## Current status

- Branch: `feat/ohos-support`
- Added OpenHarmony host project under `ohos/`
- Added local plugin `ohos/` platform skeletons for:
  - `plugins/proxy`
  - `plugins/rust_api`
  - `plugins/wifi_ssid`
  - `plugins/window_ext`
  - `plugins/setup`
- Release HAP compilation and signing work with the OpenHarmony SDK's built-in demo signing materials when `OHOS_SDK_HOME` points to the OpenHarmony SDK root
- The Flutter runtime is partially bootstrapped on OHOS and now passes Dart startup plus Drift database initialization with a bundled `libsqlite3.so`
- `dart setup.dart ohos` now auto-prepares an isolated patched Go toolchain under `.ohos_toolchain/go-nonglibc`
- The patched toolchain builds `libclash.so` with `R_AARCH64_TLSDESC` instead of the old `initial-exec` TLS model
- Emulator validation now confirms the package no longer exits immediately after launch, and the OHOS core can execute `initClash`, `setupConfig`, `getProxies`, and `getExternalProviders`
- Emulator validation also confirms the previous `flutter/navigation` `DartMessenger` runtime exception is no longer emitted after launch

## Mate 80 Pro handoff status

Latest real-device target:

- HDC target: `5JV0225B14001088`
- Device: Huawei Mate 80 Pro
- System: `OpenHarmony-6.1.1.120`
- HDC: `/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc`
- OHOS Flutter: `/Users/liushangliang/.local/ohos-flutter-3.35.7/bin/flutter`
- Current HAP: `ohos/entry/build/default/outputs/default/entry-default-signed.hap`

Build command used for the current real-device debug package:

```bash
PATH=/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin:/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin:$PATH \
  /Users/liushangliang/.local/ohos-flutter-3.35.7/bin/flutter build hap --debug --target-platform ohos-arm64 --no-pub
```

Keep the phone awake during real-device testing:

```bash
/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc -t 5JV0225B14001088 shell "power-shell wakeup"
/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc -t 5JV0225B14001088 shell "power-shell timeout -o 1800000"
```

Restore the normal screen timeout after testing:

```bash
/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc -t 5JV0225B14001088 shell "power-shell timeout -r"
```

Do not restart emulator testing for this path. DevEco Studio has previously used around 60% CPU while the phone was
connected, so monitor local load before long builds:

```bash
ps -axo pid,pcpu,pmem,comm | egrep 'qemu|emulator|DevEco|hdc|node|java|hvigor|flutter|dart' | egrep -v 'egrep' | sort -k2 -nr | head -20
```

Real-device fixes already verified on Mate 80 Pro:

- `dab118a fix(ohos): run core invocations off the main thread`
  - Moves OHOS core calls off the main thread through NAPI async work.
- `2ddf912 fix(ohos): restore delay test pending indicator`
  - Restores the per-proxy-card pending indicator during delay tests.
  - The bottom-right `延迟测速` floating button disappearing during an active test is the expected previous behavior.
- A 37-node delay test completed without `THREAD_BLOCK`, `BlockMonitor`, `CPP_CRASH`, `SIGSEGV`, or `SIGABRT`.

Current unresolved VPN finding:

- The VPN runtime itself is now proven to work. On Mate 80 Pro, `vpn-tun` comes up at `172.19.0.1/24`,
  `StartTun result ok=1` is logged, and Huawei Browser traffic can drive `vpn-tun` RX/TX counters upward.
- The remaining gap is specific to non-browser Web container apps such as `com.easy.hmos.abroad`.
  In the current repro chain, that app still reports `vpnEnabled:1` together with
  `dnsServerReturnNothing`, `dnsFromNetsys:0`, and `sock:-1`.
- OpenHarmony source inspection now shows two important platform constraints:
  - Public app APIs only expose process-local `setAppNet()`.
  - The UID-level VNIC / socket-rebind path (`EnableVnicNetwork`, `CloseSocketsUid`) is guarded by
    `ohos.permission.CONNECTIVITY_INTERNAL`, which is a system-only permission.
- OpenHarmony `web_webview` source adds another strong framework-side clue:
  - `VpnListener::OnAvailable()` only signals availability and does not carry a VPN `netId`.
  - `GetDnsServersForVpn()` exists in the adapter layer, but in the visible open-source tree it only
    appears in declarations, bridge wrappers, and unit tests. No direct production call site was found.
  - Live device logs still show the target app entering the normal default-net callback path first:
    `NetConnCallback enter, net available, net id = 113`, then
    `network_for_dns_ -1`, `dns server is empty`, and
    `BindDnsToNetwork, network_for_dns -1`.
- A fresh Huawei Browser control run on June 26, 2026 tightened the contrast further:
  - Launching `com.huawei.hmos.browser/MainAbility` and opening `https://www.youtube.com` increased
    `vpn-tun` counters from `RX/TX 1004/1580` packets to `2149/2842`, confirming real traffic crossed
    the FlClash VPN.
  - The same time window showed Huawei Browser-specific ArkWeb plumbing absent from the failing app:
    `AwcExtensionAbility`, `AwcServiceExtAbility`, `HWBR-0-arkweb_mainprocess`, `NK_CPP`, and
    `RequestFromHttpDns ... bundleName=com.huawei.hmos.browser`.
  - This strengthens the current theory that Huawei Browser is not using the plain generic
    WebAdapter/ArkWeb app path. It carries extra browser-side network glue, including its own
    Cronet/HTTPDNS machinery, while `com.easy.hmos.abroad` remains stuck on the default-net callback
    path with `network_for_dns=-1`.
- A focused single-variable experiment was re-run on June 26, 2026 by removing `isInternal: true`
  from `FlClashVpnAbility.ets`, rebuilding, reinstalling, and cold-starting the target app.
  It still failed with the same WebAdapter symptoms:
  - `NetConnCallback enter, net available, net id = 113`
  - `network_for_dns_ -1`
  - `dns server is empty`
  - `BindDnsToNetwork, network_for_dns -1`
  - `vpnEnabled:1` + `dnsServerReturnNothing`
- A second single-variable experiment was re-run on June 26, 2026 by temporarily setting
  `trustedApplications: ['com.easy.hmos.abroad']`, rebuilding, reinstalling, and cold-starting
  the target app.
  - System VPN manager accepted the target UID:
    `app: com.easy.hmos.abroad success, uid=20020274.`
  - The VPN became non-global in the expected way:
    `IsGlobalVpn: refused = 0 accepted = 1 routed = 1`
  - `vpn-tun` still came up normally and `StartTun result ok=1` still held.
  - Despite the UID-level trustlist taking effect, the target app still reported:
    `vpnEnabled:1`, `dnsFromNetsys:0`, `sock:-1`,
    `dnsServerReturnNothing` / `Couldn't resolve host name`,
    `tryConnV4:0`, and `tryConnV6:0`.
  - This is a stronger version of the earlier trustlist finding: the app is not merely
    missing VPN eligibility. It still fails after the system has explicitly mapped that UID
    into VPN routing state, which points back to the app/Web container resolver path itself.
- A runtime mission dump on June 26, 2026 also clarified the "Chrome vs Huawei Browser" split:
  - `aa dump -a` showed a background mission
    `#com.android.chrome:entry:com.google.android.apps.chrome.Main`
    hosted under `app name [com.huawei.shell_assistant]` and
    `bundle name [com.huawei.shell_assistant]`.
  - The same dump also showed
    `#com.easy.abroad:entry:com.easy.abroad.activities.MainActivity`
    hosted under the same `com.huawei.shell_assistant` wrapper.
  - By contrast, Huawei Browser appears as its own native mission:
    `#com.huawei.hmos.browser:entry:MainAbility`.
  - This means the user-visible "non-native app" bucket is at least two different runtime classes:
    1. native Harmony browser/AWC path (`com.huawei.hmos.browser`)
    2. `com.huawei.shell_assistant`-hosted compatibility missions such as Chrome and `com.easy.abroad`
  - That split fits the observed behavior: Huawei Browser traffic reaches `vpn-tun`, while the
    shell-assistant-hosted path remains the unresolved gap.
- A third single-variable experiment was re-run on June 26, 2026 by temporarily setting
  `trustedApplications: ['com.huawei.shell_assistant']`, rebuilding, reinstalling, and cold-starting
  `com.easy.hmos.abroad`.
  - System VPN manager then accepted the host wrapper UID instead of the visible compat-app UID:
    `app: com.huawei.shell_assistant success, uid=20005.`
  - `vpn-tun` counters increased during the target app launch from `RX/TX 6/6` packets to `52/57`,
    which is the first direct counter evidence that shell-assistant-hosted compat traffic can enter
    the FlClash TUN path.
  - The same run also produced successful app-side HTTP completion:
    `statusCode: 200` / `request responseCode=200`.
  - This does not fully eliminate the resolver inconsistency yet, because adjacent logs still show
    retries with `dnsServerReturnNothing` and `dnsFromNetsys:0`.
  - Even with that caveat, this is now the strongest runtime lead: for compat apps such as Chrome
    and `com.easy.abroad`, the real routing/trust target appears to be the shell assistant host UID
    rather than the user-visible package UID.
- Follow-up compat verification was then scripted into `bash scripts/ohos/verify_compat_vpn.sh`
  so the same chain can be replayed without hand-written command bundles.
  - On June 26, 2026, a delayed sample run against `com.easy.hmos.abroad` showed
    `vpn-tun` counters moving from `RX/TX 6/6` to `11/11`, then `12/12`, while the app again logged
    `request responseCode=200`.
  - This is stronger than the earlier one-shot check because it proves the compat app can now
    trigger bidirectional TUN counter growth on demand, even though the observed volume is still small
    compared with the native Huawei Browser control run.
  - A later fresh run on the same day also showed that this compat path is timing-sensitive:
    with shorter waits the app could first report `weakNetTcpTimeout` before its later retry succeeded.
    The script defaults were therefore widened to the currently verified working window:
    `VPN_START_WAIT=15`, `TARGET_LAUNCH_WAIT=20`, and `TARGET_SETTLE_WAIT=15`.
  - After writing those waits back into the script and re-running the default command,
    the compat verification again succeeded on the unmodified command line:
    `vpn-tun` moved from `RX/TX 8/8` to `8/24`, then `11/47`, and
    `request responseCode=200` was logged again.
- A fourth single-variable iteration was then re-run on June 26, 2026 by widening the trustlist to
  both `com.huawei.shell_assistant` and `com.huawei.hmos.browser`.
  - This removed the regression introduced by the shell-assistant-only trustlist.
  - The scripted compat run still passed after reinstall:
    `vpn-tun` moved from `RX/TX 14/14` to `19/19`, then `20/20`, and
    `com.easy.hmos.abroad` again logged `request responseCode=200` with `dnsFromNetsys:1`.
- A matching native browser regression check was then scripted into
  `bash scripts/ohos/verify_browser_vpn.sh`.
- Under the widened trustlist, Huawei Browser again drove substantial tunnel traffic:
  `vpn-tun` moved from `RX/TX 4/4` to `129/154`, then `188/224`, while browser-side logs again
  showed the expected ArkWeb / Cronet path such as `RequestFromHttpDns ... bundleName=com.huawei.hmos.browser`.
- The Chrome compat path is now also scripted through
  `bash scripts/ohos/verify_chrome_vpn.sh`.
  - The script keeps the device awake, returns to the desktop, resolves the Chrome dock icon from
    the live layout dump, launches Chrome, taps the restored `m.youtube.com` / `YouTube` target
    when present, and records `vpn-tun` counters plus `com.android.chrome` /
    `com.huawei.shell_assistant` mission and hilog evidence.
  - On June 26, 2026, a full run on Mate 80 Pro showed:
    `vpn-tun` moved from `RX/TX 5/5` after VPN start to `43/84` after Chrome launch,
    then `60/156`, then `74/215` after Chrome interaction and settle.
  - The same run also confirmed the foreground window as `com.android.chrome` and the compat host
    path as `com.huawei.shell_assistant`, which closes the earlier verification gap for Chrome itself.
- This is the first verified source state in which the native Huawei Browser path and the
  shell-assistant-hosted compat path both traverse the FlClash VPN on the same device build.
- This means the current strongest root-cause statement is no longer "route setup is wrong".
  It is now: FlClash successfully creates a usable HarmonyOS VPN network, but generic WebAdapter/ArkWeb
  clients only partially adopt that VPN network for DNS/socket binding even when VPN availability is observed.

### RESOLVED (June 27, 2026): browsers load YouTube — the TUN→proxy TCP path was dead (gVisor stack fix)

This is THE fix that finally made both the Huawei native browser and Chrome render YouTube (and any
foreign site) through the VPN on the Mate 80 Pro. The DNS/fake-ip work below was necessary but not
sufficient.

Symptom: every TCP connection through the tun timed out (even a raw IP like `1.1.1.1`), while a loopback
`curl -x http://127.0.0.1:7890 …` to the same node worked perfectly. A temporary core diagnostic
(dumping `statistic.DefaultManager.Snapshot()` + mihomo `log.Subscribe()` to the `debugCoreLog` file at
`/data/storage/el2/base/files/flclash-core.log`, read from the host via the world-readable real path
`/data/app/el2/100/base/com.follow.clash/files/flclash-core.log`) showed `count=0` tracked connections
and `[sing-tun] Mixed.processPacket proto=6 …` lines with **no** follow-up — TCP SYNs entered the tun but
never produced a connection. UDP/DNS worked.

Root cause: mihomo's default `mixed` TUN stack dispatches **UDP via gVisor** (`InjectInbound`) but **TCP
via the System NAT** (`third_party/sing-tun/stack_system.go processIPv4TCP`), which rewrites each SYN to
`tunAddr:tcpPort` and writes it back, relying on the **kernel to loop that packet to a local TCP
listener**. That loopback does not happen inside the OHOS VpnExtension, so all TCP was silently dropped.

Fix (both parts required):

1. `core/tun/tun.go` — force `tunStack = constant.TunGvisor` when `tunBuildGOOS == "ohos"`, so TCP is also
   handled entirely in userspace (no kernel loopback).
2. gVisor's `fdbased.New()` calls `isSocketFD(fd) → unix.Fstat(fd)`, which OHOS denies on the VPN tun fd
   (`permission denied`), so the gVisor stack failed to start. `scripts/ohos/patch_gvisor_tun_fd.sh`
   patches `isSocketFD` to treat an Fstat failure as non-socket (readv dispatch); it is run idempotently
   by `GoBuilder._patchOhosGvisorTunFd` (`plugins/setup/buildkit/build_tool/lib/src/go_builder.dart`)
   before every OHOS lib build, because gVisor is a non-replaced module-cache dependency.

Verified device-side: both browsers fully render the YouTube homepage (logo, thumbnails, player); the live
connection table shows 17+ connections routed through the HK node; `vpn-tun` RX climbs into the MBs.

The OHOS sniffer force-enable and the `core/conn_dump_ohos.go` diagnostic added while hunting this were
removed afterward (`core/sniffer_ohos.go`, `core/sniffer_default.go`, and the `ensureOhosSniffer` call in
`core/common.go` are gone); the gVisor TCP fix + the fake-ip/DNS changes below are what carry the result.

### RESOLVED (June 28, 2026): live UI ↔ running-core link (status/stats/connections/mode switch)

After browsing worked, real-device testing showed the UI had no live channel to the core serving traffic
(dashboard stuck at "连接中…", 流量统计 0, 连接 page "暂无连接", live outbound-mode/node switches no-op). The
Go core is the socket *client* (`startServer`→`dial`) and Dart `CoreService` is the *server*; when the VPN
runs in `com.follow.clash:vpn`, nothing dialed the main app's socket. Fix: thread the main app's
`unixSocketPath` through `startVpn` → `FlClashVpnAbility`, which after `startTun` calls
`nativeBridge.startEmbeddedCore(coreSocketPath, filesDir)` (dlopens the same `libclash.so`, runs
`startServerProcessDetached`→`dial`), and flip the OHOS-VPN `_handleStart(syncCoreState:false)` to
`_handleStart()`. Now the in-process VPN core connects back to the UI: live stats, connections, and live
mode/node switching all work. Full report + one-command regression suite:
`docs/ohos-real-device-test-report.md` / `scripts/ohos/verify_all.sh` (22/22 on Mate 80 Pro).

### RESOLVED (June 27, 2026): YouTube blocked by `youtube.com` in the OHOS fake-ip-filter

Root cause for browsers not loading YouTube on Mate 80 Pro was found and fixed:

- `lib/common/task.dart` `_ohosHuaweiFakeIpFilterDomains` listed `youtube.com`, `*.youtube.com`,
  `www.youtube.com`, `m.youtube.com`. The fake-ip-filter forces those domains OUT of fake-ip into
  REAL DNS resolution. On the China carrier network that is the GFW-poisoned path: the core resolved
  YouTube via China nameservers (`114.114.114.114` / `223.5.5.5` / `119.29.29.29`) in `dnsMode:normal`,
  the browser got a poisoned IP (e.g. a Facebook IP `31.13.92.37`) or nothing, and the page stayed blank.
- Fix: remove the YouTube entries so YouTube gets a fake-ip and routes through the proxy by domain.
  The Huawei `dbankcloud` HTTPDNS entries correctly remain in that list (they need real IPs to bypass).
- After the fix, the Huawei Browser actually loaded `youtube.com` through the proxy: `vpn-tun` carried
  real asymmetric traffic (RX/TX ~783/786, 56 KB) and the page progressed from the hard
  `网络连接不稳定` error to a live loading state. This is the first time a poisoned foreign domain
  resolved correctly inside an OHOS browser under FlClash.

Supporting changes made in the same investigation:

- `ohos/entry/src/main/ets/vpn/vpn_config.ts`: added `HUAWEI_HTTPDNS_EXCLUDED_CIDRS`
  (`139.9.0.0/16`, `49.4.0.0/16`, `121.36.0.0/16`, `125.88.0.0/16`,
  `119.147.0.0/16`, `183.61.0.0/16`) as excluded VPN routes. Huawei Browser resolves
  hosts via its own HTTPDNS to those China edge servers; when routed into the tunnel they are reached
  through the foreign node and never answer, stalling each lookup ~10s (`code:10069004`). Excluding them
  keeps HTTPDNS on the local carrier network. After this change the browser reported `useHttpDns:0` and
  stopped stalling.
- `core/sniffer_ohos.go` (+ `core/sniffer_default.go` no-op, called from `core/common.go applyConfig`):
  force-enable TLS/HTTP/QUIC sniffing with `override-destination` + `parse-pure-ip` + `force-dns-mapping`
  on OHOS, as defense-in-depth for the documented OHOS DNS-hijack gap (system resolver does DNS on the
  underlying carrier interface, bypassing the tun, so poisoned IPs can still reach the core).
  **Later removed** (see the "The OHOS sniffer force-enable … were removed afterward" note above); these
  files no longer exist in `core/`. This bullet is retained only as investigation history.
- The June 26 single-variable `isInternal=false` experiment did not by itself fix DNS propagation
  (`NetConnManager` never registered a VPN network either way). That probe should be read as historical
  diagnosis, not the current source-state toggle recommendation: the later June 28 landed source uses
  the current full-system VPN wiring (`blockedApplications: [bundleName]`, no `trustedApplications`
  allowlist) together with `isInternal: false`, which is the configuration covered by
  `docs/ohos-real-device-test-report.md`.

Diagnostic facts captured (Mate 80 Pro `5JV0225B14001088`):

- Core + node proven working independently: `curl -x http://127.0.0.1:7890 https://www.youtube.com/generate_204`
  via `hdc fport tcp:17890 tcp:7890` returned HTTP 204 (US egress). NOTE: that path tests the loopback
  listener, not the tun.
- `hidumper -s NetConnManager` shows only the cellular net (NetId 113); the VPN never registers as a
  NetConn supplier on this OHOS image, regardless of `isInternal`. This is why the VPN DNS (`172.19.0.2`)
  is not propagated to apps and `dns-hijack` cannot catch the system resolver's queries.

Outstanding (environmental, not a code defect): during heavy testing the jisu airport node became
unreachable (`DIRECT` to a China IP returns 404 through the proxy, but every foreign endpoint times out
`http=000`, and the dashboard `网络检测` falls back to a China egress with a persistent `连接中…` state).
Subscription is healthy (3.6 GB / 2.9 TB, valid to 2028-02-04) and a profile sync did not restore it, so
this is a node-server / source-IP-block issue. A working node is required to re-confirm the full
end-to-end YouTube render and to validate Chrome (`com.android.chrome` via `com.huawei.shell_assistant`).

Focused log artifact for the failed `isInternal=false` experiment:

```text
.ohos_live/isinternal_false_experiment.log
```

Focused control-run artifact for Huawei Browser:

```text
.ohos_live/huawei_browser_youtube_20260626_123020.log
```

Focused trustlist/UID-DNS experiment artifact:

```text
.ohos_live/trusted_app_uid_dns_20260626_123925.log
```

Focused runtime mission dump for shell-assistant-hosted apps:

```text
.ohos_live/mission_dump_shell_assistant_20260626_124304.log
```

Focused shell-assistant trust / counter artifact:

```text
.ohos_live/shell_assistant_counter_20260626_124738.log
```

Focused scripted compat verification artifacts:

```text
.ohos_live/compat_vpn_20260626_125637.log
.ohos_live/compat_vpn_20260626_125752.log
.ohos_live/compat_vpn_20260626_130155.log
.ohos_live/compat_vpn_20260626_130753.log
```

Focused dual-trust browser verification artifact:

```text
.ohos_live/native_browser_under_dual_trust_20260626_130902.log
.ohos_live/browser_vpn_20260626_131124.log
```

Useful live probes while continuing this investigation:

```bash
/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc -t 5JV0225B14001088 shell "ifconfig vpn-tun 2>/dev/null || true; ip route 2>/dev/null || netstat -rn 2>/dev/null || true"
bash scripts/ohos/verify_compat_vpn.sh
bash scripts/ohos/verify_browser_vpn.sh
```

## What is missing

The current branch is no longer blocked at core load, but it is not feature-complete yet:

- The Dart app runtime still lacks full OHOS parity for every Android-specific integration path
- Most end-to-end proxy behavior and subscription-management workflows are now re-verified on the current tablet emulator, but TUN/VPN authorization still cannot be completed on the tested Huawei emulator image
- Final confidence for device-only integration paths still requires a supported HarmonyOS image or a real device, especially for system VPN takeover and other platform-owned consent flows
- `phone` emulators still do not support the native child-process API needed by some experimental runtime paths

## Hard prerequisites

This project is pinned to modern Flutter on the mainline, and the OpenHarmony Flutter toolchain is still published on separate branches/releases. Most published SDK combinations still do not line up cleanly with this repository's Dart and Flutter constraints, so a clean checkout should be expected to need toolchain validation before it builds.

Before building, install and verify:

1. DevEco Studio / OpenHarmony SDK with `hvigor`, `ohpm`, `hdc`
2. OpenHarmony Flutter SDK branch compatible with this project
3. A dependency set that provides `ohos` implementations for all required plugins
4. `OHOS_SDK_HOME` or `OHOS_BASE_SDK_HOME` must point to the OpenHarmony SDK root, for example:

```bash
export OHOS_SDK_HOME=/path/to/sdk/default/openharmony
export OHOS_BASE_SDK_HOME=$OHOS_SDK_HOME
```

For DevEco Studio sync on this workspace, the IDE also expects the versioned SDK view under `~/Library/OpenHarmony/Sdk/24`. Use `scripts/ohos/prepare_deveco_sdk_link.sh` to create that link when DevEco reports missing `toolchains:24` / `ArkTS:24` / `js:24` / `native:24` / `previewer:24`.

## Verified toolchain findings

The following combinations were validated in this branch:

- `3.7.12-ohos-1.0.4`
  - Flutter/Dart toolchain starts, but `flutter pub get` fails immediately because it bundles Dart `2.19.6`
  - This repository requires Dart `>=3.8.0`
- `3.22.1-ohos-1.1.0` and `3.22.1-ohos-1.1.1`
  - `flutter --version --machine` reports a valid OpenHarmony Flutter version
  - Both bundle Dart `3.4.0`
  - This is still below the repository requirement `>=3.8.0`
- `oh-3.35.7-release`
  - Bundles Dart `3.9.2`, which is new enough for this repository
  - The published branch snapshot may still report Flutter version `0.0.0-unknown` during pub version solving on some setups
  - In this workspace, with a local `oh-3.35.7-release` checkout and OpenHarmony 6.0.2(22) SDK, the packaging scaffold produced a signed release HAP after the local hvigor wrapper prepared signing assets from the SDK-provided OpenHarmony demo keystore
  - In this workspace on June 22, 2026, `flutter pub get` was re-verified after pinning local patched copies of `riverpod` and `flutter_riverpod` under `third_party/`
  - Root cause: the published upstream package metadata currently places `test` inside `riverpod` runtime dependencies and `flutter_test` inside `flutter_riverpod` runtime dependencies, which conflicts with Flutter SDK `test_api` pinning during fresh resolution
  - Practical requirement: set `OHOS_SDK_HOME` before `flutter pub get`, because the local OHOS build plugin checks the Harmony SDK during dependency resolution

## Recommended build path

1. Clone OpenHarmony Flutter SDK from the current upstream release source
2. Select a release that is both:
   - published with a valid Flutter semantic version
   - bundled with Dart `>=3.8.0`
3. Point Flutter to the Harmony SDK:

```bash
flutter config --enable-ohos
flutter config --ohos-sdk <OpenHarmony SDK path>
```

4. Regenerate the `ohos/` host if your chosen Flutter OHOS branch requires a newer template
5. Resolve third-party plugin compatibility for:
   - `path_provider`
   - `shared_preferences`
   - `url_launcher`
   - `image_picker`
   - `file_picker`
   - `device_info_plus`
   - `connectivity_plus`
   - `package_info_plus`
   - `app_links`
   - `mobile_scanner`
   - `dynamic_color`

## Build command

After a compatible Harmony toolchain is installed, build the packaging scaffold from the project root with the Harmony-enabled Flutter SDK:

```bash
dart setup.dart ohos
```

OHOS-specific runtime prerequisite in this branch:

- `ohos/entry/libs/arm64/libsqlite3.so` must exist before packaging
- `ohos/entry/libs/arm64/libFlClashCore.so` must exist before packaging
- `setup.dart` auto-builds a patched Go toolchain in `.ohos_toolchain/go-nonglibc` on first use so the OHOS `libclash.so` uses the non-glibc-safe TLS model
- `setup.dart` now fails fast if that library is missing
- The current repository snapshot vendors `arm64` native libraries for emulator/device startup validation

Or build directly in the host project:

```bash
cd ohos
hvigorw --mode module -p product=default -p module=entry assembleHap
```

The host build still emits the default hvigor artifact at:

```text
ohos/entry/build/default/outputs/default/entry-default-signed.hap
```

The release-style artifact copied by `setup.dart` is:

```text
dist/FlClash-<version>-ohos-arm64.hap
```

## Emulator install smoke test

Once the HAP has been built, verify packaging on a HarmonyOS emulator before treating it as a releasable artifact.

Prerequisites:

1. Start a HarmonyOS emulator or connect a test device
2. Ensure `hdc list targets` shows exactly one target, or set `HDC_TARGET=<target>`
3. Keep the generated HAP at `dist/FlClash-<version>-ohos-arm64.hap`
4. This script does not start an emulator for you; it only validates install and launch against an existing target

Run the repository smoke test:

```bash
bash scripts/ohos/install_and_launch.sh
```

Or run the stricter runtime verification script:

```bash
bash scripts/ohos/verify_runtime.sh
```

For controlled slow-response / long-connection testing on the host side, start the local OHOS runtime test server:

```bash
bash scripts/ohos/start_runtime_test_server.sh start
```

Useful probe endpoints from the current workspace:

- `http://127.0.0.1:19003/delay?seconds=10`
- `http://127.0.0.1:19003/stream?seconds=20&interval_ms=500&chunk_bytes=256`
- `http://127.0.0.1:19003/ip-check?delay_ms=1000`

Or pass an explicit artifact path:

```bash
bash scripts/ohos/install_and_launch.sh dist/FlClash-<version>-ohos-arm64.hap
```

```bash
bash scripts/ohos/verify_runtime.sh dist/FlClash-<version>-ohos-arm64.hap
```

What this verifies today:

- the signed HAP can be installed with `hdc install -r`
- the entry ability can be started with `aa start`
- the bundled Go core can be loaded and invoked on a supported HarmonyOS target

What a passing result means on the current branch:

- install succeeds
- launch succeeds
- the app process remains alive on the emulator after launch instead of exiting immediately
- `hilog` shows successful OHOS core actions such as `initClash`, `setupConfig`, `getProxies`, and `getExternalProviders`
- `hilog` does not show `initial-exec TLS resolves to dynamic definition`

This is still weaker than a full product smoke test. It proves that the OHOS package can install, launch, and invoke the Go core, but it does not by itself prove every FlClash feature is production-ready on HarmonyOS.

Current emulator-specific limitation re-verified on June 22, 2026:

- The VPN host path now reaches `vpnExtension.startVpnExtensionAbility`, but the current Huawei emulator image at `127.0.0.1:5555` is still missing the system bundle `com.huawei.hmos.vpndialog`
- This was re-verified on the current `FlClash Tablet` emulator, not only on the earlier `phone` image
- The system therefore cannot present the VPN authorization dialog (`VpnServiceExtAbility`), and third-party VPN startup aborts before `FlClashVpnAbility.onCreate()` runs
- Evidence from `hilog` on this workspace:
  - `bundle not exist -n com.huawei.hmos.vpndialog`
  - `ExplicitQueryExtension size:0 -n com.huawei.hmos.vpndialog -e VpnServiceExtAbility`
  - `[AppPlugin] startVpn failed error=startVpnExtensionAbility timeout`
  - `[OHOS-VPN] start failed: OHOS VPN 授权组件缺失，当前模拟器无法完成系统 VPN 启动`
- Practical consequence:
  - on the same `FlClash Tablet` build and emulator session, `网络 -> VPN` set to `off` still allows the dashboard start action to enter the running state and emit real proxy traffic
  - on the same `FlClash Tablet` build and emulator session, `网络 -> VPN` set to `on` fails immediately with the explicit missing-bundle error above
  - app/core startup can still succeed
  - system-wide traffic takeover cannot be validated on this emulator image because the platform VPN consent UI is absent
  - full VPN validation now requires either a different HarmonyOS image that includes `com.huawei.hmos.vpndialog` or a real device
  - fresh June 22, 2026 evidence on the rebuilt package confirms the verification path must explicitly disable VPN before dashboard runtime validation:
    - `工具 -> 进阶配置 -> 网络 -> VPN` can be toggled off through the real OHOS settings UI
    - `hilog` then persists the change through the OHOS file-store path:
      - `[ohos-preferences] saveConfig path=/data/storage/el2/base/haps/entry/files/shared_preferences.json ...`
    - after that toggle, tapping the dashboard start button no longer emits `startVpn stack=...` or `com.huawei.hmos.vpndialog` errors on the same session
    - instead, the runtime path stays in the sustained listener/traffic loop:
      - `[OHOS-CORE] invoke startListener#... begin/done`
      - `[OHOS-CORE] invoke getTraffic#... begin/done`
      - `[OHOS-CORE] invoke getTotalTraffic#... begin/done`
  - current workspace UI evidence now also captures the dashboard start button behavior directly:
    - `.ohos_live_current/dashboard_runtime_state.jpeg`
    - `.ohos_live_current/dashboard_after_start_toggle.jpeg`
    - `.ohos_live_current/dashboard_after_start_toggle2.jpeg`
  - in that re-check:
    - tapping the dashboard start button first entered the running state with runtime text `00:00:02`
    - the network check widget switched to a real proxy egress IP `141.145.196.11` through the selected `🇫🇷法国` node
    - the emulator then forced a fallback to the stopped state after the missing `com.huawei.hmos.vpndialog` authorization component aborted the VPN path

Build-specific note for this branch:

- The effective OpenHarmony Flutter embedding source is consumed from `ohos/har/flutter.har`
- `dart setup.dart ohos` now patches the embedded `NavigationChannel.ets` inside the source HAR for the duration of the build, so the generated host package uses `call.argument('uri')` instead of the older `call.args as Map` access that triggered the spurious `DartMessenger` exception on emulator launch
- The source HAR is restored after the build completes

Latest verified emulator result in this workspace:

- Build artifact: `dist/FlClash-0.8.93-ohos-arm64.hap`
- Emulator target: `127.0.0.1:5555`
- Fresh rebuild on June 22, 2026:
  - `flutter build hap --target-platform ohos-arm64 --release --no-pub --dart-define-from-file=env.json`
  - output: `ohos/entry/build/default/outputs/default/entry-default-signed.hap`
  - copied release-style artifact:
    - `dist/FlClash-0.8.93-ohos-arm64.hap`
- Install result: success
- Launch result: success
- Runtime result: app remains running and reaches the normal shell
- Navigation channel result: no `DartMessenger --> Uncaught exception in binary message listenergetMessage is not callable` log after launch
- Core result:
  - `[OHOS-CORE] invoke initClash ... done`
  - `[OHOS-CORE] invoke setupConfig ... done`
  - `[OHOS-CORE] invoke getProxies ... done`
  - `[OHOS-CORE] invoke getExternalProviders ... done`
- TLS result: no `initial-exec TLS resolves to dynamic definition` log after launch

Latest end-to-end emulator smoke result in this workspace:

- URL profile import works against a real subscription endpoint, including provider content that is delivered as base64 / URI subscription data instead of Clash YAML
- The OHOS build now supports two real URL-import paths:
  - an OHOS-specific `从URL导入` page with manual URL entry
  - an OHOS deep link entrypoint `flclash://install-config?url=<encoded-url>`
- The deep-link path was re-verified on June 21, 2026 against the real `jisu` subscription URL on the current `FlClash Tablet` emulator:
  - `aa start -U 'flclash://install-config?url=<encoded-url>' -b com.follow.clash` reaches the real import flow instead of a placeholder handler
  - `hilog` shows:
    - `[AppPlugin] setPendingLink=flclash://install-config?...`
    - `onAppLink from ohos channel: flclash://install-config?...`
    - `[ohos-profile-url] addProfileFormURL success: id=... type=url label=<subscription-host>`
  - current workspace evidence is captured at:
    - `.ohos_live_current/deeplink_import_prompt.jpeg`
    - `.ohos_live_current/after_deeplink_import.jpeg`
- Local file profile import is also verified against a real YAML file instead of a placeholder picker flow:
  - after choosing a real config file, the `配置` page renders a new profile card `flclash-real-import.yaml`
  - current workspace UI evidence is captured at `.ohos_live_current/after_file_import2.jpeg`

Latest resource-sync finding in this workspace:

- The resource page URL-edit chain is now verified end to end on the current HarmonyOS emulator session
  - after editing `GEOSITE`, the page persists the new URL and silently reapplies the active profile so the core actually uses the updated value
  - current workspace UI evidence is captured at:
    - `.ohos_live_current/resources_after_resource_fix.jpeg`
    - `.ohos_live_current/resources_direct_page.jpeg`
- A direct-mode retry on June 21, 2026 proved that the previous `GEOSITE` sync failure was not an OHOS platform limitation and not a broken resource page
  - dashboard outbound mode was switched to `直连`
  - `GEOSITE` sync then completed successfully against `https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geosite.dat`
  - `hilog` showed:
    - `[OHOS-CORE] invoke updateGeoData ... begin/done`
    - request event with `host=fastly.jsdelivr.net` and `chains=["DIRECT"]`
    - `ResultCallback method=updateGeoData ... code:0`
  - the resource row changed from `2 小时前` to `刚刚`
  - current workspace evidence is captured at:
    - `.ohos_live_current/dashboard_direct_applied.jpeg`
    - `.ohos_live_current/geosite_sync_direct_inflight.jpeg`
    - `.ohos_live_current/geosite_sync_direct_final.jpeg`
- Practical conclusion:
  - the remaining blocker is no longer the OHOS resource-sync implementation itself
  - the stronger hypothesis is that the currently imported subscription has unusable proxy nodes, so rule-mode resource downloads can still fail when they are routed through those bad nodes
- That hypothesis was then validated in the same workspace on June 21, 2026:
  - the real `jisu` subscription from `/Users/liushangliang/github/womenlia/clash/config/values.yaml` was imported again through the OHOS deep-link flow
  - `hilog` showed:
    - `[ohos-profile-url] addProfileFormURL success: id=... type=url label=<subscription-host>`
    - after selecting that profile, `getProxies` returned real node groups instead of the earlier unusable placeholder entries
  - current workspace UI evidence is captured at:
    - `.ohos_live_current/jisu_deeplink_now.jpeg`
    - `.ohos_live_current/jisu_import_done.jpeg`
    - `.ohos_live_current/profile_jisu_selected.jpeg`
- After switching back to `规则` mode with the imported `jisu` profile active, `GEOSITE` sync also succeeded through a real proxy route:
  - `hilog` showed a request for `host=fastly.jsdelivr.net`
  - the request chain was `🇺🇸美国洛杉矶1号 -> PROXY`
  - `ResultCallback method=updateGeoData ... code:0`
  - the resource row changed to `刚刚`
  - current workspace evidence is captured at:
    - `.ohos_live_current/resources_rule_jisu_ready.jpeg`
    - `.ohos_live_current/geosite_sync_rule_jisu2_final.jpeg`
- The proxy page is now also re-verified as a real interactive page on the emulator, not a static placeholder:
  - the `代理` tab renders the `PROXY` group with real node cards from the imported `jisu` subscription
  - selecting a different node updates both UI state and core state
  - current workspace evidence is captured at:
    - `.ohos_live_current/proxy_page_opened.jpeg`
    - `.ohos_live_current/proxy_after_switch_france.jpeg`
  - `hilog` showed:
    - `[OHOS-CORE] invoke changeProxy ... begin/done`
    - `ResultCallback method=changeProxy ... code:0`
    - `[proxy-debug] getProxiesGroups groups=2 GLOBAL:37:DIRECT; PROXY:35:🇫🇷法国`
  - the proxy settings sheet is also now verified with a real render-style mutation instead of only opening the menu:
    - opening the top-right menu shows a real `设置` entry
    - switching `风格` from `标签页` to `列表` immediately changes the page from a multi-card grid to the compact selector row:
      - `PROXY`
      - `Selector`
      - `· 🇺🇸美国洛杉矶1号`
    - after leaving `代理` and reopening it, the same list-style layout remains, confirming persistence across navigation
    - the page was then restored to the original `标签页` style on the same emulator session
    - switching `布局` from `标准` to `紧凑` immediately changes the tab page from 2 columns to 3 columns:
      - row 1 changes from `🇺🇸美国洛杉矶1号 / 🇺🇸美国洛杉矶2号`
      - to `🇺🇸美国洛杉矶1号 / 🇺🇸美国洛杉矶2号 / 🇺🇸美国洛杉矶3号`
    - switching `尺寸` from `标准` to `最小` on the same `紧凑` layout visibly shrinks card height:
      - before: first card bounds `[999,375][1280,637]`
      - after: first card bounds `[999,375][1280,533]`
    - after leaving `代理` and reopening it, the same `紧凑 + 最小` layout remains, confirming persistence across navigation
    - the page was then restored to the original `标准布局 + 标准尺寸` state on the same emulator session
    - the list-only `图标样式` branch is now also verified with real visual differences instead of a dead sub-section:
      - switching `风格` to `列表` exposes the real `图标样式` row with `无 / 标准 / 仅图标`
      - current workspace sheet evidence is captured at `.ohos_live_current/proxies_settings_list_mode.jpeg`
      - selecting `无` removes the leading proxy-type icon from the compact selector row while keeping the same selected node text
      - current workspace no-icon evidence is captured at `.ohos_live_current/proxies_list_icon_none.jpeg`
      - selecting `仅图标` restores the row with the standalone leading icon while preserving the same selected node
      - current workspace icon-only evidence is captured at `.ohos_live_current/proxies_list_icon_only.jpeg`
      - the page was then restored to the original `标签页` style on the same tablet session
      - current workspace restored-tab evidence is captured at `.ohos_live_current/proxies_restored_tab_after_icon_test.jpeg`
- Proxy latency testing is also re-verified on the same emulator session:
  - tapping `延迟测试` triggers a real batch probe instead of a no-op
  - `hilog` showed `[proxy-delay] batch start proxies=35`
  - the proxy cards then rendered concrete results including numeric latency and timeout states
  - current workspace evidence is captured at:
    - `.ohos_live_current/proxy_after_delay_test.jpeg`
    - `.ohos_live_current/tools_before_requests.jpeg`
- The `工具 -> 请求` and `工具 -> 连接` pages are re-verified against real traffic records:
  - both pages displayed the actual resource-sync request `tcp://fastly.jsdelivr.net:443`
  - the rendered route chips matched the earlier traffic path `🇺🇸美国洛杉矶1号` and `PROXY`
  - current workspace evidence is captured at:
    - `.ohos_live_current/request_page_coords.jpeg`
    - `.ohos_live_current/connections_page_coords.jpeg`
  - after the later `MMDB` sync with `🇫🇷法国` selected, both pages also refreshed to the new GitHub download records:
    - `tcp://release-assets.githubusercontent.com:443`
    - `tcp://github.com:443`
    - route chips `🇫🇷法国` and `PROXY`
  - current workspace evidence is captured at:
    - `.ohos_live_current/request_page_after_mmdb.jpeg`
    - `.ohos_live_current/connections_page_after_mmdb.jpeg`
- Resource verification is no longer limited to `GEOSITE`:
  - `MMDB` sync was re-verified on June 21, 2026 with the currently selected `🇫🇷法国` proxy active
  - `hilog` showed:
    - `[OHOS-CORE] invoke updateGeoData ... begin/done`
    - request records for `github.com` and `release-assets.githubusercontent.com`
    - route `🇫🇷法国 -> PROXY`
    - `ResultCallback method=updateGeoData ... code:0`
  - the resource row changed from `2 小时前` to `刚刚`
  - current workspace evidence is captured at:
    - `.ohos_live_current/resources_before_mmdb_sync.jpeg`
    - `.ohos_live_current/mmdb_sync_inflight.jpeg`
    - `.ohos_live_current/mmdb_sync_final2.jpeg`
  - current source observability now logs the import lifecycle with:
    - `[profile-file-import] start`
    - `[profile-file-import] picked ...`
    - `[profile-file-import] success: ...`
- Dashboard editing is now verified end to end on the current OHOS emulator instead of only by transient UI screenshots:
  - entering edit mode via the top-right pencil works
  - widget add and reorder are both verified with real side effects:
    - adding `内存信息` previously produced a real persisted card instead of a fake placeholder
    - drag reorder previously produced real OHOS drag logs:
      - `[dashboard-drag] start index=5 targetIndex=5`
      - `[dashboard-drag] will index=4 targetIndex=4 dragIndex=5`
      - `[dashboard-drag] end dragIndex=5 targetIndex=4`
    - current workspace evidence from that earlier live session:
      - `.ohos_live_current/dashboard_saved_with_memory.jpeg`
      - `.ohos_live_current/dashboard_after_center_save.jpeg`
  - top-right save also works again on the rebuilt package:
    - `hilog` now shows `[dashboard-save] widgets=networkSpeed,outboundMode,networkDetection,trafficUsage,intranetIp`
    - current workspace screenshot after the save-button smoke check:
      - `.ohos_live_current/dashboard_save_button_smoke.jpeg`
  - deleting the temporary `内存信息` widget now persists correctly:
    - delete gesture evidence:
      - `[dashboard-drag] delete index=4 length=5`
    - save evidence immediately after deletion:
      - `[dashboard-save] widgets=networkSpeed,outboundMode,networkDetection,trafficUsage,intranetIp`
    - OHOS preference-store evidence:
      - `[ohos-preferences] saveConfig path=.../shared_preferences.json ...`
    - current workspace UI evidence after exiting edit mode:
      - `.ohos_live_current/dashboard_delete_retest_result.jpeg`
  - process-restart persistence is also verified:
    - after `aa force-stop com.follow.clash` and a fresh `aa start`, `内存信息` is still absent
    - current workspace restart evidence:
      - `.ohos_live_current/dashboard_after_restart_persist.jpeg`
- After importing the `jisu` provider, the `配置` page keeps the profile entry and the `代理` page shows real nodes instead of placeholder data
- The profile-card action menu on the current `FlClash Tablet` emulator was re-verified on June 21, 2026 after a full `bm clean -d` rebuild of app data:
  - reopening the `极速机场` overflow menu still renders the real profile actions instead of a placeholder sheet:
    - `编辑`
    - `预览`
    - `同步`
    - `更多`
    - `删除`
  - `删除` is now also verified as a real destructive action instead of a dead confirmation sheet:
    - tapping the action opens the real confirmation dialog:
      - `确定删除当前配置吗？`
    - current workspace dialog evidence is captured at `.ohos_live_current/delete_confirm_dialog.jpeg`
    - confirming the action removes the only profile card and returns the page to the real empty state:
      - `没有配置文件,请先添加配置文件`
    - current workspace delete evidence is captured at `.ohos_live_current/after_profile_delete_empty.jpeg`
    - the baseline was then restored on the same emulator by replaying the already-verified deep link import:
      - `flclash://install-config?url=http%3A%2F%2F10.0.2.2%3A28765%2Fjisu`
      - current workspace restore-confirm dialog evidence is captured at `.ohos_live_current/after_restore_via_deeplink.jpeg`
      - current workspace restored-card evidence is captured at `.ohos_live_current/restore_finished_profile_back.jpeg`
      - `hilog` confirms the restored import path is real:
        - `[AppPlugin] setPendingLink=flclash://install-config?url=http%3A%2F%2F10.0.2.2%3A28765%2Fjisu`
        - `[ohos-profile-url] addProfileFormURL success: id=326926570352545792 type=url label=极速机场`
  - entering `更多` still renders the real secondary actions:
    - `覆写`
    - `复制链接`
    - `导出文件`
  - `预览` now has fresh rebuilt-session evidence as a real config viewer instead of a dead route:
    - tapping the action opens a full-screen YAML preview titled `极速机场`
    - the preview renders real live config content such as:
      - `mixed-port: 7890`
      - `allow-lan: false`
      - `mode: "rule"`
      - `log-level: "error"`
      - `ipv6: false`
    - current workspace UI evidence is captured at `.ohos_live_current/profile_preview_page.jpeg`
  - `编辑` now has fresh rebuilt-session persistence evidence as a real profile form instead of a static details page:
    - opening the action reaches the editable form titled `编辑`
    - the form renders real persisted fields and controls:
      - `名称 10.0.2.2`
      - `URL http://10.0.2.2:19002/jisu`
      - `自动更新`
      - `自动更新间隔（分钟） 1440`
      - `配置 24.5KB`
      - `编辑`
      - `上传`
      - `保存`
    - current workspace page-open evidence is captured at `.ohos_live_current/profile_edit_page.jpeg`
    - toggling `自动更新` from `开启` to `关闭` changes the live form state and removes the interval input
    - current workspace changed-state evidence is captured at `.ohos_live_current/profile_edit_off_try2.jpeg`
    - tapping the real `保存` action triggers the source save path:
      - `[profile-edit] confirm start id=326905717330022400 hasFileData=false`
      - `[profile-edit] confirm putProfile done id=326905717330022400`
      - `[profile-edit] confirm pop invoked id=326905717330022400`
    - reopening the same `编辑` page shows `自动更新` still in the disabled state, confirming persistence across navigation
    - current workspace reopen evidence is captured at `.ohos_live_current/profile_edit_reopen_try2.jpeg`
    - after that persistence check, the value was switched back on and saved to restore the baseline state
    - current workspace restored-state evidence is captured at:
      - `.ohos_live_current/profile_edit_restore_on.jpeg`
      - `.ohos_live_current/profile_edit_reopen_restored_on.jpeg`
    - on the rebuilt June 22, 2026 tablet state, the same `编辑` page is now also verified with a real `名称` field writeback path:
      - the current baseline label on this session is `10.0.2.2`
      - focusing the `名称` input and committing a trailing `q` changes the live field to `10.0.2.2q`
      - current workspace input evidence is captured at `.ohos_live_current/label_edit_after_append_q.jpeg`
      - after dismissing the keyboard, the edited value still renders in the form instead of being transient IME state
      - current workspace pre-save evidence is captured at `.ohos_live_current/label_edit_keyboard_gone.jpeg`
      - tapping `保存` returns to the `配置` page and the profile card title immediately changes to `10.0.2.2q`
      - current workspace post-save evidence is captured at `.ohos_live_current/label_edit_after_save.jpeg`
      - reopening the same `编辑` page shows `名称 10.0.2.2q`, confirming the label persisted across navigation instead of only updating the list item widget
      - current workspace reopen evidence is captured at `.ohos_live_current/label_edit_reopen_verify.jpeg`
      - current-session logs confirm the real form save path:
        - `[profile-edit] confirm start id=... hasFileData=false`
        - `[profile-edit] confirm putProfile done id=...`
        - `[profile-edit] confirm pop invoked id=...`
      - after the persistence check, the temporary renamed profile was removed and the baseline state was restored through the already-verified deep-link import path:
        - delete confirm dialog evidence is captured at `.ohos_live_current/label_restore_delete_confirm.jpeg`
        - empty-state evidence is captured at `.ohos_live_current/label_restore_after_delete.jpeg`
        - deep-link restore prompt evidence is captured at `.ohos_live_current/label_restore_deeplink_prompt.jpeg`
        - restored baseline card evidence is captured at `.ohos_live_current/label_restore_after_deeplink.jpeg`
    - the nested `配置 -> 编辑` action also reaches the real YAML editor instead of a dead route:
      - the editor title is `极速机场`
      - the page renders live config content such as `mixed-port: 7890`, `allow-lan: false`, and `mode: rule`
      - the top app bar exposes real editor actions for back, save, and more
      - current workspace evidence is captured at `.ohos_live_current/profile_nested_config_editor_try2.jpeg`
    - the sibling `配置 -> 上传` action also reaches the real OHOS system picker instead of a stub action:
      - tapping `上传` opens the system `下载` picker rooted at `我的平板 > 个人 > 下载`
      - the picker renders real selectable YAML files such as `326905717330022400.yaml` and `flclash-real-import.yaml`
      - the picker also shows the real bottom action `打开`
      - current workspace picker-open evidence is captured at `.ohos_live_current/profile_upload_open.jpeg`
      - after rebuilding and reinstalling the current HAP, pressing back from that picker now returns to the app `编辑` page without surfacing the old raw cancellation error
      - current workspace rebuilt-session evidence is captured at:
        - `.ohos_live_current/upload_picker_after_fix.jpeg`
        - `.ohos_live_current/upload_cancel_after_fix.jpeg`
      - current-session logs confirm the picker path is real:
        - `[profile-edit] upload start id=326905717330022400`
        - `[AppPlugin] lastFilePickerState=pickUrisOnly:start:fileType=custom:allowMultiple=false:initialDirectory=file://docs/storage/Users/currentUser/Download:extensions=["yaml","yml"]`
        - `FilePickerUIExtAbility`
      - the rebuilt package now normalizes that user-cancel path in runtime instead of surfacing a raw dialog:
        - `[picker] ohos picker cancelled by user`
      - no new `PlatformException(cancelled, No file selected, null, null)` message is emitted on the rebuilt-session cancel path
      - the same `上传` action is also now verified end to end with a real selected file and source save path:
        - selecting `326905717330022400.yaml` changes the picker footer from `已选 (0/1)` to `已选 (1/1)`
        - current workspace selection evidence is captured at `.ohos_live_current/upload_picker_selected_real_file.jpeg`
        - tapping `打开` returns to the edit form with the local file metadata refreshed to `刚刚`
        - current workspace post-open evidence is captured at `.ohos_live_current/upload_selected_back_to_edit.jpeg`
        - tapping `保存` enters the real modified-file confirmation dialog:
          - `配置文件已经修改,是否关闭自动更新`
        - current workspace dialog evidence is captured at `.ohos_live_current/after_real_upload_save.jpeg`
        - choosing `取消` preserves the current auto-update state and still completes the real save flow
        - current workspace post-save evidence is captured at `.ohos_live_current/after_real_upload_confirm_cancel.jpeg`
        - reopening the same `编辑` page after the save shows `自动更新` still enabled, confirming that the `取消` choice did not silently flip the switch
        - current workspace reopen evidence is captured at `.ohos_live_current/upload_reopen_verify_autoupdate.jpeg`
        - current-session logs confirm the full read-and-save path:
          - `[AppPlugin] lastFilePickerState=documentPicker:success:count=1:uris=["file://docs/storage/Users/currentUser/Download/326905717330022400.yaml"]`
          - `[AppPlugin] lastFilePickerState=read:read-bytes-success:path=/data/storage/el2/base/haps/entry/files/picked_file.tmp:size=25096`
          - `[profile-edit] upload selected id=326905717330022400 bytes=25096 name=326905717330022400.yaml`
          - `[profile-edit] confirm saving uploaded file id=326905717330022400 autoUpdate=true type=url`
          - `[profile-save] success id=326905717330022400 target=/data/storage/el2/base/haps/entry/files/profiles/326905717330022400.yaml`
          - `[profile-edit] confirm saveFile done id=326905717330022400 lastUpdate=2026-06-21 11:17:52.367159`
  - `同步` now has fresh rebuilt-session runtime evidence as a real remote refresh path:
    - tapping the menu action emits the UI and action logs:
      - `[profile-sync-menu] pressed id=326905717330022400 label=极速机场`
      - `[profile-sync-ui] trigger id=326905717330022400 label=极速机场`
      - `[profile-sync-action] begin ... lastUpdate=2026-06-21T10:06:37.000`
      - `[profile-sync-action] updated ... lastUpdate=2026-06-21T10:42:21.961830`
      - `[profile-sync-action] end ...`
    - the profile card timestamp also updates from an older relative value such as `35 分钟前` to `刚刚`
    - current workspace evidence is captured at:
      - `.ohos_live_current/profile_list_before_sync.jpeg`
      - `.ohos_live_current/profile_menu_before_sync.jpeg`
      - `.ohos_live_current/profile_after_sync.jpeg`
  - `导出文件` now has fresh current-session write evidence on the rebuilt tablet state:
    - tapping the action returns to the profile list instead of hanging on the menu
    - `hilog` shows the real OHOS shared-download write:
      - `[AppPlugin] lastFilePickerState=sharedDownload:written:uri=file://docs/storage/Users/currentUser/Download/326905717330022400.yaml:path=/storage/Users/currentUser/Download/326905717330022400.yaml:size=25096:stat=25096`
      - `[profile-export] ohos writeFileToSharedDownload result=file://docs/storage/Users/currentUser/Download/326905717330022400.yaml ... fileName=326905717330022400.yaml`
      - `message: 导出成功`
    - the exported YAML is also visible later in the system `下载` picker on the same tablet session:
      - `326905717330022400.yaml`
      - `2026年6月21日 上午10:11`
      - `26 KB`
    - current workspace UI evidence after the action is captured at `.ohos_live_current/profile_export_after_action.jpeg`
    - current workspace picker evidence is captured at `.ohos_live_current/profile_export_visible_in_download_picker.jpeg`
  - `复制链接 -> 添加配置 -> URL -> 粘贴` is also now re-verified end to end on the rebuilt tablet state:
    - the source action succeeds through the OHOS clipboard bridge:
      - `[AppPlugin] setClipboardText success length=26`
      - `[profile-copy-link] ohos setClipboardText success=true hasApp=true urlLength=26`
      - `message: 复制成功`
    - reopening `添加配置` still reaches the real import chooser with:
      - `二维码`
      - `文件`
      - `URL`
    - opening `URL` still reaches the real OHOS URL-import page with:
      - `粘贴`
      - `粘贴并提交`
      - `提交`
    - tapping `粘贴` fills the live input with the copied subscription URL instead of leaving the field empty:
      - `http://10.0.2.2:28765/jisu`
    - the current clipboard read on this session hit the OHOS plugin fallback path rather than a dead failure:
      - `[AppPlugin] getClipboardText failed error=TypeError: Cannot read property length of undefined fallbackLength=26`
      - `[ohos-profile-url] paste from clipboard length=26`
    - current workspace UI evidence is captured at:
      - `.ohos_live_current/add_config_entry_after_copy.jpeg`
      - `.ohos_live_current/add_config_url_page_after_copy.jpeg`
      - `.ohos_live_current/add_config_url_after_paste.jpeg`
- The `代理` page was re-verified on June 21, 2026 on the current `FlClash Tablet` emulator:
  - the `PROXY` group renders real cards such as `🇺🇸美国洛杉矶1号`, `🇺🇸美国洛杉矶2号`, `🇺🇸美国洛杉矶3号`, and `🇫🇷法国` instead of `COMPATIBLE`
  - current workspace UI evidence is captured at `.ohos_live_current/proxy_nav_retry.jpeg`
- Proxy cards support real delay checks on the emulator:
  - observed results include values such as `421 ms`, `178 ms`, `180 ms`
  - unreachable nodes are rendered as `Timeout`
- Proxy selection works end to end:
  - selecting `🇫🇷法国` triggers `changeProxy` and `closeConnections` in the OHOS core logs
- Proxy selection was also re-verified on June 21, 2026 on the current `FlClash Tablet` emulator:
  - tapping the `🇫🇷法国` card changes the selected UI state from `🇺🇸美国洛杉矶1号` to `🇫🇷法国`
  - current workspace UI evidence is captured at `.ohos_live_current/proxy_after_france.jpeg`
  - `hilog` shows the real core switch path:
    - `[OHOS-CORE] invoke changeProxy#... begin/done`
    - `[OHOS-CORE] invoke closeConnections#... begin/done`
  - the next runtime request batch is emitted through the new node instead of the old one:
    - `dispatch request event ... host=ipwho.is chains=🇫🇷法国 -> PROXY`
    - `dispatch request event ... host=api.myip.com chains=🇫🇷法国 -> PROXY`
    - `dispatch request event ... host=ipapi.co chains=🇫🇷法国 -> PROXY`
    - `dispatch request event ... host=ident.me chains=🇫🇷法国 -> PROXY`
    - `dispatch request event ... host=ip-api.com chains=🇫🇷法国 -> PROXY`
    - `dispatch request event ... host=api.ip.sb chains=🇫🇷法国 -> PROXY`
    - `dispatch request event ... host=ipinfo.io chains=🇫🇷法国 -> PROXY`
- Additional live verification on the current OHOS emulator confirms that proxy-group switching itself is also real and stable:
  - from the `代理` page, opening the group chooser via the top-right chevron shows a real `策略组` sheet with `auto` / `select` / `us` / `google` / `k3s-image` / `github` / `stable`
  - choosing `select` changes the active top tab immediately, and a fresh layout dump marks `select` as the selected group
  - choosing `stable` also changes the active top tab immediately, and a fresh layout dump marks `stable` as the selected group
  - current blocker is narrower than “代理页不可用”: on this emulator session, those switched groups still render only a single `COMPATIBLE / Compatible` card
  - the narrowed root cause is not a Flutter OHOS rendering problem; the live provider state itself is incomplete for the affected groups
  - emulator evidence from the current branch:
    - proxy runtime logs show the affected groups already arrive from core as a single `COMPATIBLE` candidate:
      - `auto:1[COMPATIBLE]`
      - `select:1[COMPATIBLE]`
      - `us:1[COMPATIBLE]`
      - `google:1[COMPATIBLE]`
      - `github:1[COMPATIBLE]`
      - `stable:1[COMPATIBLE]`
    - the `提供者` page on emulator shows real provider counts at the same time:
      - `bywave`: `20个条目`
      - `jisu`: `3个条目`
      - `tag`: no entry-count line is rendered, which matches the current debugging hypothesis that `tag` is empty or unresolved in the live profile state
    - direct upstream verification on June 20, 2026 confirms the failing provider itself is currently unauthorized:
      - `bywave` URL returns `HTTP 200`
      - `jisu` URL returns `HTTP 200`
      - `tag` URL `https://huaikhwang.central-world.org/api/v1/trails/bolster?...` returns `HTTP 401 Unauthorized`
    - this upgrades the earlier hypothesis into a verified root cause:
      - the imported profile's main groups depend on `tag`
      - `tag` is not merely hidden by the OHOS UI; its upstream subscription is currently invalid for this token
      - Mihomo therefore falls back to `COMPATIBLE` for those `use: [tag]` groups in the live session
    - because the main proxy groups in the imported template are bound to `tag`, the current live OHOS session collapses those groups to Mihomo's fallback candidate instead of showing the expected real nodes
  - an additional runtime nuance was verified during cold-start retesting:
    - immediately after launch, `getProxies` can transiently report only `GLOBAL`
    - a few seconds later, the full group set appears again
    - therefore, proxy/provider validation on OHOS must use the stabilized post-start state instead of the first few seconds of logs
- Relaunch persistence works:
  - after relaunch, the app returns to the normal shell
  - the bottom navigation still includes `仪表盘` / `代理` / `配置` / `工具`
  - the imported profile `极速机场` still exists
  - the `代理` page still renders the real proxy list, including nodes such as `🇫🇷法国` and `🇺🇸美国洛杉矶1号`
- Request-event verification is now stronger than a static UI screenshot:
  - after tapping start on the emulator, the OHOS core emits fresh request events for the runtime IP checks instead of only historical records
  - verified hosts in the current workspace include:
    - `api.myip.com`
    - `ident.me`
    - `ipinfo.io`
    - `ipwho.is`
    - `api.ip.sb`
    - `ipapi.co`
    - `ip-api.com`
  - matching `hilog` evidence includes:
    - `[OHOS-CORE] dispatch request event ...`
    - `[OHOS-CORE] onRequest stored ...`
  - matching dashboard evidence includes the runtime timer plus non-zero traffic such as `↑ 3.2KB / ↓ 19.8KB`
- Fresh June 22, 2026 request/runtime verification on the rebuilt package now uses the explicit `VPN=off` emulator path:
  - dashboard precondition:
    - `工具 -> 进阶配置 -> 网络 -> VPN -> off`
  - after tapping start, the rebuilt package keeps the runtime loop alive instead of falling back through the missing VPN dialog path
  - fresh `hilog` evidence on the current workspace includes:
    - `find https://ipwho.is proxy: true`
    - `find https://api.myip.com proxy: true`
    - `find https://ipapi.co/json proxy: true`
    - `find https://ident.me/json proxy: true`
    - `find https://api.ip.sb/geoip proxy: true`
    - `find https://ipinfo.io/json proxy: true`
    - `dispatch request event ... host=ipapi.co chains=🇺🇸美国洛杉矶2号 -> 极速机场`
    - `dispatch request event ... host=ip-api.com chains=🇺🇸美国洛杉矶2号 -> 极速机场`
    - `dispatch request event ... host=ident.me chains=🇺🇸美国洛杉矶2号 -> 极速机场`
    - `dispatch request event ... host=ipwho.is chains=🇺🇸美国洛杉矶2号 -> 极速机场`
    - `dispatch request event ... host=ipinfo.io chains=🇺🇸美国洛杉矶2号 -> 极速机场`
    - `dispatch request event ... host=api.myip.com chains=🇺🇸美国洛杉矶2号 -> 极速机场`
    - `dispatch request event ... host=api.ip.sb chains=🇺🇸美国洛杉矶2号 -> 极速机场`
  - current workspace UI evidence is captured at:
    - `.ohos_live_current/dashboard_after_start_vpn_off.jpeg`
- The `请求` page was re-verified on June 21, 2026 on the current `FlClash Tablet` emulator against the same live `🇫🇷法国` session:
  - the page directly renders recent request rows for:
    - `ipapi.co`
    - `ipinfo.io`
    - `api.ip.sb`
    - `ip-api.com`
    - `ident.me`
    - `api.myip.com`
  - each visible row also carries the `🇫🇷法国` tag instead of falling back to a generic placeholder
  - current workspace UI evidence is captured at `.ohos_live_current/requests_tablet.jpeg`
- The `请求` page was also freshly re-verified on June 22, 2026 on the rebuilt package and current `127.0.0.1:5555` emulator session:
  - visible rows now include:
    - `tcp://api.ip.sb/172.67.75.172:443`
    - `tcp://api.myip.com/172.67.75.163:443`
    - `tcp://ipinfo.io/34.117.59.81:443`
    - `tcp://ipwho.is/104.20.44.133:443`
    - `tcp://ident.me/65.108.151.63:443`
    - `tcp://ip-api.com/208.95.112.1:80`
  - each visible row carries the real proxy tags `🇺🇸美国洛杉矶2号` and `极速机场`
  - current workspace UI evidence is captured at:
    - `.ohos_live_current/requests_final.jpeg`
- OHOS `连接` page semantics are now explicitly verified:
  - on the current branch, `lib/views/connection/connections.dart` first polls `coreController.getConnections()`
  - when OHOS returns an empty snapshot, the page falls back to recent entries from `requestsProvider`
  - emulator evidence in this workspace confirms that these are two different paths:
    - `hilog` can show `getConnections raw={... "connections":null ...}` and `getConnections parsed count=0`
    - the `连接` page can still render rows at the same time because it is showing recent request fallback entries
  - practical testing consequence:
    - `连接` page showing rows does not by itself prove a live `Snapshot()` connection exists
    - future OHOS validation must distinguish:
      - live connection snapshots from `getConnections`
      - fallback recent-request rendering from `requestsProvider`
- The `连接` page was re-verified on June 21, 2026 on the current `FlClash Tablet` emulator:
  - the page renders the same live recent-request entries for `ipapi.co`, `ipinfo.io`, `api.ip.sb`, `ip-api.com`, `ident.me`, and `api.myip.com`
  - each visible row also carries the `🇫🇷法国` tag plus the per-row block action button
  - current workspace UI evidence is captured at `.ohos_live_current/connections_tablet.jpeg`
- The `连接` page was also freshly re-verified on June 22, 2026 on the rebuilt package and current `127.0.0.1:5555` emulator session:
  - the page renders live rows for:
    - `tcp://api.ip.sb/172.67.75.172:443`
    - `tcp://api.myip.com/172.67.75.163:443`
    - `tcp://ipinfo.io/34.117.59.81:443`
    - `tcp://ipwho.is/104.20.44.133:443`
    - `tcp://ident.me/65.108.151.63:443`
    - `tcp://ip-api.com/208.95.112.1:80`
  - each visible row carries the real proxy tags `🇺🇸美国洛杉矶2号` and `极速机场`
  - current workspace UI evidence is captured at:
    - `.ohos_live_current/connections_final.jpeg`
  - this page was freshly re-verified again later on June 22, 2026 on the rebuilt HAP and current `127.0.0.1:5555` tablet emulator session:
    - the current visible rows include:
      - `tcp://fastly.jsdelivr.net/151.101.193.229:443`
      - `udp://1.1.1.1:53`
      - `udp://8.8.8.8:53`
      - `tcp://api.ip.sb/172.67.75.172:443`
      - `tcp://api.myip.com/172.67.75.163:443`
    - each visible row still carries the real proxy tags `🇺🇸美国洛杉矶2号` and `极速机场`
    - the page also renders the real per-row block action button instead of a dead icon
    - fresh current-session evidence is captured at:
      - `.ohos_live_current/connections_page_retry3.jpeg`
  - the `连接详情` page was also freshly re-verified on the same rebuilt HAP and current tablet session:
    - opening the top `tcp://fastly.jsdelivr.net/151.101.193.229:443` row navigates to a real detail page instead of a placeholder sheet
    - the detail page rendered current row fields:
      - `进程: mihomo`
      - `网络类型: tcp`
      - `规则: Match`
      - `主机: fastly.jsdelivr.net`
      - `目标地址: 151.101.193.229:443`
      - `代理链: 🇺🇸美国洛杉矶2号 -> 极速机场`
    - fresh current-session evidence is captured at:
      - `.ohos_live_current/connection_detail_retry4.jpeg`

Latest OHOS packaging stability fix in this workspace:

- Direct `flutter build hap` is now stable again in this repository instead of failing during `ohpm install --all`
- Root cause:
  - the host OHOS package could fall back to fetching `flutter_native_arm64_v8a@latest` from `https://repo.harmonyos.com/ohpm/`
  - that remote package lookup fails in this environment and blocks packaging before hvigor can finish
- Current local build prerequisite on macOS with DevEco Studio 6.1.1:
  - use DevEco's bundled Node instead of Homebrew Node 26
  - verified command in this workspace:

```bash
export NODE_HOME=/Applications/DevEco-Studio.app/Contents/tools/node
export PATH=$NODE_HOME/bin:/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin:/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin:/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains:/Applications/DevEco-Studio.app/Contents/sdk/default/hms/toolchains:$PATH
flutter build hap --debug --target-platform ohos-arm64 --no-pub
```

Latest verified developer-mode result in this workspace on June 21, 2026:

- Emulator target: `127.0.0.1:5555`
- Crash test now uses the rebuilt OHOS core at runtime instead of the old panic path
  - verified logs:
    - `[OHOS-CORE] invoke crash#... begin`
    - `ResultCallback method=crash ... "data":true,"code":0`
    - `ResultCallback queue core event ... "type":"crash","data":"core done"`
    - `[OHOS-CORE] invoke crash#... done`
    - no `internal panic: handle invoke crash`
    - no `handle invoke crash`
  - evidence:
    - `.ohos_live_current/crash_confirm2.jpeg`
    - `.ohos_live_current/crash_after_confirm.jpeg`
- Clear Data now clears persisted developer-mode state and exits the current app session cleanly on OHOS
  - implementation notes:
    - `AppPlugin.exitApp` now calls `terminateSelf()`
    - `StoreAction.handleClear()` now clears the local profiles directory directly instead of routing through the live core `deleteFile` invoke path
    - `StoreAction.handleClear()` resets in-memory Riverpod state before exit
  - verified logs:
    - `clear preferences`
    - `[developer-mode] clear profiles dir: /data/storage/el2/base/haps/entry/files/profiles`
    - no `Invoke pre deleteFile timeout`
    - no `TimeoutException after 0:00:10.000000: Future not completed`
  - post-clear emulator verification:
    - `ps -ef | grep com.follow.clash` shows no running app process before relaunch
    - app can be started again with `aa start -a EntryAbility -b com.follow.clash`
    - `工具` page no longer shows the explicit `开发者模式` entry after relaunch, including after scrolling to the bottom of the page
    - this confirms `developerMode` persisted state was actually cleared, rather than only hidden in the current page stack
  - evidence:
    - `.ohos_live_current/clear_data_confirm_after_fix.jpeg`
    - `.ohos_live_current/after_clear_trigger.jpeg`
    - `.ohos_live_current/relaunch_after_clear.jpeg`
    - `.ohos_live_current/tools_after_relaunch_clear.jpeg`
    - `.ohos_live_current/tools_bottom_after_clear.jpeg`
- Fix applied in this branch:
  - the OHOS host package now depends on a local `ohos/har/flutter_native_arm64_v8a.har`
  - `setup.dart` now copies both Flutter engine HARs into `ohos/har/` before packaging:
    - `flutter_embedding_release.har` -> `ohos/har/flutter.har`
    - `arm64_v8a_release.har` -> `ohos/har/flutter_native_arm64_v8a.har`
- Verified result on June 20, 2026:
  - `ohpm install --all` under `ohos/` completes successfully
  - `flutter build hap --target-platform ohos-arm64 --release --no-pub --dart-define-from-file=env.json` completes successfully
  - fresh artifact path remains:
    - `ohos/entry/build/default/outputs/default/entry-default-signed.hap`

Latest QR import and page-level verification result in this workspace:

- About 页开发者模式入口在 OHOS 模拟器上已经补齐了可重复验证路径
  - 原始隐藏 5 连点逻辑仍然保留
  - 但在 OHOS 模拟器自动点击下，隐藏手势不够稳定，不适合作为持续回归入口
  - 当前分支在 `PRE + OHOS` 条件下额外提供了显式 `开发者模式` 入口，位置在 `关于 -> 更多`
  - 该入口只用于 OHOS 模拟器上的真实功能验证，不改变正式版常规入口
- 已验证的开发者模式证据
  - 启用开发者模式成功
    - 应用日志：
      - `[developer-mode] onEnterDeveloperMode invoked`
      - `[developer-mode] developerMode persisted=true`
      - `message: 开发者模式已启用。`
    - 模拟器截图/布局证据：
      - `.ohos_live/dev_enable_probe_state.jpeg`
      - `.ohos_live/tools_after_dev_enabled_final.jpeg`
      - `.ohos_live/developer_page_opened.jpeg`
  - `消息测试` 可用
    - 应用日志：`[APP] message: 这是一条消息。`
    - 证据：
      - `.ohos_live/developer_message_test.jpeg`
      - `.ohos_live/developer_message_test.json`
  - `日志测试` 可用
    - 触发后日志流持续写入，说明开发者页日志注入逻辑可运行
    - 证据：
      - `.ohos_live/developer_logs_test.jpeg`
      - `.ohos_live/developer_logs_test.json`
  - `导入二维码测试图到图库` 可用
    - 首次点击会触发系统图库写入授权弹窗
    - 授权后应用日志确认写入成功：
      - `[APP] [ohos-qr] importQrTestImage path=... prepared=... imported=file://media/.../flclash_qr_test.png`
      - `[APP] message: 已导入图库`
    - 页面 toast 也显示 `已导入图库`
    - 证据：
      - `.ohos_live/developer_import_qr_gallery.jpeg`
      - `.ohos_live/developer_import_qr_gallery_allowed.jpeg`
  - `修剪缓存` 可用
    - 真实逻辑已确认走 `storeActionProvider.shakingStore()`
    - 当前模拟器上已拿到完整成功证据链：
      - `[developer-mode] shakingStore start`
      - `[developer-mode] shakingStore done`
      - `[developer-mode] prune cache success`
      - `message: 缓存修剪完成`
    - 页面成功提示证据：
      - `.ohos_live_current/developer_after_prune2.jpeg`
- 当前 `FlClash Tablet` 会话已再次补齐开发者模式链路证据
  - 从 `关于 -> 开发者模式` 启用后，当前日志再次确认真实写入而不是静态入口：
    - `[developer-mode] onEnterDeveloperMode invoked`
    - `[developer-mode] developerMode persisted=true`
    - `[APP] message: 开发者模式已启用。`
  - 启用后回到 `关于`，原先的 `开发者模式` 显式入口会立即消失，说明它确实受持久化状态控制：
    - 当前 workspace 证据：`.ohos_live_current/about_after_close_update_dialog_tablet.jpeg`
  - 回到 `工具` 后会出现真实的 `开发者模式` 条目，而不是样例卡片：
    - 当前 workspace 证据：`.ohos_live_current/tools_with_developer_item_tablet.jpeg`
  - 打开后能进入真实 `开发者模式` 页面，页面包含可交互条目：
    - `消息测试`
    - `日志测试`
    - `导入二维码测试图到图库`
    - `崩溃测试`
    - `清除数据`
    - `修剪缓存`
    - 当前 workspace 证据：`.ohos_live_current/developer_page_tablet.jpeg`
  - `消息测试` 也在当前 tablet 会话中再次验证通过：
    - `hilog` shows `[APP] message: 这是一条消息。`
    - UI toast is visible at `.ohos_live_current/developer_message_test_retry_tablet.jpeg`
  - `崩溃测试` 现在也拿到真实运行证据：
    - tapping the row opens the real confirmation dialog `确定要强制崩溃核心？`
    - current workspace dialog evidence is captured at `.ohos_live_current/developer_crash_dialog.jpeg`
    - confirming the action invokes the live core crash path instead of a placeholder no-op:
      - `[OHOS-CORE] invoke crash#... begin/done`
      - `ResultCallback method=crash ... "data":true`
      - `message: core done`
      - `[OHOS-CORE] shutdown begin`
      - `[OHOS-CORE] shutdown done result=true`
    - practical behavior on the current branch:
      - the action shuts down the running Clash core and event polling
      - the Flutter shell remains in the developer page, so this is a core-crash tool rather than a full app-process kill
    - current workspace post-action evidence is captured at `.ohos_live_current/after_crash_confirm.jpeg`
  - `清除数据` 现在也拿到真实 destructive-flow 证据：
    - tapping the row opens the real confirmation dialog `确定要清除所有数据？`
    - current workspace dialog evidence is captured at `.ohos_live_current/developer_clear_dialog.jpeg`
    - confirming the action clears persisted state and exits the app:
      - `[APP] clear preferences`
      - `[developer-mode] clear profiles dir: /data/storage/el2/base/haps/entry/files/profiles`
      - `[profile-select-core] currentProfileId changed prev=... next=null`
      - `exit`
      - `AppLifecycleState.detached`
    - after the action, the system returns to the launcher instead of staying in FlClash
    - current workspace exit evidence is captured at `.ohos_live_current/after_clear_confirm.jpeg`
    - relaunching FlClash then shows the real empty `配置` page `没有配置文件,请先添加配置文件`, proving the profile store was actually cleared
    - current workspace empty-state evidence is captured at:
      - `.ohos_live_current/app_after_clear_restart.jpeg`
      - `.ohos_live_current/config_after_clear.jpeg`
    - the baseline was then restored in the same session through the already-verified deep-link import flow:
      - `flclash://install-config?url=http%3A%2F%2F10.0.2.2%3A19002%2Fjisu`
      - current workspace restore evidence is captured at:
        - `.ohos_live_current/after_restore_deeplink_prompt2.jpeg`
        - `.ohos_live_current/after_restore_deeplink_done2.jpeg`
      - `hilog` confirms the real restore path:
        - `[AppPlugin] setPendingLink=flclash://install-config?url=http%3A%2F%2F10.0.2.2%3A19002%2Fjisu`
        - `[ohos-profile-url] addProfileFormURL success: ... label=10.0.2.2`
- 当前开发者模式条目已经全部拿到真实可用证据

## Verified DevEco 6.1.1 path findings in this workspace

- `flutter config --ohos-sdk` 需要指向：

```text
/Applications/DevEco-Studio.app/Contents/sdk/default
```

- DevEco Studio 6.1.1 下，本机实际工具路径为：

```text
/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin/ohpm
/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw
/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc
```

- Opening `ohos/` directly in DevEco Studio 6.1.1 on June 23, 2026 initially failed during `Build Init` with:
  - `ERR_PNPM_NO_MATCHING_VERSION No matching version found for @ohos/hvigor-ohos-plugin@6.22.4`
  - this was not an SDK-path failure; `ohos/local.properties` already pointed at the existing DevEco SDK under `/Applications/DevEco-Studio.app/Contents/sdk/default`
  - root cause: DevEco's direct sync path invokes its bundled `hvigorw.js --sync` instead of the repository `ohos/hvigorw` wrapper, so it tried to install the version pinned in `ohos/hvigor/hvigor-config.json5`
  - fix: `ohos/hvigor/hvigor-config.json5` now pins `@ohos/hvigor-ohos-plugin` to `6.24.2`, matching the bundled DevEco 6.1.1 `@ohos/hvigor` / `@ohos/hvigor-ohos-plugin` version and an available Harmony npm version
  - verification:
    - `cd ohos && /Applications/DevEco-Studio.app/Contents/tools/node/bin/node /Applications/DevEco-Studio.app/Contents/tools/hvigor/bin/hvigorw.js --sync -p product=default --analyze=normal --parallel --incremental --no-daemon`
    - exits `0`

- 当前 workspace 已确认以下构建命令可重新产出最新签名 HAP：

```bash
export PATH=/Applications/DevEco-Studio.app/Contents/tools/ohpm/bin:/Applications/DevEco-Studio.app/Contents/tools/hvigor/bin:/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains:/Applications/DevEco-Studio.app/Contents/sdk/default/hms/toolchains:$PATH
$HOME/.local/ohos-flutter-3.35.7/bin/flutter build hap --target-platform ohos-arm64 --release --no-pub --dart-define-from-file=env.json
```

- 当前 workspace 再次验证成功的 HAP 路径仍然是：

```text
ohos/entry/build/default/outputs/default/entry-default-signed.hap
```

- Emulator target: `127.0.0.1:5555`
- QR profile import now works end to end against a real subscription QR image:
  - 首次执行 `导入二维码测试图到图库` 时，系统会弹出图库写入授权：
    - `允许“FlClash”保存 1 张图片？`
  - 授权后测试图真实写入系统图库：
    - `[ohos-qr] tools importQrTestImage path=/data/storage/el2/base/haps/entry/temp/jisu_qr_test.png prepared=/data/storage/el2/base/haps/entry/files/flclash_qr_test.png imported=file://media/Photo/.../flclash_qr_test.png`
  - 扫码入口在当前 OHOS 模拟器会话里走系统文件选择器，选中 `jisu_qr_test_10694.png`
  - OHOS 文件访问真实读到了图片字节：
    - `[ohos-qr] pickerConfigQRCode pickerState=read:read-bytes-success:path=/data/storage/el2/base/haps/entry/files/picked_file.tmp:size=1133`
    - `[ohos-qr] pickerConfigQRCode picked=jisu_qr_test_10694.png path= bytes=1133`
  - bundled Go core 真实解码出订阅 URL：
    - `[ohos-qr] pickerConfigQRCode rawResult=https://<subscription-host>/api/v1/client/subscribe?token=...`
    - `[ohos-qr] pop scan page with url=https://<subscription-host>/api/v1/client/subscribe?token=...`
  - Flutter 提交后真实完成 URL 导入与 profile 落库：
    - `[ohos-profile-url] addProfileFormURL start: https://<subscription-host>/api/v1/client/subscribe?token=...`
    - `getFileResponseForUrl done direct=true status=200 bytes=12344`
    - `[profile-save] success id=327027083228221440 target=/data/storage/el2/base/haps/entry/files/profiles/327027083228221440.yaml`
    - `[ohos-profile-url] addProfileFormURL success: id=327027083228221440 type=url label=<subscription-host>`
  - UI evidence:
    - the `配置` page shows a newly imported profile card `<subscription-host>(1)`
- The imported QR profile also drives real proxy data instead of placeholder content:
  - selecting the new profile triggers a real core re-setup instead of a UI-only selection:
    - `[profile-select-core] currentProfileId changed prev=327023262250831872 next=327027083228221440`
    - `[setup-profile] profile=327027083228221440 ua=clash.meta/1.10.0 providers=`
    - `[profile-select-core] fullSetup end prev=327023262250831872 next=327027083228221440 applied=true current=327027083228221440`
  - the controller now exposes real proxy nodes instead of placeholder content:
    - `DIRECT`
    - `REJECT`
    - `🇺🇸美国洛杉矶1号`
    - `🇺🇸美国洛杉矶2号`
    - `🇫🇷法国`
  - real proxy traffic also closes the loop on the same profile:
    - local proxy request returns a public IP: `108.181.24.53`
    - request logs show the actual chain, for example:
      - `host=api.myip.com chains=🇺🇸美国洛杉矶1号 -> PROXY`
      - `host=ipwho.is chains=🇺🇸美国洛杉矶1号 -> PROXY`
- Additional page-level verification on the same emulator:
  - `仪表盘` renders real network state, including an observed public IP `183.23.158.31`
  - `资源` renders real resource metadata and URLs for `GEOIP`, `GEOSITE`, `MMDB`, and `ASN`
  - `资源 -> GEOIP -> 同步` is now verified end to end:
    - the UI immediately updates the timestamp from `4 小时前` to `刚刚`
    - the local file metadata changes as expected, for example `19.6MB` -> `18MB`
    - the OHOS core path executes the real update and file-poll completion logic:
      - `[OHOS-CORE] invoke updateGeoData#... begin/done`
      - `[OHOS-CORE] geo data updated file=GEOIP.dat before=... after=...`
  - this `GEOIP` sync path was freshly re-verified again on June 22, 2026 on the rebuilt HAP and current `127.0.0.1:5555` tablet emulator session:
    - the pre-sync row showed the stale state:
      - `19.6MB · 21 小时前`
    - after tapping `同步`, the same row updated to:
      - `18MB · 刚刚`
    - fresh current-session evidence is captured at:
      - `.ohos_live_current/resources_page_current.jpeg`
      - `.ohos_live_current/resources_after_sync.jpeg`
    - fresh `hilog` evidence on the same session shows:
      - `[APP] [OHOS-CORE] geo data updated file=GEOIP.dat before=2026-06-21 15:53:16.000 after=2026-06-22 13:44:59.000`
  - the detached OHOS immediate-success payload is now normalized to `code:0` instead of the old `code:"success"`
    - this removes the previous false-positive parse error during detached actions such as `updateGeoData`
  - `请求` and `连接` are now verified with real captured traffic after the dashboard start button is enabled on the emulator
  - Root cause of the earlier empty-state result:
    - the app was in the stopped state, so `FlClashHttpOverrides.handleFindProxy()` returned `DIRECT`
    - the filtered log showed `find https://example.com proxy: false`
    - once the dashboard run state was started, the filtered log switched to `find https://ipwho.is proxy: true`
  - With the app running, the OHOS core now emits real request tracker events:
    - `[OHOS-CORE] request event payload=... host: api.myip.com ... inboundName: DEFAULT-MIXED ...`
    - `[OHOS-CORE] request event payload=... host: ipwho.is ...`
  - UI verification on the same emulator:
    - `仪表盘` shows the running state and timer, for example `00:00:02`
    - `Requests` opens into a real detail page for captured proxy traffic, including fields such as:
      - `Host: api.myip.com`
      - `Source: 127.0.0.1:56606`
      - `Destination: 172.67.75.163:443`
      - `Rule: Match`
      - `Remote destination: 108.181.24.53`
      - `Proxy chains: 剩余流量：2.93 TB -> 自动选择`
    - `Connections` on the current emulator route also resolves to the same recent captured request detail view, confirming the mobile fallback path is populated by real data instead of placeholder content
  - `日志` is now verified with real captured entries instead of placeholder or empty-state content:
    - enabling `应用程序 -> 日志捕获` causes the OHOS core manager to invoke real log capture startup:
      - `[OHOS-CORE] invoke startLog ... begin`
      - `[OHOS-CORE] invoke startLog ... done`
    - after enabling the switch, the `工具` page shows a real `日志` entry
    - opening `日志` renders live captured rows such as:
      - `[APP] [OHOS-CORE] invoke getTraffic#... done`
      - `[APP] [OHOS-CORE] invoke getTotalTraffic#... begin`
      - `[APP] [OHOS-CORE] invoke getTotalTraffic#... done`
    - each row also renders the real log level chip and timestamp, for example:
      - `info`
      - `2026-06-19 03:37:46`
    - this was re-verified again on June 21, 2026 on the current `FlClash Tablet` emulator:
      - the current tablet session shows `应用程序 -> 日志捕获` toggled on at `.ohos_live_current/app_setting_logs_enabled_tablet.jpeg`
      - enabling the switch immediately triggers the live core path again:
        - `[OHOS-CORE] invoke startLog#... begin`
        - `[OHOS-CORE] invoke startLog#... done`
      - after returning to `工具`, the real `日志` entry is visible again in the current workspace at `.ohos_live_current/tools_logs_visible2_tablet.jpeg`
    - `日志 -> 导出` is now also re-verified end to end on the current tablet session:
      - the page shows a real success dialog with `导出成功`
      - OHOS native-side write evidence confirms the log file was written to the shared download directory:
        - `[AppPlugin] lastFilePickerState=sharedDownload:written:uri=file://docs/storage/Users/currentUser/Download/FlClash_2026-06-21.log:path=/storage/Users/currentUser/Download/FlClash_2026-06-21.log:size=2960:stat=2960`
      - this verification also closed a real OHOS bug on the branch:
        - the old generic `FilePicker.saveFile(...)` path failed with `PlatformException(13900002, No such file or directory)`
        - the current branch now routes OHOS log export through the same `writeFileToSharedDownload` path already proven by profile export and local backup export
      - opening `日志` renders current-session live rows instead of an empty placeholder page, for example:
        - `[APP] [OHOS-CORE] invoke getTotalTraffic#... done`
        - `[APP] [OHOS-CORE] invoke getTraffic#... begin`
        - `info`
        - `2026-06-21 07:50:20`
      - current workspace log-page evidence is captured at `.ohos_live_current/logs_tablet.jpeg`
    - this path was freshly re-verified again on June 22, 2026 on the rebuilt HAP and current `127.0.0.1:5555` tablet emulator session:
      - root cause of the temporarily missing `日志` entry was confirmed to be product configuration, not OHOS rendering failure:
        - `应用程序 -> 日志捕获` controls whether `工具` shows the `日志` navigation item
      - on the current session, enabling `应用程序 -> 日志捕获` restored the real `工具 -> 日志` entry immediately
      - fresh current-session evidence is captured at:
        - `.ohos_live_current/app_setting_logs_enabled.jpeg`
        - `.ohos_live_current/tools_top_after_open_logs.jpeg`
        - `.ohos_live_current/logs_page_current.jpeg`
      - opening `日志` then rendered live current-session rows such as:
        - `[APP] [OHOS-CORE] invoke getTotalTraffic#... done`
        - `[APP] [OHOS-CORE] invoke getTotalTraffic#... begin`
        - `[APP] [OHOS-CORE] invoke getTraffic#... done`
      - the same page also rendered the real level chip and timestamp on the current session:
        - `info`
        - `2026-06-22 13:51:46`
      - `日志 -> 导出` was also freshly re-verified on the same rebuilt HAP and current tablet session:
        - the page showed the real success dialog:
          - `提示`
          - `导出成功`
        - fresh current-session UI evidence is captured at:
          - `.ohos_live_current/logs_export_success_attempt2.jpeg`
        - fresh OHOS native-side write evidence confirms the file was really written to the shared download directory:
          - `[AppPlugin] lastFilePickerState=sharedDownload:written:uri=file://docs/storage/Users/currentUser/Download/FlClash_2026-06-22.log:path=/storage/Users/currentUser/Download/FlClash_2026-06-22.log:size=138999:stat=138999`
  - `应用程序` settings are now verified with real side effects and persistence instead of only page-open evidence:
    - opening `应用程序` renders real switches such as:
      - `退出时最小化`
      - `自动运行`
      - `选项卡动画`
      - `日志捕获`
      - `自动关闭连接`
      - `仅统计代理`
      - `自动检查更新`
    - disabling `日志捕获` immediately triggers the real core stop-log path:
      - `[OHOS-CORE] invoke stopLog ... begin`
      - `[OHOS-CORE] invoke stopLog ... done`
    - after disabling the switch, the `工具` page really hides the `日志` entry instead of leaving a dead route behind
    - reopening `应用程序` shows `日志捕获` still in the disabled state, confirming the setting persists across navigation
    - re-enabling the same switch immediately restores the real core startup path and the `工具 -> 日志` entry:
      - `[OHOS-CORE] invoke startLog ... begin`
      - `[OHOS-CORE] invoke startLog ... done`
  - The `应用程序` page was re-verified on June 21, 2026 on the current `FlClash Tablet` emulator:
    - the page renders the same real switch list instead of a placeholder screen, including:
      - `退出时最小化`
      - `自动运行`
      - `选项卡动画`
      - `日志捕获`
      - `自动关闭连接`
      - `仅统计代理`
      - `自动检查更新`
    - current workspace UI evidence before mutation is captured at `.ohos_live_current/app_setting_tablet.jpeg`
    - `自动检查更新` was toggled from on to off on the current tablet session
    - after leaving and reopening `应用程序`, the same `自动检查更新` toggle remained off, confirming persistence across navigation
    - current workspace UI evidence after the reopen check is captured at `.ohos_live_current/app_setting_reopen_tablet.jpeg`
    - on the rebuilt June 22, 2026 HAP, `自动检查更新` is now also verified with real startup-request behavior instead of only switch persistence:
      - opening `应用程序` on the rebuilt app shows the real `自动检查更新` toggle in the enabled state
      - current workspace enabled-state evidence is captured at `.ohos_live_current/auto_update_reenable_settings.jpeg`
      - after tapping the real `Toggle`, the same control renders `checked=false`
      - current workspace disabled-state evidence is captured at `.ohos_live_current/auto_update_retry_after_toggle2.jpeg`
      - after `aa force-stop com.follow.clash` + relaunch with a clean `hilog` buffer, startup logs show:
        - `[auto-check-update] enabled=false`
        - `[auto-check-update] skip request`
      - this confirms the disabled state suppresses the GitHub request instead of only changing UI chrome
      - tapping the same `Toggle` again restores the enabled state
      - current workspace re-enabled-state evidence is captured at `.ohos_live_current/auto_update_reenable_after_toggle.jpeg`
      - after another force-stop + relaunch with a clean log buffer, startup logs return to the real request path:
        - `[auto-check-update] enabled=true`
        - `[auto-check-update] request start`
        - `[check-update] request start url=https://api.github.com/repos/chen08209/FlClash/releases/latest`
        - `[check-update] response status=200`
        - `[check-update] compare local=0.8.93 remote=v0.8.93 hasUpdate=false`
        - `[auto-check-update] request done status=upToDate`
      - this confirms `自动检查更新` is a real runtime control on the rebuilt tablet HAP, not only a persisted switch
    - `选项卡动画` is now also verified with real navigation behavior instead of only by switch rendering:
      - on the current tablet session, opening `应用程序` initially rendered `选项卡动画` as enabled
      - current workspace enabled-state evidence is captured at `.ohos_live_current/app_settings_tab_anim.jpeg`
      - after a clean-slate log buffer and a real bottom-tab switch from `工具` back to `仪表盘`, `hilog` recorded the animated path:
        - `[APP] [tab-nav] toPage label=dashboard index=0 animate=true isMobile=true ignore=false`
        - `[APP] [tab-nav] animateToPage done label=dashboard`
      - the switch was then turned off on the same page
      - current workspace disabled-state evidence is captured at `.ohos_live_current/app_settings_tab_anim_off.jpeg`
      - after repeating the same clean-slate `工具 -> 仪表盘` tab switch, `hilog` recorded the non-animated path:
        - `[APP] [tab-nav] toPage label=dashboard index=0 animate=false isMobile=true ignore=false`
        - `[APP] [tab-nav] jumpToPage done label=dashboard`
      - this confirms the setting is wired to the real `PageView` navigation path on OHOS instead of being a dead UI-only toggle
    - `自动运行` is now also verified end to end on the same tablet session instead of only by switch rendering:
      - the switch was turned on in the real `应用程序` page
      - current workspace enabled-state evidence is captured at `.ohos_live_current/app_settings_autorun_on2.jpeg`
      - with the setting enabled, the currently running dashboard session was manually stopped first to establish a clean baseline:
        - the dashboard returned to the real stopped state with the play button visible
        - current workspace stopped-state evidence is captured at `.ohos_live_current/dashboard_after_manual_stop_for_autorun2.jpeg`
        - `hilog` shows the explicit stop path:
          - `[OHOS-CORE] invoke stopListener#... begin/done`
          - `[OHOS-CORE] invoke resetTraffic#... begin/done`
      - after `aa force-stop com.follow.clash` and a fresh `aa start -a EntryAbility -b com.follow.clash`, the app cold-started back into the running state without any manual dashboard tap:
        - current workspace cold-start evidence is captured at `.ohos_live_current/dashboard_after_autorun_cold_start.jpeg`
        - the dashboard runtime had already advanced to `00:00:09`
        - the dashboard also resumed real proxy traffic and restored the live egress IP `141.145.196.11`
      - matching cold-start `hilog` evidence confirms this was the app-init path rather than a manual start:
        - `[APP] init status`
        - `[OHOS-CORE] invoke startListener#... begin`
        - `[OHOS-CORE] invoke startListener#... done`
        - fresh runtime requests were then emitted for `ipwho.is`, `api.myip.com`, `api.ip.sb`, and `ipinfo.io` through `🇫🇷法国 -> PROXY`
      - after verification, `自动运行` was switched back off to restore the current-session baseline state
      - current workspace restored-state evidence is captured at `.ohos_live_current/app_settings_autorun_restored_off2.jpeg`
    - `自动关闭连接` is now also verified with a real behavioral difference instead of only by switch rendering:
      - baseline state rendered the switch as enabled
      - current workspace baseline evidence is captured at `.ohos_live_current/close_conn_baseline.jpeg`
      - after turning the switch off, the `应用程序` page persisted the disabled state
      - current workspace disabled-state evidence is captured at `.ohos_live_current/close_conn_off.jpeg`
      - with the switch disabled, the `代理` page was used to switch from `🇫🇷法国` to `🇺🇸美国洛杉矶1号`
      - current workspace proxy-state evidence before the switch is captured at `.ohos_live_current/proxy_before_switch_closeconn_off.jpeg`
      - current workspace proxy-state evidence after the switch is captured at `.ohos_live_current/proxy_after_switch_closeconn_off.jpeg`
      - the corresponding clean-slate `hilog` shows only the proxy-change path:
        - `[OHOS-CORE] invoke changeProxy#... begin/done`
        - no `closeConnections` call was emitted in that disabled-state switch
      - after turning `自动关闭连接` back on, the `应用程序` page again rendered the switch as enabled
      - current workspace restored-state evidence is captured at `.ohos_live_current/close_conn_on_restored.jpeg`
      - with the switch re-enabled, switching back from `🇺🇸美国洛杉矶1号` to `🇫🇷法国` restored the original close-on-switch behavior
      - current workspace proxy-state evidence after the enabled-state switch is captured at `.ohos_live_current/proxy_after_switch_closeconn_on.jpeg`
      - the corresponding clean-slate `hilog` now shows both paths again:
        - `[OHOS-CORE] invoke changeProxy#... begin/done`
        - `[OHOS-CORE] invoke closeConnections#... begin/done`
    - `仅统计代理` is now also verified with a real direct-traffic filtering difference instead of only by switch rendering:
      - with the switch disabled, the same `直连` dashboard session already showed that direct traffic was counted into the visible traffic widget
      - current workspace disabled-state runtime evidence is captured at `.ohos_live_current/direct_mode_onlyproxy_off_running2.jpeg`
      - in that disabled-state run, the dashboard had already advanced to `00:00:36` and the traffic widget showed non-zero totals `↑ 1.4 KB / ↓ 7 KB`
      - after turning the switch on, the `应用程序` page persisted the enabled state
      - current workspace enabled-state evidence is captured at `.ohos_live_current/app_settings_onlyproxy_on.jpeg`
      - with the dashboard kept in `直连` mode and a clean-slate `hilog`, starting the session again still produced a real running state instead of a fake idle screen
      - current workspace enabled-state runtime evidence is captured at `.ohos_live_current/direct_mode_onlyproxy_on_running2.jpeg`
      - in that enabled-state run, the dashboard advanced to `00:00:13` while the traffic widget remained `↑ 0 B / ↓ 0 B`
      - the corresponding clean-slate `hilog` confirms that real direct requests still happened in that enabled-state run:
        - `[OHOS-CORE] invoke startListener#... begin/done`
        - `api.myip.com`, `ident.me`, `ip-api.com`, `ipwho.is`, `api.ip.sb`, and `ipinfo.io`
        - every captured request was emitted with `chains: [DIRECT]`
      - the same enabled-state `hilog` also shows repeated counter reads still returning zeros:
        - `[OHOS-CORE] invoke getTraffic#...` -> `{"down":0,"up":0}`
        - `[OHOS-CORE] invoke getTotalTraffic#...` -> `{"down":0,"up":0}`
      - after verification, `仅统计代理` was switched back off to restore the current-session baseline state
      - current workspace restored-state evidence is captured at `.ohos_live_current/app_settings_onlyproxy_restored_off.jpeg`
    - `退出时最小化` is now also verified with a real foreground/background behavior difference on the same tablet session:
      - the OHOS host implementation now uses the official `UIAbilityContext.moveAbilityToBackground()` path instead of launching a synthetic `home` want
      - with the switch enabled, pressing the system `Back` key from the dashboard root moves FlClash to the launcher while keeping the process alive
      - current workspace enabled-state evidence is captured at:
        - `.ohos_live_current/exitmin_app_settings_fixed.jpeg`
        - `.ohos_live_current/exitmin_on_dashboard_before_back_fixed.jpeg`
        - `.ohos_live_current/exitmin_on_after_back_fixed.jpeg`
      - matching runtime evidence on the same run shows:
        - `[AppPlugin] moveTaskToBack success`
        - `ps -ef` still contains `com.follow.clash`
      - with the switch disabled, pressing the same `Back` key path still returns to the launcher, but the FlClash process exits instead of remaining resident
      - current workspace disabled-state evidence is captured at:
        - `.ohos_live_current/exitmin_off_settings_fixed.jpeg`
        - `.ohos_live_current/exitmin_off_dashboard_before_back_fixed.jpeg`
        - `.ohos_live_current/exitmin_off_after_back_fixed.jpeg`
      - matching runtime evidence on the disabled-state run shows `ps -ef` no longer contains `com.follow.clash`
  - `主题` is now verified with real UI state changes on the same emulator:
    - opening `主题` renders the real theme controls instead of a stub page, including:
      - `主题模式`
      - `自动`
      - `浅色`
      - `深色`
      - `主题色彩`
      - `内容主题`
      - `纯黑模式`
      - `文本缩放`
    - switching from `深色` to `浅色` visibly changes the entire page background and component styling to the light theme
    - switching back from `浅色` to `深色` restores the dark theme, confirming the control is a real reversible preference rather than static sample UI
    - current tablet-session evidence is now captured at:
      - `.ohos_live_current/theme_dark_tablet.jpeg`
      - `.ohos_live_current/theme_light_tablet.jpeg`
      - `.ohos_live_current/theme_back_dark_tablet.jpeg`
    - `主题色彩 -> 内容主题` is now also verified with a real reversible persistence path on the current tablet session:
      - opening the current button shows the full `配色方案` selector dialog with real options such as `调性点缀`、`高保真`、`单色`、`中性`、`活力`、`表现力`、`内容主题`、`彩虹`、`果缤纷`
      - current workspace dialog evidence is captured at `.ohos_live_current/theme_scheme_dialog.jpeg`
      - selecting `单色` immediately changes the page button label from `内容主题` to `单色`
      - current workspace changed-state evidence is captured at `.ohos_live_current/theme_scheme_monochrome.jpeg`
      - leaving and reopening `主题` keeps the same `单色` label, confirming persistence across navigation
      - current workspace reopen evidence is captured at `.ohos_live_current/theme_scheme_reopen_monochrome.jpeg`
      - selecting `内容主题` again restores the default scheme label on the page
      - current workspace restored-state evidence is captured at `.ohos_live_current/theme_scheme_restored_content.jpeg`
    - `纯黑模式` is now also verified with a real reversible persistence path on the current tablet session:
      - baseline state shows the `纯黑模式` toggle disabled while the page background remains the normal dark theme
      - current workspace baseline evidence is captured at `.ohos_live_current/theme_page_now2.jpeg`
      - after turning the switch on, the same page background changes from dark gray to visually pure black and the toggle state becomes checked
      - current workspace enabled-state evidence is captured at `.ohos_live_current/theme_pureblack_on.jpeg`
      - leaving and reopening `主题` keeps the toggle enabled, confirming persistence across navigation
      - current workspace reopen-on evidence is captured at `.ohos_live_current/theme_pureblack_reopen_on.jpeg`
      - after switching it back off, the page returns to the normal dark theme and the toggle returns to unchecked
      - current workspace restored-state evidence is captured at `.ohos_live_current/theme_pureblack_restored_off.jpeg`
      - reopening `主题` again keeps the restored disabled state
      - current workspace reopen-off evidence is captured at `.ohos_live_current/theme_pureblack_reopen_off.jpeg`
    - `文本缩放` is now also verified as a real adjustable preference on the current tablet session:
      - baseline state renders the row disabled with the default display around `100%`
      - current workspace baseline evidence is captured at `.ohos_live_current/theme_page_now2.jpeg`
      - after enabling the switch and tapping the slider track, the page updates to a larger text-scale value `136%`
      - current workspace changed-state evidence is captured at `.ohos_live_current/theme_textscale_on_changed.jpeg`
      - leaving and reopening `主题` keeps the switch enabled and preserves the same enlarged value `136%`, confirming persistence across navigation
      - current workspace reopen-on evidence is captured at `.ohos_live_current/theme_textscale_reopen_on.jpeg`
      - after verification, the switch was turned back off to restore the current-session baseline behavior
      - current workspace restored-off evidence is captured at `.ohos_live_current/theme_textscale_final_off.jpeg`
  - `语言` is now verified with a real options dialog:
    - opening `工具 -> 语言` shows a real selector dialog titled `语言`
    - the dialog renders the actual available choices:
      - `默认`
      - `英语`
      - `日语`
      - `俄语`
      - `中文简体`
    - selecting `英语` immediately switches the live `工具` page into English, including:
      - `Tools`
      - `Settings`
      - `Language`
      - `English`
      - `Dashboard / Proxies / Profiles / Tools`
    - reopening the selector in that state shows the real English options dialog with `English` selected:
      - `Default`
      - `English`
      - `Japanese`
      - `Russian`
      - `Simplified Chinese`
    - switching back to `Default` restores the page to Chinese, confirming the locale selector is a real reversible setting instead of a static dialog
    - current tablet-session evidence is now captured at:
      - `.ohos_live_current/tools_en_tablet.jpeg`
      - `.ohos_live_current/language_dialog_en_tablet.jpeg`
      - `.ohos_live_current/tools_back_default_tablet.jpeg`
  - `工具 -> 写入 WebDAV 测试配置` is now verified with a real downstream effect:
    - tapping the action shows the success toast `已写入 WebDAV 测试配置`
    - reopening `备份与恢复` afterwards shows the prefilled remote WebDAV account instead of the empty bind state, including:
      - `flclash`
      - `文件 backup.zip`
      - the emulator test endpoint now uses `http://127.0.0.1:19000/`, reached via `hdc rport tcp:19000 tcp:19000`
      - a green `连通性` indicator requires the host WebDAV test server to be running before launch
  - `备份与恢复` is now verified with real file and WebDAV side effects instead of only page-open evidence:
    - local backup writes a real archive into the shared download directory:
      - native/runtime evidence shows `writeFileToSharedDownload` returning `file://docs/storage/Users/currentUser/Download/FlClash_backup_2026-06-21.zip`
      - the success dialog is captured again in the current workspace state at `.ohos_live_current/after_local_backup.jpeg`
    - WebDAV backup uploads a real archive to the host-side test server:
      - before backup, `.ohos_webdav/data/FlClash/backup.zip` was the older host file
      - after backup, the same file's mtime and size changed, confirming a real remote overwrite instead of a stub toast
      - matching runtime evidence includes:
        - `[backup-action] backup start`
        - `[dav-client] backup start local=... remote=/FlClash/backup.zip`
        - `[dav-client] backup success remote=/FlClash/backup.zip`
      - the success dialog is captured at `.ohos_live_current/after_webdav_backup.jpeg`
    - WebDAV restore also completes end to end on the emulator:
      - runtime evidence includes:
        - `[dav-client] restore start remote=/FlClash/backup.zip`
        - `[dav-client] restore success remote=/FlClash/backup.zip local=/data/storage/.../backup.zip`
        - `[restore-task] archive decoded files=6`
        - `[restore-task] database migration completed`
      - the success dialog is captured at `.ohos_live_current/after_webdav_restore_only_config.jpeg`
    - local restore is now backed by both the real file picker and a captured success state:
      - the document picker lists the actual shared-download files, including `FlClash_backup_2026-06-21.zip`
      - selecting that archive triggers the live restore pipeline instead of a placeholder callback:
        - `[restore-local] picked file name=FlClash_backup_2026-06-21.zip`
        - `[zip-verify] restore picked archive entries=6`
        - `[restore-local] start restore option=onlyProfiles`
        - `[restore-task] archive decoded files=6`
        - `[restore-task] database migration completed`
      - picker evidence is captured at `.ohos_live_current/local_restore_picker_now.jpeg`
      - the current success dialog is captured at `.ohos_live_current/after_local_restore_success.jpeg`
  - The `备份与恢复` page was re-verified on June 21, 2026 on the current `FlClash Tablet` emulator:
    - the page renders the real local backup / restore actions instead of a dead route:
      - `备份`
      - `恢复`
      - `恢复策略`
    - current workspace page evidence is captured at `.ohos_live_current/backup_tablet_page.jpeg`
    - local backup again writes a real archive into the shared download directory on the current tablet session:
      - `hilog` shows:
        - `[backup-local] start backup action`
        - `[backup-action] backup done path=/data/storage/.../backup-....zip`
        - `[AppPlugin] lastFilePickerState=sharedDownload:written:uri=file://docs/storage/Users/currentUser/Download/FlClash_backup_2026-06-21.zip:path=/storage/Users/currentUser/Download/FlClash_backup_2026-06-21.zip:size=5206:stat=5206`
        - `[backup-local] writeFileToSharedDownload result: file://docs/storage/Users/currentUser/Download/FlClash_backup_2026-06-21.zip`
      - current workspace success dialog is captured at `.ohos_live_current/backup_local_tablet_result.jpeg`
    - local restore is also re-verified on the same tablet session using that freshly written archive:
      - the system picker opens directly into `下载` and lists `FlClash_backup_2026-06-21.zip` as a real selectable file
      - current workspace picker evidence is captured at `.ohos_live_current/restore_picker_tablet.jpeg`
      - selecting the archive and restoring profiles succeeds end to end:
        - `[restore-local] picked file name=FlClash_backup_2026-06-21.zip ... bytes=5206`
        - `[zip-verify] restore picked archive entries=3 [database.sqlite:file, config.json:file, profiles/326846172478050304.yaml:file]`
        - `[restore-task] archive decoded files=3`
        - `[restore-task] database migration completed`
        - `[restore-local] restore finished option=onlyProfiles`
      - current workspace success dialog is captured at `.ohos_live_current/restore_after_pick_tablet.jpeg`
  - `工具 -> 导出二维码测试图到文件` is now verified with native-side write evidence on the same emulator:
    - the UI action does not visibly navigate away on the `phone` emulator, but the OHOS plugin reports a completed shared-download write
    - captured native/runtime evidence:
      - `[APP] [ohos-qr] tools exportQrTestImage start`
      - `[AppPlugin] lastFilePickerState=sharedDownload:written:uri=file://docs/storage/Users/currentUser/Download/jisu_qr_test_10694.png:path=/storage/Users/currentUser/Download/jisu_qr_test_10694.png:size=1133:stat=1133`
      - `[APP] [ohos-qr] tools exportQrTestImage path=/data/storage/el2/base/haps/entry/temp/jisu_qr_test_10694.png saved=file://docs/storage/Users/currentUser/Download/jisu_qr_test_10694.png`
    - this confirms the QR test image export path reaches the OHOS `writeFileToSharedDownload` implementation and writes the expected 1133-byte PNG into the shared download location
  - `工具 -> 免责声明` is now verified as a real dialog path instead of a dead row:
    - tapping the row opens the actual disclaimer dialog with:
      - `免责声明`
      - `本软件仅供学习交流、科研等非商业性质的用途，严禁将本软件用于商业目的。如有任何商业行为，均与本软件无关。`
      - `退出`
      - `同意`
    - taking the safe `同意` branch returns to the `工具` page without exiting the current app session
  - `关于` is now verified with real content instead of a placeholder page:
    - opening `关于` renders the actual app identity and metadata:
      - `FlClash`
      - `0.8.93`
      - `基于ClashMeta的多平台代理客户端，简单易用，开源无广告。`
    - the page also renders the real contributor and link sections:
      - `June2`
      - `Arue`
      - `Telegram`
      - `项目`
      - `内核`
    - current workspace UI evidence on the tablet session is captured at `.ohos_live_current/about_tablet.jpeg`
    - `检查更新` is now verified on the same emulator as a real interactive update-check path:
      - current app version shown in the page is `0.8.93`
      - on the rebuilt June 22, 2026 HAP, manually tapping `检查更新` issues a real request to GitHub instead of only showing a static dialog:
        - `[check-update] request start url=https://api.github.com/repos/chen08209/FlClash/releases/latest`
        - `[check-update] response status=200`
        - `[check-update] compare local=0.8.93 remote=v0.8.93 hasUpdate=false`
      - the user-facing update check dialog then renders the correct no-update path:
        - `检查更新`
        - `当前应用已经是最新版了`
      - this branch also now distinguishes `已是最新版` from `检查更新失败` in runtime instead of reusing the same text for both cases
      - current workspace evidence for the rebuilt manual-check path is captured at:
        - `.ohos_live_current/manual_update_about_opened.jpeg`
        - `.ohos_live_current/manual_update_dialog_after_tap.jpeg`
      - this confirms the user-facing no-update path is backed by a successful upstream request on the current tablet session instead of an ambiguous fallback message
    - `Telegram` external link is now also verified end to end on the same tablet session:
      - tapping the row opens the real external-link confirmation prompt with:
        - `外部链接`
        - `https://t.me/FlClash`
        - `前往`
      - confirming the prompt reaches the OHOS native external-open path:
        - `[about-link] tap telegram`
        - `[external-url] prompt result url=https://t.me/FlClash confirmed=true`
        - `[AppPlugin] openExternalUrl success url=https://t.me/FlClash`
        - `[external-url] ohos open result url=https://t.me/FlClash success=true`
      - the system browser then opens the live Telegram page for the channel instead of staying inside FlClash
    - `项目` and `内核` external links are also verified through the same OHOS native path:
      - `项目` prompt shows `https://github.com/chen08209/FlClash`
      - `内核` prompt shows `https://github.com/chen08209/Clash.Meta/tree/FlClash`
      - both rows then complete through the native open call instead of failing silently:
        - `[about-link] tap project`
        - `[AppPlugin] openExternalUrl success url=https://github.com/chen08209/FlClash`
        - `[about-link] tap core`
        - `[AppPlugin] openExternalUrl success url=https://github.com/chen08209/Clash.Meta/tree/FlClash`
  - `进阶配置` is now verified on the same emulator with real sub-pages instead of dead links:
    - `网络` opens and renders real fields including:
      - `VPN`
      - `系统代理`
      - `栈模式 mixed`
      - `路由模式 使用配置`
      - `路由地址 配置监听路由地址`
    - `网络 -> VPN` is now exposed on OHOS instead of being Android-only:
      - the live OHOS page renders the actual `VPN` switch and companion items
      - turning `VPN` off persists through the local OHOS preferences store:
        - `[ohos-preferences] saveConfig path=/data/storage/el2/base/haps/entry/files/shared_preferences.json ...`
      - this is required for emulator-only validation because the current Huawei emulator image still lacks `com.huawei.hmos.vpndialog`
    - with `网络 -> VPN` disabled on the emulator, `仪表盘` start/stop is now verified end to end:
      - starting from the FAB now enters the running state instead of immediately rolling back
      - UI evidence:
        - runtime expands from the collapsed play button to `00:00:03`
        - dashboard traffic widgets start showing non-zero values such as `↑ 3.2KB / ↓ 19.8KB`
        - a fresh June 21, 2026 capture from the current tablet session also shows the same branch still running stably at `00:03:31`, with egress IP `141.145.196.11` and cumulative traffic `↑ 3.8KB / ↓ 26.3KB`
        - current workspace running-state evidence is captured at `.ohos_live_current/now_check.jpeg`
      - log evidence:
        - `[OHOS-CORE] invoke startListener#... begin`
        - `[OHOS-CORE] invoke startListener#... done`
        - the same live session emits fresh runtime IP-check requests through `🇫🇷法国 -> PROXY` for `ipwho.is`, `api.myip.com`, `ipinfo.io`, `api.ip.sb`, `ip-api.com`, and `ident.me`
      - tapping the same FAB again cleanly stops the runtime and clears traffic:
        - runtime returns to `00:00:00`
        - `[OHOS-CORE] invoke stopListener#... begin/done`
        - `[OHOS-CORE] invoke resetTraffic#... begin/done`
    - `网络 -> 路由模式` is now verified end to end instead of only by page rendering:
      - changed from `使用配置` to `绕过私有路由地址`
      - current workspace page evidence before the change is captured at `.ohos_live_current/network_tablet.jpeg`
      - current workspace selector-dialog evidence is captured at `.ohos_live_current/route_mode_dialog_tablet.jpeg`
      - the `网络` page immediately reflected the new value
      - current workspace changed-state evidence is captured at `.ohos_live_current/network_route_changed_tablet.jpeg`
      - leaving and reopening `网络` kept `路由模式` as `绕过私有路由地址`
      - current workspace reopen evidence is captured at `.ohos_live_current/network_route_reopen_tablet.jpeg`
      - the OHOS core applied the live config update:
        - `[OHOS-CORE] invoke updateConfig#... begin`
        - `[OHOS-CORE] invoke updateConfig#... done`
      - the OHOS local preferences store also persisted the change:
        - `[ohos-preferences] saveConfig path=/data/storage/el2/base/haps/entry/files/shared_preferences.json ... routeMode=bypassPrivate ...`
      - after the persistence check, the setting was switched back to `使用配置` to restore the baseline state
      - current workspace restored-state evidence is captured at `.ohos_live_current/network_route_restored_tablet.jpeg`
      - the restore path again hit both the live core update and the OHOS local preferences store:
        - `[OHOS-CORE] invoke updateConfig#... begin`
        - `[OHOS-CORE] invoke updateConfig#... done`
        - `[ohos-preferences] saveConfig path=/data/storage/el2/base/haps/entry/files/shared_preferences.json ... routeMode=config ...`
    - `网络 -> IPv6` is now verified with a real reversible persistence path on the current tablet session:
      - the current `网络` page renders the actual `IPv6` switch under the VPN-related network options
      - current workspace page evidence after the live enable step is captured at `.ohos_live_current/network_ipv6_on_tablet.jpeg`
      - toggling the switch changed the live UI state from disabled to enabled
      - the same action raised the real restart banner instead of a dead switch:
        - `检测到VPN相关配置改动`
        - `重启`
      - after leaving `网络` and reopening it, the `IPv6` switch remained enabled, confirming persistence across navigation instead of transient widget state
      - current workspace reopen evidence is captured at `.ohos_live_current/network_ipv6_reopen_tablet.jpeg`
      - after the persistence check, the switch was turned back off to restore the current-session baseline state
      - current workspace restored-state evidence is captured at `.ohos_live_current/network_ipv6_restored_tablet.jpeg`
    - `网络 -> 允许应用绕过VPN` is now verified with a real reversible persistence path on the current tablet session:
      - the current tablet-session baseline rendered `允许应用绕过VPN` as enabled
      - toggling the switch changed the live UI state from enabled to disabled
      - current workspace disabled-state evidence is captured at `.ohos_live_current/network_bypass_off_tablet.jpeg`
      - the same action raised the real restart banner instead of silently ignoring the change:
        - `检测到VPN相关配置改动`
        - `重启`
      - after leaving `网络` and reopening it, the `允许应用绕过VPN` switch remained disabled, confirming persistence across navigation instead of transient widget state
      - current workspace reopen evidence is captured at `.ohos_live_current/network_bypass_reopen_off_tablet.jpeg`
      - after the persistence check, the switch was turned back on to restore the current-session baseline state
      - current workspace restored-state evidence is captured at `.ohos_live_current/network_bypass_restored_tablet.jpeg`
    - `网络 -> 系统代理` is now verified with a real reversible persistence path on the current tablet session:
      - the current tablet-session baseline rendered `系统代理` as enabled
      - toggling the switch changed the live UI state from enabled to disabled
      - current workspace disabled-state evidence is captured at `.ohos_live_current/network_system_proxy_off_tablet.jpeg`
      - after leaving `网络` and reopening it, the `系统代理` switch remained disabled, confirming persistence across navigation instead of transient widget state
      - current workspace reopen evidence is captured at `.ohos_live_current/network_system_proxy_reopen_off_tablet.jpeg`
      - after the persistence check, the switch was turned back on to restore the current-session baseline state
      - current workspace restored-state evidence is captured at `.ohos_live_current/network_system_proxy_restored_tablet.jpeg`
    - `网络 -> DNS劫持` is now verified with a real reversible persistence path on the current tablet session:
      - the initial `网络` page rendered `DNS劫持` with the switch disabled
      - toggling `DNS劫持` visibly changed the live switch state from off to on
      - current workspace enabled-state evidence is captured at `.ohos_live_current/network_dns_hijack_on_tablet.jpeg`
      - after leaving `网络` and reopening it, the `DNS劫持` switch remained enabled, confirming persistence across navigation instead of transient widget state
      - current workspace reopen evidence is captured at `.ohos_live_current/network_dns_hijack_reopen_on_tablet.jpeg`
      - after the persistence check, the switch was turned back off to restore the baseline state
      - current workspace restored-state evidence is captured at `.ohos_live_current/network_dns_hijack_restored_tablet.jpeg`
    - `网络 -> 排除域名` is now verified with a real add, persist, and delete flow on the current tablet session:
      - opening `排除域名` reaches the real editable list instead of a dead submenu
      - the page renders a non-empty persisted rule list with entries such as:
        - `*zhihu.com`
        - `localhost`
        - `192.168.*`
      - current workspace page evidence is captured at `.ohos_live_current/exclude_domains_page_tablet.jpeg`
      - tapping `添加` opens the real input dialog instead of a dead button
      - adding the test entry `flclash-qa-exclude.example` succeeds and appends it into the live list
      - current workspace added-state evidence after scrolling to the appended row is captured at `.ohos_live_current/exclude_domains_scroll_1.jpeg`
      - after leaving and reopening `排除域名`, the same `flclash-qa-exclude.example` row is still present, confirming persistence across navigation
      - current workspace reopen evidence is captured at `.ohos_live_current/exclude_domains_reopen_added_tablet.jpeg`
      - selecting that row enters the real multi-select delete mode with a visible trash action instead of a fake checkbox
      - deleting the selected test row succeeds and removes it from the list, restoring the current-session baseline
      - current workspace restored-state evidence after deletion is captured at `.ohos_live_current/exclude_domains_deleted_confirmed_tablet.jpeg`
    - `网络 -> 栈模式` is now verified with a real selector and persistence path on the current tablet session:
      - tapping `栈模式` opens a real mode-selection dialog instead of a dead row
      - the dialog renders real selectable values:
        - `gvisor`
        - `system`
        - `mixed`
      - current workspace selector evidence is captured at `.ohos_live_current/network_stack_mode_dialog_tablet.jpeg`
      - switching the value from `mixed` to `system` immediately updates the live `网络` page
      - current workspace changed-state evidence is captured at `.ohos_live_current/network_stack_mode_system_tablet.jpeg`
      - after leaving `网络` and reopening it, the page still renders `栈模式 system`, confirming persistence across navigation
      - current workspace reopen evidence is captured at `.ohos_live_current/network_stack_mode_reopen_page_tablet.jpeg`
      - after the persistence check, the value was switched back to `mixed` to restore the baseline state
      - current workspace restored-state evidence is captured at `.ohos_live_current/network_stack_mode_restored_mixed_tablet.jpeg`
    - `网络 -> 路由地址` is now verified with a real add, persist, and delete flow on the current tablet session:
      - opening `路由地址` reaches the real editable list page instead of a dead submenu
      - the current baseline state is the real empty state:
        - `暂无数据`
      - current workspace empty-state evidence is captured at `.ohos_live_current/network_route_address_dialog_tablet.jpeg`
      - tapping `添加` opens the real input dialog titled `监听`
      - entering a bare IP (`198.18.0.1`) is accepted into storage but immediately surfaces a real validation error on reopen:
        - `netip.ParsePrefix("198.18.0.1"): no '/'`
      - this confirms the field expects a CIDR/prefix value instead of an arbitrary placeholder string
      - after deleting that invalid test value, the page returned to the empty baseline state
      - current workspace restored empty-state evidence after that cleanup is captured at `.ohos_live_current/network_route_address_deleted_bad_entry_tablet.jpeg`
      - entering the valid CIDR test value `198.18.0.1/32` succeeds and appends a real row into the live list
      - current workspace valid added-state evidence is captured at `.ohos_live_current/network_route_address_valid_added_tablet.jpeg`
      - after leaving and reopening `路由地址`, the same `198.18.0.1/32` row is still present, confirming persistence across navigation
      - current workspace reopen evidence is captured at `.ohos_live_current/network_route_address_valid_reopen_added_tablet.jpeg`
      - selecting that row enters the real multi-select delete mode with a visible trash action instead of a fake checkbox
      - deleting the selected CIDR test row succeeds and restores the empty baseline state
      - current workspace restored-state evidence is captured at `.ohos_live_current/network_route_address_valid_deleted_tablet.jpeg`
    - `按需运行` is now verified with real add and persistence behavior:
      - the page renders the actual empty-state management UI:
        - `排除SSIDs`
        - `添加`
        - `SSIDs为空`
      - current workspace empty-state evidence on the current tablet session is captured at `.ohos_live_current/on_demand_current_tablet.jpeg`
      - adding a test SSID through the real input dialog succeeds:
        - dialog title: `添加SSID`
        - entered value: `FLCLASH-QA-SSID`
      - current workspace add-dialog evidence is captured at `.ohos_live_current/on_demand_add_dialog_ready_tablet.jpeg`
      - current workspace added-state evidence is captured at `.ohos_live_current/on_demand_added_success_tablet.jpeg`
      - after submit, the page renders the saved SSID row instead of the empty state
      - after leaving and reopening `按需运行`, the same `FLCLASH-QA-SSID` row is still present, confirming persistence across navigation instead of transient in-memory state
      - current workspace reopen evidence is captured at `.ohos_live_current/on_demand_reopen_success_tablet.jpeg`
    - `DNS` opens and renders real DNS configuration fields including:
      - `覆写DNS`
      - `状态`
      - `监听 0.0.0.0:1053`
      - `使用Hosts`
      - `使用系统Hosts`
      - `IPv6`
      - `遵守规则`
      - `PreferH3`
      - `DNS模式 fakeIp`
      - `Fakeip范围 198.18.0.1/16`
      - `Fakeip过滤`
      - `默认域名服务器`
      - `域名服务器策略`
      - `域名服务器`
      - `Fallback`
      - current workspace page evidence on the current tablet session is captured at `.ohos_live_current/dns_page_current_tablet.jpeg`
    - `DNS -> PreferH3` is now verified with a real writeback and persistence path:
      - the initial DNS page rendered `PreferH3` with the switch disabled
      - toggling `PreferH3` visibly changed the live switch state from off to on
      - current workspace enabled-state evidence is captured at `.ohos_live_current/dns_preferh3_on_tablet.jpeg`
      - the toggle triggered a real config update on the running OHOS core path:
        - `[OHOS-CORE] invoke updateConfig#... begin`
        - `[OHOS-CORE] invoke updateConfig#... done`
      - after leaving and reopening `DNS`, the `PreferH3` switch remained enabled, confirming persistence across navigation instead of transient widget state
      - current workspace reopen evidence is captured at `.ohos_live_current/dns_preferh3_reopen_tablet.jpeg`
      - after the persistence check, the switch was turned back off to restore the baseline state
      - current workspace restored-state evidence is captured at `.ohos_live_current/dns_preferh3_restored_tablet.jpeg`
    - `DNS -> 遵守规则` is now verified with a real reversible persistence path on the current tablet session:
      - the initial DNS page rendered `遵守规则` with the switch disabled
      - toggling `遵守规则` visibly changed the live switch state from off to on
      - current workspace enabled-state evidence is captured at `.ohos_live_current/dns_respect_rules_on_tablet.jpeg`
      - after leaving and reopening `DNS`, the `遵守规则` switch remained enabled, confirming persistence across navigation instead of transient widget state
      - current workspace reopen evidence is captured at `.ohos_live_current/dns_respect_rules_reopen_on_tablet.jpeg`
      - after the persistence check, the switch was turned back off to restore the baseline state
      - current workspace restored-state evidence is captured at `.ohos_live_current/dns_respect_rules_restored_tablet.jpeg`
    - `DNS -> IPv6` is now verified with a real reversible persistence path on the current tablet session:
      - the initial DNS page rendered `IPv6` with the switch disabled
      - toggling `IPv6` visibly changed the live switch state from off to on
      - current workspace enabled-state evidence is captured at `.ohos_live_current/dns_ipv6_on_tablet.jpeg`
      - after leaving and reopening `DNS`, the `IPv6` switch remained enabled, confirming persistence across navigation instead of transient widget state
      - current workspace reopen evidence is captured at `.ohos_live_current/dns_ipv6_reopen_on_tablet.jpeg`
      - after the persistence check, the switch was turned back off to restore the baseline state
      - current workspace restored-state evidence is captured at `.ohos_live_current/dns_ipv6_restored_tablet.jpeg`
    - `DNS -> 覆写DNS` is now verified with a real reversible persistence path on the current tablet session:
      - the initial DNS page rendered `覆写DNS` with the switch disabled
      - toggling `覆写DNS` visibly changed the live switch state from off to on
      - current workspace enabled-state evidence is captured at `.ohos_live_current/dns_override_on_tablet.jpeg`
      - after leaving and reopening `DNS`, the `覆写DNS` switch remained enabled, confirming persistence across navigation instead of transient widget state
      - current workspace reopen evidence is captured at `.ohos_live_current/dns_override_reopen_on_tablet.jpeg`
      - after the persistence check, the switch was turned back off to restore the baseline state
      - current workspace restored-state evidence is captured at `.ohos_live_current/dns_override_restored_tablet.jpeg`
    - `DNS -> 状态` is now verified with a real reversible persistence path on the current tablet session:
      - the current tablet-session baseline rendered `状态` as enabled
      - toggling `状态` visibly changed the live switch state from on to off
      - current workspace disabled-state evidence is captured at `.ohos_live_current/dns_status_off_tablet.jpeg`
      - after leaving and reopening `DNS`, the `状态` switch remained disabled, confirming persistence across navigation instead of transient widget state
      - current workspace reopen evidence is captured at `.ohos_live_current/dns_status_reopen_off_tablet.jpeg`
      - after the persistence check, the switch was turned back on to restore the current-session baseline state
      - current workspace restored-state evidence is captured at `.ohos_live_current/dns_status_restored_tablet.jpeg`
    - `DNS -> 使用Hosts` is now verified with a real reversible persistence path on the current tablet session:
      - the current tablet-session baseline rendered `使用Hosts` as enabled
      - toggling `使用Hosts` visibly changed the live switch state from on to off
      - current workspace disabled-state evidence is captured at `.ohos_live_current/dns_use_hosts_off_tablet.jpeg`
      - after leaving and reopening `DNS`, the `使用Hosts` switch remained disabled, confirming persistence across navigation instead of transient widget state
      - current workspace reopen evidence is captured at `.ohos_live_current/dns_use_hosts_reopen_off_tablet.jpeg`
      - after the persistence check, the switch was turned back on to restore the current-session baseline state
      - current workspace restored-state evidence is captured at `.ohos_live_current/dns_use_hosts_restored_tablet.jpeg`
    - `DNS -> 使用系统Hosts` is now verified with a real reversible persistence path on the current tablet session:
      - the current tablet-session baseline rendered `使用系统Hosts` as enabled
      - toggling `使用系统Hosts` visibly changed the live switch state from on to off
      - current workspace disabled-state evidence is captured at `.ohos_live_current/dns_use_system_hosts_off_tablet.jpeg`
      - after leaving and reopening `DNS`, the `使用系统Hosts` switch remained disabled, confirming persistence across navigation instead of transient widget state
      - current workspace reopen evidence is captured at `.ohos_live_current/dns_use_system_hosts_reopen_off_tablet.jpeg`
      - after the persistence check, the switch was turned back on to restore the current-session baseline state
      - current workspace restored-state evidence is captured at `.ohos_live_current/dns_use_system_hosts_restored_tablet.jpeg`
    - `DNS -> DNS模式` is now verified with a real selector and persistence path on the current tablet session:
      - tapping `DNS模式` opens a real mode-selection dialog instead of a dead row
      - the dialog renders real selectable values:
        - `normal`
        - `fakeIp`
        - `redirHost`
        - `hosts`
      - current workspace selector evidence is captured at `.ohos_live_current/dns_mode_dialog_tablet.jpeg`
      - switching the value from `fakeIp` to `normal` immediately updates the live `DNS` page
      - current workspace changed-state evidence is captured at `.ohos_live_current/dns_mode_normal_tablet.jpeg`
      - after leaving `DNS` and reopening it, the page still renders `DNS模式 normal`, confirming persistence across navigation
      - current workspace reopen evidence is captured at `.ohos_live_current/dns_reopened_for_restore.jpeg`
      - after the persistence check, the value was switched back to `fakeIp` to restore the baseline state
      - current workspace restored-state evidence is captured at `.ohos_live_current/dns_mode_restored_fakeip_tablet.jpeg`
    - `DNS -> Fakeip过滤` is now verified with a real list edit, persistence, and restore path on the current tablet session:
      - tapping `Fakeip过滤` opens the actual list-management page instead of a dead route
      - the page renders existing seed items:
        - `*.lan`
        - `localhost.ptlogin2.qq.com`
      - current workspace list-page evidence is captured at `.ohos_live_current/dns_fakeip_filter_page.jpeg`
      - tapping `添加` opens the real input dialog titled `添加`
      - entering the temporary value `*.fakeip-verify.test` and confirming adds a third live row
      - current workspace added-state evidence is captured at `.ohos_live_current/dns_fakeip_filter_after_confirm.jpeg`
      - leaving back to `DNS` triggers a real preferences write:
        - `[ohos-preferences] saveConfig path=/data/storage/el2/base/haps/entry/files/shared_preferences.json ...`
      - reopening `Fakeip过滤` still renders `*.fakeip-verify.test`, confirming persistence across navigation
      - current workspace reopen evidence is captured at `.ohos_live_current/dns_fakeip_filter_reopen.jpeg`
      - after the persistence check, the temporary row was selected and deleted to restore the baseline state
      - current workspace selection evidence is captured at `.ohos_live_current/fakeip_filter_selected.jpeg`
      - current workspace restored-state evidence is captured at `.ohos_live_current/fakeip_filter_deleted.jpeg`
      - leaving back to `DNS` again triggers `saveConfig`, confirming the restore path also writes back
    - `DNS -> 域名服务器策略` is now hard-verified on the current tablet session for both edit and add flows:
      - tapping `域名服务器策略` opens the real map-management page instead of a dead route
      - the page renders real existing key/value rows:
        - `www.baidu.com -> 114.114.114.114`
        - `+.internal.crop.com -> 10.0.0.1`
        - `geosite:cn -> https://doh.pub/dns-query`
      - current workspace map-page evidence is captured at `.ohos_live_current/dns_policy_page.jpeg`
      - tapping an existing row opens the real edit dialog with both prefilled fields:
        - `键`
        - `值`
      - current workspace edit-dialog evidence is captured at `.ohos_live_current/dns_policy_edit_dialog.jpeg`
      - the previous “automation completely blocked here” conclusion was incorrect:
        - `uitest uiInput inputText <x> <y> <text>` is not a safe overwrite primitive in this dialog because it inserts at the live cursor position and can scramble existing text
        - the reliable path on this emulator is:
          - focus the second field after the keyboard has already shifted the layout
          - avoid IME candidate composition
          - inject a committed character with `uitest uiInput text`
          - dismiss the keyboard first, then confirm
      - a real edit submit path is now verified against the existing row `+.internal.crop.com -> 10.0.0.1`:
        - the `值` field was changed to `10.0.0.1w`
        - dismissing the keyboard kept the edited value visible in the dialog
        - tapping `确定` returned to the list page and the row immediately rendered `+.internal.crop.com -> 10.0.0.1w`
        - reopening the same row still rendered `10.0.0.1w`, confirming persistence across navigation instead of transient widget state
        - using the page-level reset action afterwards restored the row to `+.internal.crop.com -> 10.0.0.1`
        - reopening the same row again after reset rendered `10.0.0.1`, confirming the restore path also persists
      - current workspace evidence for that edit path is captured at:
        - `.ohos_live_current/domain_policy_keyboard_gone_clean.jpeg`
        - `.ohos_live_current/domain_policy_saved_list.jpeg`
        - `.ohos_live_current/domain_policy_reopen_after_save.jpeg`
        - `.ohos_live_current/domain_policy_list_after_reopen_check.jpeg`
        - `.ohos_live_current/domain_policy_after_reset_confirm.jpeg`
        - `.ohos_live_current/domain_policy_reopen_after_reset.jpeg`
      - a real add submit path is also now verified against a brand-new key/value pair:
        - tapping `添加` opened the real empty two-field dialog
        - `键` accepted a committed `q`
        - `值` accepted a committed `w`
        - dismissing the keyboard kept `q -> w` visible in the dialog
        - tapping `确定` returned to the list page and rendered a fourth live row `q -> w`
        - reopening that new row still rendered `q` and `w`, confirming persistence across navigation instead of transient widget state
        - using the same page-level reset action afterwards removed the temporary `q -> w` row and restored the original three-row baseline
      - current workspace evidence for that add path is captured at:
        - `.ohos_live_current/domain_policy_add_now.jpeg`
        - `.ohos_live_current/domain_policy_add_first_focus_now.jpeg`
        - `.ohos_live_current/domain_policy_add_key_q.jpeg`
        - `.ohos_live_current/domain_policy_add_second_focus_now.jpeg`
        - `.ohos_live_current/domain_policy_add_qw_keyboard_gone.jpeg`
        - `.ohos_live_current/domain_policy_add_qw_saved.jpeg`
        - `.ohos_live_current/domain_policy_add_qw_reopen.jpeg`
        - `.ohos_live_current/domain_policy_add_qw_back_to_list.jpeg`
        - `.ohos_live_current/domain_policy_add_qw_reset_prompt.jpeg`
        - `.ohos_live_current/domain_policy_add_qw_after_reset.jpeg`
      - the remaining caveat is now about automation ergonomics rather than product behavior:
        - direct field-level delete automation remains fragile because the Huawei tablet IME can switch into candidate-composition mode mid-test, so the reliable restore path currently uses the page-level reset action instead
    - `附加规则` is now verified with real add and persistence behavior:
      - the page renders the actual empty-state management UI:
        - `添加`
        - `暂无规则`
      - opening the add dialog shows the real editable rule form instead of a stub:
        - rule type chip: `DOMAIN`
        - target selector default: `DIRECT`
      - adding a test rule succeeds with:
        - content: `flclash-qa.example`
        - target: `DIRECT`
      - after save, the rule list renders a real row:
        - `DOMAIN`
        - `flclash-qa.example`
        - `DIRECT`
      - after leaving and reopening `附加规则`, the same rule row remains, confirming persistence across navigation
    - `脚本` is now verified with real add and save behavior:
      - the page renders the actual empty-state management UI:
        - `添加`
        - `暂无脚本`
      - tapping `添加` opens the real script editor instead of a dead route or sample page
      - the editor loads the actual default JavaScript template:
        - `const main = (config) => {`
        - `return config;`
      - editing and save flow are verified end to end:
        - a content change was applied in the editor by appending `//qa`
        - tapping the save icon opens the real naming dialog titled `保存`
        - entering `qa-script` and submitting returns to the script list
      - after save, the script list renders a real persisted item:
        - `qa-script`
    - `覆写` is now verified as a real per-profile configuration entry instead of a dead submenu:
      - opening `配置 -> 极速机场(3) -> 更多 -> 覆写` reaches the real `覆写` page
      - the page renders actual overwrite modes:
        - `标准`
        - `脚本`
        - `自定义`
      - switching overwrite mode from `标准` to `脚本` succeeds
      - the page immediately switches to real script-mode content:
        - `覆写脚本`
        - `qa-script`
        - `前往配置脚本`
      - after leaving and reopening `覆写`, the page still stays in `脚本` mode and still shows `qa-script`, confirming persistence across navigation instead of transient UI state
      - switching overwrite mode from `脚本` to `自定义` also succeeds and reaches the real custom-data page:
        - initial counters rendered as `策略组 0` and `规则 0`
      - tapping `一键填入` opens a real destructive confirmation dialog instead of a dead button:
        - `提示`
        - `确定后将会覆盖已有数据`
        - `取消`
        - `确定`
      - confirming the action writes real data derived from the current profile config into the local database:
        - the page immediately updates to `策略组 3`
        - the page immediately updates to `规则 516`
      - after leaving and reopening `覆写 -> 自定义`, the same values `策略组 3` and `规则 516` are still present, confirming persistence across navigation instead of transient widget state
      - both nested editors are now verified as real data views instead of dead counters:
        - `覆写 -> 自定义 -> 规则` opens a real rule list and edit flow
        - `覆写 -> 自定义 -> 策略组` opens a real proxy-group list showing:
          - `极速机场 / Selector`
          - `自动选择 / URLTest`
          - `故障转移 / Fallback`
      - `覆写 -> 自定义 -> 规则` is now verified with a real write path and persistence:
        - adding a new custom rule with:
          - type `DOMAIN`
          - content `flclash-qa-custom.example`
          - target `DIRECT`
        - the save flow triggers a real confirmation dialog when leaving the editor with modified data:
          - `提示`
          - `检测到数据有更改，是否保存`
          - `取消`
          - `确定`
        - after confirming save, the new rule appears at the top of the real rule list:
          - `DOMAIN`
          - `flclash-qa-custom.example`
          - `DIRECT`
        - after returning to `覆写 -> 自定义`, the rule counter increases from `516` to `517`
        - after reopening `规则` and returning again, the same counter `517` is still present, confirming persistence across navigation instead of transient UI state
      - the same `覆写 -> 自定义 -> 一键填入` write path was re-verified again on June 21, 2026 after a full app-data reset on the current tablet session:
        - the rebuilt clean-state page starts from the real zero baseline:
          - `策略组 0`
          - `规则 0`
        - current workspace clean-state evidence is captured at `.ohos_live_current/overwrite_custom_rebuild_before_fill.jpeg`
        - tapping `一键填入` still opens the real confirmation dialog:
          - `提示`
          - `确定后将会覆盖已有数据`
          - `取消`
          - `确定`
        - current workspace dialog evidence is captured at `.ohos_live_current/overwrite_custom_fill_dialog_rebuild.jpeg`
        - confirming the action still writes real derived data on the rebuilt session:
          - `策略组 3`
          - `规则 516`
        - current workspace rebuilt-session write evidence is captured at `.ohos_live_current/overwrite_custom_after_fill_rebuild.jpeg`
  - `全局修改基本配置` is now verified with real option updates instead of only page-open evidence:
    - opening `基本配置` renders the real editable settings page including:
      - `日志等级`
      - `UA`
      - `测速链接`
      - `端口`
      - `Hosts`
      - `IPv6`
      - `局域网代理`
      - `统一延迟`
      - `追加系统DNS`
    - current workspace page-open evidence is captured at `.ohos_live_current/basic_config_page_real_tablet.jpeg`
    - `UA` is verified with a real selector dialog:
      - dialog title: `UA`
      - actual options rendered:
        - `默认`
        - `clash-verge/v2.4.2`
        - `ClashforWindows/0.19.23`
      - current workspace selector-dialog evidence is captured at `.ohos_live_current/ua_dialog_tablet.jpeg`
      - selecting `ClashforWindows/0.19.23` immediately updates the page subtitle to `ClashforWindows/0.19.23`
      - current workspace changed-state evidence is captured at `.ohos_live_current/basic_config_ua_selected_tablet.jpeg`
      - leaving `基本配置` and reopening it keeps `UA` as `ClashforWindows/0.19.23`, confirming persistence across navigation instead of transient widget state
      - current workspace reopen evidence is captured at `.ohos_live_current/basic_config_ua_reopen_tablet.jpeg`
      - the OHOS local preferences store persisted the change:
        - `[ohos-preferences] saveConfig path=/data/storage/el2/base/haps/entry/files/shared_preferences.json ...`
      - after the persistence check, `UA` was switched back to `默认` to restore the baseline state
      - current workspace restore-dialog evidence is captured at `.ohos_live_current/ua_dialog_restore_default_tablet.jpeg`
      - current workspace restored-state evidence is captured at `.ohos_live_current/basic_config_ua_restored_default_tablet.jpeg`
    - `端口` is now also verified with a real dialog writeback and persistence path on the current tablet session:
      - opening `端口` shows the actual mixed-port dialog with:
        - current value `7890`
        - `重置`
        - `提交`
      - current workspace dialog-open evidence is captured at `.ohos_live_current/basic_port_dialog.jpeg`
      - the current tablet automation path can now edit this field reliably by:
        - focusing the input
        - sending `KEYCODE_DEL=2055` once to remove the trailing digit
        - sending `text 1`
        - using the keyboard `完成` key to keep the dialog open with the edited value
      - current workspace edited-value evidence is captured at `.ohos_live_current/port_after_text1.jpeg`
      - submitting the dialog updates the page subtitle from `7890` to `7891`
      - current workspace changed-state evidence is captured at `.ohos_live_current/basic_port_saved_7891_final.jpeg`
      - the submit action also triggered both the runtime config-update path and OHOS local persistence:
        - `[OHOS-CORE] invoke updateConfig#... begin/done`
        - `[ohos-preferences] saveConfig path=/data/storage/el2/base/haps/entry/files/shared_preferences.json ...`
      - leaving and reopening `基本配置` keeps `端口` as `7891`, confirming persistence across navigation
      - current workspace reopen evidence is captured at `.ohos_live_current/basic_port_reopen_7891.jpeg`
      - after verification, the dialog `重置 -> 确定` flow restored the baseline `7890`
      - current workspace restored-state evidence is captured at `.ohos_live_current/basic_port_restored_7890_done.jpeg`
    - `测速链接` is now verified beyond persistence with a real runtime delay-probe side effect:
      - the page initially rendered the temporary alias URL `http://qa.flclash.test:19003/ip-check?delay_ms=1000#w.gstatic.com/generate_204`
      - current workspace alias-state evidence is captured at `.ohos_live_current/basic_after_alias_submit.jpeg`
      - tapping `代理 -> 延迟测试` after that change made the running core issue real probes against the edited URL instead of the default `gstatic` target:
        - `[proxy-delay] start ... url=http://qa.flclash.test:19003/ip-check?delay_ms=1000#w.gstatic.com/generate_204`
        - `ResultCallback method=asyncTestDelay ... "name":"DIRECT","value":6`
      - the host-side runtime test server also received the probe:
        - `.ohos_runtime_test_server/server.log`
        - `"HEAD /ip-check?delay_ms=1000 HTTP/1.1" 501 -`
      - after the runtime check, `重置` restored the baseline value `https://www.gstatic.com/generate_204`
      - current workspace restored-state evidence is captured at:
        - `.ohos_live_current/testurl_after_reset.jpeg`
        - `.ohos_live_current/basic_testurl_restored.jpeg`
      - the restore path again hit the OHOS preference store:
        - `[ohos-preferences] saveConfig path=/data/storage/el2/base/haps/entry/files/shared_preferences.json ...`
    - `Hosts` is now verified as both persisted input data and effective runtime config:
      - adding `qa.flclash.test -> 127.0.0.1` through the live OHOS dialog produced a real saved row instead of a placeholder card
      - current workspace add-flow evidence is captured at:
        - `.ohos_live_current/hosts_after_key_only.jpeg`
        - `.ohos_live_current/hosts_after_value_inputtext.jpeg`
        - `.ohos_live_current/hosts_added_list.jpeg`
      - after leaving and reopening `Hosts`, the same entry remained present, confirming persistence across navigation
      - current workspace reopen evidence is captured at `.ohos_live_current/hosts_reopen_persist.jpeg`
      - the same session also persisted through the OHOS preference store:
        - `[ohos-preferences] saveConfig path=/data/storage/el2/base/haps/entry/files/shared_preferences.json ...`
      - runtime application was then verified by combining that host mapping with the temporary alias `测速链接` above and cold-starting the app so `setupConfig` rewrote the active config file
      - the running core then used the alias host during batch delay testing:
        - `[setup-profile] wrote config path=/data/storage/el2/base/haps/entry/files/config.yaml ...`
        - `[OHOS-CORE] invoke setupConfig ... begin`
        - `[proxy-delay] start ... url=http://qa.flclash.test:19003/ip-check?delay_ms=1000#w.gstatic.com/generate_204`
        - `ResultCallback method=asyncTestDelay ... "name":"DIRECT","value":6`
      - the host-side runtime test server again confirmed the request hit the mapped alias target:
        - `.ohos_runtime_test_server/server.log`
        - `"HEAD /ip-check?delay_ms=1000 HTTP/1.1" 501 -`
      - practical boundary on the current branch:
        - `Hosts` changes are proven to enter the active runtime after app restart / `setupConfig`
        - this is stronger than preference-only persistence, but it is not currently documented as a hot-applied `updateConfig` path
    - `日志等级` is verified with a real selector dialog and writeback:
      - dialog title: `日志等级`
      - actual options rendered:
        - `debug`
        - `info`
        - `warning`
        - `error`
        - `silent`
      - selecting `warning` immediately updates the page subtitle from `error` to `warning`
      - current workspace restore dialog for returning to the baseline `error` state is captured at `.ohos_live_current/log_level_dialog_restore_tablet.jpeg`
      - current workspace fully restored baseline state is captured at `.ohos_live_current/basic_config_restored_baseline_tablet.jpeg`
    - `日志等级` was re-verified again on the current tablet session with a full persistence round-trip:
      - current workspace dialog evidence is captured at `.ohos_live_current/basic_log_level_dialog.jpeg`
      - selecting `debug` immediately updates the page subtitle from `error` to `debug`
      - current workspace changed-state evidence is captured at `.ohos_live_current/basic_log_level_debug.jpeg`
      - leaving and reopening `基本配置` keeps `日志等级` as `debug`, confirming persistence across navigation
      - current workspace reopen evidence is captured at `.ohos_live_current/basic_log_level_reopen_debug.jpeg`
      - after verification, the setting was switched back to `error` to restore the baseline state
      - current workspace restored-state evidence is captured at `.ohos_live_current/basic_log_level_restored_error.jpeg`
    - `IPv6` is verified with a real switch writeback and persistence path:
      - toggling the `IPv6` switch from off to on visibly updates the live switch state on the page
      - current workspace baseline evidence before the change is captured at `.ohos_live_current/basic_config_before_ipv6_retest_tablet.jpeg`
      - current workspace enabled-state evidence is captured at `.ohos_live_current/basic_config_ipv6_on_tablet.jpeg`
      - the toggle triggers a real config update on the running OHOS core path:
        - `[OHOS-CORE] invoke updateConfig#... begin`
        - `[OHOS-CORE] invoke updateConfig#... done`
      - the current tablet session also persisted the change through the OHOS local preferences store:
        - `[ohos-preferences] saveConfig path=/data/storage/el2/base/haps/entry/files/shared_preferences.json ... ipv6=true`
      - after leaving and reopening `基本配置`, the `IPv6` switch remains enabled, confirming persistence across navigation instead of transient widget state
      - current workspace reopen evidence is captured at `.ohos_live_current/basic_config_ipv6_reopen_tablet.jpeg`
      - after the persistence check, the switch was turned back off to restore the baseline state
      - current workspace restored-state evidence is captured at `.ohos_live_current/basic_config_ipv6_restored_tablet.jpeg`
      - the restore path again hit both the live core update and the OHOS local preferences store:
        - `[OHOS-CORE] invoke updateConfig#... begin`
        - `[OHOS-CORE] invoke updateConfig#... done`
        - `[ohos-preferences] saveConfig path=/data/storage/el2/base/haps/entry/files/shared_preferences.json ... ipv6=false`
    - `统一延迟` is now verified with a real switch writeback and persistence path:
      - the current baseline page rendered `统一延迟` enabled
      - toggling `统一延迟` visibly changed the live switch state from on to off
      - current workspace disabled-state evidence is captured at `.ohos_live_current/basic_config_unified_delay_off_tablet.jpeg`
      - the toggle triggered a real config update on the running OHOS core path:
        - `[OHOS-CORE] invoke updateConfig#... begin`
        - `[OHOS-CORE] invoke updateConfig#... done`
      - after leaving and reopening `基本配置`, the `统一延迟` switch remained disabled, confirming persistence across navigation instead of transient widget state
      - current workspace reopen evidence is captured at `.ohos_live_current/basic_config_unified_delay_reopen_tablet.jpeg`
      - after the persistence check, the switch was turned back on to restore the baseline state
      - current workspace restored-state evidence is captured at `.ohos_live_current/basic_config_unified_delay_restored_tablet.jpeg`
    - `局域网代理` is now verified with a real switch writeback and persistence path:
      - the current baseline page rendered `局域网代理` disabled
      - toggling `局域网代理` visibly changed the live switch state from off to on
      - current workspace enabled-state evidence is captured at `.ohos_live_current/basic_config_lan_on_tablet.jpeg`
      - the toggle triggered a real config update on the running OHOS core path:
        - `[OHOS-CORE] invoke updateConfig#... begin`
        - `[OHOS-CORE] invoke updateConfig#... done`
      - after leaving and reopening `基本配置`, the `局域网代理` switch remained enabled, confirming persistence across navigation instead of transient widget state
      - current workspace reopen evidence is captured at `.ohos_live_current/basic_config_lan_reopen_tablet.jpeg`
      - after the persistence check, the switch was turned back off to restore the baseline state
      - current workspace restored-state evidence is captured at `.ohos_live_current/basic_config_lan_restored_tablet.jpeg`
    - `追加系统DNS` is now verified with a real switch writeback and persistence path:
      - the initial `基本配置` page rendered `追加系统DNS` with the switch disabled
      - toggling `追加系统DNS` visibly changed the live switch state from off to on
      - current workspace enabled-state evidence is captured at `.ohos_live_current/basic_config_append_dns_on_tablet.jpeg`
      - leaving and reopening `基本配置` kept `追加系统DNS` enabled, confirming persistence across navigation instead of transient widget state
      - current workspace reopen evidence is captured at `.ohos_live_current/basic_config_append_dns_reopen_tablet.jpeg`
      - the current tablet session showed persistence through the OHOS local preferences store:
        - `[ohos-preferences] saveConfig path=/data/storage/el2/base/haps/entry/files/shared_preferences.json ...`
      - after the persistence check, the switch was turned back off to restore the baseline state
      - current workspace restored-state evidence is captured at `.ohos_live_current/basic_config_append_dns_restored_tablet.jpeg`
    - `查找进程` is now also verified with a real reversible persistence path on the current tablet session:
      - the current lower `基本配置` page rendered `查找进程` enabled
      - turning the switch off visibly changed the live state to disabled
      - current workspace disabled-state evidence is captured at `.ohos_live_current/basic_findprocess_off.jpeg`
      - the toggle triggered both the runtime config-update path and local persistence:
        - `[OHOS-CORE] invoke updateConfig#... begin/done`
        - `[ohos-preferences] saveConfig path=/data/storage/el2/base/haps/entry/files/shared_preferences.json ...`
      - leaving and reopening `基本配置` kept `查找进程` disabled, confirming persistence across navigation
      - current workspace reopen-off evidence is captured at `.ohos_live_current/basic_findprocess_reopen_off.jpeg`
      - after verification, the switch was turned back on to restore the baseline state
      - current workspace restored-state evidence is captured at `.ohos_live_current/basic_findprocess_restored_on.jpeg`
    - `TCP并发` is now also verified with a real reversible persistence path on the current tablet session:
      - the current lower `基本配置` page rendered `TCP并发` enabled
      - turning the switch off visibly changed the live state to disabled
      - current workspace disabled-state evidence is captured at `.ohos_live_current/basic_tcp_off.jpeg`
      - the toggle triggered both the runtime config-update path and local persistence:
        - `[OHOS-CORE] invoke updateConfig#... begin/done`
        - `[ohos-preferences] saveConfig path=/data/storage/el2/base/haps/entry/files/shared_preferences.json ...`
      - leaving and reopening `基本配置` kept `TCP并发` disabled, confirming persistence across navigation
      - current workspace reopen-off evidence is captured at `.ohos_live_current/basic_tcp_reopen_off.jpeg`
      - after verification, the switch was turned back on to restore the baseline state
      - current workspace restored-state evidence is captured at `.ohos_live_current/basic_tcp_restored_on.jpeg`
    - `Geo低内存模式` is now also verified with a real reversible persistence path on the current tablet session:
      - the current lower `基本配置` page rendered `Geo低内存模式` enabled
      - turning the switch off visibly changed the live state to disabled
      - current workspace disabled-state evidence is captured at `.ohos_live_current/basic_geoload_off.jpeg`
      - the current branch persisted the change into OHOS local preferences:
        - `[ohos-preferences] saveConfig path=/data/storage/el2/base/haps/entry/files/shared_preferences.json ...`
      - unlike `查找进程` / `TCP并发` / `外部控制器`, no `updateConfig` callback was emitted here, which matches current source behavior:
        - `lib/providers/state.dart` only maps runtime `UpdateParams` for `allowLan`, `findProcessMode`, `mode`, `logLevel`, `ipv6`, `tcpConcurrent`, `externalController`, `unifiedDelay`, and `mixedPort`
        - `geodataLoader` is therefore persisted but not hot-applied to the already-running core in this branch
      - leaving and reopening `基本配置` kept `Geo低内存模式` disabled, confirming persistence across navigation
      - current workspace reopen-off evidence is captured at `.ohos_live_current/basic_geoload_reopen_off.jpeg`
      - after verification, the switch was turned back on to restore the baseline state
      - current workspace restored-state evidence is captured at `.ohos_live_current/basic_geoload_restored_on.jpeg`
    - `外部控制器` is now also verified with a real control-port side effect on the current tablet session:
      - with the switch enabled, forwarding `tcp:19090 -> tcp:9090` and querying `http://127.0.0.1:19090/version` returns the live Clash Meta version payload:
        - `{"meta":true,"version":"1.10.0"}`
      - after turning the switch off, the page renders the disabled state
      - current workspace disabled-state evidence is captured at `.ohos_live_current/basic_external_controller_off.jpeg`
      - the same forwarded request then fails with `curl: (56) Recv failure: Connection reset by peer`, proving the control port is actually withdrawn instead of only changing widget state
      - leaving and reopening `基本配置` keeps the switch disabled, confirming persistence across navigation
      - current workspace reopen-off evidence is captured at `.ohos_live_current/basic_external_controller_reopen_off.jpeg`
      - after turning the switch back on, the page renders the enabled state again and the same `http://127.0.0.1:19090/version` request succeeds again:
        - `{"meta":true,"version":"1.10.0"}`
      - current workspace restored-state evidence is captured at `.ohos_live_current/basic_external_controller_restored_on.jpeg`
  - Emulator interaction note for this verification cycle:
    - OHOS phone-emulator `uitest` text targeting is not completely stable for these list rows
    - verification was completed by combining captured layout bounds with direct coordinate taps
    - the instability was in the automation layer, not in the FlClash page routing or rendering logic

Latest verified deep-link import result in this workspace:

- Emulator target: `127.0.0.1:5555`
- Trigger method:

```bash
hdc -t 127.0.0.1:5555 shell \
  "aa start -U 'flclash://install-config?url=http%3A%2F%2F10.0.2.2%3A28765%2Fjisu' -b com.follow.clash"
```

- Runtime evidence:
  - OHOS host receives the URI:
    - `[AppPlugin] setPendingLink=flclash://install-config?...`
  - Flutter receives the running-app callback:
    - `onAppLink from ohos channel: flclash://install-config?...`
  - Confirmed import success:
    - `[ohos-profile-url] addProfileFormURL start: http://10.0.2.2:28765/jisu`
    - `[ohos-profile-url] addProfileFormURL success: ... label=极速机场`
- UI evidence:
  - confirmation dialog shows `是否要通过 http://10.0.2.2:28765/jisu 创建配置`
  - the `配置` page shows the imported profile `极速机场`
  - the bottom navigation expands back to 4 tabs and includes `代理`

Practical note for emulator validation:

- Directly typing a long subscription URL into HarmonyOS `TextInput` is still unreliable on the emulator because `uitest uiInput inputText` may truncate or corrupt long strings with query parameters
- For repeatable automated validation, prefer:
  - `flclash://install-config?...` deep-link import
  - or a short redirect URL that points to the real subscription URL
- On the current HarmonyOS phone emulator target in this workspace, FlClash does not expose a clipboard-import action for subscription URLs.
  Direct read access to the system pasteboard is not a shippable path here because declaring `ohos.permission.READ_PASTEBOARD`
  makes the generated HAP fail installation on the tested target.

Latest verified request-page/runtime result in this workspace:

- Build artifact: `dist/FlClash-0.8.93-ohos-arm64.hap`
- Emulator target: `127.0.0.1:5555`
- Reproduced path:
  - start FlClash from the dashboard
  - open `工具 -> 资源`
  - tap `GEOIP -> 同步`
- Runtime evidence after the latest rebuild:
  - the previous detached-action parse failure is no longer emitted for `updateGeoData`
  - current OHOS logs show the detached callback now returns a numeric code again:
    - `ResultCallback method=updateGeoData ... payload={"id":"...","method":"updateGeoData","data":"","code":0}`
  - the same sync action produces fresh real request events:
    - `dispatch request event ... host=github.com`
    - `dispatch request event ... host=release-assets.githubusercontent.com`
- UI evidence:
  - the `资源` page enters the in-progress sync state for `GEOIP`
  - the `请求` page shows the fresh `github.com` and `release-assets.githubusercontent.com` entries near the top instead of only older startup records
  - the `请求详情` page was freshly re-verified again on June 22, 2026 on the rebuilt HAP and current `127.0.0.1:5555` tablet emulator session:
    - opening the top request `tcp://fastly.jsdelivr.net/151.101.193.229:443` navigates to a real detail page instead of a placeholder route
    - the detail page rendered live fields from the captured record:
      - `进程: mihomo`
      - `网络类型: tcp`
      - `规则: Match`
      - `主机: fastly.jsdelivr.net`
      - `目标地址: 151.101.193.229:443`
      - `代理链: 🇺🇸美国洛杉矶2号 -> 极速机场`
    - fresh current-session evidence is captured at:
      - `.ohos_live_current/requests_page_for_detail.jpeg`
      - `.ohos_live_current/request_detail_current.jpeg`
- The `资源` page was re-verified on June 21, 2026 on the current `FlClash Tablet` emulator:
  - the page renders the real external resource cards for:
    - `GEOIP`
    - `GEOSITE`
    - `MMDB`
    - `ASN`
  - each card shows live size / updated-at metadata plus the real upstream download URL instead of placeholder text
  - current workspace UI evidence before sync is captured at `.ohos_live_current/resources_tablet.jpeg`
  - `GEOIP -> 同步` was also re-verified end to end on the same tablet session:
    - tapping the button changes the card into the in-progress spinner state
    - current workspace in-progress evidence is captured at `.ohos_live_current/resources_after_sync_tablet.jpeg`
    - `hilog` shows the real detached core path:
      - `[OHOS-CORE] invoke updateGeoData#... begin/done`
      - `detached invokeCore callback method=updateGeoData ... done`
      - `[OHOS-CORE] geo data updated file=GEOIP.dat before=... after=...`
    - the same sync also emits fresh upstream requests through the active `🇫🇷法国` node:
      - `host=github.com chains=🇫🇷法国 -> PROXY`
      - `host=release-assets.githubusercontent.com chains=🇫🇷法国 -> PROXY`
    - after completion, the `GEOIP` card updated-at label changes to `刚刚` and the normal `同步` button returns
    - current workspace post-sync evidence is captured at `.ohos_live_current/resources_sync_progress_tablet.jpeg`
  - `GEOIP -> 编辑` is now also re-verified with a real reversible persistence path on the same tablet session:
    - the edit dialog opens with the live upstream URL instead of a stub input
    - current workspace dialog-open evidence is captured at `.ohos_live_current/resources_geoip_edit_dialog.jpeg`
    - a reversible test mutation was submitted and the list row immediately reflected the changed URL:
      - `https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-?qa=1dat@release/geoip.dat`
    - current workspace mutated-state evidence is captured at `.ohos_live_current/resources_geoip_after_submit.jpeg`
    - reopening the same dialog then exposed the real `重置` action, confirming the page recognized the stored value differed from the default
    - current workspace reopen evidence is captured at `.ohos_live_current/resources_geoip_edit_reopen.jpeg`
    - tapping `重置` restored the default upstream URL on the resource card:
      - `https://fastly.jsdelivr.net/gh/MetaCubeX/meta-rules-dat@release/geoip.dat`
    - current workspace restored-state evidence is captured at:
      - `.ohos_live_current/resources_geoip_after_reset.jpeg`
      - `.ohos_live_current/resources_geoip_reopen_after_reset.jpeg`
    - this confirms the resource URL editor is not a dead dialog: it persists edited values, exposes reset only when appropriate, and writes the reverted default back to the live page state
- Source fix that enabled this verification:
  - `ActionResult.code` now accepts both numeric values (`0`, `-1`) and string values (`success`, `error`) when parsing OHOS core responses, while still serializing back to numeric values

Current runtime blockers confirmed after packaging validation:

- On the HarmonyOS 6.1.1(24) `phone` emulator in this workspace, `childProcessManager.startNativeChildProcess()` fails with `Capability not support`.
- OpenHarmony's child-process documentation states that the relevant ArkTS/native child-process APIs are supported on PCs, 2-in-1 devices, and tablets. Other device types return `801` / `16000061`.
- The current fallback path (`startBundledCoreProcess`) can fork and create a memfd-backed child, but the emulator still rejects execution with `fexecve failed: Permission denied` and `execv proc path failed: Permission denied`.
- The historical Go `initial-exec TLS` blocker is resolved in this branch by building OHOS libraries with an isolated patched Go toolchain.
- `scripts/ohos/reproduce_go_musl_tls.sh` is still useful as the rationale for why the patched toolchain is required: stock Go `c-shared` and `c-archive` builds reproduce the non-glibc TLS failure.
- On the same `phone` emulator, the proxy-page bulk delay test can still take a long time when many nodes time out, and HarmonyOS may emit an `APP_FREEZE` / `BUSSINESS_THREAD_BLOCK_6S` fault log even though the page eventually renders delay results.

Recommended validation target from this point:

- Use a HarmonyOS `tablet` or `2in1` emulator, or a real supported device, when validating the child-process startup path.
- The local OpenHarmony Flutter `3.35.7` SDK in this workspace bundles Dart `3.9.2`
- Fresh `flutter pub get` no longer blocks on the earlier Riverpod/Test API solver conflict in this branch, because the repository now overrides `riverpod` and `flutter_riverpod` with local patched copies under `third_party/`
- For local dependency resolution in this workspace, still export `OHOS_SDK_HOME` or `HOS_SDK_HOME` first so the OHOS plugin toolchain probe can succeed
- The repository now also provides `bash scripts/ohos/verify_capabilities.sh [child-process|vpn|all]` to classify the remaining system-capability checks from live `hilog`, from a saved log file, or from an archived `hilog` directory instead of hand-written grep chains

Current verification boundary in this workspace:

- Verified on the current `phone` emulator:
  - HAP install and launch
  - Go core load and basic actions
  - URL import, deep-link import, QR import, and local file import
  - proxy list rendering, delay test, node switch, request page, connection fallback page
  - resources sync, about/update check, theme, locale, application settings
  - backup/restore with local files and WebDAV
  - real request emission after startup, including `ipwho.is`, `api.myip.com`, `ipapi.co`, `ident.me`, `ip-api.com`, `api.ip.sb`, and `ipinfo.io`
- Verified on the current `tablet` emulator (`127.0.0.1:5555`):
  - real deep-link subscription import against the `jisu` provider URL
  - real profile-card overflow menu rendering for `极速机场`
  - real `配置 -> 极速机场 -> 删除 -> 确定` destructive flow, plus deep-link restore of the baseline profile
  - real `配置 -> 极速机场 -> 预览` YAML preview page
  - real `配置 -> 极速机场 -> 编辑` persistence for `自动更新`
  - real `配置 -> 极速机场 -> 编辑 -> 配置 -> 编辑` route to the live YAML editor
  - real `配置 -> 极速机场 -> 编辑 -> 上传 -> 返回` cancel-safe flow without raw error toast
  - real `配置 -> 极速机场 -> 编辑 -> 上传 -> 选择 YAML -> 打开 -> 保存` read-and-save flow
  - real `配置 -> 极速机场 -> 同步` refresh path with updated `lastUpdate`
  - real `配置 -> 极速机场 -> 更多 -> 导出文件` write to OHOS shared download
  - real `配置 -> 极速机场 -> 更多 -> 复制链接 -> 添加配置 -> URL -> 粘贴` clipboard round-trip
  - dashboard start/stop with `网络 -> VPN` disabled
  - real proxy list rendering for the `PROXY` group, including direct node cards instead of placeholder data
  - real proxy selection from `🇺🇸美国洛杉矶1号` to `🇫🇷法国`
  - real reversible `代理 -> 设置 -> 图标样式` switching in list mode (`无 -> 无前置图标`, `仅图标 -> 恢复前置图标`)
  - real `请求` page rendering for the live `🇫🇷法国` request batch
  - real `连接` page rendering through the OHOS recent-request fallback path
  - real `资源` page rendering plus `GEOIP` sync completion
  - real reversible `资源 -> GEOIP -> 编辑` switching with persistence and reset verification (`默认 URL -> 临时变更 -> 重置恢复默认`)
  - real local backup write to shared download and local restore replay from that archive
  - real `应用程序 -> 自动检查更新` runtime control (`Toggle off -> next startup logs enabled=false + skip request`, `Toggle on -> next startup resumes GitHub releases/latest request`)
  - real reversible `应用程序 -> 选项卡动画` switching with navigation-path verification (`开启 -> animateToPage -> 关闭 -> jumpToPage`)
  - real reversible `应用程序 -> 退出时最小化` switching with launcher/background behavior verification (`开启 -> Back 回桌面且进程保留 -> 关闭 -> Back 回桌面且进程退出`)
  - real reversible `应用程序 -> 自动运行` switching with cold-start auto-start verification (`关闭 -> 开启 -> 冷启动自动进入运行态 -> 关闭`)
  - real reversible `应用程序 -> 自动关闭连接` switching with proxy-switch behavior verification (`开启 -> 关闭 -> 切节点无 closeConnections -> 开启 -> 切节点恢复 closeConnections`)
  - real reversible `应用程序 -> 仅统计代理` switching with direct-traffic filtering verification (`关闭 -> 直连统计非零 -> 开启 -> DIRECT 请求继续但统计归零 -> 关闭`)
  - real `应用程序 -> 日志捕获 -> 工具 -> 日志` round-trip on the current tablet session
  - real `关于 -> 检查更新` manual request path on the rebuilt tablet HAP (`GitHub releases/latest -> HTTP 200 -> compare local 0.8.93 vs remote v0.8.93 -> 已是最新版 dialog`, with failure text now separated from the no-update text)
  - real `关于 -> 开发者模式 -> 消息测试` round-trip on the current tablet session
  - real `关于 -> 开发者模式 -> 崩溃测试` core-shutdown path (`确认弹窗 -> crash callback -> shutdown 完成 -> Flutter 壳保留`)
  - real `关于 -> 开发者模式 -> 清除数据` destructive reset (`清空 preferences + profiles -> app 退出 -> 配置页空状态 -> deep link 恢复`)
  - real reversible `语言` switching (`中文 -> English -> 默认中文`)
  - real reversible `主题` switching (`深色 -> 浅色 -> 深色`)
  - real reversible `主题色彩 -> 内容主题` switching (`内容主题 -> 单色 -> 重进仍保持 -> 内容主题`)
  - real reversible `主题 -> 纯黑模式` switching (`关闭 -> 纯黑背景 + toggle on -> 关闭恢复`)
  - real `主题 -> 文本缩放` adjustment with persistence verification (`100% -> 136% -> 重进仍保持 -> 关闭开关`)
  - real reversible `进阶配置 -> 网络 -> 路由模式` switching (`使用配置 -> 绕过私有路由地址 -> 使用配置`)
  - real reversible `进阶配置 -> 网络 -> IPv6` switching (`关闭 -> 开启 -> 关闭`)
  - real reversible `进阶配置 -> 网络 -> 允许应用绕过VPN` switching (`开启 -> 关闭 -> 开启`)
  - real reversible `进阶配置 -> 网络 -> 系统代理` switching (`开启 -> 关闭 -> 开启`)
  - real reversible `进阶配置 -> 网络 -> DNS劫持` switching (`关闭 -> 开启 -> 关闭`)
  - real `进阶配置 -> 网络 -> 排除域名` add-persist-delete flow
  - real reversible `进阶配置 -> 网络 -> 栈模式` switching (`mixed -> system -> mixed`)
  - real `进阶配置 -> 网络 -> 路由地址` add-persist-delete flow with CIDR validation
  - real reversible `进阶配置 -> DNS -> IPv6` switching (`关闭 -> 开启 -> 关闭`)
  - real reversible `进阶配置 -> DNS -> 覆写DNS` switching (`关闭 -> 开启 -> 关闭`)
  - real reversible `进阶配置 -> DNS -> 状态` switching (`开启 -> 关闭 -> 开启`)
  - real reversible `进阶配置 -> DNS -> 使用Hosts` switching (`开启 -> 关闭 -> 开启`)
  - real reversible `进阶配置 -> DNS -> 使用系统Hosts` switching (`开启 -> 关闭 -> 开启`)
  - real reversible `进阶配置 -> DNS -> DNS模式` switching (`fakeIp -> normal -> fakeIp`)
  - real reversible `进阶配置 -> DNS -> PreferH3` switching (`关闭 -> 开启 -> 关闭`)
  - real reversible `进阶配置 -> DNS -> 遵守规则` switching (`关闭 -> 开启 -> 关闭`)
  - real `进阶配置 -> DNS -> Fakeip过滤` add-persist-delete flow (`*.lan / localhost.ptlogin2.qq.com -> 添加 *.fakeip-verify.test -> 重进仍存在 -> 删除恢复`)
  - real `进阶配置 -> DNS -> 域名服务器策略` add-edit-persist-reset flow (`+.internal.crop.com -> 10.0.0.1 -> 10.0.0.1w -> 重开编辑弹窗仍保持 -> 页面重置恢复` and `添加 q -> w -> 重开仍存在 -> 页面重置删除`)
  - real `进阶配置 -> 按需运行` add-and-persist flow (`空列表 -> FLCLASH-QA-SSID -> 重进后仍存在`)
  - real `配置 -> 极速机场 -> 更多 -> 覆写` mode switching and `自定义 -> 一键填入` writeback
  - real `基本配置 -> UA` persistence (`默认 -> ClashforWindows/0.19.23 -> 默认`)
  - real `基本配置 -> 端口` dialog persistence (`7890 -> 7891 -> 重进仍保持 -> 重置回 7890`)
  - real `基本配置 -> 测速链接` runtime verification (`临时 alias URL -> 代理页延迟测试命中本地 runtime test server -> 重置恢复默认`)
  - real `基本配置 -> Hosts` add-persist-runtime verification (`qa.flclash.test -> 127.0.0.1 -> 重进仍存在 -> cold start 后参与实际 delay probe`)
  - real `基本配置 -> 日志等级` persistence (`error -> debug -> 重进仍保持 -> error`)
  - real reversible `基本配置 -> IPv6` switching (`关闭 -> 开启 -> 关闭`)
  - real reversible `基本配置 -> 统一延迟` switching (`开启 -> 关闭 -> 开启`)
  - real reversible `基本配置 -> 局域网代理` switching (`关闭 -> 开启 -> 关闭`)
  - real reversible `基本配置 -> 追加系统DNS` switching (`关闭 -> 开启 -> 关闭`)
  - real reversible `基本配置 -> 查找进程` switching (`开启 -> 关闭 -> 重进仍保持 -> 开启`)
  - real reversible `基本配置 -> TCP并发` switching (`开启 -> 关闭 -> 重进仍保持 -> 开启`)
  - real reversible `基本配置 -> Geo低内存模式` switching (`开启 -> 关闭 -> 重进仍保持 -> 开启`)
  - real reversible `基本配置 -> 外部控制器` switching with live `9090` control-port verification (`开启 -> /version 可访问 -> 关闭 -> 连接被重置 -> 开启恢复`)
- Not an OHOS UI bug, but blocked by upstream data:
  - some imported proxy groups collapse to `COMPATIBLE` because the profile's `tag` provider currently returns `HTTP 401 Unauthorized`
- Blocked by the tested emulator image rather than this branch's Flutter logic:
  - VPN authorization cannot complete because `com.huawei.hmos.vpndialog` is missing on the tested Huawei emulator image, including the current `FlClash Tablet` target
  - native child-process startup cannot be validated on this `phone` image because the platform reports `Capability not support` / execution permission denial
- Historical-evidence status inside the current workspace:
  - the repository now retains enough archived `tablet` `hilog` data to re-classify the VPN blocker offline with either:
    - `bash scripts/ohos/verify_capabilities.sh vpn --log-file <filtered-log>`
    - `bash scripts/ohos/verify_capabilities.sh vpn --log-dir "$HOME/.Huawei/Emulator/deployed/FlClash Tablet/Log/hilog_tmp_2026-06-21T055156"`
  - that archived log data still directly shows:
    - `[AppPlugin] startVpn stack=...`
    - `bundle not exist -n com.huawei.hmos.vpndialog`
    - `[AppPlugin] startVpn failed error=startVpnExtensionAbility timeout`
    - `[OHOS-VPN] start failed: OHOS VPN 授权组件缺失，当前模拟器无法完成系统 VPN 启动`
  - a fresh low-load re-check on June 22, 2026 added new same-package UI evidence on the live `127.0.0.1:5555` tablet target:
    - `工具 -> 设置 -> 进阶配置 -> 网络` still exposes the real `VPN` row (`通过VpnService自动路由系统所有流量`)
    - the dashboard card editor still reports the `VPN` card toggle as enabled in the live layout dump:
      - `.ohos_live_current/vpn_after_second_topright.json`
      - `VPN\n选项` with `type=Toggle` and `checked=true`
    - tapping the top-right green circular dashboard action now triggers the real restart confirmation dialog:
      - `.ohos_live_current/vpn_after_exit_edit_mode.jpeg`
      - dialog text: `您确定要强制重启核心吗？`
    - the same restart-confirmation path was re-run again on June 23, 2026 and upgraded from "dialog visible" to "confirm button actually triggered a real core restart":
      - `.ohos_live_current/restart_probe_dialog.jpeg`
      - `.ohos_live_current/restart_probe_dialog.json`
      - dialog buttons were resolved from the live layout dump as:
        - `取消` at `[1424,1025][1583,1144]`
        - `确定` at `[1603,1025][1761,1144]`
      - after tapping the live `确定` button, same-round `hilog` captured:
        - `[OHOS-CORE] shutdown begin`
        - `[OHOS-CORE] invoke shutdown#... done`
        - `[OHOS-CORE] shutdown done result=true`
        - `[OHOS-CORE] preload begin`
        - `[OHOS-CORE] invoke initClash#... done`
      - same-round UI evidence after that confirm step:
        - `.ohos_live_current/after_restart_confirm_click.jpeg`
      - the dashboard `网络检测` card refreshed from `67.200.104.152` to `67.200.104.157`, which proves the restart-confirmation flow did not only repaint the UI; the app returned to live network probing after the core restart
    - a June 23 follow-up re-check confirms the same green action remains repeatable on the current target:
      - `.ohos_live_current/after_second_check_recover_try.jpeg`
      - the same restart-confirmation dialog reappears with identical live-layout button bounds
      - practical consequence:
        - the current workspace now has repeatable same-package evidence for the "confirm -> core restart -> dashboard network probe refresh" chain
        - the current workspace still does not have proof that this action exits a distinct dashboard-edit mode; it is safer to treat it only as a repeatable restart trigger on the tested tablet target
  - that same June 22 re-check still did not upgrade VPN from configuration evidence to runtime-pass evidence:
    - after the restart-confirmation flow, the short live `hilog` sampling window still did not capture `startVpn`, `FlClashVpnAbility`, or a new `com.huawei.hmos.vpndialog` failure line
    - practical consequence:
      - the current package still proves `VPN=on` state can be reached in the real UI
      - the current package now also proves that the VPN-related restart confirmation executes a real core restart on the current tablet target
      - the current package still does not have a same-round live log proving either successful VPN ability startup or the final blocker on this specific retest path
  - a June 23, 2026 follow-up re-check moved the same path onto the live `Pura 90` `HarmonyOS-6.1.1/phone_all_arm` target at `127.0.0.1:5555`:
    - fresh phone UI evidence now includes:
      - `.ohos_live_current/phone_probe_start.jpeg`
      - `.ohos_live_current/phone_network_page.jpeg`
      - `.ohos_live_current/phone_vpn_on_page.jpeg`
      - `.ohos_live_current/phone_restart_dialog_vpn_on.jpeg`
    - on that target:
      - `工具 -> 进阶配置 -> 网络 -> VPN` can still be toggled to `on` through the real page
      - the same top-right green dashboard action still opens `您确定要强制重启核心吗？`
    - after tapping the live `确定` button on the phone target, same-round `hilog` again captured only the core restart chain:
      - `[OHOS-CORE] shutdown begin`
      - `[OHOS-CORE] invoke shutdown#... done`
      - `[OHOS-CORE] shutdown done result=true`
      - `[OHOS-CORE] preload begin`
      - `[OHOS-CORE] invoke initClash#... done`
    - same-round post-confirm UI evidence on the phone target:
      - `.ohos_live_current/phone_after_restart_confirm_vpn_on.jpeg`
    - immediately after that restart-confirmation flow, `bash scripts/ohos/verify_capabilities.sh vpn --skip-install` still returned:
      - `INCONCLUSIVE no VPN startup attempt was observed in the filtered logs.`
    - the same short filtered phone `hilog` window still did not capture:
      - `startVpn`
      - `FlClashVpnAbility`
      - `com.huawei.hmos.vpndialog`
    - practical consequence:
      - the current phone image upgrades the evidence only from "tablet UI path exists" to "phone UI path also exists on the current package"
      - it still does not prove that this `phone_all_arm` image contains the missing VPN consent component or that the VPN ability ever starts
  - the `--log-dir` replay path has been re-run in the current workspace and still classifies the archived tablet VPN attempt as `FAIL`
  - by contrast, the current workspace no longer retains a directly reusable raw `hilog` / bridge log snippet that proves the historical `phone` child-process failure path end to end
  - re-running `bash scripts/ohos/verify_capabilities.sh child-process --log-dir "$HOME/.Huawei/Emulator/deployed/FlClash Tablet/Log/hilog_tmp_2026-06-21T055156"` remains `INCONCLUSIVE`, so the archived tablet logs still do not upgrade native child-process from documented finding to replayable raw evidence
  - a fresh June 23, 2026 cold-start re-check on the live `Pura 90` phone target also failed to upgrade child-process from prose conclusion to replayable raw evidence:
    - the re-check used:
      - `hdc shell 'hilog -r'`
      - `hdc shell 'aa force-stop com.follow.clash'`
      - `hdc shell 'aa start -a EntryAbility -b com.follow.clash'`
      - `bash scripts/ohos/verify_capabilities.sh child-process --skip-install`
    - same-round UI evidence after that cold start:
      - `.ohos_live_current/phone_after_cold_start.jpeg`
    - the verifier still returned:
      - `INCONCLUSIVE no decisive child-process evidence was observed.`
    - the fresh filtered startup logs on this phone target only showed:
      - `FlutterEngineCxnRegistry --> Adding plugin: AppPlugin`
      - `[OHOS-CORE] create CoreLib instance`
      - `[OHOS-CORE] preload begin`
      - `[OHOS-CORE] invoke initClash#... done`
    - the same cold-start window still did not capture:
      - `startCoreChildProcess`
      - `startBundledCoreProcess`
      - `Capability not support`
      - `fexecve failed: Permission denied`
      - `execv proc path failed: Permission denied`
  - practical consequence:
    - `VPN=on` failure on the tested tablet image is now backed by both prose documentation and archived raw log evidence inside the repository state
    - the current phone image also does not produce new replayable child-process evidence, so native child-process still requires a fresh supported `tablet` / `2in1` / PC-class target or a real device
  - a June 23, 2026 first-pass real-device attempt on the connected `HUAWEI Mate 80 Pro` (`SGT-AL00`, `OpenHarmony-6.1.1.120`) exposed a different blocker before any runtime verification could begin:
    - live target identity on this workspace:
      - `hdc list targets -v` shows `5JV0225B14001088 USB Connected localhost`
      - `param get const.product.name` returns `HUAWEI Mate 80 Pro`
      - `param get const.product.model` returns `SGT-AL00`
    - same-round real-device UI evidence:
      - `.ohos_live_current/real_device_unlocked_state.jpeg`
      - the device was connected and manually unlocked, but remained inside the system `开发者选项` page during the first install attempt
    - installing the current repository artifact on that device with:
      - `bash scripts/ohos/install_and_launch.sh dist/FlClash-0.8.93-ohos-arm64.hap`
      - failed before app launch with:
        - `code:9568257`
        - `error: fail to verify pkcs7 file`
    - the install helper was then hardened against this exact class of false positive:
      - `scripts/ohos/install_and_launch.sh` now captures `hdc install` output
      - it fails before launch when the install output contains `error:`, `failed to install`, `fail to`, or `Error Code:`
      - the re-run against `5JV0225B14001088` now exits with:
        - `ERROR: HAP install reported failure; see install output above.`
    - the same workspace build configuration still shows:
      - `ohos/build-profile.json5`
      - `type: "OpenHarmony"`
      - `runtimeOS: "OpenHarmony"`
      - signing assets under `ohos/hvigor/.signing/openharmony/`
      - those assets are generated from the SDK-bundled `OpenHarmony.p12` demo keystore
    - the current HAP's embedded signature was also verified locally with:
      - `java -jar /Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/lib/hap-sign-tool.jar verify-app -inFile dist/FlClash-0.8.93-ohos-arm64.hap -outCertChain /tmp/flclash-hap-verify/outCertChain.cer -outProfile /tmp/flclash-hap-verify/outProfile.p7b`
      - local verification succeeds as an OpenHarmony-signed package, but the exported certificate chain is explicitly OpenHarmony:
        - `Subject: CN=OpenHarmony Application Root CA, OU=OpenHarmony Team, O=OpenHarmony, C=CN`
        - `Subject: CN=OpenHarmony Application Release, OU=OpenHarmony Team, O=OpenHarmony, C=CN`
        - `Subject: CN=OpenHarmony Application CA, OU=OpenHarmony Team, O=OpenHarmony, C=CN`
      - the generated profile source is also OpenHarmony-only:
        - `developer-id: OpenHarmony`
        - `bundle-name: com.follow.clash`
        - `issuer: pki_internal`
    - follow-up local signing investigation on the same workspace confirmed:
      - the SDK has separate signing toolchains:
        - OpenHarmony: `openharmony/toolchains/lib/hap-sign-tool.jar`
        - HarmonyOS/HMS: `hms/toolchains/lib/Provisionsigntool.jar`
      - `Provisionsigntool.jar --help` describes Harmony provision signing as an account-backed flow:
        - `provisionsigner sign --in provision-input.json --out CAPABILITY.PROFILE --username ... --password ...`
      - DevEco's bundled HarmonyOS preview project uses:
        - `signingConfigs: []`
        - `runtimeOS: "HarmonyOS"`
        - string SDK versions such as `compatibleSdkVersion: "5.0.0(12)"`
      - hvigor's local error catalog points failed/missing signing materials back to:
        - `Project Structure > Project > Signing Configs`
        - `apply the signature material`
      - a local search under the current user and DevEco support/cache directories did not find a usable Huawei device signing set for this project:
        - no matching `*.p12`
        - no matching `*.p7b`
        - no matching `*.cer`
        - no `agconnect-services.json`
    - practical consequence:
      - the current HAP that works on the OpenHarmony emulator is not currently accepted by this Huawei real device
      - this is a packaging / signing acceptance blocker that happens before `VPN=on`, child-process, or ordinary runtime verification can even start on the real device
      - based on the local signing configuration, the PKCS7 verification failure, and the missing local HarmonyOS signing material, the current workspace still lacks a Huawei-device-accepted signing path for this branch
    - the same real-device attempt also re-confirmed an operational prerequisite for any future retry:
      - when the screen relocked, `aa start -a EntryAbility -b com.follow.clash` returned:
        - `Error Code:10106102`
        - `The device screen is locked during the application launch, unlock screen failed.`
      - therefore any future real-device install / launch retry must keep the phone unlocked throughout the launch window

Lessons from the current OHOS verification cycle:

- Separate platform limits, upstream data failures, and FlClash bugs before changing code:
  - the `代理` page did not regress because of OHOS rendering; the imported template's `tag` provider is currently returning `HTTP 401`, so Mihomo collapses those groups to `COMPATIBLE`
- Treat subscription fetch `User-Agent` values as runtime compatibility inputs, not branding fields:
  - on the current `jisu` subscription, `ClashforWindows/0.19.23` is now treated as an outdated client token and only returns placeholder nodes
  - on the same endpoint, the OHOS build now verifies real import plus runtime traffic with `clash.meta/1.10.0`
- Treat screenshots as weak evidence unless they are paired with a real side effect or runtime log:
  - for example, `资源 -> GEOIP -> 同步` is only counted as verified because the UI state change, request events, and detached action callback all line up
- Avoid long raw URL input when automating subscription import on the HarmonyOS emulator:
  - `uitest uiInput inputText` can truncate or corrupt query strings, so repeatable validation should prefer deep links, QR import, or a short redirect URL
- Any successful manual recovery step must be written back into source or scripts immediately:
  - the OHOS-specific callback normalization and the build/runtime helper scripts are now part of the repository so the fix survives the next rebuild
- The current Huawei `phone` emulator must be treated as a constrained validation target, not as proof that the product logic is wrong:
  - missing `com.huawei.hmos.vpndialog` and denied child-process execution are platform/runtime limits on this image, not user-facing Flutter widget defects
- The same separation applies on the current `tablet` emulator:
  - `VPN=off` works on the same build and session where `VPN=on` fails, so the blocking condition is the missing system consent component rather than a generic FlClash startup regression

Docker reproduction command for the Go TLS issue:

```bash
GO_TAGS='1.25-alpine' scripts/ohos/reproduce_go_musl_tls.sh
```

Expected evidence from that script:

- `Error relocating ./libgo.so: : initial-exec TLS resolves to dynamic definition in ./libgo.so`
- `Error relocating ./host.so: : initial-exec TLS resolves to dynamic definition in ./host.so`

During the build, `ohos/hvigor/hvigor-wrapper.js` prepares these generated signing assets under `ohos/hvigor/.signing/openharmony/`:

- `OpenHarmonyApplicationRelease.cer`
- `OpenHarmonyProfileRelease.json`
- `OpenHarmonyProfileRelease.p7b`

These files are generated from the SDK's built-in `OpenHarmony.p12` demo keystore and are ignored by git.
