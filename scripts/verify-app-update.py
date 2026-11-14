#!/usr/bin/env python3
"""Verify real Sparkle installation and relaunch using disposable signed app copies.

Run with --app <assembled .app> --sign-tool <Sparkle bin/sign_update> --out <evidence>.
The script takes the shared native lock. It never replaces the supplied app or a user's app.
"""
import argparse
import base64
import contextlib
import datetime
import functools
import http.server
import json
import os
from pathlib import Path
import platform
import plistlib
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
import uuid
import xml.etree.ElementTree as ET
from release import Release, appcast as release_appcast, history_html


ROOT = Path(__file__).resolve().parents[1]
SPARKLE = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
ET.register_namespace('sparkle', SPARKLE)


def run(*args, **kwargs):
    return subprocess.run([str(x) for x in args], check=True, capture_output=True, **kwargs)


def until(description, predicate, timeout=30):
    deadline = time.monotonic() + timeout
    last = None
    while time.monotonic() < deadline:
        try:
            value = predicate()
            if value:
                return value
        except (OSError, ValueError, KeyError) as error:
            last = error
        time.sleep(0.15)
    raise RuntimeError(f'Timed out waiting for {description}; last observation: {last}')


def request(path, op):
    with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as connection:
        connection.settimeout(10)
        connection.connect(str(path))
        connection.sendall((json.dumps({'id': 1, 'op': op}) + '\n').encode())
        data = bytearray()
        while not data.endswith(b'\n'):
            chunk = connection.recv(65536)
            if not chunk:
                raise OSError('Control socket closed before replying')
            data.extend(chunk)
    result = json.loads(data)['result']
    if 'failed' in result:
        raise RuntimeError(f'Control operation failed: {result["failed"]}')
    return result


def hello(path):
    return request(path, {'hello': {}})['hello']['_0']


def view(path):
    return request(path, {'view': {}})['view']['_0']


def dispatch(path, command):
    return request(path, {'dispatch': {'command': command}})


def clone(source, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    run('cp', '-cR', source, destination)


def signing_key(folder):
    secret, public = folder / 'signing.key', folder / 'signing.pub'
    code = '''import Foundation
import CryptoKit
let key = Curve25519.Signing.PrivateKey()
try key.rawRepresentation.base64EncodedString().write(toFile: CommandLine.arguments[1], atomically: true, encoding: .utf8)
try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: CommandLine.arguments[1])
try key.publicKey.rawRepresentation.base64EncodedString().write(toFile: CommandLine.arguments[2], atomically: true, encoding: .utf8)
'''
    source = folder / 'signing.swift'
    source.write_text(code)
    run('swift', source, secret, public)
    value = public.read_text().strip()
    if len(base64.b64decode(value)) != 32:
        raise RuntimeError('Fixture public key has the wrong length')
    return secret, value


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_):
        pass


def fixture_app(app, name, bundle_id, build, version, public_key, base, environment):
    path = app / 'Contents/Info.plist'
    info = plistlib.loads(path.read_bytes())
    info.update(CFBundleName=name, CFBundleDisplayName=name, CFBundleIdentifier=bundle_id,
                CFBundleVersion=str(build), CFBundleShortVersionString=version,
                SUFeedURL=base + '/appcast.xml', SUPublicEDKey=public_key,
                SUEnableAutomaticChecks=False, SUAutomaticallyUpdate=False)
    info['LSEnvironment'] = {**info.get('LSEnvironment', {}), **environment}
    info['NSAppTransportSecurity'] = {'NSAllowsLocalNetworking': True}
    path.write_bytes(plistlib.dumps(info))
    notes = app / 'Contents/Resources/Help/release-notes.html'
    notes.parent.mkdir(parents=True, exist_ok=True)
    notes.write_text(history_html(ROOT, Release(version, f'# Brk {version}\n\n- Fixture update for {version}/{build}.'), False))
    run(ROOT / 'scripts/sign-developer-id.sh', app, env={**os.environ, 'SIGN_IDENTITY': '-'})
    run('codesign', '--verify', '--deep', '--strict', app)
    return app / 'Contents/MacOS' / info['CFBundleExecutable']


def appcast(path, base, archive, signature, build, version):
    release = Release(version, Release.load(ROOT).notes)
    rss = ET.fromstring(release_appcast(release, 'cyang2020/brk', platform.machine(), str(build),
                                       archive, signature, datetime.datetime.now(datetime.timezone.utc)))
    item = rss.find('./channel/item')
    item.find('enclosure').set('url', base + '/' + archive.name)
    item.find(f'{{{SPARKLE}}}releaseNotesLink').text = base + '/release-notes.html'
    ET.ElementTree(rss).write(path, encoding='utf-8', xml_declaration=True)


