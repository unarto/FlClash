#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
INSTALL_SCRIPT="$ROOT_DIR/scripts/ohos/install_and_launch.sh"
DEFAULT_TIMEOUT=45
DEVECO_HDC="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/ohos/verify_capabilities.sh [vpn|child-process|all] [path/to/app.hap]
  bash scripts/ohos/verify_capabilities.sh [vpn|child-process|all] --log-file /path/to/hilog.txt
  bash scripts/ohos/verify_capabilities.sh [vpn|child-process|all] --log-dir /path/to/hilog_dir

Environment:
  HDC_TARGET       Explicit HDC target serial/name to use.
  VERIFY_TIMEOUT   Seconds to wait for live capability logs. Default: 45

Options:
  --skip-install   Do not reinstall/relaunch the app before collecting logs.
  --log-file PATH  Parse an existing hilog capture instead of querying a live target.
  --log-dir PATH   Parse every file under a log directory. '*.gz' files are decompressed automatically.

What this checks:
  child-process
    - PASS only when native child-process startup is directly proven
    - FAIL on known target blockers such as:
      - Capability not support
      - fexecve failed: Permission denied
      - execv proc path failed: Permission denied
      - source exec failed
    - INCONCLUSIVE if only fallback/bundled-exec evidence is seen

  vpn
    - PASS only when FlClashVpnAbility reports a started tunnel
    - FAIL on known emulator blockers such as:
      - com.huawei.hmos.vpndialog missing
      - startVpnExtensionAbility timeout with no later started marker
      - failed:* final VPN status / explicit start failure marker
      - AppPlugin / OHOS-VPN start failures
    - INCONCLUSIVE if no decisive VPN start result is observed
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

clear_logs() {
  local target="$1"
  local hdc_bin="$2"
  run_hdc "$target" "$hdc_bin" shell "hilog -r" >/dev/null
}

collect_live_logs() {
  local target="$1"
  local hdc_bin="$2"
  local pattern="$3"
  local tail_lines="$4"
  run_hdc "$target" "$hdc_bin" shell "hilog -z $tail_lines | grep -E '$pattern' | tail -n $tail_lines" || true
}

read_log_source() {
  local source="$1"

  if [[ -d "$source" ]]; then
    local file
    while IFS= read -r file; do
      [[ -n "$file" ]] || continue
      if [[ "$file" == *.gz ]]; then
        gzip -cd "$file" 2>/dev/null || true
      else
        cat "$file" 2>/dev/null || true
      fi
    done < <(find "$source" -type f | sort)
    return 0
  fi

  if [[ "$source" == *.gz ]]; then
    gzip -cd "$source" 2>/dev/null || true
    return 0
  fi

  cat "$source"
}

print_section() {
  local title="$1"
  echo
  echo "== $title =="
}

vpn_logs_have_started() {
  local logs="$1"
  grep -Eq '\[FlClashVpnAbility\] started fd=' <<<"$logs"
}

vpn_logs_have_timeout_style_appplugin_failure() {
  local logs="$1"
  grep -Eq '\[AppPlugin\] startVpn failed error=startVpnExtensionAbility timeout([[:space:]]|$)' <<<"$logs"
}

vpn_logs_have_non_timeout_appplugin_failure() {
  local logs="$1"
  grep -E '\[AppPlugin\] startVpn failed' <<<"$logs" \
    | grep -Ev 'error=startVpnExtensionAbility timeout([[:space:]]|$)' >/dev/null
}

vpn_logs_have_live_terminal_failure() {
  local logs="$1"

  if grep -Eq '(com\.huawei\.hmos\.vpndialog|\[OHOS-VPN\] start failed|\[FlClashVpnAbility\] start failed:)' <<<"$logs"; then
    return 0
  fi

  vpn_logs_have_non_timeout_appplugin_failure "$logs"
}

vpn_logs_have_final_failure() {
  local logs="$1"

  if vpn_logs_have_live_terminal_failure "$logs"; then
    return 0
  fi

  vpn_logs_have_timeout_style_appplugin_failure "$logs"
}

vpn_latest_decisive_marker() {
  local logs="$1"
  local marker=""

  while IFS= read -r line; do
    if [[ "$line" =~ \[FlClashVpnAbility\]\ started\ fd= ]]; then
      marker="started"
      continue
    fi
    if [[ "$line" =~ com\.huawei\.hmos\.vpndialog ]]; then
      marker="failure"
      continue
    fi
    if [[ "$line" =~ \[OHOS-VPN\]\ start\ failed ]]; then
      marker="failure"
      continue
    fi
    if [[ "$line" =~ \[FlClashVpnAbility\]\ start\ failed: ]]; then
      marker="failure"
      continue
    fi
    if [[ "$line" =~ \[AppPlugin\]\ startVpn\ failed ]]; then
      marker="failure"
      continue
    fi
  done <<<"$logs"

  printf '%s\n' "$marker"
}

