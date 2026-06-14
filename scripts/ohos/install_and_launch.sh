#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
DEFAULT_BUNDLE_NAME="com.follow.clash"
DEFAULT_ABILITY_NAME="EntryAbility"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/ohos/install_and_launch.sh [path/to/app.hap]

Environment:
  HDC_TARGET   Explicit HDC target serial/name to use.
  BUNDLE_NAME  Override bundle name. Default: com.follow.clash
  ABILITY_NAME Override ability name. Default: EntryAbility

Notes:
  - The current OHOS branch only verifies package install + ability launch.
  - A successful launch on this branch still ends on the in-app unsupported-runtime
    error screen, because the Flutter runtime port is not implemented yet.
EOF
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
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
    targets+=("$target")
  done < <(hdc list targets 2>/dev/null || true)

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
  shift
  hdc -t "$target" "$@"
}

main() {
  if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    usage
    exit 0
  fi

  require_command hdc

  local hap_path
  hap_path=$(resolve_hap_path "$@")
  [[ -f "$hap_path" ]] || fail "HAP file not found: $hap_path"

  local target
  target=$(resolve_target)

  local bundle_name="${BUNDLE_NAME:-$DEFAULT_BUNDLE_NAME}"
  local ability_name="${ABILITY_NAME:-$DEFAULT_ABILITY_NAME}"

  echo "Using HDC target: $target"
  echo "Installing HAP: $hap_path"
  run_hdc "$target" install -r "$hap_path"

  echo "Launching ${bundle_name}/${ability_name}"
  run_hdc "$target" shell aa start -a "$ability_name" -b "$bundle_name"

  cat <<EOF
Install and launch commands completed.

Next checks on the emulator:
  1. Confirm FlClash appears in the launcher and can be opened.
  2. Confirm launch reaches the app error screen instead of failing to start.
  3. If deeper investigation is needed, inspect logs with:
     hdc -t "$target" shell hilog

Current branch expectation:
  Launch succeeds, then the app shows the intentional unsupported-runtime error
  until the OHOS runtime port is implemented.
EOF
}

main "$@"
