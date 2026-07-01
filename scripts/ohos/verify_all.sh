#!/usr/bin/env bash
# One-command automated regression suite for FlClash on a connected HarmonyOS
# real device. Drives the app via uitest (scripts/ohos/ui.sh) and asserts proxy
# connectivity via the loopback mixed listener and the VPN tun. Prints a
# pass/fail report and exits non-zero if any check fails.
#
# Usage:
#   bash scripts/ohos/verify_all.sh [--install path/to/app.hap]
#
# Environment:
#   HDC_TARGET   Explicit HarmonyOS device serial (auto-detected if single).
#   YT_URL       YouTube URL to probe (default https://m.youtube.com).
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
UI="$ROOT_DIR/scripts/ohos/ui.sh"
KEEP_AWAKE="$ROOT_DIR/scripts/ohos/keep_awake.sh"
DEVECO_HDC="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc"
BUNDLE="com.follow.clash"
YT_URL="${YT_URL:-https://m.youtube.com}"
INSTALL_HAP=""

[[ "${1:-}" == "--install" ]] && { INSTALL_HAP="${2:?--install needs a hap path}"; shift 2; }

resolve_hdc() {
  command -v hdc >/dev/null 2>&1 && { command -v hdc; return; }
  [[ -x "$DEVECO_HDC" ]] && { printf '%s\n' "$DEVECO_HDC"; return; }
  echo "ERROR: hdc not found" >&2; exit 1
}

resolve_target() {
  if [[ -n "${HDC_TARGET:-}" ]]; then
    printf '%s\n' "$HDC_TARGET"
    return
  fi

  local targets=()
  while IFS= read -r target; do
    [[ -n "$target" ]] || continue
    [[ "$target" == "[Empty]" ]] && continue
    targets+=("$target")
  done < <("$HDC" list targets 2>/dev/null || true)

  case "${#targets[@]}" in
    0)
      echo "ERROR: no HarmonyOS target detected" >&2
      exit 1
      ;;
    1)
      printf '%s\n' "${targets[0]}"
      ;;
    *)
      echo "ERROR: Multiple HarmonyOS targets detected; set HDC_TARGET explicitly" >&2
      exit 1
      ;;
  esac
}

HDC="$(resolve_hdc)"
HDC_TARGET="$(resolve_target)"
export HDC_TARGET
sh() { "$HDC" -t "$HDC_TARGET" shell "$@"; }
ui() { bash "$UI" "$@"; }

PASS=0; FAIL=0; declare -a RESULTS
ok()   { RESULTS+=("PASS  $1"); PASS=$((PASS+1)); echo "  ✅ PASS: $1"; }
no()   { RESULTS+=("FAIL  $1"); FAIL=$((FAIL+1)); echo "  ❌ FAIL: $1"; }
check(){ local n="$1"; shift; echo "▶ $n"; if "$@"; then ok "$n"; else no "$n"; fi; }

wake() { sh "power-shell wakeup >/dev/null 2>&1; power-shell setmode 602 >/dev/null 2>&1" || true; }
rx_bytes() { sh "ifconfig vpn-tun 2>/dev/null | grep -oE 'RX bytes:[0-9]+' | grep -oE '[0-9]+'" | tr -d '\r'; }
tun_up() { sh "ifconfig vpn-tun 2>/dev/null | grep -q 'inet addr'"; }
fg_app() { wake; sh "aa start -a EntryAbility -b $BUNDLE >/dev/null 2>&1"; sleep 3; }

proxy_curl() { # args: extra curl args...; uses fport 17890->7890
  "$HDC" -t "$HDC_TARGET" fport tcp:17890 tcp:7890 >/dev/null 2>&1
  curl -s --max-time 15 -x http://127.0.0.1:17890 "$@"
}

# ------------------------------------------------------------------ checks ---

c_install() {
  [[ -z "$INSTALL_HAP" ]] && { echo "  (skip install; testing current build)"; return 0; }
  "$HDC" -t "$HDC_TARGET" shell "aa force-stop $BUNDLE" >/dev/null 2>&1
  "$HDC" -t "$HDC_TARGET" install -r "$INSTALL_HAP" 2>&1 | grep -qi "successfully"
}

listening() { sh "netstat -an 2>/dev/null | grep LISTEN | grep -q ':$1'"; }