child_process_latest_decisive_marker() {
  local logs="$1"
  local marker=""

  while IFS= read -r line; do
    if [[ "$line" =~ \[AppPlugin\]\ startCoreChildProcess\ pid= ]]; then
      marker="success"
      continue
    fi
    if [[ "$line" =~ Started\ OHOS\ core\ child\ process\ pid= ]]; then
      marker="success"
      continue
    fi
    if [[ "$line" =~ NativeChildProcess_MainProc\ pid= ]]; then
      marker="success"
      continue
    fi
    if [[ "$line" =~ Capability\ not\ support ]]; then
      marker="failure"
      continue
    fi
    if [[ "$line" =~ startCoreChildProcess\ failed\ pid= ]]; then
      marker="failure"
      continue
    fi
    if [[ "$line" =~ fexecve\ failed:\ Permission\ denied ]]; then
      marker="failure"
      continue
    fi
    if [[ "$line" =~ execv\ proc\ path\ failed:\ Permission\ denied ]]; then
      marker="failure"
      continue
    fi
    if [[ "$line" =~ source\ exec\ failed ]]; then
      marker="failure"
      continue
    fi
    if [[ "$line" =~ startBundledCoreProcess\ failed ]]; then
      marker="failure"
      continue
    fi
    if [[ "$line" =~ Started\ OHOS\ core\ executable\ via\ native\ bridge\ pid= ]]; then
      marker="fallback"
      continue
    fi
    if [[ "$line" =~ startBundledCoreProcess\ source= ]]; then
      marker="fallback"
      continue
    fi
    if [[ "$line" =~ fork\ ok\ pid= ]]; then
      marker="fallback"
      continue
    fi
  done <<<"$logs"

  printf '%s\n' "$marker"
}

classify_child_process() {
  local logs="$1"
  local latest_marker
  latest_marker=$(child_process_latest_decisive_marker "$logs")

  if [[ "$latest_marker" == "success" ]]; then
    echo "PASS native child-process startup is directly proven."
    return 0
  fi

  if [[ "$latest_marker" == "failure" ]] || grep -Eq '(Capability not support|startCoreChildProcess failed pid=|fexecve failed: Permission denied|execv proc path failed: Permission denied|source exec failed|startBundledCoreProcess failed)' <<<"$logs"; then
    echo "FAIL target blocked before native child-process verification completed."
    return 1
  fi

  if [[ "$latest_marker" == "fallback" ]] || grep -Eq '(Started OHOS core executable via native bridge pid=|startBundledCoreProcess source=|fork ok pid=)' <<<"$logs"; then
    echo "INCONCLUSIVE only bundled-exec fallback evidence was observed; native child-process is not proven."
    return 2
  fi

  echo "INCONCLUSIVE no decisive child-process evidence was observed."
  return 2
}

classify_vpn() {
  local logs="$1"
  local latest_marker
  latest_marker=$(vpn_latest_decisive_marker "$logs")

  if [[ "$latest_marker" == "started" ]]; then
    echo "PASS VPN ability started successfully."
    return 0
  fi

  if [[ "$latest_marker" == "failure" ]] || vpn_logs_have_final_failure "$logs"; then
    echo "FAIL VPN startup is blocked on the current target."
    return 1
  fi

  if grep -Eq '(\[AppPlugin\] startVpn stack=|\[FlClashVpnAbility\] protectProcessNet failed:)' <<<"$logs"; then
    echo "INCONCLUSIVE VPN start was attempted but no success/failure completion marker was captured."
    return 2
  fi

  echo "INCONCLUSIVE no VPN startup attempt was observed in the filtered logs."
  return 2
}

