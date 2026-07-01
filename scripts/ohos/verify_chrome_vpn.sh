#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
KEEP_AWAKE_SCRIPT="$ROOT_DIR/scripts/ohos/keep_awake.sh"
UI_SCRIPT="$ROOT_DIR/scripts/ohos/ui.sh"
LOG_PATTERN_SCRIPT="$ROOT_DIR/scripts/ohos/log_patterns.mjs"
CHROME_LAYOUT_SCRIPT="$ROOT_DIR/scripts/ohos/chrome_layout.mjs"
OUT_DIR_DEFAULT="$ROOT_DIR/.ohos_live"
DEVECO_HDC="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc"
DEFAULT_CHROME_BUNDLE="com.android.chrome"
DEFAULT_CHROME_ABILITY="com.google.android.apps.chrome.Main"
DEFAULT_CHROME_URI="https://www.youtube.com"
DEFAULT_SHELL_ASSISTANT_BUNDLE="com.huawei.shell_assistant"
DEFAULT_FLCLASH_BUNDLE="com.follow.clash"
DEFAULT_FLCLASH_ABILITY="EntryAbility"
DEFAULT_CHROME_URL_BAR_X=521
DEFAULT_CHROME_URL_BAR_Y=240
DEFAULT_VPN_TOGGLE_X=1126
DEFAULT_VPN_TOGGLE_Y=2300
DEFAULT_FLCLASH_LAUNCH_WAIT=5
DEFAULT_VPN_START_WAIT=8
DEFAULT_CHROME_LAUNCH_WAIT=12
DEFAULT_CHROME_URL_INPUT_WAIT=3
DEFAULT_CHROME_INTERACT_WAIT=8
DEFAULT_CHROME_SETTLE_WAIT=12

