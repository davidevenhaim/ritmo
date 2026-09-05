#!/usr/bin/env python3
"""Serve build/web for the demo with caching turned off.

Chrome will happily reuse a heuristically-fresh copy of exercises.json from
disk cache, which makes a rebuilt catalogue look like it never landed. Every
response here is no-store so a reload always shows the current build.
"""
import functools
import http.server
import os
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "build", "web")


class NoCache(http.server.SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store, must-revalidate")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()

    def log_message(self, *args):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    handler = functools.partial(NoCache, directory=os.path.abspath(ROOT))
    print(f"serving {os.path.abspath(ROOT)} at http://localhost:{port}")
    http.server.ThreadingHTTPServer(("127.0.0.1", port), handler).serve_forever()
