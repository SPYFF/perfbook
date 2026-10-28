#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-2.0-or-later
#
# foliate-js session: Foliate 3.3's own reader page (<webroot>/reader/
# harness.html, see fj-harness.js) in a WebKitGTK 6 view.  Run inside the
# Foliate flatpak's GNOME runtime so the engine matches the app; any GDK
# backend works (harness uses Broadway for headless runs).  Serves the page
# and a control API on one loopback port:
#   GET  /status                  {"ready": bool, "title": str}
#   POST /eval      body=JS       async function body; {"value": ...} or {"error": ...}
#   GET  /shot?out=/abs/path.png  snapshot of the visible view
#   POST /quit
#   fj-session.py <webroot> <port> <book-url-path> <query-string>
# Env: WW WH (window px), FONTSIZE MONO_FONTSIZE (Foliate default 16),
#      SERIF SANS MONO (font families, Foliate defaults).

import http.server
import json
import os
import socketserver
import sys
import threading
import urllib.parse

import gi

gi.require_version('Gtk', '4.0')
gi.require_version('WebKit', '6.0')
from gi.repository import Gio, GLib, Gtk, WebKit  # noqa: E402

webroot, port, book, query = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4]
state = {}


def on_main(fn, timeout=280):
    """Run fn(done) on the GTK main loop and wait for done(result)."""
    ev, box = threading.Event(), {}

    def done(value):
        box['v'] = value
        ev.set()

    GLib.idle_add(lambda: (fn(done), False)[1])
    return box['v'] if ev.wait(timeout) else {'error': 'timeout'}


def js_eval(code, done):
    wv = state['wv']

    def fin(o, res, _):
        try:
            v = wv.call_async_javascript_function_finish(res)
            done({'value': None if v is None or v.is_undefined() else json.loads(v.to_json(0))})
        except GLib.Error as e:
            done({'error': e.message})
    wv.call_async_javascript_function(code, -1, None, None, None, None, fin, None)


def snapshot(path, done):
    wv = state['wv']

    def fin(o, res, _):
        try:
            wv.get_snapshot_finish(res).save_to_png(path)
            done({'value': path})
        except GLib.Error as e:
            done({'error': e.message})
    wv.get_snapshot(WebKit.SnapshotRegion.VISIBLE, WebKit.SnapshotOptions.NONE, None, fin, None)


class Handler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *a, **kw):
        super().__init__(*a, directory=webroot, **kw)

    def log_message(self, *a):
        pass

    def reply(self, obj, code=200):
        body = json.dumps(obj).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        u = urllib.parse.urlparse(self.path)
        if u.path == '/status':
            r = on_main(lambda done: js_eval('return document.title', done), 10)
            return self.reply({'ready': r.get('value') == 'ready', 'title': r.get('value')})
        if u.path == '/shot':
            out = urllib.parse.parse_qs(u.query)['out'][0]
            return self.reply(on_main(lambda done: snapshot(out, done)))
        return super().do_GET()

    def do_POST(self):
        u = urllib.parse.urlparse(self.path)
        if u.path == '/eval':
            code = self.rfile.read(int(self.headers.get('Content-Length', 0))).decode()
            return self.reply(on_main(lambda done: js_eval(code, done)))
        if u.path == '/quit':
            self.reply({'value': True})
            GLib.idle_add(lambda: (state['app'].quit(), False)[1])
            return None
        return self.reply({'error': 'unknown endpoint'}, 404)


class Server(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


def activate(app):
    win = Gtk.ApplicationWindow(application=app, title='foliate-js harness')
    win.set_default_size(int(os.environ.get('WW', '1400')), int(os.environ.get('WH', '900')))
    win.set_resizable(False)
    wv = WebKit.WebView()
    s = wv.get_settings()
    # Foliate's book-viewer.js WebKit.Settings and default FontSettings.
    s.set_enable_developer_extras(True)
    s.set_enable_back_forward_navigation_gestures(False)
    s.set_enable_html5_database(False)
    s.set_enable_html5_local_storage(False)
    s.set_enable_smooth_scrolling(False)
    size = int(os.environ.get('FONTSIZE', '16'))
    s.set_default_font_size(size)
    s.set_default_monospace_font_size(int(os.environ.get('MONO_FONTSIZE', str(size))))
    s.set_serif_font_family(os.environ.get('SERIF', 'Serif'))
    s.set_sans_serif_font_family(os.environ.get('SANS', 'Sans'))
    s.set_monospace_font_family(os.environ.get('MONO', 'Monospace'))
    s.set_default_font_family(os.environ.get('SERIF', 'Serif'))
    win.set_child(wv)
    win.present()
    state.update(app=app, wv=wv, win=win)
    wv.load_uri('http://127.0.0.1:%d/reader/harness.html?book=%s&%s'
                % (port, urllib.parse.quote(book), query))


srv = Server(('127.0.0.1', port), Handler)
threading.Thread(target=srv.serve_forever, daemon=True).start()
app = Gtk.Application(flags=Gio.ApplicationFlags.NON_UNIQUE)
app.connect('activate', activate)
app.run(None)
srv.shutdown()
