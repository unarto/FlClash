#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
STATE_DIR="$ROOT_DIR/.ohos_webdav"
VENV_DIR="$STATE_DIR/venv"
DATA_DIR="$STATE_DIR/data"
PID_FILE="$STATE_DIR/webdav.pid"
LOG_FILE="$STATE_DIR/webdav.log"
PORT="${OHOS_WEBDAV_PORT:-19000}"
USER_NAME="${OHOS_WEBDAV_USER:-flclash}"
PASSWORD="${OHOS_WEBDAV_PASSWORD:-flclash-pass}"

mkdir -p "$STATE_DIR" "$DATA_DIR"

find_listen_pid() {
  lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | head -n 1
}

create_venv() {
  python3 -m venv "$VENV_DIR"
  "$VENV_DIR/bin/pip" install --quiet --upgrade pip
  "$VENV_DIR/bin/pip" install --quiet WsgiDAV cheroot
}

ensure_venv() {
  if [[ ! -x "$VENV_DIR/bin/python" ]]; then
    create_venv
    return
  fi

  if ! "$VENV_DIR/bin/python" - <<'PY' >/dev/null 2>&1
import importlib.util
import sys
required = ["wsgidav", "cheroot"]
sys.exit(0 if all(importlib.util.find_spec(name) for name in required) else 1)
PY
  then
    create_venv
  fi
}

is_running() {
  local listen_pid
  listen_pid=$(find_listen_pid || true)
  if [[ -n "$listen_pid" ]]; then
    echo "$listen_pid" >"$PID_FILE"
    return 0
  fi
  rm -f "$PID_FILE"
  return 1
}

start_server() {
  ensure_venv
  if is_running; then
    echo "WebDAV server already running on port $PORT (pid $(cat "$PID_FILE"))"
    return
  fi

  nohup "$VENV_DIR/bin/wsgidav" \
    --host 0.0.0.0 \
    --port "$PORT" \
    --root "$DATA_DIR" \
    --auth anonymous \
    --server cheroot \
    >"$LOG_FILE" 2>&1 &

  echo $! >"$PID_FILE"
  sleep 2

  if ! is_running; then
    echo "Failed to start WebDAV server. See $LOG_FILE" >&2
    exit 1
  fi

  echo "WebDAV server started"
  echo "  root: $DATA_DIR"
  echo "  port: $PORT"
  echo "  auth: anonymous"
  echo "  user: $USER_NAME (ignored by server)"
  echo "  log:  $LOG_FILE"
}

stop_server() {
  if ! is_running; then
    echo "WebDAV server is not running"
    rm -f "$PID_FILE"
    return
  fi

  local pid
  pid=$(cat "$PID_FILE")
  kill "$pid"
  sleep 1
  local listen_pid
  listen_pid=$(find_listen_pid || true)
  if [[ -n "$listen_pid" ]]; then
    kill "$listen_pid" 2>/dev/null || true
  fi
  rm -f "$PID_FILE"
  echo "WebDAV server stopped"
}

status_server() {
  if is_running; then
    echo "WebDAV server running on port $PORT (pid $(cat "$PID_FILE"))"
  else
    echo "WebDAV server is not running"
    rm -f "$PID_FILE"
  fi
}

case "${1:-start}" in
  start)
    start_server
    ;;
  stop)
    stop_server
    ;;
  restart)
    stop_server || true
    start_server
    ;;
  status)
    status_server
    ;;
  *)
    echo "Usage: $0 [start|stop|restart|status]" >&2
    exit 1
    ;;
esac
