#!/usr/bin/env python3

import sys
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: subscription_proxy.py <target_url> <port>", file=sys.stderr)
        return 1

    target = sys.argv[1]
    port = int(sys.argv[2])

    class ProxyHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            if self.path != "/" and not self.path.startswith("/j"):
                self.send_response(404)
                self.end_headers()
                self.wfile.write(b"not found")
                return

            try:
                user_agent = self.headers.get("User-Agent") or "clash.meta/1.10.0"
                request = Request(target, headers={"User-Agent": user_agent})
                with urlopen(request, timeout=30) as response:
                    body = response.read()
                    self.send_response(response.status)
                    self.send_header(
                        "Content-Type",
                        response.headers.get(
                            "Content-Type",
                            "text/plain; charset=utf-8",
                        ),
                    )
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
            except HTTPError as error:
                body = error.read()
                self.send_response(error.code)
                self.send_header("Content-Type", "text/plain; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
            except URLError as error:
                body = str(error).encode()
                self.send_response(502)
                self.send_header("Content-Type", "text/plain; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

        def do_HEAD(self):
            self.do_GET()

        def log_message(self, fmt, *args):
            print(fmt % args, flush=True)

    HTTPServer(("127.0.0.1", port), ProxyHandler).serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