collect_logs_for_mode() {
  local mode="$1"
  local target="$2"
  local hdc_bin="$3"
  local timeout="$4"
  local log_file="$5"
  local log_dir="$6"

  local pattern
  local tail_lines=500
  case "$mode" in
    child-process)
      pattern='(AppPlugin|OHOS native child process unavailable|Started OHOS core|Capability not support|fexecve failed|execv proc path failed|startBundledCoreProcess|startCoreChildProcess|source exec failed|NativeChildProcess|FlClashCoreMain|OHOS-CORE)'
      ;;
    vpn)
      pattern='(AppPlugin|FlClashVpnAbility|OHOS-VPN|vpndialog|VpnServiceExtAbility|startVpn|vpn extension)'
      ;;
    *)
      fail "Unsupported mode: $mode"
      ;;
  esac

  if [[ -n "$log_file" ]]; then
    cat "$log_file"
    return 0
  fi

  if [[ -n "$log_dir" ]]; then
    read_log_source "$log_dir" | grep -E "$pattern" || true
    return 0
  fi

  local deadline=$((SECONDS + timeout))
  while (( SECONDS < deadline )); do
    local logs
    logs=$(collect_live_logs "$target" "$hdc_bin" "$pattern" "$tail_lines")
    if [[ -n "$logs" ]]; then
      case "$mode" in
        child-process)
          if grep -Eq '(\[AppPlugin\] startCoreChildProcess pid=|Started OHOS core child process pid=|NativeChildProcess_MainProc pid=|Capability not support|startCoreChildProcess failed pid=|fexecve failed: Permission denied|execv proc path failed: Permission denied|source exec failed|startBundledCoreProcess failed|Started OHOS core executable via native bridge pid=|startBundledCoreProcess source=|fork ok pid=)' <<<"$logs"; then
            printf '%s\n' "$logs"
            return 0
          fi
          ;;
        vpn)
          if vpn_logs_have_started "$logs" || vpn_logs_have_live_terminal_failure "$logs"; then
            printf '%s\n' "$logs"
            return 0
          fi
          ;;
      esac
    fi
    sleep 2
  done

  collect_live_logs "$target" "$hdc_bin" "$pattern" "$tail_lines"
}

main() {
  local mode="all"
  local hap_path=""
  local log_file=""
  local log_dir=""
  local skip_install=0

  while [[ $# -gt 0 ]]; do
    case "$1" in
      vpn|child-process|all)
        mode="$1"
        shift
        ;;
      --skip-install)
        skip_install=1
        shift
        ;;
      --log-file)
        [[ $# -ge 2 ]] || fail "--log-file requires a path"
        log_file="$2"
        shift 2
        ;;
      --log-dir)
        [[ $# -ge 2 ]] || fail "--log-dir requires a path"
        log_dir="$2"
        shift 2
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        if [[ -z "$hap_path" ]]; then
          hap_path="$1"
          shift
        else
          fail "Unexpected argument: $1"
        fi
        ;;
    esac
  done

  if [[ -n "$log_file" && ! -f "$log_file" ]]; then
    fail "Log file not found: $log_file"
  fi
  if [[ -n "$log_dir" && ! -d "$log_dir" ]]; then
    fail "Log directory not found: $log_dir"
  fi
  if [[ -n "$log_file" && -n "$log_dir" ]]; then
    fail "--log-file and --log-dir are mutually exclusive"
  fi

  local hdc_bin=""
  local target=""
  if [[ -z "$log_file" && -z "$log_dir" ]]; then
    [[ -f "$INSTALL_SCRIPT" ]] || fail "Missing install script: $INSTALL_SCRIPT"
    hdc_bin=$(resolve_hdc)
    HDC_BIN="$hdc_bin"
    target=$(resolve_target)
    clear_logs "$target" "$hdc_bin"
    if [[ "$skip_install" -eq 0 ]]; then
      if [[ -n "$hap_path" ]]; then
        bash "$INSTALL_SCRIPT" "$hap_path"
      else
        bash "$INSTALL_SCRIPT"
      fi
    fi
  fi

  local timeout="${VERIFY_TIMEOUT:-$DEFAULT_TIMEOUT}"
  local overall_status=0
  local modes=()
  if [[ "$mode" == "all" ]]; then
    modes=(child-process vpn)
  else
    modes=("$mode")
  fi

  local current_mode
  for current_mode in "${modes[@]}"; do
    if [[ "$current_mode" == "vpn" && -z "$log_file" && -z "$log_dir" ]]; then
      print_section "VPN Manual Step"
      cat <<'EOF'
Trigger the VPN path on the target now:
  1. 工具 -> 进阶配置 -> 网络 -> VPN -> on
  2. 返回仪表盘
  3. 点击启动按钮
EOF
    fi

    print_section "Collecting $current_mode logs"
    local logs=""
    logs=$(collect_logs_for_mode "$current_mode" "$target" "$hdc_bin" "$timeout" "$log_file" "$log_dir")
    if [[ -n "$logs" ]]; then
      printf '%s\n' "$logs"
    else
      echo "(no filtered logs captured)"
    fi

    print_section "$current_mode result"
    local status=0
    case "$current_mode" in
      child-process)
        classify_child_process "$logs" || status=$?
        ;;
      vpn)
        classify_vpn "$logs" || status=$?
        ;;
    esac

    if (( status == 1 )); then
      overall_status=1
    elif (( status == 2 )) && (( overall_status == 0 )); then
      overall_status=2
    fi
  done

  exit "$overall_status"
}

main "$@"
