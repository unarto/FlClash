#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
KEEP_AWAKE_SCRIPT="$ROOT_DIR/scripts/ohos/keep_awake.sh"
UI_SCRIPT="$ROOT_DIR/scripts/ohos/ui.sh"
LOG_PATTERN_SCRIPT="$ROOT_DIR/scripts/ohos/log_patterns.mjs"
CHROME_LAYOUT_SCRIPT="$ROOT_DIR/scripts/ohos/chrome_layout.mjs"
OUT_DIR_DEFAULT="$ROOT_DIR/.ohos_live"
DEVECO_HDC="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc"
DEFAULT_BROWSER_BUNDLE="com.huawei.hmos.browser"
DEFAULT_BROWSER_ABILITY="MainAbility"
DEFAULT_BROWSER_URI="https://www.youtube.com"
DEFAULT_SHELL_ASSISTANT_BUNDLE="com.huawei.shell_assistant"
DEFAULT_FLCLASH_BUNDLE="com.follow.clash"
DEFAULT_FLCLASH_ABILITY="EntryAbility"
DEFAULT_VPN_TOGGLE_X=1126
DEFAULT_VPN_TOGGLE_Y=2300
DEFAULT_FLCLASH_LAUNCH_WAIT=5
DEFAULT_VPN_START_WAIT=8
DEFAULT_BROWSER_LAUNCH_WAIT=15
DEFAULT_BROWSER_URL_INPUT_WAIT=3
DEFAULT_BROWSER_INTERACT_WAIT=5
DEFAULT_BROWSER_SETTLE_WAIT=15

usage() {
  cat <<'EOF'
Usage:
  bash scripts/ohos/verify_browser_vpn.sh

Environment:
  HDC_TARGET             Explicit HarmonyOS device target.
  BROWSER_BUNDLE         Override browser bundle. Default: com.huawei.hmos.browser
  BROWSER_ABILITY        Override browser ability. Default: MainAbility
  BROWSER_URI            Override launch URI. Default: https://www.youtube.com
  SHELL_ASSISTANT_BUNDLE Override browser host bundle. Default: com.huawei.shell_assistant
  FLCLASH_BUNDLE         Override FlClash bundle. Default: com.follow.clash
  FLCLASH_ABILITY        Override FlClash ability. Default: EntryAbility
  VPN_TOGGLE_X           Dashboard VPN button X coordinate. Default: 1126
  VPN_TOGGLE_Y           Dashboard VPN button Y coordinate. Default: 2300
  FLCLASH_LAUNCH_WAIT    Seconds to wait after launching FlClash. Default: 5
  VPN_START_WAIT         Seconds to wait after tapping start VPN. Default: 8
  BROWSER_LAUNCH_WAIT    Seconds to wait after launching the browser. Default: 15
  BROWSER_URL_INPUT_WAIT Seconds to wait after typing the browser URI. Default: 3
  BROWSER_INTERACT_WAIT  Seconds to wait after browser text probing/capture. Default: 5
  BROWSER_SETTLE_WAIT    Extra seconds before a delayed second counter sample. Default: 15
  OUT_DIR                Output directory for log artifacts. Default: .ohos_live

What this verifies:
  1. Force-stop FlClash, the browser, and the browser host bundle, then clear browser-host app data.
  2. Launch FlClash and start the VPN from the dashboard.
  3. Launch the browser main ability, then submit the target URI inside the browser search page.
  4. Capture vpn-tun counters before and after browser traffic.
  5. Save focused hilog evidence for browser-specific ArkWeb / Cronet activity.
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

resolve_hdc() {
  if command -v hdc >/dev/null 2>&1; then
    command -v hdc
    return
  fi
  if [[ -x "$DEVECO_HDC" ]]; then
    printf '%s\n' "$DEVECO_HDC"
    return
  fi
  fail "Missing required command: hdc"
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
  done < <("$HDC_BIN" list targets 2>/dev/null || true)

  case "${#targets[@]}" in
    0) fail "No HarmonyOS target detected" ;;
    1) printf '%s\n' "${targets[0]}" ;;
    *) fail "Multiple HarmonyOS targets detected; set HDC_TARGET explicitly" ;;
  esac
}

run_hdc() {
  local target="$1"
  shift
  "$HDC_BIN" -t "$target" "$@"
}