usage() {
  cat <<'EOF'
Usage:
  bash scripts/ohos/verify_chrome_vpn.sh

Environment:
  HDC_TARGET              Explicit HarmonyOS device target.
  CHROME_BUNDLE           Override Chrome bundle. Default: com.android.chrome
  CHROME_ABILITY          Override Chrome ability. Default: com.google.android.apps.chrome.Main
  CHROME_URI              Override launch URI. Default: https://www.youtube.com
  SHELL_ASSISTANT_BUNDLE  Override compat host bundle. Default: com.huawei.shell_assistant
  FLCLASH_BUNDLE          Override FlClash bundle. Default: com.follow.clash
  FLCLASH_ABILITY         Override FlClash ability. Default: EntryAbility
  CHROME_URL_BAR_X        Chrome address bar X coordinate. Default: 521
  CHROME_URL_BAR_Y        Chrome address bar Y coordinate. Default: 240
  VPN_TOGGLE_X            Dashboard VPN button X coordinate. Default: 1126
  VPN_TOGGLE_Y            Dashboard VPN button Y coordinate. Default: 2300
  FLCLASH_LAUNCH_WAIT     Seconds to wait after launching FlClash. Default: 5
  VPN_START_WAIT          Seconds to wait after tapping start VPN. Default: 8
  CHROME_LAUNCH_WAIT      Seconds to wait after launching Chrome. Default: 12
  CHROME_URL_INPUT_WAIT   Seconds to wait after typing the Chrome URL. Default: 3
  CHROME_INTERACT_WAIT    Seconds to wait after tapping a Chrome page target. Default: 8
  CHROME_SETTLE_WAIT      Extra seconds before the delayed counter sample. Default: 12
  OUT_DIR                 Output directory for log artifacts. Default: .ohos_live

What this verifies:
  1. Force-stop FlClash, Chrome, and the configured Chrome host bundle, then clear Chrome-host app data.
  2. Launch FlClash and start the VPN from the dashboard.
  3. Launch Chrome itself without a URI redirect.
  4. Focus the Chrome address bar, type the target URL, and submit it inside Chrome.
  5. Trigger Chrome page traffic using the configured URI host, with YouTube-only fallbacks kept for the default target family.
  6. Capture vpn-tun counters plus mission/log evidence for the current Chrome host-bundle path.
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

try_tap_chrome_target() {
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

main() {
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
  fi

  HDC_BIN=$(resolve_hdc)
  local target
  target=$(resolve_target)

  local chrome_bundle="${CHROME_BUNDLE:-$DEFAULT_CHROME_BUNDLE}"
  local chrome_ability="${CHROME_ABILITY:-$DEFAULT_CHROME_ABILITY}"
  local chrome_uri="${CHROME_URI:-$DEFAULT_CHROME_URI}"
  local chrome_uri_host
  chrome_uri_host=$(resolve_uri_host "$chrome_uri")
  local chrome_uri_probe="$chrome_uri_host"
  if [[ "$chrome_uri_probe" == www.* ]]; then
    chrome_uri_probe="${chrome_uri_probe#www.}"
  fi
  local shell_assistant_bundle="${SHELL_ASSISTANT_BUNDLE:-$DEFAULT_SHELL_ASSISTANT_BUNDLE}"
  local chrome_bundle_pattern
  chrome_bundle_pattern=$(escape_ere "$chrome_bundle")
  local chrome_uri_host_pattern
  chrome_uri_host_pattern=$(escape_ere "$chrome_uri_host")
  local shell_assistant_bundle_pattern
  shell_assistant_bundle_pattern=$(escape_ere "$shell_assistant_bundle")
  local chrome_uri_is_youtube=0
  if [[ "$chrome_uri_host" == *"youtube.com"* || "$chrome_uri_host" == *"youtu.be"* ]]; then
    chrome_uri_is_youtube=1
  fi
  local flclash_bundle="${FLCLASH_BUNDLE:-$DEFAULT_FLCLASH_BUNDLE}"
  local flclash_ability="${FLCLASH_ABILITY:-$DEFAULT_FLCLASH_ABILITY}"
  local chrome_url_bar_x="${CHROME_URL_BAR_X:-$DEFAULT_CHROME_URL_BAR_X}"
  local chrome_url_bar_y="${CHROME_URL_BAR_Y:-$DEFAULT_CHROME_URL_BAR_Y}"
  local vpn_toggle_x="${VPN_TOGGLE_X:-$DEFAULT_VPN_TOGGLE_X}"
  local vpn_toggle_y="${VPN_TOGGLE_Y:-$DEFAULT_VPN_TOGGLE_Y}"
  local flclash_launch_wait="${FLCLASH_LAUNCH_WAIT:-$DEFAULT_FLCLASH_LAUNCH_WAIT}"
  local vpn_start_wait="${VPN_START_WAIT:-$DEFAULT_VPN_START_WAIT}"
  local chrome_launch_wait="${CHROME_LAUNCH_WAIT:-$DEFAULT_CHROME_LAUNCH_WAIT}"
  local chrome_url_input_wait="${CHROME_URL_INPUT_WAIT:-$DEFAULT_CHROME_URL_INPUT_WAIT}"
  local chrome_interact_wait="${CHROME_INTERACT_WAIT:-$DEFAULT_CHROME_INTERACT_WAIT}"
  local chrome_settle_wait="${CHROME_SETTLE_WAIT:-$DEFAULT_CHROME_SETTLE_WAIT}"
  local out_dir="${OUT_DIR:-$OUT_DIR_DEFAULT}"
  mkdir -p "$out_dir"

  [[ -f "$KEEP_AWAKE_SCRIPT" ]] || fail "Missing keep-awake script: $KEEP_AWAKE_SCRIPT"
  [[ -f "$UI_SCRIPT" ]] || fail "Missing UI script: $UI_SCRIPT"
  [[ -f "$LOG_PATTERN_SCRIPT" ]] || fail "Missing log pattern helper: $LOG_PATTERN_SCRIPT"
  [[ -f "$CHROME_LAYOUT_SCRIPT" ]] || fail "Missing Chrome layout helper: $CHROME_LAYOUT_SCRIPT"

  local startup_log_pattern
  startup_log_pattern=$(node "$LOG_PATTERN_SCRIPT" startup)
  local chrome_log_pattern
  chrome_log_pattern=$(node "$LOG_PATTERN_SCRIPT" chrome)
  chrome_log_pattern="${chrome_log_pattern}|${chrome_bundle_pattern}|${shell_assistant_bundle_pattern}"
  if [[ -n "$chrome_uri_host_pattern" ]]; then
    chrome_log_pattern="${chrome_log_pattern}|${chrome_uri_host_pattern}"
  fi

  HDC_TARGET="$target" bash "$KEEP_AWAKE_SCRIPT" >/dev/null

  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)
  local log_file="$out_dir/chrome_vpn_${timestamp}.log"
  local launch_capture_name="chrome_launch_${timestamp}"
  local post_submit_capture_name="chrome_post_submit_${timestamp}"
  local after_tap_capture_name="chrome_after_tap_${timestamp}"
  local submit_capture_name="chrome_submit_${timestamp}"

  {
    echo "=== target ==="
    echo "hdc_target=$target"
    echo "chrome_bundle=$chrome_bundle"
    echo "chrome_ability=$chrome_ability"
    echo "chrome_uri=$chrome_uri"
    echo "chrome_uri_host=$chrome_uri_host"
    echo "shell_assistant_bundle=$shell_assistant_bundle"
    echo "flclash_bundle=$flclash_bundle"
    echo "flclash_ability=$flclash_ability"
    echo

    echo "=== cold stop + clear ==="
    run_hdc "$target" shell "aa force-stop $chrome_bundle >/dev/null 2>&1 || true; aa force-stop $shell_assistant_bundle >/dev/null 2>&1 || true; aa force-stop $flclash_bundle >/dev/null 2>&1 || true; bm clean -n $chrome_bundle -c >/dev/null 2>&1 || true; bm clean -n $shell_assistant_bundle -c >/dev/null 2>&1 || true; hilog -r"
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
    run_hdc "$target" shell "ifconfig vpn-tun 2>/dev/null | sed -n '1,8p'"
    echo

    echo "=== vpn startup diagnostic logs ==="
    run_hdc "$target" shell "hilog -x | grep -E '$startup_log_pattern' | tail -n 320 || true"
    echo

    echo "=== launch Chrome ==="
    run_hdc "$target" shell "aa start -a $chrome_ability -b $chrome_bundle"
    sleep "$chrome_launch_wait"
    HDC_TARGET="$target" bash "$UI_SCRIPT" capture "$launch_capture_name" "$out_dir"
    echo "launch_capture=$out_dir/${launch_capture_name}.json"
    echo

    echo "=== navigate inside Chrome ==="
    HDC_TARGET="$target" bash "$UI_SCRIPT" text-at "$chrome_url_bar_x" "$chrome_url_bar_y" "$chrome_uri"
    sleep "$chrome_url_input_wait"
    HDC_TARGET="$target" bash "$UI_SCRIPT" key 66 || true
    sleep 2

    HDC_TARGET="$target" bash "$UI_SCRIPT" capture "$submit_capture_name" "$out_dir"
    local submit_capture_json="$out_dir/${submit_capture_name}.json"
    local submitted_target="key66"
    local submit_point=""
    if [[ -s "$submit_capture_json" ]]; then
      submit_point=$(node "$CHROME_LAYOUT_SCRIPT" search-result "$submit_capture_json" "$chrome_uri" || true)
      if [[ -z "$submit_point" ]]; then
        submit_point=$(node "$CHROME_LAYOUT_SCRIPT" search-submit "$submit_capture_json" || true)
      fi
    fi
    if [[ -n "$submit_point" ]]; then
      local submit_x submit_y
      read -r submit_x submit_y <<<"$submit_point"
      run_hdc "$target" shell "uitest uiInput click $submit_x $submit_y"
      submitted_target="chrome-search-candidate"
    elif [[ -n "$chrome_uri_host" ]] && try_tap_chrome_target "$target" "$chrome_uri_host" exact; then
      submitted_target="$chrome_uri_host"
    elif [[ -n "$chrome_uri_probe" ]] && try_tap_chrome_target "$target" "$chrome_uri_probe" contains; then
      submitted_target="$chrome_uri_probe"
    elif (( chrome_uri_is_youtube )) && try_tap_chrome_target "$target" "www.youtube.com" exact; then
      submitted_target="www.youtube.com"
    elif try_tap_chrome_target "$target" "$chrome_uri" exact; then
      submitted_target="$chrome_uri"
    fi
    echo "submitted_target=$submitted_target"
    sleep "$chrome_interact_wait"
    HDC_TARGET="$target" bash "$UI_SCRIPT" capture "$post_submit_capture_name" "$out_dir"
    echo "post_submit_capture=$out_dir/${post_submit_capture_name}.json"
    echo

    echo "=== counters after Chrome launch ==="
    run_hdc "$target" shell "ifconfig vpn-tun 2>/dev/null | sed -n '1,8p'"
    echo

    echo "=== trigger Chrome page traffic ==="
    local tapped_target="none"
    if [[ -n "$chrome_uri_host" ]] && try_tap_chrome_target "$target" "$chrome_uri_host" contains; then
      tapped_target="$chrome_uri_host"
    elif [[ -n "$chrome_uri_probe" ]] && try_tap_chrome_target "$target" "$chrome_uri_probe" contains; then
      tapped_target="$chrome_uri_probe"
    elif (( chrome_uri_is_youtube )) && try_tap_chrome_target "$target" "YouTube" contains; then
      tapped_target="YouTube"
    elif (( chrome_uri_is_youtube )) && try_tap_chrome_target "$target" "m.youtube.com" contains; then
      tapped_target="m.youtube.com"
    fi
    echo "tapped_target=$tapped_target"
    sleep "$chrome_interact_wait"
    HDC_TARGET="$target" bash "$UI_SCRIPT" capture "$after_tap_capture_name" "$out_dir"
    echo "after_tap_capture=$out_dir/${after_tap_capture_name}.json"
    echo

    echo "=== counters after Chrome interaction ==="
    run_hdc "$target" shell "ifconfig vpn-tun 2>/dev/null | sed -n '1,8p'"
    echo

    echo "=== delayed counters after Chrome interaction ==="
    sleep "$chrome_settle_wait"
    run_hdc "$target" shell "ifconfig vpn-tun 2>/dev/null | sed -n '1,8p'"
    echo

    echo "=== mission dump ==="
    run_hdc "$target" shell "aa dump -a | grep -n -A8 -B2 '$chrome_bundle_pattern|$shell_assistant_bundle_pattern' || true"
    echo

    echo "=== key logs ==="
    run_hdc "$target" shell "hilog -x | grep -E '$chrome_log_pattern' | tail -n 320 || true"
  } | tee "$log_file"

  echo
  echo "Saved Chrome VPN verification log:"
  echo "$log_file"
}

main "$@"
