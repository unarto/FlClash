#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET_DIR="${1:-$ROOT_DIR/.ohos_toolchain/go-nonglibc}"
REPO_URL="${FLCLASH_OHOS_GO_REPO:-https://github.com/jgowdy/go}"
REF="${FLCLASH_OHOS_GO_REF:-1a087d05b5cf9573876b18812d8d5516f16bbe57}"

if [[ -x "$TARGET_DIR/bin/go" ]]; then
  "$TARGET_DIR/bin/go" version
  exit 0
fi

BOOTSTRAP_GO="$(command -v go || true)"
if [[ -z "$BOOTSTRAP_GO" ]]; then
  echo "bootstrap go not found in PATH" >&2
  exit 1
fi

BOOTSTRAP_GOROOT="$("$BOOTSTRAP_GO" env GOROOT)"
if [[ -z "$BOOTSTRAP_GOROOT" ]]; then
  echo "failed to resolve GOROOT from bootstrap go" >&2
  exit 1
fi

mkdir -p "$(dirname "$TARGET_DIR")"

if [[ ! -d "$TARGET_DIR/.git" ]]; then
  rm -rf "$TARGET_DIR"
  git clone "$REPO_URL" "$TARGET_DIR"
fi

git -C "$TARGET_DIR" fetch --tags --force origin "$REF"
git -C "$TARGET_DIR" checkout --force "$REF"

(
  cd "$TARGET_DIR/src"
  env \
    GOTOOLCHAIN=local \
    GOROOT_BOOTSTRAP="$BOOTSTRAP_GOROOT" \
    ./make.bash
)

"$TARGET_DIR/bin/go" version
