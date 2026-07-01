#!/usr/bin/env bash

set -euo pipefail

DEVECO_HDC="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc"
DEFAULT_TIMEOUT_MS=1800000
DEFAULT_POWER_MODE=602

usage() {
  cat <<'EOF'
Usage:
  bash scripts/ohos/keep_awake.sh

Environment:
  HDC_TARGET            Explicit HDC target serial/name to use.
  SCREEN_TIMEOUT_MS     Screen-off timeout override in milliseconds. Default: 1800000
  POWER_MODE            Power mode to apply. Default: 602 (performance mode)
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
    0)
      fail "No HarmonyOS emulator/device detected. Ensure 'hdc list targets' shows it."
      ;;
    1)
      printf '%s\n' "${targets[0]}"
      ;;
    *)
      fail "Multiple HarmonyOS targets detected. Re-run with HDC_TARGET=<target>."
      ;;
  esac
}

run_hdc() {
  local target="$1"
  local hdc_bin="$2"
  shift 2
  "$hdc_bin" -t "$target" "$@"
}

main() {
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
  fi

  local hdc_bin
  hdc_bin=$(resolve_hdc)
  HDC_BIN="$hdc_bin"

  local target
  target=$(resolve_target)

  local screen_timeout_ms="${SCREEN_TIMEOUT_MS:-$DEFAULT_TIMEOUT_MS}"
  local power_mode="${POWER_MODE:-$DEFAULT_POWER_MODE}"

  echo "Using HDC target: $target"
  run_hdc "$target" "$hdc_bin" shell "power-shell wakeup"
  run_hdc "$target" "$hdc_bin" shell "power-shell timeout -o $screen_timeout_ms"
  run_hdc "$target" "$hdc_bin" shell "power-shell setmode $power_mode"
}

main "$@"
