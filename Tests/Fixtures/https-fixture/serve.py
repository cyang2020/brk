#!/usr/bin/env python3
"""The https side of the test site: three pages for the site controls' Secure / Insecure row.

    python3 -I Tests/Fixtures/https-fixture/serve.py --port 8781 --http-port 8782 [--ready FILE]

One TLS port, two certificates chosen by the name the browser asks for (SNI):
  https://127.0.0.1:<port>/secure.html                a clean page on trusted.pem
  https://untrusted.brk.test:<port>/invalid.html      untrusted.pem: certificate interstitial, then an error
  https://127.0.0.1:<port>/mixed.html                 trusted.pem, plus an image and a form action on plain
                                                      HTTP from insecure.brk.test:<http-port>
The plain HTTP port serves the mixed page's image and records each request, so a run can show the insecure
image was really fetched. *.brk.test names resolve only inside Brk launched with BRK_CONTROL_SOCKET (its test
host-resolver rule maps them to 127.0.0.1). Port 0 picks free ports; --ready writes {"https", "http", "pid"}
as JSON once both listen. Nothing here touches the keychain or system trust; see make-certs.sh.
"""
import argparse
import http.server
import json
import os
import ssl
import sys
import threading
from pathlib import Path

HERE = Path(__file__).resolve().parent
PIXEL = (b'<svg xmlns="http://www.w3.org/2000/svg" width="40" height="40">'
         b'<rect width="40" height="40" fill="#d33"/></svg>')


def page(title, body):
    return ('<!doctype html><meta charset="utf-8"><title>' + title + '</title>'
            '<style>body{font:16px -apple-system,system-ui;margin:48px;color:#222}</style>'
            '<h1>' + title + '</h1>' + body).encode()


def pages(http_port):
    insecure = f'http://insecure.brk.test:{http_port}'
    image = f'<p><img id="insecure-image" alt="plain HTTP image" src="{insecure}/pixel.svg" width="40" height="40"></p>'
    form = (f'<form id="insecure-form" action="{insecure}/submit" method="post">'
            '<input name="q" value="sent over plain HTTP"> <button>Send</button></form>')
    return {
        '/secure.html': page('Secure fixture', '<p>Served over HTTPS with the test certificate Brk trusts.</p>'),
        '/invalid.html': page('Invalid certificate fixture', '<p>Served with a certificate no one trusts.</p>'),
        '/mixed.html': page('Mixed content fixture', '<p>HTTPS page with plain HTTP parts.</p>' + image + form),
        '/mixed-image.html': page('Mixed image fixture', image),
        '/mixed-form.html': page('Mixed form fixture', form),
    }


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = 'BrkHTTPSFixture/1'
    routes = {}
    log = None

    def do_GET(self):
        path = self.path.split('?')[0]
        if self.log:
            self.log.write(json.dumps({'scheme': self.server.scheme, 'host': self.headers.get('Host'), 'path': path}) + '\n')
            self.log.flush()
        if self.server.scheme == 'http':
            body, kind = (PIXEL, 'image/svg+xml') if path == '/pixel.svg' else (b'ok', 'text/plain')
        elif path in self.routes:
            body, kind = self.routes[path], 'text/html; charset=utf-8'
        else:
            self.send_error(404); return
        self.send_response(200)
        self.send_header('Content-Type', kind)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(body)

    do_POST = do_GET

    def log_message(self, fmt, *args):
        pass


def tls_context(name):
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(HERE / f'{name}.pem', HERE / f'{name}-key.pem')
    return context


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=8781)
    parser.add_argument('--http-port', type=int, default=8782)
    parser.add_argument('--ready')
    parser.add_argument('--requests', help='append one JSON line per request to this file')
    args = parser.parse_args()

    trusted, untrusted = tls_context('trusted'), tls_context('untrusted')

    def choose(sock, server_name, _context):
        if server_name and server_name.lower() == 'untrusted.brk.test':
            sock.context = untrusted
    trusted.sni_callback = choose

    if args.requests:
        Handler.log = open(args.requests, 'a')
    plain = http.server.ThreadingHTTPServer(('127.0.0.1', args.http_port), Handler)
    plain.scheme = 'http'
    secure = http.server.ThreadingHTTPServer(('127.0.0.1', args.port), Handler)
    secure.scheme = 'https'
    secure.socket = trusted.wrap_socket(secure.socket, server_side=True)
    Handler.routes = pages(plain.server_address[1])

    threading.Thread(target=plain.serve_forever, daemon=True).start()
    if args.ready:
        ready = {'https': secure.server_address[1], 'http': plain.server_address[1], 'pid': os.getpid()}
        Path(args.ready).write_text(json.dumps(ready))
    print(f'https on 127.0.0.1:{secure.server_address[1]}, http on 127.0.0.1:{plain.server_address[1]}', flush=True)
    try:
        secure.serve_forever()
    except KeyboardInterrupt:
        pass


if __name__ == '__main__':
    sys.exit(main())
