#!/usr/bin/env python3

import json
import os
import sys
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse


def parse_int(params: dict[str, list[str]], key: str, default: int) -> int:
    raw = params.get(key, [str(default)])[0]
    try:
        value = int(raw)
    except ValueError:
        return default
    return value if value >= 0 else default


def write_json(handler: BaseHTTPRequestHandler, status: int, body: dict) -> None:
    payload = json.dumps(body).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(payload)))
    handler.end_headers()
    handler.wfile.write(payload)


def daemonize(log_path: str) -> None:
    if os.fork() > 0:
        raise SystemExit(0)
    os.setsid()
    if os.fork() > 0:
        raise SystemExit(0)

    sys.stdout.flush()
    sys.stderr.flush()

    with open("/dev/null", "rb", buffering=0) as devnull_read:
        os.dup2(devnull_read.fileno(), sys.stdin.fileno())

    with open(log_path, "ab", buffering=0) as log_file:
        os.dup2(log_file.fileno(), sys.stdout.fileno())
        os.dup2(log_file.fileno(), sys.stderr.fileno())


def main() -> int:
    daemon_mode = len(sys.argv) == 4 and sys.argv[1] == "--daemon"

    if daemon_mode:
        port = int(sys.argv[2])
        log_path = sys.argv[3]
        daemonize(log_path)
    elif len(sys.argv) == 2:
        port = int(sys.argv[1])
    else:
        print(
            "usage: runtime_test_server.py [--daemon <port> <log_path> | <port>]",
            file=sys.stderr,
        )
        return 1

    class Handler(BaseHTTPRequestHandler):
        server_version = "FlClashRuntimeTest/1.0"
        protocol_version = "HTTP/1.1"

        def do_GET(self) -> None:
            parsed = urlparse(self.path)
            params = parse_qs(parsed.query)

            if parsed.path in ("", "/"):
                write_json(
                    self,
                    200,
                    {
                        "ok": True,
                        "paths": [
                            "/delay?seconds=5",
                            "/stream?seconds=15&interval_ms=500&chunk_bytes=256",
                            "/ip-check?delay_ms=0",
                        ],
                    },
                )
                return

            if parsed.path == "/delay":
                seconds = parse_int(params, "seconds", 5)
                time.sleep(seconds)
                body = f"delayed {seconds}s\n".encode("utf-8")
                self.send_response(200)
                self.send_header("Content-Type", "text/plain; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return

            if parsed.path == "/stream":
                seconds = max(1, parse_int(params, "seconds", 15))
                interval_ms = max(100, parse_int(params, "interval_ms", 500))
                chunk_bytes = max(1, parse_int(params, "chunk_bytes", 256))
                iterations = max(1, int(seconds * 1000 / interval_ms))
                chunk = (b"x" * (chunk_bytes - 1)) + b"\n"

                self.send_response(200)
                self.send_header("Content-Type", "text/plain; charset=utf-8")
                self.send_header("Cache-Control", "no-store")
                self.end_headers()

                for index in range(iterations):
                    line = f"chunk={index + 1}/{iterations} ".encode("utf-8")
                    payload = line + chunk
                    self.wfile.write(payload)
                    self.wfile.flush()
                    time.sleep(interval_ms / 1000)
                return

            if parsed.path == "/ip-check":
                delay_ms = parse_int(params, "delay_ms", 0)
                if delay_ms > 0:
                    time.sleep(delay_ms / 1000)
                write_json(
                    self,
                    200,
                    {
                        "ip": "203.0.113.10",
                        "country": "US",
                        "cc": "US",
                    },
                )
                return

            write_json(
                self,
                404,
                {"ok": False, "error": "not found", "path": parsed.path},
            )

        def log_message(self, fmt: str, *args) -> None:
            print(fmt % args, flush=True)

    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
