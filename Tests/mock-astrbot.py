#!/usr/bin/python3
import http.server
import os
import sys
import time

assert sys.argv[1:] == ["run"]
print("mock: stdout", flush=True)
print("mock: stderr", file=sys.stderr, flush=True)
time.sleep(0.9)
print("\033[32mAstrBot v99.0.0 WebUI is ready\033[0m", flush=True)
# The real CLI can print the banner before its HTTP listener is accepting connections.
time.sleep(0.8)


class Dashboard(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        page = b"<!doctype html><title>Dashboard</title><h1>Mock AstrBot Dashboard</h1>"
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(page)))
        self.end_headers()
        self.wfile.write(page)


try:
    with http.server.HTTPServer(("127.0.0.1", int(os.environ["DASHBOARD_PORT"])), Dashboard) as server:
        server.timeout = 0.25
        deadline = time.monotonic() + 15
        parent = os.getppid()
        while parent != 1 and os.getppid() == parent and time.monotonic() < deadline:
            server.handle_request()
except KeyboardInterrupt:
    print("mock: stopped", flush=True)
