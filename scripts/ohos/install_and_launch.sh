#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
KEEP_AWAKE_SCRIPT="$ROOT_DIR/scripts/ohos/keep_awake.sh"
DEFAULT_BUNDLE_NAME="com.follow.clash"
DEFAULT_ABILITY_NAME="EntryAbility"
DEVECO_HDC="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/ohos/install_and_launch.sh [path/to/app.hap]

Environment:
  HDC_TARGET   Explicit HDC target serial/name to use.
  BUNDLE_NAME  Override bundle name. Default: com.follow.clash
  ABILITY_NAME Override ability name. Default: EntryAbility

Notes:
  - This script verifies install + ability launch against an existing emulator/device.
  - Before launch it wakes the device, extends the screen timeout, and switches to
    performance mode to reduce lock-screen interference during debugging.
  - It also installs an HDC reverse port mapping `device tcp:19000 -> host tcp:19000`
    so the built-in OHOS WebDAV test config can reach the host test server via
    `http://127.0.0.1:19000/` inside the emulator.
  - A passing install/launch result is only the first step. Inspect hilog to confirm
    the OHOS core actually initializes without TLS relocation failures.
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

resolve_hap_path() {
  if [[ $# -gt 1 ]]; then
    usage >&2
    exit 1
  fi

  if [[ $# -eq 1 ]]; then
    printf '%s\n' "$1"
    return
  fi

  local dist_dir="$ROOT_DIR/dist"
  [[ -d "$dist_dir" ]] || fail "Missing dist directory: $dist_dir"

  local candidates=()
  while IFS= read -r path; do
    candidates+=("$path")
  done < <(find "$dist_dir" -maxdepth 1 -type f -name 'FlClash-*-ohos-arm64.hap' | sort)

  case "${#candidates[@]}" in
    0)
      fail "No OHOS HAP found under $dist_dir"
      ;;
    1)
      printf '%s\n' "${candidates[0]}"
      ;;
    *)
      fail "Multiple OHOS HAP files found under $dist_dir; pass the intended path explicitly."
      ;;
  esac
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

setup_webdav_rport() {
  local target="$1"
  local hdc_bin="$2"
  local rules_output
  rules_output=$(run_hdc "$target" "$hdc_bin" fport ls 2>&1 || true)
  if [[ "$rules_output" == *"tcp:19000 tcp:19000"* && "$rules_output" == *"[Reverse]"* ]]; then
    echo "Configured emulator WebDAV reverse port: tcp:19000 -> host tcp:19000"
    return
  fi

  local output
  output=$(run_hdc "$target" "$hdc_bin" rport tcp:19000 tcp:19000 2>&1 || true)
  if [[ "$output" == *"Forwardport result:OK"* || "$output" == *"already"* ]]; then
    echo "Configured emulator WebDAV reverse port: tcp:19000 -> host tcp:19000"
    return
  fi
  echo "WARNING: failed to configure WebDAV reverse port: $output" >&2
}

install_hap() {
  local target="$1"
  local hdc_bin="$2"
  local hap_path="$3"
  local output
  local status

  set +e
  output=$(run_hdc "$target" "$hdc_bin" install -r "$hap_path" 2>&1)
  status=$?
  set -e
  printf '%s\n' "$output"

  if ((status != 0)); then
    fail "HAP install command failed with exit status $status."
  fi

  if grep -Eqi '(error:|failed to install|fail to |Error Code:)' <<<"$output"; then
    fail "HAP install reported failure; see install output above."
  fi
}

main() {
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
  fi

  local hdc_bin
  hdc_bin=$(resolve_hdc)
  HDC_BIN="$hdc_bin"

  local hap_path
  hap_path=$(resolve_hap_path "$@")
  [[ -f "$hap_path" ]] || fail "HAP file not found: $hap_path"

  local target
  target=$(resolve_target)

  local bundle_name="${BUNDLE_NAME:-$DEFAULT_BUNDLE_NAME}"
  local ability_name="${ABILITY_NAME:-$DEFAULT_ABILITY_NAME}"

  echo "Using HDC target: $target"
  [[ -f "$KEEP_AWAKE_SCRIPT" ]] || fail "Missing keep-awake script: $KEEP_AWAKE_SCRIPT"
  HDC_TARGET="$target" bash "$KEEP_AWAKE_SCRIPT"
  echo "Installing HAP: $hap_path"
  install_hap "$target" "$hdc_bin" "$hap_path"

  setup_webdav_rport "$target" "$hdc_bin"

  echo "Launching ${bundle_name}/${ability_name}"
  run_hdc "$target" "$hdc_bin" shell "aa start -a $ability_name -b $bundle_name"

  cat <<EOF
Install and launch commands completed.

Next checks on the emulator:
  1. Confirm FlClash appears in the launcher and can be opened.
  2. Confirm the app reaches the normal shell instead of an immediate init failure.
  3. Inspect logs and look for successful OHOS core actions such as:
     [OHOS-CORE] invoke initClash ... done
     [OHOS-CORE] invoke setupConfig ... done
  4. Confirm logs do not contain:
     initial-exec TLS resolves to dynamic definition
  5. If deeper investigation is needed, inspect logs with:
     "$hdc_bin" -t "$target" shell 'hilog -x | grep -E "(OHOS-CORE|initial-exec TLS|Error relocating|FlClashEntry)"'

Current branch expectation:
  Launch succeeds and the bundled Go core can be invoked on a supported
  HarmonyOS target. Install/launch alone does not prove functional parity,
  but it should no longer stop at the old unsupported-runtime screen.
EOF
}

main "$@"