def centre(rect):
    (x, y), (width, height) = rect
    return x + width / 2, y + height / 2


def native_click(control, pid, element=None, move_only=False, away=False):
    state = view(control)
    request(control, {'activateApp': {'window': state['id']}})
    native = request(control, {'native': {}})['native']['_0']
    rect = native['computed']['sidebar'].get('updateBanner') if element is None else None
    if away:
        width, height = native['windowFrame'][1]
        rect = [[width * 0.75, height * 0.5], [1, 1]]
    if not rect:
        candidates = [v['frame'] for k, v in native['actual'].items()
                      if (element or 'install-update') in k and not v.get('hidden', False)]
        if len(candidates) != 1:
            raise RuntimeError(f'No unique visible update button: {candidates}')
        rect = candidates[0]
    x, y = centre(rect)
    (wx, wy), (_, wh) = native['windowFrame']
    height = float(run('swift', '-e', 'import CoreGraphics; print(CGDisplayBounds(CGMainDisplayID()).height)').stdout)
    x, y = wx + x, height - wy - wh + y
    top = ROOT / 'scripts/station/bin/topwin'
    top_command = [top] if top.exists() else ['swift', ROOT / 'scripts/station/topwin.swift']
    front = run(*top_command, x, y).stdout.decode().strip().split('|')
    if len(front) < 2 or front[1] != str(pid):
        raise RuntimeError(f'Another application covers the update button: {front}')
    mouse = ROOT / 'scripts/station/bin/mouse'
    mouse_command = [mouse] if mouse.exists() else ['swift', ROOT / 'scripts/station/mouse.swift']
    run(*mouse_command, 'move' if move_only else 'click', x, y)


def reveal_card(control, pid):
    native_click(control, pid, move_only=True)
    until('expanded update controls', lambda: any('update-primary' in key and not value.get('hidden', False)
          for key, value in request(control, {'native': {}})['native']['_0']['actual'].items()))


def key_tap(key, modifiers=None):
    executable = ROOT / 'scripts/station/bin/key'
    command = [executable] if executable.exists() else ['swift', ROOT / 'scripts/station/key.swift']
    run(*command, 'tap', key, *([modifiers] if modifiers else []))


def card_visible(control):
    return any('update-primary' in key and not value.get('hidden', False)
               for key, value in request(control, {'native': {}})['native']['_0']['actual'].items())


def action_color(control):
    actual = request(control, {'native': {}})['native']['_0']['actual']
    (x, y), (width, height) = next(value['frame'] for key, value in actual.items() if 'update-primary' in key)
    return request(control, {'pixel': {'point': [x + width * 0.1, y + height / 2]}})['pixel']


def verify_notes(control, version='0.0.1', build=44, bundled=False):
    expected = json.dumps(f'Fixture update for {version}/{build}.')
    def check():
        state = view(control)
        panes = state['content']['panes']
        page = next((p['content']['page']['_0'] for p in panes if p.get('focused') and 'page' in p['content']), None)
        if page is None or state['urlPill']['loading']:
            return False
        if bundled and '/Contents/Resources/Help/' not in (state['urlPill'].get('text') or ''):
            return False
        request(control, {'evaluate': {'page': page, 'script': "document.title = 'UPDATER_NOTES:' + document.body.innerText.includes(" + expected + ");"}})
        return True
    until('release notes document', check)
    until('the actual version notes content', lambda: 'UPDATER_NOTES:true' in json.dumps(view(control)))


def screenshot(control, output):
    request(control, {'screenshot': {'path': str(output)}})


def stop_fixture(control, folder):
    with contextlib.suppress(Exception):
        request(control, {'quit': {}})
    deadline = time.monotonic() + 12
    while time.monotonic() < deadline:
        rows = run('ps', '-axo', 'pid=,command=').stdout.decode().splitlines()
        owned = []
        for row in rows:
            parts = row.strip().split(None, 1)
            if len(parts) == 2 and str(folder) in parts[1] and '/Contents/MacOS/' in parts[1]:
                owned.append(int(parts[0]))
        if not owned:
            return
        time.sleep(0.2)
    for pid in owned:
        with contextlib.suppress(ProcessLookupError):
            os.kill(pid, signal.SIGTERM)


