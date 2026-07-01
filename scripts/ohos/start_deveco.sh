#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
APP_BIN="/Applications/DevEco-Studio.app/Contents/MacOS/devecostudio"
RUNTIME_DIR="$ROOT_DIR/.ohos_verify/deveco"
PROPERTIES_FILE="$RUNTIME_DIR/idea.properties"
VMOPTIONS_FILE="$RUNTIME_DIR/devecostudio.vmoptions"

mkdir -p "$RUNTIME_DIR/config" "$RUNTIME_DIR/system" "$RUNTIME_DIR/log"

cat >"$PROPERTIES_FILE" <<EOF
idea.config.path=$RUNTIME_DIR/config
idea.system.path=$RUNTIME_DIR/system
idea.plugins.path=$RUNTIME_DIR/config/plugins
idea.log.path=$RUNTIME_DIR/log
EOF

cat >"$VMOPTIONS_FILE" <<EOF
-Xms256m
-Xmx2048m
-Dfile.encoding=UTF-8
-XX:ReservedCodeCacheSize=512m
-XX:+HeapDumpOnOutOfMemoryError
-XX:-OmitStackTraceInFastThrow
-XX:CICompilerCount=2
-XX:+IgnoreUnrecognizedVMOptions
-ea
-Dsun.io.useCanonCaches=false
-Dsun.java2d.metal=true
-Djbr.catch.SIGABRT=true
-Djdk.http.auth.tunneling.disabledSchemes=
-Djdk.attach.allowAttachSelf=true
-Djdk.module.illegalAccess.silent=true
-Djdk.nio.maxCachedBufferSize=2097152
-Djava.util.zip.use.nio.for.zip.file.access=true
-Dkotlinx.coroutines.debug=off
-XX:+UnlockDiagnosticVMOptions
-XX:TieredOldPercentage=100000
-Dapple.awt.application.appearance=system
-Didea.properties.file=$PROPERTIES_FILE
EOF

if [[ ! -x "$APP_BIN" ]]; then
  echo "ERROR: DevEco Studio executable not found: $APP_BIN" >&2
  exit 1
fi

exec env DEVECOSTUDIO_VM_OPTIONS="$VMOPTIONS_FILE" "$APP_BIN" "$@"