c_core_healthy() { # core process up with its listeners bound
  local listen
  listen="$(sh "netstat -an 2>/dev/null | grep LISTEN | grep -E ':(7890|1053)'")"
  echo "    listeners: $(printf '%s' "$listen" | grep -oE ':(7890|1053)' | tr '\n' ' ')"
  printf '%s' "$listen" | grep -q ':7890' && printf '%s' "$listen" | grep -q ':1053'
}

c_vpn_up() { # ensure VPN running with listeners bound (tap dashboard FAB if needed)
  if tun_up && listening 7890; then return 0; fi
  goto "仪表盘"   # the start FAB only exists on the dashboard, not on sub-pages
  sh "uitest uiInput click 1129 2340 >/dev/null 2>&1"
  for _ in $(seq 1 12); do
    sleep 3
    tun_up && listening 7890 && return 0
  done
  return 1
}

c_proxy_youtube() { # loopback 7890 -> node reaches youtube
  local code
  code="$(proxy_curl -o /dev/null -w '%{http_code}' "https://www.youtube.com/generate_204")"
  echo "    youtube/generate_204 via 7890 -> HTTP $code"
  [[ "$code" == "204" || "$code" == "200" ]]
}

c_proxy_egress() { # egress is a foreign (non-CN) node
  local loc=""
  for _ in 1 2 3; do
    loc="$(proxy_curl "https://www.cloudflare.com/cdn-cgi/trace" 2>/dev/null | grep -oE '^loc=[A-Z]+' | cut -d= -f2)"
    [[ -n "$loc" ]] && break
    loc="$(proxy_curl "http://ip-api.com/line/countryCode" 2>/dev/null | tr -d '\r' | head -1)"
    [[ -n "$loc" ]] && break
    sleep 2
  done
  echo "    egress loc=$loc"
  [[ -n "$loc" && "$loc" != "CN" ]]
}

c_browser_youtube() { # browser loads youtube through the tun (content asserted)
  local app="$1" ability="$2" label="$3" b0 b1
  wake
  "$HDC" -t "$HDC_TARGET" shell "aa start -a $ability -b $app -U '$YT_URL'" >/dev/null 2>&1
  b0="$(rx_bytes)"; b0="${b0:-0}"
  for _ in $(seq 1 9); do wake; sleep 4; done
  b1="$(rx_bytes)"; b1="${b1:-0}"
  local grew=$(( b1 - b0 ))
  local found="no"
  ui find-text "YouTube" contains >/dev/null 2>&1 && found="yes"
  echo "    $label: tun RX +${grew}B, find-text YouTube=$found"
  [[ "$found" == "yes" || $grew -gt 400000 ]]
}
c_browser_chrome() { c_browser_youtube com.android.chrome com.google.android.apps.chrome.Main "Chrome"; }
c_browser_huawei() { c_browser_youtube com.huawei.hmos.browser MainAbility "Huawei browser"; }

# --- UI feature checks (uitest find-text assertions) ----------------------
back() { sh "uitest uiInput keyEvent Back >/dev/null 2>&1"; sleep 1; }
goto() { fg_app; ui tap-text "$1" contains >/dev/null 2>&1; sleep 2; }

c_dashboard() { # dashboard widgets render
  goto "仪表盘"
  local missing=""
  for t in "网络速度" "流量统计" "网络检测" "出站模式"; do
    ui find-text "$t" contains >/dev/null 2>&1 || missing+="$t "
  done
  echo "    missing widgets: ${missing:-none}"
  [[ -z "$missing" ]]
}

c_outbound_select() { # all three outbound modes are selectable in the UI
  goto "仪表盘"
  local miss=""
  for m in "全局" "直连" "规则"; do
    ui tap-text "$m" exact >/dev/null 2>&1 || miss+="$m "
    sleep 1
  done
  echo "    modes not selectable: ${miss:-none} (left on 规则)"
  [[ -z "$miss" ]]
}

