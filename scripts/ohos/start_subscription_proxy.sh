#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
STATE_DIR="$ROOT_DIR/.ohos_subscription_proxy"
PID_FILE="$STATE_DIR/proxy.pid"
LOG_FILE="$STATE_DIR/proxy.log"
PYTHON_ENTRY="$ROOT_DIR/scripts/ohos/subscription_proxy.py"
PORT="${OHOS_SUBSCRIPTION_PROXY_PORT:-19002}"
TARGET_URL="${OHOS_SUBSCRIPTION_PROXY_TARGET:-https://example.com/api/v1/client/subscribe?token=REPLACE_ME}"

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
    echo "Subscription proxy already running on port $PORT (pid $(cat "$PID_FILE"))"
    return
  fi

  nohup python3 "$PYTHON_ENTRY" "$TARGET_URL" "$PORT" >"$LOG_FILE" 2>&1 </dev/null &

  echo $! >"$PID_FILE"
  sleep 1

  if ! is_running; then
    echo "Failed to start subscription proxy. See $LOG_FILE" >&2
    exit 1
  fi

  echo "Subscription proxy started"
  echo "  target: $TARGET_URL"
  echo "  port:   $PORT"
  echo "  log:    $LOG_FILE"
}

stop_server() {
  if ! is_running; then
    echo "Subscription proxy is not running"
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
  echo "Subscription proxy stopped"
}

status_server() {
  if is_running; then
    echo "Subscription proxy running on port $PORT (pid $(cat "$PID_FILE"))"
    echo "Target: $TARGET_URL"
  else
    echo "Subscription proxy is not running"
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
