#!/usr/bin/env bash

set -euo pipefail

SOURCE_SDK="${SOURCE_SDK:-/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony}"
DEVECO_OPENHARMONY_SDK="${DEVECO_OPENHARMONY_SDK:-$HOME/Library/OpenHarmony/Sdk}"
DEVECO_SDK_VERSION="${DEVECO_SDK_VERSION:-24}"
DEVECO_OPENHARMONY_SDK_VERSION_DIR="$DEVECO_OPENHARMONY_SDK/$DEVECO_SDK_VERSION"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

[[ -d "$SOURCE_SDK" ]] || fail "Source OpenHarmony SDK not found: $SOURCE_SDK"
[[ -f "$SOURCE_SDK/toolchains/oh-uni-package.json" ]] ||
  fail "Source SDK is missing toolchains metadata: $SOURCE_SDK"

if [[ -L "$DEVECO_OPENHARMONY_SDK" ]]; then
  current_target=$(readlink "$DEVECO_OPENHARMONY_SDK")
  if [[ "$current_target" == "$SOURCE_SDK" ]]; then
    rm "$DEVECO_OPENHARMONY_SDK"
  else
    fail "Refusing to replace existing symlink path: $DEVECO_OPENHARMONY_SDK"
  fi
elif [[ -e "$DEVECO_OPENHARMONY_SDK" && ! -d "$DEVECO_OPENHARMONY_SDK" ]]; then
  fail "Refusing to replace existing non-directory path: $DEVECO_OPENHARMONY_SDK"
fi

mkdir -p "$(dirname "$DEVECO_OPENHARMONY_SDK")"
mkdir -p "$DEVECO_OPENHARMONY_SDK"

if [[ -L "$DEVECO_OPENHARMONY_SDK_VERSION_DIR" ]]; then
  current_target=$(readlink "$DEVECO_OPENHARMONY_SDK_VERSION_DIR")
  if [[ "$current_target" == "$SOURCE_SDK" ]]; then
    echo "DevEco OpenHarmony SDK link already configured: $DEVECO_OPENHARMONY_SDK_VERSION_DIR -> $SOURCE_SDK"
    exit 0
  fi
  rm "$DEVECO_OPENHARMONY_SDK_VERSION_DIR"
elif [[ -e "$DEVECO_OPENHARMONY_SDK_VERSION_DIR" ]]; then
  fail "Refusing to replace existing non-symlink path: $DEVECO_OPENHARMONY_SDK_VERSION_DIR"
fi

ln -s "$SOURCE_SDK" "$DEVECO_OPENHARMONY_SDK_VERSION_DIR"
echo "Configured DevEco OpenHarmony SDK link: $DEVECO_OPENHARMONY_SDK_VERSION_DIR -> $SOURCE_SDK"