resolve_uri_host() {
  local uri="$1"
  node -e '
const raw = process.argv[1] ?? "";
if (!raw) {
  process.exit(0);
}
try {
  const normalized = raw.includes("://") ? raw : `https://${raw}`;
  process.stdout.write(new URL(normalized).host);
} catch (_) {}
' "$uri"
}

escape_ere() {
  printf '%s' "$1" | sed -e 's/[][(){}.^$+*?|\\]/\\&/g'
}

try_tap_browser_target() {
  local target="$1"
  local text="$2"
  local mode="${3:-contains}"
  if HDC_TARGET="$target" bash "$UI_SCRIPT" find-text "$text" "$mode" >/dev/null 2>&1; then
    if HDC_TARGET="$target" bash "$UI_SCRIPT" tap-text-repeat "$text" "$mode"; then
      return 0
    fi
  fi
  return 1
}

try_tap_browser_id() {
  local target="$1"
  local id="$2"
  if HDC_TARGET="$target" bash "$UI_SCRIPT" tap-id "$id" >/dev/null 2>&1; then
    return 0
  fi
  if HDC_TARGET="$target" bash "$UI_SCRIPT" tap-key "$id" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

main() {
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
  fi

  HDC_BIN=$(resolve_hdc)
  local target
  target=$(resolve_target)

  local browser_bundle="${BROWSER_BUNDLE:-$DEFAULT_BROWSER_BUNDLE}"
  local browser_ability="${BROWSER_ABILITY:-$DEFAULT_BROWSER_ABILITY}"
  local browser_uri="${BROWSER_URI:-$DEFAULT_BROWSER_URI}"
  local browser_uri_host
  browser_uri_host=$(resolve_uri_host "$browser_uri")
  local browser_uri_probe="$browser_uri_host"
  if [[ "$browser_uri_probe" == www.* ]]; then
    browser_uri_probe="${browser_uri_probe#www.}"
  fi
  local shell_assistant_bundle="${SHELL_ASSISTANT_BUNDLE:-$DEFAULT_SHELL_ASSISTANT_BUNDLE}"
  local browser_bundle_pattern
  browser_bundle_pattern=$(escape_ere "$browser_bundle")
  local browser_uri_host_pattern
  browser_uri_host_pattern=$(escape_ere "$browser_uri_host")
  local shell_assistant_bundle_pattern
  shell_assistant_bundle_pattern=$(escape_ere "$shell_assistant_bundle")
  local browser_uri_is_youtube=0
  if [[ "$browser_uri_host" == *"youtube.com"* || "$browser_uri_host" == *"youtu.be"* ]]; then
    browser_uri_is_youtube=1
  fi
  local flclash_bundle="${FLCLASH_BUNDLE:-$DEFAULT_FLCLASH_BUNDLE}"
  local flclash_ability="${FLCLASH_ABILITY:-$DEFAULT_FLCLASH_ABILITY}"
  local vpn_toggle_x="${VPN_TOGGLE_X:-$DEFAULT_VPN_TOGGLE_X}"
  local vpn_toggle_y="${VPN_TOGGLE_Y:-$DEFAULT_VPN_TOGGLE_Y}"
  local flclash_launch_wait="${FLCLASH_LAUNCH_WAIT:-$DEFAULT_FLCLASH_LAUNCH_WAIT}"
  local vpn_start_wait="${VPN_START_WAIT:-$DEFAULT_VPN_START_WAIT}"
  local browser_launch_wait="${BROWSER_LAUNCH_WAIT:-$DEFAULT_BROWSER_LAUNCH_WAIT}"
  local browser_url_input_wait="${BROWSER_URL_INPUT_WAIT:-$DEFAULT_BROWSER_URL_INPUT_WAIT}"
  local browser_interact_wait="${BROWSER_INTERACT_WAIT:-$DEFAULT_BROWSER_INTERACT_WAIT}"
  local browser_settle_wait="${BROWSER_SETTLE_WAIT:-$DEFAULT_BROWSER_SETTLE_WAIT}"
  local out_dir="${OUT_DIR:-$OUT_DIR_DEFAULT}"
  mkdir -p "$out_dir"

  [[ -f "$KEEP_AWAKE_SCRIPT" ]] || fail "Missing keep-awake script: $KEEP_AWAKE_SCRIPT"
  [[ -f "$UI_SCRIPT" ]] || fail "Missing UI script: $UI_SCRIPT"
  [[ -f "$LOG_PATTERN_SCRIPT" ]] || fail "Missing log pattern helper: $LOG_PATTERN_SCRIPT"
  [[ -f "$CHROME_LAYOUT_SCRIPT" ]] || fail "Missing layout helper: $CHROME_LAYOUT_SCRIPT"
  local startup_log_pattern
  startup_log_pattern=$(node "$LOG_PATTERN_SCRIPT" startup)
  local browser_log_pattern
  browser_log_pattern=$(node "$LOG_PATTERN_SCRIPT" browser)
  browser_log_pattern="${browser_log_pattern}|${browser_bundle_pattern}|${shell_assistant_bundle_pattern}"
  if [[ -n "$browser_uri_host_pattern" ]]; then
    browser_log_pattern="${browser_log_pattern}|${browser_uri_host_pattern}"
  fi

  HDC_TARGET="$target" bash "$KEEP_AWAKE_SCRIPT" >/dev/null

  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)
  local log_file="$out_dir/browser_vpn_${timestamp}.log"
  local launch_capture_name="browser_launch_${timestamp}"
  local settled_capture_name="browser_settled_${timestamp}"
  local submit_capture_name="browser_submit_${timestamp}"

  {
    echo "=== target ==="
    echo "hdc_target=$target"
    echo "browser_bundle=$browser_bundle"
    echo "browser_ability=$browser_ability"
    echo "browser_uri=$browser_uri"
    echo "browser_uri_host=$browser_uri_host"
    echo "shell_assistant_bundle=$shell_assistant_bundle"
    echo "flclash_bundle=$flclash_bundle"
    echo "flclash_ability=$flclash_ability"
    echo

    echo "=== cold stop + clear ==="
    run_hdc "$target" shell "aa force-stop $browser_bundle >/dev/null 2>&1 || true; aa force-stop $flclash_bundle >/dev/null 2>&1 || true; aa force-stop $shell_assistant_bundle >/dev/null 2>&1 || true; bm clean -n $browser_bundle -c >/dev/null 2>&1 || true; bm clean -n $shell_assistant_bundle -c >/dev/null 2>&1 || true; hilog -r"
    echo

    echo "=== launch FlClash ==="
    run_hdc "$target" shell "aa start -a $flclash_ability -b $flclash_bundle"
    sleep "$flclash_launch_wait"
    echo

    echo "=== start VPN ==="
    HDC_TARGET="$target" bash "$UI_SCRIPT" tap "$vpn_toggle_x" "$vpn_toggle_y"
    sleep "$vpn_start_wait"
    echo

    echo "=== counters after vpn start ==="
    run_hdc "$target" shell "ifconfig vpn-tun 2>/dev/null | sed -n '1,8p'; true"
    echo

    echo "=== vpn startup diagnostic logs ==="
    run_hdc "$target" shell "hilog -x | grep -E '$startup_log_pattern' | tail -n 320 || true"
    echo

    echo "=== launch browser ==="
    run_hdc "$target" shell "aa start -a $browser_ability -b $browser_bundle"
    sleep "$browser_launch_wait"
    HDC_TARGET="$target" bash "$UI_SCRIPT" capture "$launch_capture_name" "$out_dir"
    echo "launch_capture=$out_dir/${launch_capture_name}.json"
    echo

    echo "=== submit browser search page when needed ==="
    if try_tap_browser_id "$target" "search_box_in_homepage"; then
      echo "open_search=search_box_in_homepage"
      sleep 2
    else
      echo "open_search=none"
    fi
    if try_tap_browser_id "$target" "url_input_in_search"; then
      echo "input_target=url_input_in_search"
    elif try_tap_browser_id "$target" "search_bar_in_search_page"; then
      echo "input_target=search_bar_in_search_page"
    elif try_tap_browser_target "$target" "搜索" exact; then
      echo "input_target=search"
    else
      echo "input_target=none"
    fi
    sleep 1
    HDC_TARGET="$target" bash "$UI_SCRIPT" text "$browser_uri"
    sleep "$browser_url_input_wait"
    HDC_TARGET="$target" bash "$UI_SCRIPT" capture "$submit_capture_name" "$out_dir"
    echo "submitted_target=browser-uri"
    local submit_capture_json="$out_dir/${submit_capture_name}.json"
    local submit_action="none"
    if try_tap_browser_id "$target" "search_btn_in_search"; then
      submit_action="search_btn_in_search"
    elif try_tap_browser_target "$target" "$browser_uri" exact; then
      submit_action="$browser_uri"
    elif [[ -n "$browser_uri_probe" ]] && try_tap_browser_target "$target" "$browser_uri_probe" contains; then
      submit_action="$browser_uri_probe"
    elif (( browser_uri_is_youtube )) && try_tap_browser_target "$target" "youtube.com" contains; then
      submit_action="youtube.com"
    else
      local browser_submit_point=""
      if [[ -s "$submit_capture_json" ]]; then
        browser_submit_point=$(node "$CHROME_LAYOUT_SCRIPT" search-result "$submit_capture_json" "$browser_uri" || true)
        if [[ -z "$browser_submit_point" ]]; then
          browser_submit_point=$(node "$CHROME_LAYOUT_SCRIPT" search-submit "$submit_capture_json" || true)
        fi
      fi
      if [[ -z "$browser_submit_point" ]]; then
        sleep "$browser_interact_wait"
        HDC_TARGET="$target" bash "$UI_SCRIPT" capture "$submit_capture_name" "$out_dir"
        if [[ -s "$submit_capture_json" ]]; then
          browser_submit_point=$(node "$CHROME_LAYOUT_SCRIPT" search-result "$submit_capture_json" "$browser_uri" || true)
          if [[ -z "$browser_submit_point" ]]; then
            browser_submit_point=$(node "$CHROME_LAYOUT_SCRIPT" search-submit "$submit_capture_json" || true)
          fi
        fi
      fi
      if [[ -n "$browser_submit_point" ]]; then
        local submit_x submit_y
        read -r submit_x submit_y <<<"$browser_submit_point"
        run_hdc "$target" shell "uitest uiInput click $submit_x $submit_y"
        submit_action="tap:$submit_x,$submit_y"
      fi
    fi
    echo "submit_action=$submit_action"
    sleep "$browser_interact_wait"
    echo

    echo "=== counters after browser ==="
    run_hdc "$target" shell "ifconfig vpn-tun 2>/dev/null | sed -n '1,8p'; true"
    echo

    echo "=== browser text probes ==="
    if [[ -n "$browser_uri_host" ]]; then
      HDC_TARGET="$target" bash "$UI_SCRIPT" find-text "$browser_uri_host" contains || true
    fi
    if [[ -n "$browser_uri_probe" && "$browser_uri_probe" != "$browser_uri_host" ]]; then
      HDC_TARGET="$target" bash "$UI_SCRIPT" find-text "$browser_uri_probe" contains || true
    fi
    if (( browser_uri_is_youtube )); then
      HDC_TARGET="$target" bash "$UI_SCRIPT" find-text "YouTube" contains || true
      HDC_TARGET="$target" bash "$UI_SCRIPT" find-text "youtube.com" contains || true
      HDC_TARGET="$target" bash "$UI_SCRIPT" find-text "m.youtube.com" contains || true
    fi
    sleep "$browser_interact_wait"
    echo

    echo "=== delayed counters after browser ==="
    sleep "$browser_settle_wait"
    HDC_TARGET="$target" bash "$UI_SCRIPT" capture "$settled_capture_name" "$out_dir"
    echo "settled_capture=$out_dir/${settled_capture_name}.json"
    run_hdc "$target" shell "ifconfig vpn-tun 2>/dev/null | sed -n '1,8p'; true"
    echo

    echo "=== process list ==="
    run_hdc "$target" shell "ps -A -o pid,uid,name | grep -E '$browser_bundle_pattern|com\.huawei\.hmos\.aidispatchservice|$shell_assistant_bundle_pattern' || true"
    echo

    echo "=== mission dump ==="
    run_hdc "$target" shell "aa dump -a | grep -n -A8 -B2 '$browser_bundle_pattern|com\.huawei\.hmos\.aidispatchservice|$shell_assistant_bundle_pattern' || true"
    echo

    echo "=== vpn setup logs ==="
    run_hdc "$target" shell "hilog -x | grep -E '$startup_log_pattern' | tail -n 320 || true"
    echo

    echo "=== browser + flclash logs ==="
    run_hdc "$target" shell "hilog -x | grep -E '$browser_log_pattern' | tail -n 520 || true"
  } | tee "$log_file"

  echo
  echo "Saved browser VPN verification log:"
  echo "$log_file"
}

main "$@"
