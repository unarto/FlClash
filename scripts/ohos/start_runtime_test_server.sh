#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
STATE_DIR="$ROOT_DIR/.ohos_runtime_test_server"
PID_FILE="$STATE_DIR/server.pid"
LOG_FILE="$STATE_DIR/server.log"
PYTHON_ENTRY="$ROOT_DIR/scripts/ohos/runtime_test_server.py"
PORT="${OHOS_RUNTIME_TEST_PORT:-19003}"

mkdir -p "$STATE_DIR"

find_listen_pid() {
  lsof -tiTCP:"$PORT" -sTCP:LISTEN 2>/dev/null | head -n 1
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
  if is_running; then
    echo "Runtime test server already running on port $PORT (pid $(cat "$PID_FILE"))"
    return
  fi

  python3 "$PYTHON_ENTRY" --daemon "$PORT" "$LOG_FILE"
  sleep 1

  if ! is_running; then
    echo "Failed to start runtime test server. See $LOG_FILE" >&2
    exit 1
  fi

  cat <<EOF
Runtime test server started
  port: $PORT
  log:  $LOG_FILE

Suggested endpoints:
  http://127.0.0.1:$PORT/delay?seconds=10
  http://127.0.0.1:$PORT/stream?seconds=20&interval_ms=500&chunk_bytes=256
  http://127.0.0.1:$PORT/ip-check?delay_ms=1000
EOF
}

stop_server() {
  if ! is_running; then
    echo "Runtime test server is not running"
    rm -f "$PID_FILE"
    return
  fi

  local pid
  pid=$(cat "$PID_FILE")
  kill "$pid" 2>/dev/null || true
  sleep 1
  local listen_pid
  listen_pid=$(find_listen_pid || true)
  if [[ -n "$listen_pid" ]]; then
    kill "$listen_pid" 2>/dev/null || true
  fi
  rm -f "$PID_FILE"
  echo "Runtime test server stopped"
}

status_server() {
  if is_running; then
    echo "Runtime test server running on port $PORT (pid $(cat "$PID_FILE"))"
  else
    echo "Runtime test server is not running"
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