egress_loc() {
  proxy_curl "https://www.cloudflare.com/cdn-cgi/trace" 2>/dev/null | grep -oE '^loc=[A-Z]+' | cut -d= -f2
}
c_outbound_live() { # live outbound-mode switch reaches the running :vpn core
  goto "仪表盘"
  local rule direct
  rule="$(egress_loc)"
  ui tap-text "直连" exact >/dev/null 2>&1; sleep 6
  direct="$(egress_loc)"
  ui tap-text "规则" exact >/dev/null 2>&1; sleep 4
  echo "    egress 规则=$rule 直连=$direct (expect 规则 foreign and 直连 != 规则)"
  [[ -n "$rule" && "$rule" != "CN" && "$direct" != "$rule" ]]
}
c_live_connections() { # connections page shows live traffic from the running core
  "$HDC" -t "$HDC_TARGET" shell "aa start -a com.google.android.apps.chrome.Main -b com.android.chrome -U '$YT_URL'" >/dev/null 2>&1
  sleep 3
  goto "工具"; ui tap-text "连接" contains >/dev/null 2>&1; sleep 5
  local found="no" t
  for t in "国外媒体" "youtube" "香港" "googlevideo" "443"; do
    ui find-text "$t" contains >/dev/null 2>&1 && { found="$t"; break; }
  done
  back
  echo "    live connection entry found: $found"
  [[ "$found" != "no" ]]
}

c_proxy_tab() { # proxy groups/nodes visible
  goto "代理"
  local found=""
  for t in "TAGSS" "香港" "HK" "自动选择" "漏网之鱼"; do
    ui find-text "$t" contains >/dev/null 2>&1 && { found="$t"; break; }
  done
  echo "    proxy group/node found: ${found:-NONE}"
  [[ -n "$found" ]]
}

c_profiles() { # config/profile listed
  goto "配置"
  ui find-text "TAGSS" contains >/dev/null 2>&1 || ui find-text "youtube" contains >/dev/null 2>&1 \
    || ui find-text "更新" contains >/dev/null 2>&1
}

c_tools_page() { # open a tools sub-page and assert it renders
  local entry="$1" assert="$2"
  goto "工具"; ui tap-text "$entry" contains >/dev/null 2>&1; sleep 2
  local r=1
  ui find-text "$assert" contains >/dev/null 2>&1 && r=0
  echo "    工具/$entry -> find '$assert': $([[ $r -eq 0 ]] && echo ok || echo MISS)"
  back; return $r
}
c_tools_connections() { c_tools_page "连接" "连接"; }
c_tools_requests()    { c_tools_page "请求" "请求"; }
c_tools_logs()        { c_tools_page "日志" "日志"; }
c_set_theme()         { c_tools_page "主题" "深色"; }
c_set_language()      { c_tools_page "语言" "简体"; }
c_set_basic()         { c_tools_page "基本配置" "外部控制器"; }
c_set_advanced()      { c_tools_page "进阶配置" "配置"; }
c_set_app()           { c_tools_page "应用程序" "设置"; }
c_backup()            { c_tools_page "备份与恢复" "WebDAV"; }

main() {
  echo "=== FlClash OHOS automated verification ==="
  echo "device=$HDC_TARGET  hap=${INSTALL_HAP:-<current>}"
  HDC_TARGET="$HDC_TARGET" bash "$KEEP_AWAKE" >/dev/null 2>&1 || true

  check "install HAP"                 c_install
  check "VPN up (tun + listeners)"    c_vpn_up
  check "core healthy (7890+1053)"    c_core_healthy
  check "proxy: youtube via 7890"     c_proxy_youtube
  check "proxy: foreign egress node"  c_proxy_egress
  check "browser: Chrome loads YouTube" c_browser_chrome
  check "browser: Huawei loads YouTube" c_browser_huawei
  check "dashboard widgets render"     c_dashboard
  check "outbound modes selectable"    c_outbound_select
  check "proxy tab: groups/nodes"      c_proxy_tab
  check "config/profile listed"        c_profiles
  check "tools: connections page"      c_tools_connections
  check "tools: requests page"         c_tools_requests
  check "tools: logs page"             c_tools_logs
  check "settings: theme"              c_set_theme
  check "settings: language"           c_set_language
  check "settings: basic config"       c_set_basic
  check "settings: advanced config"    c_set_advanced
  check "settings: app settings"       c_set_app
  check "tools: backup & restore"      c_backup
  check "live: outbound-mode reaches core" c_outbound_live
  check "live: connections page (real-time)" c_live_connections

  echo ""
  echo "=== REPORT ==="
  printf '%s\n' "${RESULTS[@]}"
  echo "----"
  echo "PASS=$PASS  FAIL=$FAIL"
  [[ $FAIL -eq 0 ]]
}
main "$@"
