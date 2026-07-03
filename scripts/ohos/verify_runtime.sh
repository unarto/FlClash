#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
INSTALL_SCRIPT="$ROOT_DIR/scripts/ohos/install_and_launch.sh"
DEFAULT_TIMEOUT=45
DEVECO_HDC="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/ohos/verify_runtime.sh [path/to/app.hap]

Environment:
  HDC_TARGET       Explicit HDC target serial/name to use.
  VERIFY_TIMEOUT   Seconds to wait for OHOS core initialization logs. Default: 45

What this checks:
  1. Install + launch the HAP through scripts/ohos/install_and_launch.sh
  2. Poll hilog until these core actions are observed:
     - initClash
     - setupConfig
     - getProxies
     - getExternalProviders
  3. Fail immediately if logs contain known runtime blockers such as:
     - initial-exec TLS resolves to dynamic definition
     - Error relocating
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
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
      fail "No HarmonyOS emulator/device detected. Start an emulator and ensure 'hdc list targets' shows it."
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

collect_logs() {
  local target="$1"
  local hdc_bin="$2"
  run_hdc "$target" "$hdc_bin" shell "hilog -z 800 | grep -E '(OHOS-CORE|initial-exec TLS|Error relocating|DartMessenger|FlClashEntry)' | tail -n 400" || true
}

main() {
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
  fi

  [[ -f "$INSTALL_SCRIPT" ]] || fail "Missing install script: $INSTALL_SCRIPT"
  local hdc_bin
  hdc_bin=$(resolve_hdc)
  HDC_BIN="$hdc_bin"

  local target
  target=$(resolve_target)
  local timeout="${VERIFY_TIMEOUT:-$DEFAULT_TIMEOUT}"
  local deadline=$((SECONDS + timeout))
  local hap_args=()
  if [[ $# -gt 0 ]]; then
    hap_args=("$1")
  fi

  run_hdc "$target" "$hdc_bin" shell "hilog -r" >/dev/null
  bash "$INSTALL_SCRIPT" "${hap_args[@]}"

  while (( SECONDS < deadline )); do
    local logs
    logs=$(collect_logs "$target" "$hdc_bin")

    if grep -Eq 'initial-exec TLS resolves to dynamic definition|Error relocating' <<<"$logs"; then
      echo "$logs"
      fail "Observed known OHOS runtime blocker in hilog."
    fi

    if grep -Fq 'invoke initClash' <<<"$logs" &&
       grep -Fq 'invoke setupConfig' <<<"$logs" &&
       grep -Fq 'invoke getProxies' <<<"$logs" &&
       grep -Fq 'invoke getExternalProviders' <<<"$logs"; then
      cat <<EOF
OHOS runtime verification passed.

Verified target: $target
Verified evidence:
  - invoke initClash
  - invoke setupConfig
  - invoke getProxies
  - invoke getExternalProviders
  - no TLS relocation blocker found in filtered hilog
EOF
      exit 0
    fi

    sleep 2
  done

  echo "Timed out after ${timeout}s waiting for OHOS core initialization logs." >&2
  collect_logs "$target" "$hdc_bin"
  exit 1
}

main "$@"
