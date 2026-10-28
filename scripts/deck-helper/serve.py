#!/usr/bin/env python3
"""Serve the built Deck Helper (build_output/deck-helper) on $PORT or 8765, so card images load (docs/DECK_HELPER.md).

  python3 scripts/deck-helper/serve.py            # then open http://localhost:8765
"""
import os, sys
from functools import partial
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2] / 'build_output/deck-helper'
PORT = int(os.environ.get('PORT') or (sys.argv[1] if len(sys.argv) > 1 else 8765))


class Quiet(SimpleHTTPRequestHandler):
    def log_message(self, fmt, *args):  # one line per page load is plenty
        if self.path in ('/', '/index.html'):
            sys.stderr.write(f'{self.address_string()} {self.path}\n')

    def end_headers(self):
        self.send_header('Cache-Control', 'no-cache')
        super().end_headers()


if not (ROOT / 'index.html').exists():
    sys.exit(f'{ROOT}/index.html is missing: run scripts/deck-helper/build.py first')
server = ThreadingHTTPServer(('127.0.0.1', PORT), partial(Quiet, directory=str(ROOT)))
print(f'Deck Helper at http://localhost:{PORT} (serving {ROOT})', flush=True)
try:
    server.serve_forever()
except KeyboardInterrupt:
    pass