def verify(args, mode):
    output = args.out / mode
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='brk-upgrade-', dir='/tmp') as temporary:
        folder = Path(temporary)
        web = folder / 'web'
        web.mkdir()
        (web / 'page.html').write_text('<!doctype html><title>Updater fixture</title><h1>Update fixture</h1>'
                                      '<script>document.addEventListener("keydown", e => document.title = "Updater fixture:" + e.key)</script>')
        (web / 'release-notes.html').write_text('<!doctype html><title>Update changes</title><p>Fixture update for 0.0.1/44.</p>')
        server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), functools.partial(QuietHandler, directory=str(web)))
        threading.Thread(target=server.serve_forever, daemon=True).start()
        base = f'http://127.0.0.1:{server.server_port}'
        source, target = folder / 'current/Brk.app', folder / 'target/Brk.app'
        control, data = folder / 'control.sock', folder / 'data'
        token = uuid.uuid4().hex[:12]
        name = 'Brk'
        bundle_id = 'dev.brk.updatefixture.' + token
        environment = dict(BRK_DATA_DIR=str(data), BRK_CONTROL_SOCKET=str(control),
                           BRK_START_URL=base + '/page.html', BRK_TEST_NO_GLOBAL_SHORTCUT='1')
        secret, public = signing_key(folder)
        clone(args.app, source)
        clone(args.app, target)
        executable = fixture_app(source, name, bundle_id, 42, '0.1.0', public, base, environment)
        fixture_app(target, name, bundle_id, 44, '0.0.1', public, base, environment)
        archive = web / ('Brk-' + platform.machine() + '.dmg')
        run('hdiutil', 'create', '-quiet', '-fs', 'APFS', '-volname', name, '-srcfolder', target.parent,
            '-format', 'ULFO', '-o', archive)
        signature = run(args.sign_tool, '--ed-key-file', secret, '-p', archive).stdout.decode().strip()
        run(args.sign_tool, '--verify', '--ed-key-file', secret, archive, signature)
        if mode == 'reject':
            raw = bytearray(base64.b64decode(signature))
            raw[0] ^= 1
            signature = base64.b64encode(raw).decode()
        appcast(web / 'appcast.xml', base, archive, signature, 44, '0.0.1')
        log = (output / 'app.log').open('wb')
        process = subprocess.Popen([str(executable)], env={**os.environ, **environment},
                                   stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            first = until('source app startup', lambda: hello(control), timeout=40)
            state = view(control)
            space = state['space']['id']
            dispatch(control, {'space': {'_0': {'update': {'_0': space, 'title': 'Update preserved this space'}}}})
            request(control, {'flush': {}})
            dispatch(control, {'app': {'_0': {'help': {'_0': {'checkForUpdates': {}}}}}})
            until('a real appcast update offer', lambda: (view(control)['sidebar'].get('update') or {}).get('available'))
            screenshot(control, output / 'available.png')
            if mode == 'ui':
                request(control, {'setWindowFrame': {'frame': [[320, 180], [1280, 776]]}})
                geometry = {}
                for appearance, color in [('light', [0.95, 0.918, 0.894]), ('dark', [0.4236151278, 0.7285773754, 0.8512415886])]:
                    native_click(control, first['pid'], move_only=True, away=True)
                    theme = dict(colors=[dict(zip(('red', 'green', 'blue', 'alpha'), [*color, 1]))],
                                 wheel='analogous', texture='grain', noise=0.5, intensity=0.25, appearance=appearance)
                    dispatch(control, {'space': {'_0': {'update': {'_0': space, 'theme': theme}}}})
                    time.sleep(0.5)
                    native = request(control, {'native': {}})['native']['_0']
                    geometry[appearance] = native['computed']['sidebar']['updateBanner']
                    screenshot(control, output / f'{appearance}.png')
                    reveal_card(control, first['pid'])
                    screenshot(control, output / f'{appearance}-expanded.png')
                    if appearance == 'dark':
                        motion_before = action_color(control)
                        time.sleep(1.2)
                        motion_after = action_color(control)
                        screenshot(control, output / 'dark-animation.png')
                        reduced = run('swift', '-e', 'import AppKit; print(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)').stdout.strip() == b'true'
                        changes = max(abs(motion_after[c] - motion_before[c]) for c in ('red', 'green', 'blue'))
                        if (not reduced and changes < 3) or (reduced and changes > 2):
                            raise RuntimeError(f'Update animation did not follow Reduce Motion ({reduced}): {motion_before} -> {motion_after}')
                native_click(control, first['pid'], 'update-automatic')
                until('automatic update preference enabled', lambda: view(control)['sidebar']['automaticUpdates'])
                native_click(control, first['pid'], 'update-automatic')
                until('automatic update preference disabled', lambda: not view(control)['sidebar']['automaticUpdates'])
                if hello(control)['pid'] != first['pid']:
                    raise RuntimeError('Changing the preference restarted an active app')
                key_tap('escape')
                until('card closed by Escape', lambda: not card_visible(control))
                key_tap('a')
                until('webpage keyboard focus restored', lambda: 'Updater fixture:a' in json.dumps(view(control)))
                reveal_card(control, first['pid'])
                key_tap('t', 'command')
                until('command bar opened above the card', lambda: view(control).get('overlay'))
                key_tap('escape')
                until('command bar closed with one Escape', lambda: view(control).get('overlay') is None)
                (output / 'geometry.json').write_text(json.dumps(geometry, indent=2) + '\n')
                result = dict(mode=mode, passed=True, measured=['light', 'dark'], geometry=geometry,
                              automaticPreferenceToggled=True, focusRestored=True, commandBarEscape=True,
                              reduceMotion=reduced, animationSamples=[motion_before, motion_after])
            elif mode in ('reject', 'offline'):
                reveal_card(control, first['pid'])
                if mode == 'offline':
                    server.shutdown()
                    server.server_close()
                native_click(control, first['pid'], 'update-primary')
                until('update rejection', lambda: (view(control)['sidebar'].get('update') or {}).get('failed'), timeout=60)
                after = hello(control)
                installed = plistlib.loads((source / 'Contents/Info.plist').read_bytes())
                if after['pid'] != first['pid'] or installed['CFBundleVersion'] != '42':
                    raise RuntimeError('An unauthenticated update replaced or restarted the application')
                screenshot(control, output / 'rejected.png')
                result = dict(mode=mode, passed=True, sourcePID=first['pid'], build=installed['CFBundleVersion'])
                result['signatureRejected' if mode == 'reject' else 'offlineRejected'] = True
            else:
                reveal_card(control, first['pid'])
                native_click(control, first['pid'], 'update-notes')
                verify_notes(control)
                reveal_card(control, first['pid'])
                native_click(control, first['pid'], 'update-primary')
                after = until('updated application relaunch', lambda: (h if (h := hello(control))['pid'] != first['pid'] else None), timeout=90)
                screenshot(control, output / 'updated-animation-start.png')
                time.sleep(0.35)
                screenshot(control, output / 'updated-animation-end.png')
                installed = plistlib.loads((source / 'Contents/Info.plist').read_bytes())
                if installed['CFBundleVersion'] != '44' or installed['CFBundleShortVersionString'] != '0.0.1':
                    raise RuntimeError(f'Wrong installed version: {installed["CFBundleShortVersionString"]} ({installed["CFBundleVersion"]})')
                restored = view(control)
                if restored['space']['id'] != space or restored['space']['title'] != 'Update preserved this space':
                    raise RuntimeError('Browser state did not survive replacement and relaunch')
                if Path(after['dataDirectory']).resolve() != data.resolve():
                    raise RuntimeError('Updated app did not keep the isolated data directory')
                screenshot(control, output / 'updated.png')
                until('post-update summary', lambda: (view(control)['sidebar'].get('update') or {}).get('updated'))
                reveal_card(control, after['pid'])
                screenshot(control, output / 'updated-summary.png')
                native_click(control, after['pid'], 'update-primary')
                verify_notes(control, bundled=True)
                until('summary acknowledged', lambda: view(control)['sidebar'].get('update') is None)
                stop_fixture(control, folder)
                process = subprocess.Popen([str(executable)], env={**os.environ, **environment}, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
                until('restart after reading notes', lambda: hello(control), timeout=40)
                if view(control)['sidebar'].get('update') is not None:
                    raise RuntimeError('An acknowledged summary reappeared on the next launch')
                result = dict(mode=mode, passed=True, sourcePID=first['pid'], targetPID=after['pid'],
                              sourceVersion='0.1.0', sourceBuild=42, version='0.0.1', build=44, statePreserved=True,
                              candidateNotesRead=True, installedNotesRead=True, summaryAcknowledged=True)
            (output / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
            print(json.dumps(result), flush=True)
        finally:
            stop_fixture(control, folder)
            process.poll()
            server.shutdown()
            server.server_close()
            log.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', required=True, type=Path)
    parser.add_argument('--sign-tool', required=True, type=Path)
    parser.add_argument('--out', required=True, type=Path)
    parser.add_argument('--mode', choices=['ui', 'install', 'reject', 'offline', 'all'], default='all')
    parser.add_argument('--locked', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    args.app, args.sign_tool, args.out = args.app.resolve(), args.sign_tool.resolve(), args.out.resolve()
    if not args.locked:
        return subprocess.call([sys.executable, str(ROOT / 'scripts/with-batch-locks.py'),
                                '--lock', '/tmp/brk-core-native.lock', '--', sys.executable,
                                str(Path(__file__).resolve()), *sys.argv[1:], '--locked'])
    args.out.mkdir(parents=True, exist_ok=True)
    for mode in ['ui', 'install', 'reject', 'offline'] if args.mode == 'all' else [args.mode]:
        verify(args, mode)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
