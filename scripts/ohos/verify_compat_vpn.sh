#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
KEEP_AWAKE_SCRIPT="$ROOT_DIR/scripts/ohos/keep_awake.sh"
UI_SCRIPT="$ROOT_DIR/scripts/ohos/ui.sh"
OUT_DIR_DEFAULT="$ROOT_DIR/.ohos_live"
DEVECO_HDC="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc"
DEFAULT_TARGET_BUNDLE="com.easy.hmos.abroad"
DEFAULT_TARGET_ABILITY="EntryAbility"
DEFAULT_SHELL_ASSISTANT_BUNDLE="com.huawei.shell_assistant"
DEFAULT_FLCLASH_BUNDLE="com.follow.clash"
DEFAULT_FLCLASH_ABILITY="EntryAbility"
DEFAULT_VPN_TOGGLE_X=1126
DEFAULT_VPN_TOGGLE_Y=2300
DEFAULT_FLCLASH_LAUNCH_WAIT=5
DEFAULT_VPN_START_WAIT=15
DEFAULT_TARGET_LAUNCH_WAIT=20
DEFAULT_TARGET_SETTLE_WAIT=15

usage() {
  cat <<'EOF'
Usage:
  bash scripts/ohos/verify_compat_vpn.sh
  bash scripts/ohos/verify_compat_vpn.sh <target-bundle> [target-ability]

Environment:
  HDC_TARGET            Explicit HarmonyOS device target.
  TARGET_BUNDLE         Override compat app bundle. Default: com.easy.hmos.abroad
  TARGET_ABILITY        Override compat app ability. Default: EntryAbility
  SHELL_ASSISTANT_BUNDLE Override compat host bundle. Default: com.huawei.shell_assistant
  FLCLASH_BUNDLE        Override FlClash bundle. Default: com.follow.clash
  FLCLASH_ABILITY       Override FlClash ability. Default: EntryAbility
  VPN_TOGGLE_X          Dashboard VPN button X coordinate. Default: 1126
  VPN_TOGGLE_Y          Dashboard VPN button Y coordinate. Default: 2300
  FLCLASH_LAUNCH_WAIT   Seconds to wait after launching FlClash. Default: 5
  VPN_START_WAIT        Seconds to wait after tapping start VPN. Default: 15
  TARGET_LAUNCH_WAIT    Seconds to wait after launching target app. Default: 20
  TARGET_SETTLE_WAIT    Extra seconds before a delayed second counter sample. Default: 15
  OUT_DIR               Output directory for log artifacts. Default: .ohos_live

What this verifies:
  1. Force-stop FlClash, the target app, and the configured compat host bundle.
  2. Launch FlClash and start the VPN from the dashboard.
  3. Capture vpn-tun counters before and after launching the compat app.
  4. Save focused hilog evidence for compat-host trust, DNS failures, and HTTP success.
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

escape_ere() {
  printf '%s' "$1" | sed -e 's/[][(){}.^$+*?|\\]/\\&/g'
}

escape_ere_union() {
  local input="$1"
  local pattern=""
  local part
  local IFS='|'
  read -r -a parts <<<"$input"
  for part in "${parts[@]}"; do
    [[ -n "$part" ]] || continue
    if [[ -n "$pattern" ]]; then
      pattern+="|"
    fi
    pattern+="$(escape_ere "$part")"
  done
  printf '%s' "$pattern"
}

main() {
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
  fi

  HDC_BIN=$(resolve_hdc)
  local target
  target=$(resolve_target)

  local target_bundle="${TARGET_BUNDLE:-${1:-$DEFAULT_TARGET_BUNDLE}}"
  local target_ability="${TARGET_ABILITY:-${2:-$DEFAULT_TARGET_ABILITY}}"
  local mission_grep="${MISSION_GREP:-$target_bundle}"
  local shell_assistant_bundle="${SHELL_ASSISTANT_BUNDLE:-$DEFAULT_SHELL_ASSISTANT_BUNDLE}"
  local flclash_bundle="${FLCLASH_BUNDLE:-$DEFAULT_FLCLASH_BUNDLE}"
  local flclash_ability="${FLCLASH_ABILITY:-$DEFAULT_FLCLASH_ABILITY}"
  local vpn_toggle_x="${VPN_TOGGLE_X:-$DEFAULT_VPN_TOGGLE_X}"
  local vpn_toggle_y="${VPN_TOGGLE_Y:-$DEFAULT_VPN_TOGGLE_Y}"
  local flclash_launch_wait="${FLCLASH_LAUNCH_WAIT:-$DEFAULT_FLCLASH_LAUNCH_WAIT}"
  local vpn_start_wait="${VPN_START_WAIT:-$DEFAULT_VPN_START_WAIT}"
  local target_launch_wait="${TARGET_LAUNCH_WAIT:-$DEFAULT_TARGET_LAUNCH_WAIT}"
  local target_settle_wait="${TARGET_SETTLE_WAIT:-$DEFAULT_TARGET_SETTLE_WAIT}"
  local out_dir="${OUT_DIR:-$OUT_DIR_DEFAULT}"
  mkdir -p "$out_dir"

  if [[ "$mission_grep" == "$target_bundle" ]]; then
    local compat_alias="${target_bundle/.hmos/}"
    if [[ "$compat_alias" != "$target_bundle" ]]; then
      mission_grep="$target_bundle|$compat_alias"
    fi
  fi
  local mission_grep_pattern
  mission_grep_pattern=$(escape_ere_union "$mission_grep")
  local shell_assistant_bundle_pattern
  shell_assistant_bundle_pattern=$(escape_ere "$shell_assistant_bundle")
  local compat_log_pattern="app: ${shell_assistant_bundle_pattern} success|responseCode=200|statusCode: 200|dnsFromNetsys|dnsServerReturnNothing|Couldn.t resolve host name|StartTun result ok=1|OHOSVPN|ProcUpdateVpnRoutePolicy"

  [[ -f "$KEEP_AWAKE_SCRIPT" ]] || fail "Missing keep-awake script: $KEEP_AWAKE_SCRIPT"
  [[ -f "$UI_SCRIPT" ]] || fail "Missing UI script: $UI_SCRIPT"

  HDC_TARGET="$target" bash "$KEEP_AWAKE_SCRIPT" >/dev/null

  local timestamp
  timestamp=$(date +%Y%m%d_%H%M%S)
  local log_file="$out_dir/compat_vpn_${timestamp}.log"

  {
    echo "=== target ==="
    echo "hdc_target=$target"
    echo "target_bundle=$target_bundle"
    echo "target_ability=$target_ability"
    echo "mission_grep=$mission_grep"
    echo "shell_assistant_bundle=$shell_assistant_bundle"
    echo "flclash_bundle=$flclash_bundle"
    echo "flclash_ability=$flclash_ability"
    echo

    echo "=== cold stop + clear ==="
    run_hdc "$target" shell "aa force-stop $target_bundle >/dev/null 2>&1 || true; aa force-stop $flclash_bundle >/dev/null 2>&1 || true; aa force-stop $shell_assistant_bundle >/dev/null 2>&1 || true; hilog -r"
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

    echo "=== launch compat app ==="
    run_hdc "$target" shell "aa start -a $target_ability -b $target_bundle"
    sleep "$target_launch_wait"
    echo

    echo "=== counters after compat app ==="
    run_hdc "$target" shell "ifconfig vpn-tun 2>/dev/null | sed -n '1,8p'"
    echo

    echo "=== delayed counters after compat app ==="
    sleep "$target_settle_wait"
    run_hdc "$target" shell "ifconfig vpn-tun 2>/dev/null | sed -n '1,8p'"
    echo

    echo "=== mission dump ==="
    run_hdc "$target" shell "aa dump -a | grep -n -A8 -B2 '$mission_grep_pattern|$shell_assistant_bundle_pattern' || true"
    echo

    echo "=== key logs ==="
    run_hdc "$target" shell "hilog -x | grep -E '$compat_log_pattern' | tail -n 160 || true"
  } | tee "$log_file"

  echo
  echo "Saved compat VPN verification log:"
  echo "$log_file"
}

main "$@"
