#!/usr/bin/env python3
"""Serve a Web export on this computer with the isolation headers it needs.

  python3 tools/serve_web.py public            then open http://localhost:8060/

Files split for the static host (listed in parts.json beside the served
folder) are joined again on the fly, like worker.js does online.
"""
import argparse
import functools
import json
import pathlib
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer


class Handler(SimpleHTTPRequestHandler):
    extensions_map = {**SimpleHTTPRequestHandler.extensions_map, '.wasm': 'application/wasm',
                      '.js': 'text/javascript', '.webmanifest': 'application/manifest+json'}
    parts = {}

    def end_headers(self):
        self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
        self.send_header('Cross-Origin-Embedder-Policy', 'require-corp')
        self.send_header('Cross-Origin-Resource-Policy', 'same-origin')
        self.send_header('Cache-Control', 'no-cache')
        super().end_headers()

    def send_head(self):
        path = self.path.split('?', 1)[0]
        entry = self.parts.get(path)
        if entry is None:
            return super().send_head()
        base = pathlib.Path(self.directory) / path.lstrip('/')
        pieces = [base.with_name(f'{base.name}.part{i}') for i in range(entry['count'])]
        if not all(p.is_file() for p in pieces):
            self.send_error(404, 'Incomplete split file')
            return None
        self.send_response(200)
        self.send_header('Content-Type', self.guess_type(path))
        self.send_header('Content-Length', str(entry['size']))
        self.end_headers()
        self._pieces = pieces
        return None

    def do_GET(self):
        self._pieces = None
        head = self.send_head()
        if self._pieces:
            for piece in self._pieces:
                self.wfile.write(piece.read_bytes())
        elif head:
            try:
                self.copyfile(head, self.wfile)
            finally:
                head.close()


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('directory')
    parser.add_argument('--bind', default='127.0.0.1')
    parser.add_argument('--port', type=int, default=8060)
    args = parser.parse_args()
    manifest = pathlib.Path(args.directory).resolve().parent / 'parts.json'
    Handler.parts = json.loads(manifest.read_text()) if manifest.is_file() else {}
    print(f'Serving {args.directory} at http://{"localhost" if args.bind == "127.0.0.1" else args.bind}:{args.port}/')
    ThreadingHTTPServer((args.bind, args.port), functools.partial(Handler, directory=args.directory)).serve_forever()
