#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
OUT_DIR_DEFAULT="$ROOT_DIR/.ohos_live"
TOOLCHAIN_DIR_DEFAULT="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains"

if [[ -d "${OHOS_TOOLCHAIN_DIR:-$TOOLCHAIN_DIR_DEFAULT}" ]]; then
  export PATH="${OHOS_TOOLCHAIN_DIR:-$TOOLCHAIN_DIR_DEFAULT}:$PATH"
fi

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

sanitize_layout_json() {
  local src="$1"
  local dst="$2"
  python3 - "$src" "$dst" <<'PY'
import json
import sys
from pathlib import Path

src_path, dst_path = sys.argv[1:3]
raw = Path(src_path).read_text(errors="ignore")
decoder = json.JSONDecoder()

for index, char in enumerate(raw):
    if char not in "{[":
        continue
    try:
        obj, end = decoder.raw_decode(raw[index:])
    except json.JSONDecodeError:
        continue
    Path(dst_path).write_text(json.dumps(obj, ensure_ascii=False))
    sys.exit(0)

sys.exit(1)
PY
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
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

shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

dump_layout() {
  local target="$1"
  local remote_json_name="$2"
  for _ in 1 2 3; do
    if run_hdc "$target" shell "cd /data/local/tmp && uitest dumpLayout -p $remote_json_name" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done
  return 1
}

fetch_layout_json() {
  local target="$1"
  local remote_json_name="$2"
  local local_json="$3"

  dump_layout "$target" "$remote_json_name" || return 1

  for _ in 1 2 3; do
    run_hdc "$target" shell "cd /data/local/tmp && cat $remote_json_name" >"$local_json" 2>/dev/null || true
    if [[ -s "$local_json" ]]; then
      sanitize_layout_json "$local_json" "$local_json.cleaned" || true
      if [[ -s "$local_json.cleaned" ]]; then
        mv "$local_json.cleaned" "$local_json"
        return 0
      fi
    fi
    : >"$local_json"
    dump_layout "$target" "$remote_json_name" || true
    sleep 1
  done

  return 1
}

capture_state() {
  local target="$1"
  local name="$2"
  local out_dir="${3:-$OUT_DIR_DEFAULT}"
  mkdir -p "$out_dir"
  local remote_jpeg="/data/local/tmp/${name}.jpeg"
  local remote_json_name="${name}.json"
  run_hdc "$target" shell "snapshot_display -f $remote_jpeg"
  run_hdc "$target" file recv "$remote_jpeg" "$out_dir/"
  local local_json="$out_dir/${name}.json"
  if ! fetch_layout_json "$target" "$remote_json_name" "$local_json"; then
    : >"$out_dir/${name}.json"
  fi
}

tap_text() {
  local target="$1"
  local query="$2"
  local mode="${3:-contains}"
  local repeat="${4:-1}"
  local remote_json_name="ui_tap_text_layout.json"
  local local_json
  local_json=$(mktemp "${TMPDIR:-/tmp}/flclash-ui-layout.XXXXXX")
  fetch_layout_json "$target" "$remote_json_name" "$local_json" ||
    fail "Unable to read a valid layout json while locating text: $query"

  local tap_target
  tap_target=$(python3 - "$local_json" "$query" "$mode" <<'PY'
import json
import re
import sys

layout_path, query, mode = sys.argv[1:4]
data = json.load(open(layout_path))
query_cmp = query.casefold()
best = None

def parse_bounds(bounds):
    match = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", bounds or "")
    if not match:
        return None
    return tuple(map(int, match.groups()))

def is_match(text):
    value = (text or "").strip()
    if not value:
        return False
    cmp_value = value.casefold()
    if mode == "exact":
        return cmp_value == query_cmp
    return query_cmp in cmp_value

def walk(node, depth=0):
    global best
    attrs = node.get("attributes", {})
    candidates = [
        attrs.get("text", ""),
        attrs.get("originalText", ""),
        attrs.get("hint", ""),
        attrs.get("description", ""),
    ]
    bounds = parse_bounds(attrs.get("bounds", ""))
    clickable = attrs.get("clickable") == "true" or attrs.get("longClickable") == "true"
    for candidate in candidates:
        if not is_match(candidate) or bounds is None:
            continue
        x1, y1, x2, y2 = bounds
        width = x2 - x1
        height = y2 - y1
        area = width * height
        score = (
            0 if clickable else 1,
            depth,
            area,
        )
        if best is None or score < best[0]:
            best = (score, (x1, y1, x2, y2), candidate, clickable, attrs.get("type", ""))
    for child in node.get("children", []):
        walk(child, depth + 1)

walk(data)
if best is None:
    sys.exit(1)

attrs = best[1]
x1, y1, x2, y2 = attrs
print(f"{x1} {y1} {x2} {y2}")
PY
  ) || fail "No matching node found for text: $query"

  local x1 y1 x2 y2
  read -r x1 y1 x2 y2 <<<"$tap_target"
  local width=$((x2 - x1))
  local height=$((y2 - y1))

  # OHOS uitest click is flaky on large list items. Try a small set of
  # conservative points across the row instead of relying on one center hit.
  local points=("$(((x1 + x2) / 2)) $(((y1 + y2) / 2))")
  if [[ "$repeat" != "1" ]]; then
    points+=(
      "$((x1 + width * 3 / 4)) $(((y1 + y2) / 2))"
      "$((x1 + width / 4)) $(((y1 + y2) / 2))"
      "$(((x1 + x2) / 2)) $((y1 + height / 3))"
    )
  fi

  local point x y
  for point in "${points[@]}"; do
    read -r x y <<<"$point"
    run_hdc "$target" shell "uitest uiInput click $x $y"
    sleep 0.2
  done
  rm -f "$local_json"
}

tap_node_attr() {
  local target="$1"
  local attr="$2"
  local query="$3"
  local repeat="${4:-1}"
  local remote_json_name="ui_tap_node_layout.json"
  local local_json
  local_json=$(mktemp "${TMPDIR:-/tmp}/flclash-ui-layout.XXXXXX")
  fetch_layout_json "$target" "$remote_json_name" "$local_json" ||
    fail "Unable to read a valid layout json while locating ${attr}: $query"

  local tap_target
  tap_target=$(python3 - "$local_json" "$attr" "$query" <<'PY'
import json
import re
import sys

layout_path, attr_name, query = sys.argv[1:4]
data = json.load(open(layout_path))
query_cmp = query.casefold()
best = None

def parse_bounds(bounds):
    match = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", bounds or "")
    if not match:
        return None
    return tuple(map(int, match.groups()))

def walk(node, depth=0):
    global best
    attrs = node.get("attributes", {})
    value = (attrs.get(attr_name, "") or "").strip()
    bounds = parse_bounds(attrs.get("bounds", ""))
    clickable = attrs.get("clickable") == "true" or attrs.get("longClickable") == "true"
    if value and value.casefold() == query_cmp and bounds is not None:
        x1, y1, x2, y2 = bounds
        area = (x2 - x1) * (y2 - y1)
        score = (
            0 if clickable else 1,
            depth,
            area,
        )
        if best is None or score < best[0]:
            best = (score, (x1, y1, x2, y2))
    for child in node.get("children", []):
        walk(child, depth + 1)

walk(data)
if best is None:
    sys.exit(1)

x1, y1, x2, y2 = best[1]
print(f"{x1} {y1} {x2} {y2}")
PY
  ) || fail "No matching node found for ${attr}: $query"

  local x1 y1 x2 y2
  read -r x1 y1 x2 y2 <<<"$tap_target"
  local width=$((x2 - x1))
  local height=$((y2 - y1))
  local points=("$(((x1 + x2) / 2)) $(((y1 + y2) / 2))")
  if [[ "$repeat" != "1" ]]; then
    points+=(
      "$((x1 + width * 3 / 4)) $(((y1 + y2) / 2))"
      "$((x1 + width / 4)) $(((y1 + y2) / 2))"
      "$(((x1 + x2) / 2)) $((y1 + height / 3))"
    )
  fi

  local point x y
  for point in "${points[@]}"; do
    read -r x y <<<"$point"
    run_hdc "$target" shell "uitest uiInput click $x $y"
    sleep 0.2
  done
  rm -f "$local_json"
}

find_text() {
  local target="$1"
  local query="$2"
  local mode="${3:-contains}"
  local remote_json_name="ui_find_text_layout.json"
  local local_json
  local_json=$(mktemp "${TMPDIR:-/tmp}/flclash-ui-layout.XXXXXX")
  fetch_layout_json "$target" "$remote_json_name" "$local_json" ||
    fail "Unable to read a valid layout json while finding text: $query"

  python3 - "$local_json" "$query" "$mode" <<'PY'
import json
import re
import sys

layout_path, query, mode = sys.argv[1:4]
data = json.load(open(layout_path))
query_cmp = query.casefold()

def parse_bounds(bounds):
    match = re.match(r"\[(\d+),(\d+)\]\[(\d+),(\d+)\]", bounds or "")
    if not match:
        return None
    return tuple(map(int, match.groups()))

def is_match(text):
    value = (text or "").strip()
    if not value:
        return False
    cmp_value = value.casefold()
    if mode == "exact":
        return cmp_value == query_cmp
    return query_cmp in cmp_value

def walk(node, depth=0):
    attrs = node.get("attributes", {})
    candidates = [
        attrs.get("text", ""),
        attrs.get("originalText", ""),
        attrs.get("hint", ""),
        attrs.get("description", ""),
    ]
    for candidate in candidates:
        if not is_match(candidate):
            continue
        print(
            "\t".join(
                [
                    candidate.replace("\n", "\\n"),
                    attrs.get("bounds", ""),
                    attrs.get("type", ""),
                    attrs.get("clickable", ""),
                    attrs.get("longClickable", ""),
                    attrs.get("id", ""),
                    attrs.get("key", ""),
                ]
            )
        )
    for child in node.get("children", []):
        walk(child, depth + 1)

walk(data)
PY

  rm -f "$local_json"
}

usage() {
  cat <<'EOF'
Usage:
  bash scripts/ohos/ui.sh tap <x> <y>
  bash scripts/ohos/ui.sh text-at <x> <y> <text>
  bash scripts/ohos/ui.sh tap-text <text> [contains|exact]
  bash scripts/ohos/ui.sh tap-text-repeat <text> [contains|exact]
  bash scripts/ohos/ui.sh tap-id <id>
  bash scripts/ohos/ui.sh tap-key <key>
  bash scripts/ohos/ui.sh find-text <text> [contains|exact]
  bash scripts/ohos/ui.sh swipe <x1> <y1> <x2> <y2> [velocity]
  bash scripts/ohos/ui.sh key <Back|Home|Power|keyId>
  bash scripts/ohos/ui.sh text <text>
  bash scripts/ohos/ui.sh capture <name> [out_dir]
  bash scripts/ohos/ui.sh clear-logs
  bash scripts/ohos/ui.sh logs <grep_pattern> [tail_lines]

Environment:
  HDC_TARGET  Explicit HarmonyOS device/emulator target
EOF
}

main() {
  local hdc_bin
  if command -v hdc >/dev/null 2>&1; then
    hdc_bin=$(command -v hdc)
  elif [[ -x "${OHOS_TOOLCHAIN_DIR:-$TOOLCHAIN_DIR_DEFAULT}/hdc" ]]; then
    hdc_bin="${OHOS_TOOLCHAIN_DIR:-$TOOLCHAIN_DIR_DEFAULT}/hdc"
  else
    fail "Missing required command: hdc"
  fi
  HDC_BIN="$hdc_bin"
  local target
  target=$(resolve_target)

  local cmd="${1:-}"
  shift || true

  case "$cmd" in
    tap)
      [[ $# -eq 2 ]] || fail "tap requires: x y"
      run_hdc "$target" shell "uitest uiInput click $1 $2"
      ;;
    text-at)
      [[ $# -ge 3 ]] || fail "text-at requires: x y text"
      local x="$1"
      local y="$2"
      shift 2
      local text_payload="$*"
      run_hdc "$target" shell "uitest uiInput inputText $x $y $(shell_quote "$text_payload")"
      ;;
    tap-text)
      [[ $# -eq 1 || $# -eq 2 ]] || fail "tap-text requires: text [contains|exact]"
      tap_text "$target" "$1" "${2:-contains}" "1"
      ;;
    tap-text-repeat)
      [[ $# -eq 1 || $# -eq 2 ]] || fail "tap-text-repeat requires: text [contains|exact]"
      tap_text "$target" "$1" "${2:-contains}" "4"
      ;;
    tap-id)
      [[ $# -eq 1 ]] || fail "tap-id requires: id"
      tap_node_attr "$target" "id" "$1" "1"
      ;;
    tap-key)
      [[ $# -eq 1 ]] || fail "tap-key requires: key"
      tap_node_attr "$target" "key" "$1" "1"
      ;;
    find-text)
      [[ $# -eq 1 || $# -eq 2 ]] || fail "find-text requires: text [contains|exact]"
      find_text "$target" "$1" "${2:-contains}"
      ;;
    swipe)
      [[ $# -eq 4 || $# -eq 5 ]] || fail "swipe requires: x1 y1 x2 y2 [velocity]"
      local velocity="${5:-800}"
      run_hdc "$target" shell "uitest uiInput swipe $1 $2 $3 $4 $velocity"
      ;;
    key)
      [[ $# -eq 1 ]] || fail "key requires: Back|Home|Power|keyId"
      run_hdc "$target" shell "uitest uiInput keyEvent $1"
      ;;
    text)
      [[ $# -ge 1 ]] || fail "text requires at least one argument"
      local text_payload="$*"
      run_hdc "$target" shell "uitest uiInput text $(shell_quote "$text_payload")"
      ;;
    capture)
      [[ $# -ge 1 && $# -le 2 ]] || fail "capture requires: name [out_dir]"
      capture_state "$target" "$1" "${2:-$OUT_DIR_DEFAULT}"
      ;;
    clear-logs)
      run_hdc "$target" shell "hilog -r"
      ;;
    logs)
      [[ $# -ge 1 && $# -le 2 ]] || fail "logs requires: grep_pattern [tail_lines]"
      local pattern="$1"
      local tail_lines="${2:-120}"
      run_hdc "$target" shell "hilog -x | grep -E $(shell_quote "$pattern") | tail -n $tail_lines || true"
      ;;
    ""|-h|--help|help)
      usage
      ;;
    *)
      fail "Unknown command: $cmd"
      ;;
  esac
}

main "$@"
