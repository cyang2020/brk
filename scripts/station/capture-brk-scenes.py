#!/usr/bin/env python3
"""Capture the Brk side of the paired scenes from one built app, in one go.

    capture-brk-scenes.py <Brk.app> <outdir> [--scenes P01a,P02b,...] [--list] [--keep]

Launches the app with a control socket and a data directory seeded from tools/fixture-state.json (the same
sidebar the Arc references were taken with: favorites Wikipedia / MDN / GitHub / Apple, pinned Home, Docs and the
folder 资料, Today Inbox / Long title… / Secondary reference / Visual fixture), puts the window at the standard
1280×776 frame at screen point (320,70), then drives each scene and writes <outdir>/<scene>-<letter>-brk.png.
Pair those with ~/brk-arc-reference/<scene>/<scene>-<letter>-arc.png.

Needs the fixture site on 127.0.0.1:8764 (python3 -m http.server 8764 --bind 127.0.0.1 --directory
scripts/station/fixture-site). Uses real mouse and key events, so do not type while it runs. Every scene
restores the baseline afterwards; a scene that fails is reported and skipped. Scenes that need Arc-only state or
a second machine (badges, external sign-ins) are not here.

The launch also carries three test switches: BRK_TEST_TRUSTED_SPKI (the https fixture's certificate is trusted, P36-b;
the fixture is started on 8781/8782 when nobody runs it there), BRK_AI_FIXTURE_EXECUTABLE (tools/fake-ai.py answers in
place of claude / codex, P45-P50) and BRK_TEST_NO_GLOBAL_SHORTCUT (the instance leaves ⌥⌘N to the other apps).
"""
import argparse, http.server, json, os, shutil, socket, ssl, subprocess, sys, threading, time, signal, urllib.parse, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
BIN = os.path.join(HERE, 'bin')
X0, Y0, W, H = 320, 70, 1280, 776            # window frame in screen points (top-left origin)
SCREEN_H = 1080
SITE = 'http://127.0.0.1:8764/'
GITHUB_FIXTURE = None   # set by main(): a private static server answering /repos/fixture/repo/notifications (P08)
SUGGEST_FIXTURE = None  # set by main(): BRK_SUGGEST_URL, Arc's suggestions for P49's question, anything else asked of the engine
HTTPS_FIXTURE = None    # set by main(): the https fixture's base URL (P36-b), e.g. https://127.0.0.1:8781/
HTTPS_DIR = os.path.join(HERE, '..', '..', 'Tests', 'Fixtures', 'https-fixture')
FAKE_AI = os.path.join(HERE, 'fake-ai.py')
HOSTS = ((1032, 756), (1042, 756))   # the engine's untitled host windows, owned by the same Brk process
UNTITLED = ''   # browser windows, the About panel and the Boost panel carry no window title (WindowController hides it)
LITTLE = lambda title: title.startswith('Little ')   # Little Arc: "Little Brk — <page>" (LittleArcCopy.title)

def sh(*cmd, check=False, capture=True):
    r = subprocess.run(cmd, capture_output=capture, text=True)
    if check and r.returncode != 0: raise RuntimeError(f"{cmd} -> {r.stderr.strip()}")
    return r.stdout if capture else ''

def tool(name, *args): return sh(os.path.join(BIN, name), *[str(a) for a in args])
def mouse(*a): tool('mouse', *a)
def key(*a): tool('key', *a)
def osa(script): return sh('osascript', '-e', script).strip()
def sleep(s): time.sleep(s)
def away(): mouse('move', 1500, 1000); sleep(0.3)
def in_window():
    """The pointer on a blank spot of the first pane's page, inside the window: Arc's split shots P23 a and c were
    taken with the pointer in the window (b and P12 e already have it on the sidebar here) (Arc then shows the unfocused panes' ×; with it away, as in P23 f, it does not)."""
    mouse('move', X0 + 640, Y0 + 186); sleep(0.4)

def fixture_state():
    """tools/fixture-state.json with its times moved to the present. The file's tabs were last shown days ago, so a
    fresh launch auto-archived the Today tabs (twelve hours) a few minutes into a run and later scenes found Today
    empty or restored in reverse; Arc's references were taken right after the tabs were used. The newest tab is two
    minutes old and the order stays the same."""
    state = json.load(open(os.path.join(HERE, 'fixture-state.json')))
    items = state['doc']['items']
    now = int(time.time() * 1000)
    shift = now - 2 * 60000 - max(i['tab']['lastActiveAt'] for i in items.values() if i['kind'] == 'tab')
    for i in items.values():
        i['createdAt'] += shift
        if i['kind'] == 'tab': i['tab']['lastActiveAt'] += shift
    return state

class Brk:
    def __init__(self, app, workdir):
        self.exe = os.path.join(app, 'Contents', 'MacOS', 'Brk')
        self.dir = workdir; self.sock = os.path.join(workdir, 'control.sock'); self.data = os.path.join(workdir, 'data')
        self.proc = None; self.pid = None; self.n = 0; self.main = None; self.main_cg = None
    def launch(self, state=None):
        """Starts Brk on the fixture state (tools/fixture-state.json with its times moved to now), or on `state` (a
        whole state document) when given. A relaunch (Q05) gets a new browser window, so the remembered one is dropped."""
        os.makedirs(self.data, exist_ok=True)
        self.main_cg = None
        with open(os.path.join(self.data, 'state.json'), 'w') as f: json.dump(fixture_state() if state is None else state, f, ensure_ascii=False)
        env = {k: v for k, v in os.environ.items() if not k.startswith('BRK_')}
        # the test clock: real time plus an offset the warm-up moves forward (P13 a's "44 minutes ago")
        env.update(BRK_CONTROL_SOCKET=self.sock, BRK_DATA_DIR=self.data, BRK_TEST_NO_GLOBAL_SHORTCUT='1', BRK_TEST_CLOCK='1',
                   BRK_AI_FIXTURE_EXECUTABLE=FAKE_AI, BRK_AI_FIXTURE_LOG=os.path.join(self.dir, 'ai-calls.jsonl'))
        if GITHUB_FIXTURE: env['BRK_GITHUB_FIXTURE_BASE'] = GITHUB_FIXTURE
        if SUGGEST_FIXTURE: env['BRK_SUGGEST_URL'] = SUGGEST_FIXTURE
        spki = os.path.join(HTTPS_DIR, 'trusted.spki')
        if os.path.exists(spki): env['BRK_TEST_TRUSTED_SPKI'] = open(spki).read().strip()
        log = open(os.path.join(self.dir, 'app.log'), 'w')
        self.proc = subprocess.Popen([self.exe], env=env, stdout=log, stderr=subprocess.STDOUT)
        self.pid = self.proc.pid
        deadline = time.time() + 30
        while time.time() < deadline:
            try:
                k, v = self.send({'hello': {}}); self.main = v['_0']['windows'][0]; break
            except Exception: sleep(0.4)
        else: raise RuntimeError('no control socket within 30 s')
        sleep(2.5)
        self.send({'setWindowFrame': {'window': self.main, 'frame': [[X0, SCREEN_H - Y0 - H], [W, H]]}})
        self.settle(8)
    def report_shortcut(self):
        """After the scenes, so the launch takes no longer than it did before: off when the instance took no
        system-wide shortcut (BRK_TEST_NO_GLOBAL_SHORTCUT)."""
        try:
            k, v = self.send({'settings': {}}); print(f"[scenes] system-wide Little Arc shortcut: {json.dumps(v['_0'].get('littleArcShortcut'))}", flush=True)
        except Exception as e: print(f'[scenes] system-wide Little Arc shortcut: not read ({e})', flush=True)
    def quit(self):
        try: self.send({'quit': {}}, timeout=5)
        except Exception: pass
        if self.proc:
            try: self.proc.wait(12)
            except Exception: self.proc.kill()
    def send(self, op, timeout=60):
        self.n += 1
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.settimeout(timeout); s.connect(self.sock)
        s.sendall((json.dumps({'id': self.n, 'op': op}) + '\n').encode())
        buf = b''
        while not buf.endswith(b'\n'):
            c = s.recv(1 << 16)
            if not c: break
            buf += c
        s.close()
        r = json.loads(buf)['result']; k = next(iter(r)); v = r[k]
        if k == 'failed': raise RuntimeError(f"{json.dumps(op)[:120]} -> {v}")
        return k, v
    def dispatch(self, command, window=None):
        op = {'dispatch': {'command': command}}
        if window: op['dispatch']['window'] = window
        return self.send(op)
    def view(self, window=None):
        k, v = self.send({'view': {'window': window or self.main}}); return v['_0']
    def settle(self, t=6):
        try: self.send({'settle': {'timeout': t}}, timeout=t + 10)
        except Exception: pass
    def press(self, chord): self.send({'press': {'chord': chord}})
    def type(self, text): self.send({'type': {'text': text}})
    def windows(self):
        k, v = self.send({'hello': {}}); return v['_0']['windows']
    # ---- sidebar helpers
    def rows(self, section):
        out = []
        def walk(rs, depth):
            for r in rs:
                kind = next(iter(r)); d = r[kind]['_0'] if '_0' in r[kind] else r[kind]
                out.append((kind, d.get('title'), d.get('id'), d))
                for kk in ('children', 'rows'):
                    if isinstance(d.get(kk), list): walk(d[kk], depth + 1)
        walk(self.view()['space'][section]['rows'], 0); return out
    def find(self, title, section=None):
        for sec in ([section] if section else ['today', 'pinned']):
            for kind, t, i, d in self.rows(sec):
                if t == title: return i
        raise KeyError(title)
    def focus(self, title): self.dispatch({'tab': {'_0': {'focus': {'_0': self.find(title)}}}}); self.settle(3)
    def space_id(self, title):
        return next(d['id'] for d in self.view()['dock'] if d['title'] == title)
    # ---- window helpers
    def front(self):
        for _ in range(4):
            osa(f'tell application "System Events" to set frontmost of (first process whose unix id is {self.pid}) to true')
            sleep(0.4)
            if osa('tell application "System Events" to get unix id of first application process whose frontmost is true') == str(self.pid): return True
        return False
    def win_list(self):
        rows = []
        for line in tool('wins', 'Brk').splitlines():
            parts = line.split('|')
            if len(parts) >= 6 and parts[5] == f'pid {self.pid}': rows.append(parts)
        return rows
    def win_ids(self):
        """The ids of this Brk's windows on screen now: what a scene notes before the action that opens a window (a
        window AppKit hides and shows again keeps its id, so only the on-screen ones count as already there)."""
        return {p[0] for p in self.win_list() if p[4] == 'onscreen 1'}
    def find_window(self, seen, title=None, size=None, minimum=None, maximum=None, layers=('layer 0',), timeout=3.0):
        """The one window rule of every scene: a window of this run's Brk (its pid), on screen, not in `seen` (the ids
        `win_ids()` gave before the action that opened it), titled `title` (case-insensitive; a tuple of titles; a test
        on the title; None takes any title), never one of the engine's untitled 1032x756 / 1042x756 host windows, on one of `layers`,
        exactly `size` (w, h) or within `minimum` / `maximum`. Polls up to `timeout` s; the row of `win_list()` or None."""
        if title is None or callable(title): match = title or (lambda t: True)
        else:
            titles = {t.lower() for t in ((title,) if isinstance(title, str) else title)}; match = lambda t: t.lower() in titles
        deadline = time.time() + timeout
        while True:
            for p in self.win_list():
                if p[0] in seen or p[4] != 'onscreen 1' or p[3] not in layers: continue
                if not match(p[1] or ''): continue
                x, y, w, h = geometry(p)
                if (w, h) in HOSTS: continue
                if size and (w, h) != tuple(size): continue
                if minimum and (w < minimum[0] or h < minimum[1]): continue
                if maximum and (w > maximum[0] or h > maximum[1]): continue
                return p
            if time.time() >= deadline: return None
            sleep(0.3)
    def main_wid(self):
        """The browser window this launch opened: the first 1280x776 window of the process on screen when a scene
        first asks (the frame is set at launch, before any scene opens another window), then that same window while
        it is on screen (a window keeps its id for its lifetime)."""
        rows = self.win_list()
        if self.main_cg: return self.main_cg if any(p[0] == self.main_cg and p[4] == 'onscreen 1' for p in rows) else None
        for p in rows:
            if p[4] == 'onscreen 1' and p[3] == 'layer 0' and (p[1] or '') == UNTITLED and geometry(p)[2:] == (W, H):
                self.main_cg = p[0]; return p[0]
        return None
    def menus(self):
        return [p for p in self.win_list() if p[3] == 'layer 101' and p[4] == 'onscreen 1']
    def popovers(self):
        """The process's other on-screen windows smaller than the browser window: a popover is its own window, whatever
        layer it sits on. The engine's untitled host windows are not popovers."""
        main = self.main_wid()
        return [p for p in self.win_list() if p[0] != main and p[4] == 'onscreen 1' and geometry(p)[2:] not in HOSTS
                and geometry(p)[2] < W and geometry(p)[3] < H]

def geometry(p):
    """x, y, w, h (screen points) of a `win_list()` row."""
    xy, wh = p[2].split(' '); x, y = map(int, xy.split(',')); w, h = map(int, wh.split('x')); return x, y, w, h

# ---- capture kinds
def cap_window(b, path, wid=None):
    wid = wid or b.main_wid()
    if not wid: raise RuntimeError('main window not on screen')
    sh('screencapture', '-x', '-o', '-l', wid, path)
BANNERS = os.path.join(HERE, 'close-banners.sh')
def no_banners():
    """Notification Center's banners and permission alerts stay on a full-screen window above everything until someone
    answers them, and test instances keep adding more (P26, P32, P37, Q05 had them over the window's right edge). Closes
    them (Close only: no permission is decided, no setting changes). The sshd alert on layer 8 is not one of them."""
    if any('layer 21' in row and 'onscreen 1' in row for row in tool('wins', 'Notification Center').splitlines()):
        sh(BANNERS); sleep(0.5)
def cap_region(path, x=X0, y=Y0, w=W, h=H):
    no_banners(); sh('screencapture', '-x', f'-R{x},{y},{w},{h}', path)
def cap_stack(b, path, x=X0, y=Y0, w=W, h=H):
    """A region shot in which this Brk's main window is taken again by window id and pasted over it: a banner that comes
    up during the shot and another agent's window can only spoil the margin outside it. Popovers and panels keep their
    region (a popover shot by id has nothing behind it to blur and comes out pale, and Arc's references show the system
    alert over the Boost panel's corner)."""
    base = path + '.base.png'; cap_region(base, x, y, w, h)
    main = b.main_wid()
    if not main:
        os.replace(base, path); return
    shown = [p for p in b.popovers() if p[3] != 'layer 101']
    window = path + '.window.png'; cap_window(b, window)
    # `screencapture -l` starts at the top-left of the window and its child windows together
    args = [window, min([X0] + [geometry(p)[0] for p in shown]) - x, min([Y0] + [geometry(p)[1] for p in shown]) - y]
    for n, p in enumerate(shown):
        px, py, pw, ph = geometry(p); m = f'{path}.p{n}.png'
        cap_region(m, px, py, pw, ph)
        args += [m, px - x, py - y]
    tool('compose', base, path, *args)
    for f in [base, window] + [a for a in args if isinstance(a, str) and a.endswith('.png')]:
        if os.path.exists(f) and f != path: os.remove(f)
def cap_popover(b, path, x, y, w, h):
    """Like `cap_menu` for a popover, in the frame of its Arc reference (x, y, w, h in screen points): the popover hangs
    past the window's left edge and the reference shows the desktop around the window, so the canvas is that frame,
    not the window. The window's own capture and the popover's screen region go on a capture of the frame; another
    agent's window can only spoil the margin. A scene with no popover open fails here instead of saving a bare window.
    `screencapture -l` also draws the window's child windows, so its image starts at the top-left of the window and the
    popover together; the popover comes out pale there (nothing behind it to blur), hence its own region on top."""
    shown = b.popovers()
    if not shown: raise RuntimeError('no popover window on screen')
    base, window = path + '.base.png', path + '.window.png'; cap_region(base, x, y, w, h); cap_window(b, window)
    args = [window, min([X0] + [geometry(p)[0] for p in shown]) - x, min([Y0] + [geometry(p)[1] for p in shown]) - y]
    for n, p in enumerate(shown):
        px, py, pw, ph = geometry(p); m = f'{path}.p{n}.png'; cap_region(m, px, py, pw, ph); args += [m, px - x, py - y]
    tool('compose', base, path, *args)
    for f in [base, window] + [a for a in args if isinstance(a, str) and a.endswith('.png')]:
        if os.path.exists(f) and f != path: os.remove(f)
def cap_menu(b, path):
    base = path + '.base.png'; cap_window(b, base); args = []
    for n, p in enumerate(b.menus()):
        geo = p[2]; xy, wh = geo.split(' '); x, y = xy.split(','); w, h = wh.split('x')
        m = f'{path}.m{n}.png'; cap_region(m, x, y, w, h); args += [m, str(int(x) - X0), str(int(y) - Y0)]
    if args: tool('compose', base, path, *args)
    else: shutil.copy(base, path)
    for f in [base] + [a for a in args if a.endswith('.png')]:
        try: os.remove(f)
        except OSError: pass

def held_drag(b, start, end, shoot, hold=30.0, shown=None):
    """Press at `start`, drag to `end` (window points) and hold there while `shoot()` captures, then drag back to
    `start` and release, so nothing is dropped (tools/dragback.swift). The hold lasts until the shot is done, `hold`
    being only a ceiling: with a fixed hold a busy machine could answer the check or take the shot after the drag had
    gone back (P23 d at 8%: the row hovered and nothing else, the state after the release). `shown`: a view identifier
    the held drag must show; the drag is tried again once when it does not (a press that never became a drag)."""
    for attempt in (1, 2):
        require_front(b, start)
        sig = os.path.join(b.dir, 'drag.signal'); release = sig + '.release'
        for f in (sig, release):
            if os.path.exists(f): os.remove(f)
        p = subprocess.Popen([os.path.join(BIN, 'dragback'), str(X0 + start[0]), str(Y0 + start[1]), str(X0 + end[0]), str(Y0 + end[1]), str(hold), sig, release])
        ok = True
        try:
            deadline = time.time() + 15
            while not os.path.exists(sig) and time.time() < deadline: sleep(0.05)
            sleep(0.8)
            if shown:
                try:
                    k, v = b.send({'native': {'window': b.main}})
                    n = v.get('_0', v); view = n.get('actual', {}).get(shown)
                    ok = bool(view) and not view.get('hidden')
                    if not ok:
                        front = osa('tell application "System Events" to get name of first application process whose frontmost is true')
                        print(f'[scenes] held drag attempt {attempt}: no {shown}; frontmost {front!r}, key {n.get("isKey")}, first responder {n.get("firstResponder")}', flush=True)
                except Exception: ok = True
            if ok or attempt == 2: shoot()
        finally:
            open(release, 'w').close()
            p.wait(); sleep(0.5)
        if ok: return
        print(f'[scenes] held drag did not show {shown}, trying again', flush=True)
        b.front(); away()

# ---- the space theme. The fixture's is Arc's first Brand swatch (#F2EAE4). Arc's P28, P36 and P37 references were
# taken after its theme had been set to the Greyscale page's white with the wave slider near 0.8 (P28-a shows that
# swatch selected and the handle at 191.5 pt of the panel), so those scenes switch to it and back.
FIXTURE_THEME = {'appearance': 'auto', 'colors': [{'red': 0xF2 / 255, 'green': 0xEA / 255, 'blue': 0xE4 / 255, 'alpha': 1}],
                 'intensity': 0.25, 'noise': 0.5, 'texture': 'grain', 'wheel': 'analogous'}
# Brk's intensity runs opposite to Arc's slider (SpaceTheme.intensity): Arc's 0.8 is 0.2 here. Since the window shows
# the system material through the theme (docs/checks/2026-11-13-window-translucency.md) the slider matters for white too.
WHITE_THEME = dict(FIXTURE_THEME, colors=[{'red': 1, 'green': 1, 'blue': 1, 'alpha': 1}], intensity=0.2)
def set_theme_doc(b, theme):
    b.dispatch({'space': {'_0': {'update': {'_0': b.space_id('对照'), 'theme': theme}}}}); sleep(0.8)
def load_pinned(b):
    # Arc's P28, P36 and P37 references draw the pinned rows as loaded tabs (black titles): its session had opened
    # them. Brk restores them unloaded (dimmed), so these scenes open each once and go back to Visual fixture.
    for title in ('Home', 'Docs', 'Design notes', 'Interface comparison'):
        try: b.focus(title)
        except Exception: pass
    b.focus('Visual fixture'); sleep(0.5)

# ---- baseline
TODAY = ['Inbox', 'Long title for truncation and readable sidebar ellipsis', 'Secondary reference', 'Visual fixture']
TODAY_PAGES = dict(zip(TODAY, ('inbox.html', 'long.html', 'secondary.html', 'visual.html')))

def warm(b):
    """Arc's references show every Pinned tab and Favorite loaded (full-strength icons and black titles, a pinned
    row's × on hover, Wikipedia and GitHub among the switcher's recent pages); the fixture starts them unloaded. Each
    is shown once, then the Today tabs in order, so Visual fixture is current. A tab's time is when it last left the
    screen, so the test clock moves on between the folder's two pages and after them: Arc's folder card (P13 a) reads
    Interface comparison 44 minutes ago and Design notes 1 hour ago."""
    tiles = [t['id'] for t in b.view()['favorites']['tiles']]
    pinned = {t: i for kind, t, i, d in b.rows('pinned') if kind == 'tab'}
    first = [pinned.pop('Design notes')] if 'Design notes' in pinned else []
    last = [pinned.pop('Interface comparison')] if 'Interface comparison' in pinned else []
    for i in first + list(pinned.values()) + tiles:
        b.dispatch({'tab': {'_0': {'focus': {'_0': i}}}}); sleep(1.2)
    b.settle(10)
    b.send({'advanceClock': {'seconds': 17 * 60}})
    for i in last: b.dispatch({'tab': {'_0': {'focus': {'_0': i}}}}); sleep(1.2)
    for t in TODAY: b.focus(t)
    b.send({'advanceClock': {'seconds': 44 * 60}})

def app_now(b):
    """The app's clock in seconds (the test clock runs ahead of real time after the warm-up)."""
    try: k, v = b.send({'advanceClock': {'seconds': 0}}); return v['now'] / 1000
    except Exception: return time.time()

# Arc's references from 14:06 to 18:15 on 2026-11-03 (P13 a/b, P15 a, P43 a, Q01 a/b and others) were taken while
# 对照 had a white theme, not the fixture's #F2EAE4: the sidebar reads #FDFCFB, the tiles #F1F0EF and the titles a
# neutral #1A1A1A. Those scenes switch 对照 to white while they shoot and put the fixture's theme back afterwards.
WHITE = [1.0, 1.0, 1.0]
# The 20:31 ones (P23 c/d/splitmenu, P27 b, Q02 b) and the parent's later P23 c and vsplitmenu had a pale teal: a
# near-neutral sidebar (#F8F8F8 to #FDFCFB) with #001E1D titles, teal-grey placeholder icons and a #006362 focus ring.
# Two near-white companions keep the gradient from turning teal.
TEAL = [0.96, 1.0, 1.0]
TEAL_COMPANIONS = [[0.97, 0.97, 0.97], [0.97, 0.97, 0.97]]
# The 2026-11-04 ones (Q11, P50) have a pale blue: #E8F3FD at the top of the sidebar, #F2F8FC lower down.
SKY = [0.90, 0.95, 0.99]
SKY_COMPANIONS = [[0.95, 0.975, 0.99]]

class theme:
    def __init__(self, b, rgb): self.b, self.rgb = b, rgb
    def _set(self, t):
        sid = self.b.space_id('对照')
        self.b.dispatch({'space': {'_0': {'update': {'_0': sid, 'theme': t}}}}); sleep(0.8)
    def __enter__(self):
        state = json.load(open(os.path.join(HERE, 'fixture-state.json')))
        self.saved = next(s['theme'] for s in state['doc']['spaces'].values() if s['title'] == '对照')
        rgbs = [self.rgb] + (TEAL_COMPANIONS if self.rgb == TEAL else SKY_COMPANIONS if self.rgb == SKY else [])
        t = dict(self.saved); t['colors'] = [{'red': c[0], 'green': c[1], 'blue': c[2], 'alpha': 1} for c in rgbs]
        self._set(t)
    def __exit__(self, *exc): self._set(self.saved)

class without_today:
    """Today without `title` for a shot, the tab put back where it was afterwards (Arc's later P23 c and
    vsplitmenu were taken with Secondary reference archived)."""
    def __init__(self, b, title): self.b, self.title = b, title
    def __enter__(self):
        rows = [(t, i) for kind, t, i, d in self.b.rows('today')]
        self.index = next((n for n, (t, i) in enumerate(rows) if t == self.title), None)
        self.focused = next((p['tab'] for p in self.b.view()['content']['panes'] if p['focused']), None)
        if self.index is not None:
            self.b.dispatch({'tab': {'_0': {'archive': {'_0': {'item': {'_0': rows[self.index][1]}}}}}}); sleep(0.6)
    def __exit__(self, *exc):
        if self.index is None: return
        self.b.dispatch({'archive': {'_0': {'restoreLast': {}}}}); sleep(0.6)
        root = self.b.view()['space']['today']['root']
        item = next((i for kind, t, i, d in self.b.rows('today') if t == self.title), None)
        if item: self.b.dispatch({'item': {'_0': {'move': {'_0': item, 'to': {'into': {'parent': root, 'index': self.index}}}}}})
        # restoring shows the restored tab: the pane that was focused (in its split) comes back
        if self.focused: self.b.dispatch({'tab': {'_0': {'focus': {'_0': self.focused}}}}); sleep(0.8)

class without_favorites:
    """Favorites emptied for a shot (Arc's "Drag to add Favorites" box), the tiles moved to the end of Pinned and put
    back in their order afterwards."""
    def __init__(self, b): self.b = b
    def __enter__(self):
        v = self.b.view(); self.root = v['favorites']['root']; self.tiles = [t['id'] for t in v['favorites']['tiles']]
        pinned = v['space']['pinned']['root']
        for i in self.tiles: self.b.dispatch({'item': {'_0': {'move': {'_0': i, 'to': {'into': {'parent': pinned, 'index': 99}}}}}})
        sleep(0.8)
    def __exit__(self, *exc):
        for n, i in enumerate(self.tiles): self.b.dispatch({'item': {'_0': {'move': {'_0': i, 'to': {'into': {'parent': self.root, 'index': n}}}}}})
        sleep(0.8)

def row_center(b, title):
    """The centre of a sidebar row, in window points."""
    k, v = b.send({'native': {'window': b.main}})
    (x, y), (w, h) = (v.get('_0', v))['actual']['row-' + b.find(title)]['frame']
    return (round(x + w / 2), round(y + h / 2))

def favorite(b, host):
    return next(t['id'] for t in b.view()['favorites']['tiles'] if host in (t.get('url') or ''))

def recent(b, *items):
    """Shows `items` (ids, or Today titles) oldest first and ends on Visual fixture: what the command bar's and the
    switcher's recent pages list after the current tab. The window is brought forward first: the switcher keeps a
    page's look only while the window is not covered (Arc's own window sits at the same frame)."""
    b.front()
    for i in items + ('Visual fixture',):
        if i in TODAY: b.focus(i)
        else: b.dispatch({'tab': {'_0': {'focus': {'_0': i}}}}); b.settle(3)
        sleep(1.0)

def today_in_order(b):
    """Today back to the fixture's four tabs in the fixture's order: a scene that archives or closes one leaves it
    missing, and restoring from the archive brings tabs back in reverse."""
    have = {t: i for kind, t, i, d in b.rows('today') if kind == 'tab' and t in TODAY}
    for t in TODAY:
        if t not in have:
            k, v = b.send({'load': {'window': b.main, 'url': SITE + TODAY_PAGES[t]}}); have[t] = v['tab']
    b.settle(4)
    if [t for kind, t, i, d in b.rows('today') if kind == 'tab'] != TODAY:
        root = b.view()['space']['today']['root']
        for n, t in enumerate(TODAY):
            b.dispatch({'item': {'_0': {'move': {'_0': have[t], 'to': {'into': {'parent': root, 'index': n}}}}}})

def page_id(b, index=None):
    """The focused pane's page, or pane `index`'s."""
    panes = b.view()['content']['panes']
    pane = panes[index] if index is not None else next(p for p in panes if p['focused'])
    return pane['content']['page']['_0']

def select_text(b, start, end_selector=None):
    """Arc's references keep a highlight on Visual fixture: from `start` in the first paragraph to the end of that
    paragraph, or of the element `end_selector` names (the URL pill then reads Share Quote)."""
    js = ("var p=document.querySelector('p').firstChild,r=document.createRange();r.setStart(p,p.data.indexOf(%s));"
          "var e=%s;r.setEnd(e,e.length);getSelection().removeAllRanges();getSelection().addRange(r);"
          % (json.dumps(start), "document.querySelector(%s).firstChild" % json.dumps(end_selector) if end_selector else 'p'))
    b.send({'evaluate': {'page': page_id(b), 'script': js}})

def select_draft(b, index=0):
    """Arc's split references (P23 a and b, P12 e) keep the word Draft highlighted in the Visual fixture pane."""
    js = "var t=document.querySelector('label').firstChild,r=document.createRange();r.setStart(t,0);r.setEnd(t,5);getSelection().removeAllRanges();getSelection().addRange(r);"
    b.send({'evaluate': {'page': page_id(b, index), 'script': js}})

def clear_selection(b):
    try: b.send({'evaluate': {'page': page_id(b), 'script': 'getSelection().removeAllRanges()'}})
    except Exception: pass
def baseline(b):
    # A Command chord from whoever ran before can leave the flag set system-wide; every mouse press would then read as
    # a Command-click (P23 d at 8.45%: the drag never started, a hovered row).
    key('clear')
    try: b.dispatch({'commandBar': {'_0': {'dismiss': {}}}})
    except Exception: pass
    for w in b.windows():
        if w != b.main:
            try: b.send({'activate': {'window': w}}); sleep(0.3); key('tap', 'w', 'command'); sleep(0.8)
            except Exception: pass
    for cmd in ({'library': {'_0': {'close': {}}}}, {'sidebar': {'_0': {'openDialog': {}}}}, {'capture': {'_0': {'cancel': {}}}}, {'settings': {'_0': {'closeWindow': {}}}}):
        try: b.dispatch(cmd)
        except Exception: pass
    v = b.view()
    if not v['sidebar']['visible']: b.dispatch({'sidebar': {'_0': {'toggle': {}}}})
    if v['sidebar']['toolbarVisible']: b.dispatch({'sidebar': {'_0': {'toggleToolbar': {}}}})
    if v['sidebar']['width'] != 228: b.dispatch({'sidebar': {'_0': {'resize': {'width': 228}}}})
    if v['space']['pinned'].get('collapsed'): b.dispatch({'space': {'_0': {'togglePinnedSection': {'_0': {'current': {}}}}}})
    try:
        active = next(d['title'] for d in v['dock'] if d['active'])
        if active != '对照': b.dispatch({'space': {'_0': {'focus': {'_0': b.space_id('对照')}}}})
    except Exception: pass
    # today list back to the fixture
    seen = set()
    for kind, t, i, d in b.rows('today'):
        if kind == 'tab' and (t not in TODAY or t in seen):
            try: b.dispatch({'tab': {'_0': {'close': {'_0': {'item': {'_0': i}}}}}})
            except Exception: pass
        else: seen.add(t)
    try: today_in_order(b)
    except Exception as e: print(f'[scenes] Today not restored: {e}', flush=True)
    try: b.focus('Visual fixture')
    except Exception: pass
    clear_selection(b)
    b.send({'setWindowFrame': {'window': b.main, 'frame': [[X0, SCREEN_H - Y0 - H], [W, H]]}})
    away()

# ---- test data the later Arc references were taken with
# From P28 on, Arc's 对照 space had a near-white theme (sidebar #FDFCFC, P32/P33/Q05), not the fixture's beige. The
# scenes whose references show it (Q05, P33) switch 对照 to white while they capture and back afterwards.
def fixture_doc():
    with open(os.path.join(HERE, 'fixture-state.json')) as f: return json.load(f)
def set_theme(b, space_title, colors):
    sid = b.space_id(space_title)
    theme = dict(fixture_doc()['doc']['spaces'][sid]['theme']); theme['colors'] = colors
    b.dispatch({'space': {'_0': {'update': {'_0': sid, 'theme': theme}}}}); sleep(0.8)
WHITE_COLORS = [{'red': 1, 'green': 1, 'blue': 1, 'alpha': 1}]   # for set_theme(b, space_title, colors)
def reset_theme(b, space_title):
    sid = b.space_id(space_title)
    b.dispatch({'space': {'_0': {'update': {'_0': sid, 'theme': fixture_doc()['doc']['spaces'][sid]['theme']}}}}); sleep(0.5)

# Arc's history list in Q05-a, newest first: minutes before the newest visit, title, address. Breaks fall where Arc
# draws them (more than 15 minutes apart). The visible rows end with the Google ones.
ARC_HISTORY = [
    (0, 'Visual fixture', SITE + 'visual.html'), (0, 'Docs', SITE + 'docs.html'), (0, 'Interface comparison', SITE + 'interface.html'),
    (0, 'Secondary reference', SITE + 'secondary.html'), (13, 'Home', SITE + 'home.html'),
    (48, 'Apple', 'https://apple.com/'), (48, 'GitHub · Change is constant. GitHub keeps you ahead. · GitHub · GitHub', 'https://github.com/'),
    (48, 'MDN Web Docs', 'https://developer.mozilla.org/'), (49, 'Wikipedia', 'https://wikipedia.org/'),
    (49, 'Inbox', SITE + 'inbox.html'), (49, 'Long title for truncation and readable sidebar ellipsis', SITE + 'long.html'),
    (51, 'Design notes', SITE + 'design.html'),
    (69, 'Google Calendar - Week of November 1, 2026', 'https://calendar.google.com/calendar/u/0/r'), (69, 'Google Account', 'https://myaccount.google.com/'),
    (69, 'Add a profile picture', 'https://gds.google.com/web/chip'), (69, 'Google Account', 'https://gds.google.com/'),
]
def relaunch_with_arc_history(b):
    """Restarts Brk on the fixture plus Arc's Q05-a visits. The newest is today at 1:06 PM (Arc's times) while that is
    still ahead, else a few minutes from now with Arc's spacing; either way it is newer than any visit the run makes,
    so the History page folds those into Arc's rows."""
    import datetime, uuid
    now = datetime.datetime.now()
    newest = now.replace(hour=13, minute=6, second=30, microsecond=0)
    if newest < now + datetime.timedelta(minutes=5): newest = (now + datetime.timedelta(minutes=5)).replace(second=30, microsecond=0)
    visits = [{'url': url, 'title': title, 'profile': 'default', 'id': str(uuid.uuid4()).upper(),
               'visitedAt': int((newest - datetime.timedelta(minutes=minutes, seconds=i)).timestamp() * 1000)}
              for i, (minutes, title, url) in enumerate(ARC_HISTORY)]
    # The fixture's times moved to now, as at the first launch: with its old times the 60 s archive sweep empties Today
    # before the next scenes (P33 at +0.25 points once the capture took a little longer).
    state = fixture_state(); state['doc']['historyVisits'] = visits; state['doc']['history'] = visits
    b.quit(); sleep(1); b.launch(state); baseline(b)

# ---- scenes: name -> function(b, out) ; out(letter, kind) captures
def scene(name):
    def deco(f): SCENES[name] = f; return f
    return deco
SCENES = {}

@scene('P01')
def _(b, out):
    out('a', 'window')
    b.dispatch({'sidebar': {'_0': {'toggleToolbar': {}}}}); sleep(1); out('b', 'window'); b.dispatch({'sidebar': {'_0': {'toggleToolbar': {}}}}); sleep(0.5)
    b.front(); mouse('move', 352, 90); sleep(1.2); out('c', 'window'); away()
    osa('tell application "Finder" to activate'); sleep(1.2); out('d', 'window')

@scene('P02')
def _(b, out):
    out('a', 'window')
    b.front(); b.dispatch({'commandBar': {'_0': {'open': {'_0': 'editCurrent'}}}}); sleep(1.2); away(); out('b', 'window')
    b.type('doc'); sleep(1.5); out('c', 'window'); b.dispatch({'commandBar': {'_0': {'dismiss': {}}}}); sleep(0.4)
    b.focus(TODAY[1]); sleep(0.8); out('d', 'window')

@scene('P03')
def _(b, out):
    for letter, w in (('b', 164), ('c', 500)):
        b.dispatch({'sidebar': {'_0': {'resize': {'width': w}}}}); sleep(0.8); out(letter, 'window')
    b.dispatch({'sidebar': {'_0': {'resize': {'width': 228}}}})

@scene('P04')
def _(b, out):
    b.dispatch({'sidebar': {'_0': {'toggle': {}}}}); sleep(1); out('a', 'window')
    b.front(); mouse('move', 322, 450); sleep(0.3); mouse('move', 324, 452); sleep(1.5); out('b', 'window'); away(); sleep(0.6)
    b.dispatch({'sidebar': {'_0': {'toggle': {}}}})

@scene('P05')
def _(b, out):
    b.front(); mouse('move', 420, 233); sleep(1.2); out('c', 'window')
    mouse('click', 348, 233); sleep(1.2); out('d', 'window'); mouse('click', 348, 233); sleep(0.6); away()
    # f: the narrowest sidebar (164, Arc's minimum; Arc's P05-f has the pale teal theme). The 16 pt steps from 228 down
    # to it, with Favorites and with them emptied (the "Drag to add Favorites" box), go beside it as f-w<width> and
    # f-w<width>-empty (no Arc partner: they are for checking that no text leaves its box).
    def width(w): b.dispatch({'sidebar': {'_0': {'resize': {'width': w}}}}); sleep(0.8)
    with theme(b, TEAL):
        for w in (212, 196, 180): width(w); out(f'f-w{w}', 'window')
        width(164); out('f', 'window')
        with without_favorites(b):
            for w in (228, 212, 196, 180, 164): width(w); out(f'f-w{w}-empty', 'window')
    width(228)

@scene('P06')
def _(b, out):
    b.dispatch({'commandBar': {'_0': {'open': {'_0': 'newTab'}}}}); b.dispatch({'commandBar': {'_0': {'submit': {'_0': 'http://10.255.255.1/'}}}})
    sleep(1.5); out('a', 'window')
    for kind, t, i, d in b.rows('today'):
        if d.get('url', '').startswith('http://10.255.255.1'): b.dispatch({'tab': {'_0': {'close': {'_0': {'item': {'_0': i}}}}}})

@scene('P07')
def _(b, out):
    out('a', 'window')
    b.dispatch({'space': {'_0': {'focus': {'_0': b.space_id('Space 1')}}}}); sleep(1.2); out('b', 'window')
    b.dispatch({'space': {'_0': {'focus': {'_0': b.space_id('对照')}}}}); sleep(1)
    b.front(); mouse('click', 351, 184); sleep(2.5); away(); out('c', 'window')
    b.front(); mouse('move', 405, 184); sleep(1.3); out('d', 'window'); away()

@scene('P09')
def _(b, out):
    # Arc's strip: Visual fixture, Long title…, Inbox, Wikipedia, GitHub (the two Favorites shown before the clicks)
    recent(b, favorite(b, 'github.com'), favorite(b, 'wikipedia.org'))
    b.front()
    for y in (537, 578, 660): mouse('click', 433, y); sleep(0.7)
    # `press`, not `tap`: a tap ends by releasing its modifiers (R4-12b), which would close the switcher before the shot.
    away(); key('down', 'control'); key('press', 'tab', 'control'); sleep(1); out('a', 'window')
    key('press', 'tab', 'control'); sleep(1); out('b', 'window'); key('up', 'control'); sleep(0.8)

@scene('P11')
def _(b, out):
    b.front(); mouse('click', 433, 537); sleep(0.6); key('down', 'shift'); mouse('click', 433, 578); key('up', 'shift'); sleep(0.8); away(); out('a', 'window')
    b.front(); mouse('rightclick', 433, 578); sleep(1.2); out('b', 'menu'); key('tap', 'escape'); sleep(0.5)

@scene('P12')
def _(b, out):
    for letter, (x, y) in {'a': (433, 537), 'b': (433, 274), 'c': (351, 184), 'd': (378, 356), 'g': (433, 740)}.items():
        b.front(); mouse('rightclick', x, y); sleep(1.2); out(letter, 'menu'); key('tap', 'escape'); sleep(0.5)
    # f (17:06) was taken under the white theme with P15 a's highlight on the page
    select_text(b, 'comparing', 'aside')
    with theme(b, WHITE):
        b.front(); mouse('rightclick', 343, 233); sleep(1.2); out('f', 'menu'); key('tap', 'escape'); sleep(0.5)
    away()

@scene('P13')
def _(b, out):
    b.dispatch({'tabTools': {'_0': {'preferences': {'includeFavorites': True, 'previews': True}}}})
    # the folder is closed and opened by command: a click right after bringing the window forward can be taken as
    # the activating click and dropped (the station's P13 a once showed the folder still open and no card)
    folder = b.find('资料', 'pinned')
    with theme(b, WHITE):
        b.dispatch({'item': {'_0': {'toggleFolder': {'_0': folder}}}}); sleep(0.6)
        b.front(); mouse('move', 1100, 700); sleep(0.3); mouse('move', 376, 354); sleep(0.2); mouse('move', 378, 356); sleep(2.5); out('a', 'window'); mouse('move', 1100, 700); sleep(0.5)
        b.dispatch({'item': {'_0': {'toggleFolder': {'_0': folder}}}}); sleep(0.6)
        b.front(); mouse('move', 431, 272); sleep(0.2); mouse('move', 433, 274); sleep(3); out('b', 'window'); away()
    # c: the Previews Settings sheet on the General pane
    try:
        seen = b.win_ids(); b.send({'openSettings': {'pane': 'general'}}); sleep(1.2); b.front()
        b.send({'click': {'view': {'settingsField': {'_0': 'previewsSettings'}}, 'count': 1}}); sleep(1.3); away()
        p = b.find_window(seen, title='General', minimum=(501, 301))
        if p: x, y, ww, hh = geometry(p); cap_region(out.path('c'), x, y, ww, hh); out.note('c')
        key('tap', 'escape'); sleep(0.4)
    except Exception as e: print(f'[scenes] P13 c skipped: {e}')
    b.dispatch({'settings': {'_0': {'closeWindow': {}}}})
    # d: a calendar Favorite's hover card (meetings with Join); e: a page link's preview card (Preview reference).
    try:
        b.dispatch({'tabTools': {'_0': {'preferences': {'includeFavorites': True, 'previews': True}}}})
        calendar = _stopped_favorite(b, 'https://calendar.google.com/')
        b.focus('Visual fixture')
        b.dispatch({'tabTools': {'_0': {'site': {'_0': {'selectCalendar': {'_0': _calendar_file(b), 'join': False}}}}}}); sleep(1.0)
        x, y = _screen(_native(b)['actual']['favorite-' + calendar]['frame'])
        b.front(); mouse('move', 1100, 700); sleep(0.3); mouse('move', x, y); sleep(1.5); out('d', 'region'); away()
        b.dispatch({'tab': {'_0': {'archive': {'_0': {'item': {'_0': calendar}}}}}}); sleep(0.5)
    except Exception as e: print(f'[scenes] P13 d skipped: {e}')
    try:
        b.focus('Visual fixture'); b.front(); mouse('move', 1100, 700); sleep(0.3)
        mouse('move', 760, 157); sleep(0.2); mouse('move', 764, 157); sleep(2.5); out('e', 'region'); away()
    except Exception as e: print(f'[scenes] P13 e skipped: {e}')
    b.dispatch({'tabTools': {'_0': {'preferences': {'includeFavorites': True, 'previews': False}}}})

def _native(b, window=None):
    k, v = b.send({'native': {'window': window or b.main}}); return v['_0']
def _screen(frame):
    (x, y), (w, h) = frame; return X0 + x + w / 2, Y0 + y + h / 2
def _stopped_favorite(b, address):
    """A Favorite of `address` that never loads (the capture needs its tile, not the site)."""
    k, v = b.send({'load': {'window': b.main, 'url': address}}); item = v['tab']
    b.dispatch({'page': {'_0': {'stop': {'_0': {'focused': {}}}}}})
    root = b.view()['favorites']['root']
    b.dispatch({'item': {'_0': {'move': {'_0': item, 'to': {'into': {'parent': root, 'index': 9}}}}}})
    return item
def _calendar_file(b, minutes=30):
    now = app_now(b)   # the capture app's test clock, ahead of real time after the warm-up
    fmt = lambda t: time.strftime('%Y%m%dT%H%M%SZ', time.gmtime(t))
    path = os.path.join(b.dir, 'p08-meetings.ics')
    with open(path, 'w') as f:
        f.write('BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nDTSTART:%s\r\nDTEND:%s\r\nSUMMARY:Planning\r\nURL:https://example.com/?brk=P08\r\nEND:VEVENT\r\nEND:VCALENDAR' % (fmt(now + minutes * 60), fmt(now + minutes * 60 + 1800)))
    return 'file://' + path

@scene('P08')
def _(b, out):
    """Favorites' overlays: a: GitHub's unread dot (fixture notifications); b: that tile's context menu; c: a calendar
    Favorite's time to the next meeting (one extra tile, archived afterwards)."""
    github = next(t['id'] for t in b.view()['favorites']['tiles'] if 'github.com' in (t.get('url') or ''))
    b.dispatch({'tabTools': {'_0': {'site': {'_0': {'connectGitHub': {'favorite': github}}}}}}); sleep(1.0)
    b.send({'sidebarPanel': {'window': b.main, 'action': {'focus': {'identifier': 'tab-tools-repository'}}}})
    b.type('fixture/repo'); b.send({'sidebarPanel': {'window': b.main, 'action': {'button': {'_0': 'Connect'}}}})
    deadline = time.time() + 8
    while time.time() < deadline and not any(t['id'] == github and t.get('badgeTint') for t in b.view()['favorites']['tiles']): sleep(0.3)
    away(); sleep(0.5); out('a', 'window')
    x, y = _screen(_native(b)['actual']['favorite-' + github]['frame'])
    b.front(); mouse('rightclick', x, y); sleep(1.2); out('b', 'menu'); key('tap', 'escape'); sleep(0.4)
    calendar = _stopped_favorite(b, 'https://calendar.google.com/')
    b.focus('Visual fixture')
    b.dispatch({'tabTools': {'_0': {'site': {'_0': {'selectCalendar': {'_0': _calendar_file(b), 'join': False}}}}}})
    deadline = time.time() + 6
    while time.time() < deadline and not any(t['id'] == calendar and t.get('subtitle') for t in b.view()['favorites']['tiles']): sleep(0.3)
    away(); sleep(0.5); out('c', 'window')
    b.dispatch({'tab': {'_0': {'archive': {'_0': {'item': {'_0': calendar}}}}}}); sleep(0.5)

@scene('P15')
def _(b, out):
    # Arc's page kept a highlight from the first paragraph's "comparing" to the end of the card's caption
    select_text(b, 'comparing', 'aside')
    with theme(b, WHITE): b.front(); key('tap', 'k', 'shift,command'); sleep(0.7); out('a', 'window'); sleep(3)
    for _ in range(4): b.dispatch({'archive': {'_0': {'restoreLast': {}}}})

@scene('P18')
def _(b, out):
    b.focus(TODAY[1]); b.front(); key('tap', 'f', 'command'); sleep(1); tool('mouse', 'move', 1500, 1000)
    for ch in 'the': key('tap', ch); sleep(0.08)
    sleep(1.2); out('a', 'region'); key('tap', 'a', 'command')
    for ch in 'zzzz': key('tap', ch); sleep(0.08)
    sleep(1.2); out('b', 'region'); key('tap', 'escape'); sleep(0.4)
    b.send({'setWindowFrame': {'window': b.main, 'frame': [[X0, SCREEN_H - Y0 - H], [900, H]]}}); sleep(0.6); b.front(); key('tap', 'f', 'command'); sleep(0.8)
    for ch in 'the': key('tap', ch); sleep(0.08)
    sleep(1); cap_region(out.path('d'), X0, Y0, 900, H); out.note('d'); key('tap', 'escape')
    b.send({'setWindowFrame': {'window': b.main, 'frame': [[X0, SCREEN_H - Y0 - H], [W, H]]}})

@scene('P19')
def _(b, out):
    b.focus('Home'); b.front()
    osa(f'tell application "System Events" to tell (first process whose unix id is {b.pid}) to click menu bar item "View" of menu bar 1'); sleep(0.4)
    osa(f'tell application "System Events" to tell (first process whose unix id is {b.pid}) to click menu item "Appearance" of menu 1 of menu bar item "View" of menu bar 1'); sleep(0.8)
    cap_region(out.path('a'), 0, 0, 1300, 846); out.note('a'); key('tap', 'escape'); key('tap', 'escape'); sleep(0.3)
    for letter, item in (('b', 'Dark'), ('c', 'Light'), ('z', 'Automatic')):
        b.dispatch({'site': {'_0': {'appearance': {'_0': item.lower()}}}}); sleep(1.5); away()
        if letter != 'z': out(letter, 'window')
    # R3-5: View > Developer (Arc 1.170's seven rows) and Help with Troubleshooting open; Brk-only shots (no Arc partner yet)
    b.focus('Home'); b.front()
    osa(f'tell application "System Events" to tell (first process whose unix id is {b.pid}) to click menu bar item "View" of menu bar 1'); sleep(0.4)
    osa(f'tell application "System Events" to tell (first process whose unix id is {b.pid}) to click menu item "Developer" of menu 1 of menu bar item "View" of menu bar 1'); sleep(0.8)
    cap_region(out.path('developer'), 0, 0, 1300, 846); out.note('developer'); key('tap', 'escape'); key('tap', 'escape'); sleep(0.3)
    b.front()
    osa(f'tell application "System Events" to tell (first process whose unix id is {b.pid}) to click menu bar item "Help" of menu bar 1'); sleep(0.4)
    osa(f'tell application "System Events" to tell (first process whose unix id is {b.pid}) to click menu item "Troubleshooting" of menu 1 of menu bar item "Help" of menu bar 1'); sleep(0.8)
    cap_region(out.path('help'), 0, 0, 1300, 846); out.note('help'); key('tap', 'escape'); key('tap', 'escape'); sleep(0.3)

@scene('P20')
def _(b, out):
    seen = b.win_ids()
    before = set(b.windows()); b.dispatch({'window': {'_0': {'newBlank': {}}}}); sleep(2.5)
    nw = [w for w in b.windows() if w not in before][0]
    def wid():
        p = b.find_window(seen, title=UNTITLED, size=(W, H))
        if not p: raise RuntimeError('the new window is not on screen')
        return p[0]
    b.send({'setWindowFrame': {'window': nw, 'frame': [[X0, SCREEN_H - Y0 - H], [W, H]]}}); sleep(0.5); away()
    cap_window(b, out.path('a'), wid()); out.note('a')
    b.send({'load': {'window': nw, 'url': SITE + 'home.html'}}); sleep(2.5); cap_window(b, out.path('b'), wid()); out.note('b')
    b.send({'load': {'window': nw, 'url': SITE + 'docs.html'}}); sleep(2.5); cap_window(b, out.path('c'), wid()); out.note('c')
    b.send({'activate': {'window': nw}}); sleep(0.4); key('tap', 'w', 'shift,command'); sleep(1.2)

@scene('P21')
def _(b, out):
    seen = b.win_ids()
    before = set(b.windows()); b.dispatch({'window': {'_0': {'newLittle': {}}}}); sleep(2.5)
    nws = [w for w in b.windows() if w not in before]
    def lw(): return b.find_window(seen, title=LITTLE, minimum=(301, 201), layers=('layer 0', 'layer 3'))
    p = lw()
    if p: sh('screencapture', '-x', '-o', '-l', p[0], out.path('a')); out.note('a')
    if nws:
        b.send({'load': {'window': nws[0], 'url': SITE + 'home.html'}}); sleep(2.5); p = lw()
        if p: sh('screencapture', '-x', '-o', '-l', p[0], out.path('b')); out.note('b')
        b.send({'activate': {'window': nws[0]}}); sleep(0.4); key('tap', 'w', 'command'); sleep(1)

@scene('P22')
def _(b, out):
    b.focus('Home'); b.front(); key('down', 'shift'); mouse('click', 914, 156); key('up', 'shift'); sleep(2.5); away(); out('a', 'region')
    key('tap', 'escape'); sleep(0.8)
    for kind, t, i, d in b.rows('today'):
        if 'peek=1' in (d.get('url') or ''): b.dispatch({'tab': {'_0': {'close': {'_0': {'item': {'_0': i}}}}}})

# ---- Q13: Favorites on real Arc (Q13/NOTES.md). The references were taken with a press 86 along the row and the window
# at the station's frame; a-h under the pale blue theme, the count series, the widths and the presses under white.
def require_front(b, point):
    """Real mouse events go to whatever is in front at that point of the screen, and Arc, other tasks' Brk windows and
    their floating panels can sit at this very frame: a gesture stops here unless this run's Brk is the frontmost app and
    owns the topmost window at `point` (window points). 2026-11-05: a station run's drags did not reach its Brk while
    another task was driving Arc."""
    if not b.front(): raise RuntimeError('this Brk is not the frontmost app; real mouse events not posted')
    top = tool('topwin', X0 + point[0], Y0 + point[1]).strip().split('|')
    if len(top) < 2 or top[1] != str(b.pid): raise RuntimeError(f'{top[0]} (pid {top[1] if len(top) > 1 else "?"}) is on top at {point}; real mouse events not posted')

def held_path(b, points, shoot, pause=0.4):
    """Press at the first of `points` (window points), glide through the rest, hold while `shoot()` captures, glide back
    the same way and release at the press point (tools/pathdrag.swift). A press opens the tab now: the scene shows
    Visual fixture again afterwards if it needs it."""
    require_front(b, points[0])
    sig = os.path.join(b.dir, 'path.signal'); release = sig + '.release'
    for f in (sig, release):
        if os.path.exists(f): os.remove(f)
    coords = [str(v) for x, y in points for v in (X0 + x, Y0 + y)]
    p = subprocess.Popen([os.path.join(BIN, 'pathdrag'), str(pause)] + coords + ['--signal', sig, '--release', release, '--back'], stdout=subprocess.DEVNULL)
    try:
        deadline = time.time() + 20
        while not os.path.exists(sig) and time.time() < deadline: sleep(0.05)
        sleep(0.9)
        k, v = b.send({'native': {'window': b.main}})
        if 'tab-tools-drag-image' not in (v.get('_0', v)).get('actual', {}): raise RuntimeError('the held drag did not reach this Brk')
        shoot()
    finally:
        open(release, 'w').close()
        p.wait(); sleep(0.6)

def path_drop(b, points, pause=0.4):
    """The same, released at the last point: a real drop."""
    require_front(b, points[0])
    coords = [str(v) for x, y in points for v in (X0 + x, Y0 + y)]
    tool('pathdrag', pause, *coords); sleep(0.8)

def held_press(b, point, shoot):
    """Mouse down at `point` without moving, while `shoot()` captures (tools/press.swift)."""
    require_front(b, point)
    sig = os.path.join(b.dir, 'press.signal')
    if os.path.exists(sig): os.remove(sig)
    p = subprocess.Popen([os.path.join(BIN, 'press'), str(X0 + point[0]), str(Y0 + point[1]), '3', sig], stdout=subprocess.DEVNULL)
    try:
        deadline = time.time() + 10
        while not os.path.exists(sig) and time.time() < deadline: sleep(0.05)
        sleep(0.8)
        shoot()
    finally:
        p.wait(); sleep(0.3)

def tile_center(b, item):
    k, v = b.send({'native': {'window': b.main}})
    (x, y), (w, h) = (v.get('_0', v))['actual']['favorite-' + item]['frame']
    return (x + w / 2, y + h / 2)

def cut(b, out, letter, w, h):
    """A window capture cut to the top-left w x h points, the shape of the crop references."""
    path = out.path(letter); whole = path + '.whole.png'
    cap_window(b, whole); tool('cut', whole, path, 0, 0, w, h); os.remove(whole); out.note(letter)

def q13_arrange(b, names, tiles, today, current):
    """Favorites `tiles` and Today `today`, in those orders, `current` shown; `names` maps a short name to its item."""
    v = b.view(); fav_root = v['favorites']['root']; today_root = v['space']['today']['root']
    for n, name in enumerate(today): b.dispatch({'item': {'_0': {'move': {'_0': names[name], 'to': {'into': {'parent': today_root, 'index': n}}}}}})
    for n, name in enumerate(tiles): b.dispatch({'item': {'_0': {'move': {'_0': names[name], 'to': {'into': {'parent': fav_root, 'index': n}}}}}})
    b.dispatch({'tab': {'_0': {'focus': {'_0': names[current]}}}}); sleep(1.2)

# Arc's Today and current tab at each count (the references' order: tabs were dragged in and out one at a time).
Q13_FIVE = ['W', 'Inbox', 'M', 'G', 'A']
Q13_COUNTS = {
    0: ([], ['W', 'M', 'Inbox', 'Long', 'Secondary', 'Visual', 'A', 'G'], 'W'),
    1: (['W'], ['M', 'Inbox', 'Long', 'Secondary', 'Visual', 'A', 'G'], 'W'),
    2: (['W', 'M'], ['Inbox', 'Long', 'Secondary', 'Visual', 'A', 'G'], 'M'),
    3: (['W', 'M', 'G'], ['Inbox', 'Long', 'Secondary', 'Visual', 'A'], 'A'),
    5: (Q13_FIVE, ['Long', 'Secondary', 'Visual'], 'Inbox'),
    6: (Q13_FIVE + ['Long'], ['Secondary', 'Visual'], 'Long'),
    7: (Q13_FIVE + ['Long', 'Secondary'], ['Visual'], 'Secondary'),
    8: (Q13_FIVE + ['Long', 'Secondary', 'Visual'], ['Design', 'Interaction'], 'Design'),
    9: (Q13_FIVE + ['Long', 'Secondary', 'Visual', 'Design'], ['Interaction'], 'Long'),
    10: (Q13_FIVE + ['Long', 'Secondary', 'Visual', 'Design', 'Interaction'], [], 'Interaction'),
}

@scene('Q13')
def _(b, out):
    tiles = b.view()['favorites']['tiles']
    apple, wiki = tiles[3]['id'], tiles[0]['id']
    def back(): b.focus('Visual fixture'); away()
    with theme(b, SKY):
        back(); b.front()
        inbox = row_center(b, 'Inbox'); press = (86, inbox[1]); home = (86, row_center(b, 'Home')[1])
        held_path(b, [press, (114, 113)], lambda: out('a', 'window')); back()
        held_path(b, [press, (196, 113)], lambda: out('b', 'window')); back()
        held_path(b, [tile_center(b, wiki), (141, 113)], lambda: out('c', 'window')); back()
        held_path(b, [tile_center(b, apple), (86, 488)], lambda: out('d', 'window')); back()
        held_path(b, [tile_center(b, apple), (780, 330)], lambda: out('e', 'window')); back()
        held_path(b, [home, (114, 113)], lambda: out('f', 'window')); back()
        held_path(b, [press, (86, 146)], lambda: out('g', 'window')); back()
        # h: dropped on the strip: the first pinned tab, shown, with the hint line
        path_drop(b, [press, (86, 146)]); away(); sleep(0.8); cut(b, out, 'h', 236, 776)
        root = b.view()['space']['today']['root']
        b.dispatch({'item': {'_0': {'move': {'_0': b.find('Inbox'), 'to': {'into': {'parent': root, 'index': 0}}}}}}); back()
    names = {'W': wiki, 'M': tiles[1]['id'], 'G': tiles[2]['id'], 'A': apple, 'Inbox': b.find('Inbox', 'today'), 'Long': b.find(TODAY[1], 'today'),
             'Secondary': b.find('Secondary reference', 'today'), 'Visual': b.find('Visual fixture', 'today')}
    base_today = ['Inbox', 'Long', 'Secondary', 'Visual']
    # The count series compares the tiles' places and sizes; Arc's sidebar reads #FDFDFD in these shots (Q14), the white theme is only near it.
    with theme(b, WHITE):
        for count, (fav, today, current) in Q13_COUNTS.items():
            if count == 8:
                # Arc's two extra pages arrive here, with Today otherwise emptied into the grid.
                names['Design'] = b.send({'load': {'window': b.main, 'url': SITE + 'design.html'}})[1]['tab']
                names['Interaction'] = b.send({'load': {'window': b.main, 'url': SITE + 'interaction.html'}})[1]['tab']
                b.settle(4)
            q13_arrange(b, names, fav, today, current); away()
            cut(b, out, f'n{count}', 236, 776)
        # five favorites at other widths, and the two presses
        q13_arrange(b, names, Q13_FIVE, ['Long', 'Secondary', 'Visual', 'Design', 'Interaction'], 'Inbox')
        for width, size in ((500, (560, 330)), (200, (300, 330)), (166, (300, 400))):
            b.dispatch({'sidebar': {'_0': {'resize': {'width': width}}}}); sleep(0.6); away()
            cut(b, out, f'w{width}-n5', *size)
        b.dispatch({'sidebar': {'_0': {'resize': {'width': 228}}}}); sleep(0.5)
        b.front(); held_press(b, tile_center(b, wiki), lambda: cut(b, out, 'press-favorite', 700, 330))
        b.dispatch({'tab': {'_0': {'focus': {'_0': names['Inbox']}}}}); sleep(0.8)
        b.front(); held_press(b, row_center(b, 'Secondary reference'), lambda: cut(b, out, 'press-row', 700, 700))
    # the fixture's four favorites and Today again; the extra pages go with the baseline
    q13_arrange(b, names, ['W', 'M', 'G', 'A'], base_today + ['Design', 'Interaction'], 'Visual')

@scene('P23')
def _(b, out):
    # d: Interface comparison (the pinned folder's second tab) held at the content's right edge, before any split
    # (Arc: the page gives up the right half to a ringed slot and a white card rides the pointer). The card keeps the
    # pointer's place along the row, 128 of 228: at 1085 it stands where Arc's does.
    with theme(b, TEAL): b.front(); held_drag(b, (128, 368), (1085, 398), lambda: out('d', 'window'), shown='tab-tools-content-drag-card'); away()
    b.focus('Visual fixture'); sleep(0.5)   # the press opened the dragged tab, and the drag ended back on its row
    b.dispatch({'split': {'_0': {'addPane': {}}}}); sleep(1.2); b.type(SITE + 'docs.html'); b.press('return'); sleep(3)
    select_draft(b); sleep(0.4); in_window(); out('a', 'window')
    # splitmenu: the focused (right) pane's split button, 32 left of its close (Arc's P23-splitmenu-arc.png, taken
    # later without the highlight)
    b.send({'evaluate': {'page': page_id(b, 0), 'script': 'getSelection().removeAllRanges()'}})
    with theme(b, TEAL):
        b.front(); mouse('click', X0 + 1217, Y0 + 26); sleep(1.2); cap_menu(b, out.path('splitmenu')); out.note('splitmenu'); key('tap', 'escape'); sleep(0.5); away()
        # c: the same two panes stacked top and bottom (Arc: pane menu -> Convert to Vertical Split View), then back
        with without_today(b, 'Secondary reference'):
            b.dispatch({'split': {'_0': {'orientCurrent': {'_0': 'vertical'}}}}); sleep(1.5); in_window(); out('c', 'window')
            # vsplitmenu: the focused (bottom) pane's split button; the stacked pane starts at 388, its header 32 tall
            b.front(); mouse('click', X0 + 1217, Y0 + 404); sleep(1.2); cap_menu(b, out.path('vsplitmenu')); out.note('vsplitmenu'); key('tap', 'escape'); sleep(0.5); away()
    b.dispatch({'split': {'_0': {'orientCurrent': {'_0': 'horizontal'}}}}); sleep(1.2)
    select_draft(b); sleep(0.4)
    b.front(); mouse('rightclick', 433, 660); sleep(1.2); cap_menu(b, out.path('P12e')); out.note('P12e'); key('tap', 'escape'); sleep(0.5)
    for u in ('interface', 'secondary'):
        b.dispatch({'split': {'_0': {'addPane': {}}}}); sleep(1.2); b.type(SITE + u + '.html'); b.press('return'); sleep(3)
    out('b', 'window')
    for kind, t, i, d in b.rows('today') + b.rows('pinned'):
        if kind == 'split':
            b.dispatch({'tab': {'_0': {'focus': {'_0': i}}}}); b.dispatch({'split': {'_0': {'separateAll': {}}}})
    sleep(1)
    for kind, t, i, d in b.rows('today') + b.rows('pinned'):
        if kind == 'tab' and t in ('New Tab', 'Docs', 'Interface comparison', 'Secondary reference') and d.get('section') == 'today' and t != 'Secondary reference':
            b.dispatch({'tab': {'_0': {'close': {'_0': {'item': {'_0': i}}}}}})
    # e/f: Inbox dragged onto the middle of Secondary reference (Arc's P23-e/f: Today reads Long title…, Inbox,
    # Secondary reference, Visual fixture with Inbox shown). Held, a slot shows in the half under the pointer and the row
    # image lies over it, 14 right of the row (P23-e); released on the left half, the two are one split row there,
    # Inbox the focused left pane. e-right: the same, on the right half (Arc's own right half is Q15-b).
    sleep(0.8); baseline(b)   # closes the second Secondary reference b left behind and restores the order
    with theme(b, TEAL):
        root = b.view()['space']['today']['root']
        b.dispatch({'item': {'_0': {'move': {'_0': b.find('Inbox', 'today'), 'to': {'into': {'parent': root, 'index': 1}}}}}})
        b.focus('Inbox'); sleep(0.8)
        src, dst = row_center(b, 'Inbox'), row_center(b, 'Secondary reference')
        press = (60, src[1])
        b.front(); held_drag(b, press, (74, dst[1]), lambda: out('e', 'window'), shown='tab-tools-drag-image'); away()
        b.front(); held_drag(b, press, (154, dst[1]), lambda: out('e-right', 'window'), shown='tab-tools-drag-image'); away()
        require_front(b, press); mouse('drag', X0 + press[0], Y0 + press[1], X0 + 74, Y0 + dst[1], 0.8); sleep(2.5); away()
        out('f', 'window')
    for kind, t, i, d in b.rows('today'):
        if kind == 'split': b.dispatch({'tab': {'_0': {'focus': {'_0': i}}}}); b.dispatch({'split': {'_0': {'separateAll': {}}}})
    sleep(0.8); today_in_order(b)

def q15_split_row(b):
    return next(i for kind, t, i, d in b.rows('today') if kind == 'split')

def q15_row_y(b, item):
    k, v = b.send({'native': {'window': b.main}})
    (x, y), (w, h) = (v.get('_0', v))['actual']['row-' + item]['frame']
    return y + h / 2

def _q18_media(b, out):
    # Q18/NOTES.md, the media part: the tone page playing, as Arc's pictures were taken. Arc's card stands 32 pt higher than
    # Brk's because Arc's New Arc Version Available banner sits under it (r5-5/REPORT.md).
    def tool_center(name):
        k, v = b.send({'native': {'window': b.main}})
        (x, y), (w, h) = (v.get('_0', v))['actual']['tab-tools-' + name]['frame']
        return (round(x + w / 2), round(y + h / 2))
    def over(name, wait=1.4):
        x, y = tool_center(name); mouse('move', X0 + x, Y0 + y); sleep(wait)
    def to_today_top(tab):
        root = b.view()['space']['today']['root']
        b.dispatch({'item': {'_0': {'move': {'_0': tab, 'to': {'into': {'parent': root, 'index': 0}}}}}})
    def visual(): b.focus('Visual fixture'); sleep(0.8); away(); sleep(0.5)
    def click_page_play(tab):
        b.dispatch({'tab': {'_0': {'focus': {'_0': tab}}}}); b.settle(2); b.front(); mouse('click', X0 + 287, Y0 + 178); sleep(1.6)
    with theme(b, SKY):
        media = b.send({'load': {'window': b.main, 'url': SITE + 'media.html'}})[1]['tab']; b.settle(4); to_today_top(media)
        click_page_play(media); away(); sleep(0.5); cut(b, out, 'media-a', 236, 776)
        visual(); cut(b, out, 'media-c', 236, 776)
        b.front(); over('mini-player-play-' + media, 2.2); cut(b, out, 'media-e', 236, 776)
        mouse('click', X0 + tool_center('mini-player-play-' + media)[0], Y0 + tool_center('mini-player-play-' + media)[1]); sleep(1.0)
        cut(b, out, 'media-h-paused-hover', 236, 776)
        away(); sleep(4); cut(b, out, 'media-i-paused', 236, 776)
        over('mini-player-speaker-' + media, 1.2); mouse('click', X0 + tool_center('mini-player-speaker-' + media)[0], Y0 + tool_center('mini-player-speaker-' + media)[1]); sleep(1.2)
        cut(b, out, 'media-j-volume', 236, 776)
        away(); sleep(3); over('mini-player-play-' + media, 0.6)
        mouse('click', X0 + tool_center('mini-player-play-' + media)[0], Y0 + tool_center('mini-player-play-' + media)[1]); sleep(1.5); away(); sleep(1)
        over('audio-' + media, 2.4); cut(b, out, 'media-f', 236, 776)
        mouse('click', X0 + tool_center('audio-' + media)[0], Y0 + tool_center('audio-' + media)[1]); sleep(1.0); away(); sleep(1.2)
        cut(b, out, 'media-g', 236, 776)
        tracks = b.send({'load': {'window': b.main, 'url': os.environ.get('Q18_SITE', SITE) + 'media-tracks.html'}})[1]['tab']; b.settle(4); to_today_top(tracks)
        click_page_play(tracks)
        b.focus('Secondary reference'); sleep(0.8); away(); sleep(0.6); cut(b, out, 'media-n-two-cards', 236, 776)
        over('mini-player-play-' + tracks, 2.2); cut(b, out, 'media-o-two-cards-hover', 236, 776)
        over('mini-player-next-' + tracks, 2.2); cut(b, out, 'media-p-tracks-next', 236, 776); away(); sleep(0.5)
        for tab in (tracks, media): b.dispatch({'tab': {'_0': {'close': {'_0': {'item': {'_0': tab}}}}}})
        visual()

@scene('Q17')
def _(b, out):
    # Q17/NOTES.md, the same paths as Arc's: press on Inbox (or the fourth Favorite), glide, hold, glide back and release on
    # the press point. A, B and F were taken with Visual fixture current, C, D and E with Inbox itself current (an earlier
    # drag had ended on its row: the row colours in Arc's pictures show it), so each shot starts from that state.
    def other(): b.focus('Visual fixture'); sleep(0.3); away()
    def own(): b.focus('Inbox'); sleep(0.3); away()
    apple = b.view()['favorites']['tiles'][3]['id']
    with theme(b, SKY):   # Arc's pictures here have the pale blue sidebar, as Q13's do
        other(); b.front()
        press = (86, row_center(b, 'Inbox')[1])
        fav = tile_center(b, apple)
        def shot(label, points, start):
            start(); held_path(b, points, lambda: out(label, 'window'))
        for x in (330, 440, 580, 680, 748, 752, 760, 770, 780, 800, 820, 840, 860, 880, 980, 1060, 1180):
            shot(f'a-x{x}', [press, (x, 330)], other)
        for y in (50, 180, 530, 730):
            shot(f'a-y{y}', [press, (780, y)], other)
        for x in (780, 930):
            shot(f'b-x{x}', [press, (320, 330), (x, 330)], other)
        for x in (840, 780, 752, 720, 680, 640, 580):
            shot(f'c-x{x}', [press, (1180, 330), (x, 330)], own)
        for y in (80, 110, 140, 600, 650, 690):
            shot(f'd-y{y}', [press, (780, 330), (780, y)], own)
        shot('e-380-80', [press, (380, 330), (380, 80)], own)
        shot('e-380-730', [press, (380, 330), (380, 730)], own)
        shot('e-1180-80', [press, (1180, 330), (1180, 80)], own)
        for x in (440, 748, 1060, 1255):
            shot(f'f-x{x}', [fav, (300, 230), (x, 330)], other)
        shot('f-straight', [fav, (780, 330)], other)
        other()
        # Second probe. A pinned tab released on the right half: Today [Inbox, Long title, Secondary, Visual | Home].
        home = (86, row_center(b, 'Home')[1])
        require_front(b, home); path_drop(b, [home, (1060, 330)]); sleep(1.2); away()
        out('drop-pinned-right-half', 'window')
        split = next(i for kind, t, i, d in b.rows('today') if kind == 'split')
        b.dispatch({'tab': {'_0': {'focus': {'_0': split}}}}); b.dispatch({'split': {'_0': {'separateAll': {}}}}); sleep(0.8); away()
        out('drop-pinned-then-separated', 'window')
        baseline(b)
        # A third tab over the split [Visual fixture | Inbox]: Today [Long title, Secondary reference, the split].
        other()
        visual, inbox = b.find('Visual fixture', 'today'), b.find('Inbox', 'today')
        b.dispatch({'split': {'_0': {'joinRow': {'_0': inbox, 'onto': visual, 'at': 1}}}}); sleep(0.8)
        split = next(i for kind, t, i, d in b.rows('today') if kind == 'split')
        def on_split(): b.dispatch({'tab': {'_0': {'focus': {'_0': split}}}}); sleep(0.4); away()
        on_split(); out('split-before-third', 'window')
        third = (86, row_center(b, TODAY[1])[1])
        held_path(b, [third, (486, 330)], lambda: out('split-hold-486-330', 'window')); on_split()
        held_path(b, [third, (1012, 330)], lambda: out('split-hold-1012-330', 'window')); on_split()
        require_front(b, third); path_drop(b, [third, (1012, 330)]); sleep(1.2); away()
        out('split-drop-on-framed-pane', 'window')
        b.dispatch({'split': {'_0': {'separateAll': {}}}}); sleep(0.8); away()
        out('split-drop-on-framed-pane-then-separated', 'window')
        baseline(b)

@scene('Q15')
def _(b, out):
    # A tab onto another tab or split row (Q15/NOTES.md). Pressed 86 along the row, as the references.
    def separate():
        for kind, t, i, d in b.rows('today'):
            if kind == 'split': b.dispatch({'tab': {'_0': {'focus': {'_0': i}}}}); b.dispatch({'split': {'_0': {'separateAll': {}}}})
        sleep(0.8); today_in_order(b); b.focus('Visual fixture'); away()
    with theme(b, SKY):
        b.focus('Visual fixture'); away()
        inbox, target = row_center(b, 'Inbox'), row_center(b, 'Secondary reference')
        press = (86, inbox[1])
        held_path(b, [press, (70, target[1])], lambda: out('a', 'window')); b.focus('Visual fixture'); away()
        held_path(b, [press, (160, target[1])], lambda: out('b', 'window')); b.focus('Visual fixture'); away()
        # d: dropped on the right half: "Second… | Inbox", the right pane focused
        path_drop(b, [press, (160, target[1])]); away(); sleep(1.5); out('d', 'window')
        # Inbox has left its place, so Long title now sits one row higher
        split_y = q15_row_y(b, q15_split_row(b)); press_long = (86, row_center(b, TODAY[1])[1])
        # e: Long title held on the split row: one band
        held_path(b, [press_long, (114, split_y)], lambda: out('e', 'window')); away()
        # f: dropped at the left end: the first pane
        path_drop(b, [press_long, (30, split_y)]); away(); sleep(1.5); out('f', 'window')
        separate()
        # g: dropped at the right end of the same split: the last pane
        path_drop(b, [press, (160, target[1])]); sleep(1.0)
        path_drop(b, [(86, row_center(b, TODAY[1])[1]), (200, q15_row_y(b, q15_split_row(b)))]); away(); sleep(1.5); out('g', 'window')
        separate()

@scene('P24')
def _(b, out):
    b.dispatch({'sidebar': {'_0': {'openDialog': {'_0': {'newSpace': {}}}}}}); sleep(1.5); away(); out('a', 'region')
    b.dispatch({'sidebar': {'_0': {'openDialog': {}}}})

@scene('P25')
def _(b, out): out('a', 'window')

@scene('P26')
def _(b, out):
    # Arc's reference has the folder 资料 closed
    folder = b.find('资料', 'pinned'); b.dispatch({'item': {'_0': {'toggleFolder': {'_0': folder}}}}); sleep(0.6)
    b.front(); osa(f'tell application "System Events" to tell (first process whose unix id is {b.pid}) to click menu item "Rename Space" of menu 1 of menu bar item "Spaces" of menu bar 1'); sleep(1.2); away(); out('a', 'region'); key('tap', 'escape'); sleep(0.4)
    b.dispatch({'item': {'_0': {'toggleFolder': {'_0': folder}}}})
    b.dispatch({'sidebar': {'_0': {'openDialog': {}}}})

@scene('P27')
def _(b, out):
    b.dispatch({'space': {'_0': {'requestDelete': {'_0': b.space_id('对照')}}}}); sleep(1.2); b.front(); away(); out('a', 'window'); key('tap', 'escape'); sleep(0.5)
    # b: the 对照 dot (second dock cell, centred at x 130.5) held 50.5 to the left (Arc's capsule spans 63...97)
    with theme(b, TEAL): b.front(); held_drag(b, (130.5, 751), (80, 751), lambda: out('b', 'window'), shown='tab-tools-dock-reorder-capsule'); away()

@scene('Q02')
def _(b, out):
    # b: Today emptied (every Today tab closed) with the folder 资料 closed, as in the Arc reference. Arc (and Brk)
    # show the window's most recently used pinned tab once Today is empty, and the empty card only when the window has
    # used none (checked on Arc, results.tsv Q02-c); the reference was taken in a window that had used none, so the
    # scene opens a fresh standard window at the station frame and empties Today from there.
    seen = b.win_ids(); before = set(b.windows())
    b.dispatch({'window': {'_0': {'new': {}}}}); sleep(2.0)
    nw = [w for w in b.windows() if w not in before][0]
    b.send({'setWindowFrame': {'window': nw, 'frame': [[X0, SCREEN_H - Y0 - H], [W, H]]}}); sleep(0.5)
    folder = b.find('资料', 'pinned')
    theme_on = theme(b, TEAL); theme_on.__enter__()   # Arc's b was taken under the pale teal theme
    b.dispatch({'item': {'_0': {'toggleFolder': {'_0': folder}}}}, window=nw)
    for kind, t, i, d in b.rows('today'):
        if kind == 'tab': b.dispatch({'tab': {'_0': {'close': {'_0': {'item': {'_0': i}}}}}}, window=nw)
    sleep(1.5); away()
    p = b.find_window(seen, size=(W, H))
    if not p: raise RuntimeError('Q02: the new window is not on screen')
    cap_window(b, out.path('b'), p[0]); out.note('b')
    theme_on.__exit__()
    for _ in range(4): b.dispatch({'archive': {'_0': {'restoreLast': {}}}}, window=nw)
    b.dispatch({'item': {'_0': {'toggleFolder': {'_0': folder}}}}, window=nw)
    b.send({'activate': {'window': nw}}); sleep(0.4); key('tap', 'w', 'shift,command'); sleep(1.2)

@scene('P28')
def _(b, out):
    # Arc's P28-a is 1280x920 from the window origin: the panel runs past the window's bottom edge
    set_theme_doc(b, WHITE_THEME); load_pinned(b)
    try:
        b.front(); osa(f'tell application "System Events" to tell (first process whose unix id is {b.pid}) to click menu item "Edit Theme…" of menu 1 of menu bar item "Spaces" of menu bar 1'); sleep(1.5); away()
        cap_region(out.path('a'), X0, Y0, W, 920); out.note('a'); key('tap', 'escape'); sleep(0.4)
        b.dispatch({'sidebar': {'_0': {'openDialog': {}}}})
    finally: set_theme_doc(b, FIXTURE_THEME)

@scene('Q11')
def _(b, out):
    # The dock's + is at 188..220 x 735..767 in the window; Q11-a-menu-arc is the 222 x 308 pt piece around the popover.
    with theme(b, SKY):
        b.focus(TODAY[3]); sleep(0.5); away(); b.front(); mouse('click', X0 + 204, Y0 + 751); sleep(1)
        out('a', 'window')
        sh('sips', '-c', '616', '444', '--cropOffset', '846', '8', out.path('a'), '--out', out.path('a-menu')); out.note('a-menu')
        key('tap', 'escape'); sleep(0.4); away()
        b.front(); key('tap', 'c', 'shift,command'); sleep(0.7); out('b', 'window'); sleep(7)

@scene('P10')
def _(b, out):
    # Through the real menus: a right-click, then the row by typing its first letters, as a person can.
    # Arc's references are 1450 x 846 pt from the screen's top, desktop included, and both popovers hang past the window's left edge.
    frame = (150, 0, 1450, 846)
    for letter, (x, y) in {'a': (378, 356), 'c': (343, 233)}.items():
        if letter == 'c': select_draft(b)   # Arc's c keeps the word Draft highlighted on the page
        b.front(); mouse('rightclick', x, y); sleep(1.2)
        for ch in 'ch': key('tap', ch); sleep(0.08)
        key('tap', 'return'); sleep(1.2); away()
        cap_popover(b, out.path(letter), *frame); out.note(letter); key('tap', 'escape'); sleep(0.5)
    clear_selection(b)

@scene('P29')
def _(b, out):
    osa('tell application "System Events" to tell appearance preferences to set dark mode to true'); sleep(2.5); away(); out('b', 'window')
    with theme(b, SKY):   # Arc's c: the pale blue theme, with the system dark
        b.front(); b.dispatch({'commandBar': {'_0': {'open': {'_0': 'editCurrent'}}}}); sleep(1.2); away(); out('c', 'window'); b.dispatch({'commandBar': {'_0': {'dismiss': {}}}})
    b.front(); mouse('rightclick', 433, 537); sleep(1.2); out('d', 'menu'); key('tap', 'escape'); sleep(0.4)
    osa('tell application "System Events" to tell appearance preferences to set dark mode to false'); sleep(1.5)

@scene('P30')
def _(b, out):
    set_theme(b, '对照', WHITE_COLORS)   # Arc's references: 对照 near-white
    try: _p30(b, out)
    finally: reset_theme(b, '对照')

def _p30(b, out):
    # a: the Spaces page (window); c: 对照's card … clicked where Arc's was (its centre), the menu composed over the
    # window (the canvas grows when the menu runs past the window's bottom)
    b.dispatch({'library': {'_0': {'open': {'_0': 'spaces'}}}}); sleep(2); b.front(); away(); out('a', 'window')
    k, v = b.send({'native': {'window': b.main}})
    more = v['_0']['actual']['space-tools-manager-more-' + b.space_id('对照')]['frame']
    (x, y), (w, h) = more
    mouse('click', X0 + int(x + w / 2), Y0 + int(y + h / 2)); sleep(1.2); out('c', 'menu'); key('tap', 'escape'); sleep(0.4)
    # leave Media as the page the Library reopens on, as a fresh launch has it (P32-a opens the Library without a page)
    b.dispatch({'library': {'_0': {'open': {'_0': 'media'}}}}); b.dispatch({'library': {'_0': {'close': {}}}})

# ---- Easels: ids from the view, and deletion through Arc's confirmation (what the Library card's menu does)
def easel_ids(b):
    ids = []
    for kind, t, i, d in b.rows('pinned'):
        u = d.get('url') or ''
        if u.startswith('brk://easel/'): ids.append(u[len('brk://easel/'):])
    return ids
def delete_easel(b, eid):
    b.dispatch({'easel': {'_0': {'requestDelete': {'_0': eid}}}}); sleep(0.4)
    req = b.view().get('pendingEaselDeletion')
    if req: b.dispatch({'easel': {'_0': {'confirmDelete': {'_0': eid, 'token': req['token'], 'confirmed': True}}}}); sleep(0.4)

# Arc's P32-e lists five archived tabs under Today, newest first (Home was archived first).
ARC_ARCHIVE = ['home.html', 'visual.html?peek=1', 'secondary.html', 'interface.html', 'docs.html']
def archive_pages(b, pages):
    for page in pages:
        k, v = b.send({'load': {'window': b.main, 'url': SITE + page}}); b.settle(4); sleep(0.4)
        b.dispatch({'tab': {'_0': {'archive': {'_0': {'item': {'_0': v['tab']}}}}}}); sleep(0.3)
    b.focus('Visual fixture')

@scene('P32')
def _(b, out):
    set_theme(b, '对照', WHITE_COLORS)   # Arc's references: 对照 near-white (the strips above and under the page)
    try: _p32(b, out)
    finally:
        reset_theme(b, '对照')
        try: b.dispatch({'archive': {'_0': {'clear': {}}}})
        except Exception: pass

def _p32(b, out):
    b.dispatch({'library': {'_0': {'open': {}}}}); sleep(2); b.front(); away(); out('a', 'region')
    for letter, page in (('b', 'downloads'), ('c', 'easelsAndNotes'), ('d', 'spaces'), ('e', 'archive'), ('f', 'boosts'), ('i', 'media')):
        made = []
        if letter == 'c':
            # Arc's P32 c lists two Untitled Easels while the page stays in the content area and no row shows them.
            for _n in range(2):
                b.dispatch({'easel': {'_0': {'create': {}}}}); sleep(0.4)
            made = easel_ids(b)
            for kind, t, i, d in b.rows('pinned'):
                if (d.get('url') or '').startswith('brk://easel/'): b.dispatch({'tab': {'_0': {'archive': {'_0': {'item': {'_0': i}}}}}})
            b.focus('Visual fixture'); sleep(0.6)
        if letter == 'e':
            b.dispatch({'library': {'_0': {'close': {}}}}); b.dispatch({'archive': {'_0': {'clear': {}}}})
            archive_pages(b, ARC_ARCHIVE); sleep(0.6)
        b.dispatch({'library': {'_0': {'open': {'_0': page}}}}); sleep(1.2); out(letter, 'region')
        for eid in made: delete_easel(b, eid)
    b.dispatch({'library': {'_0': {'close': {}}}})

@scene('Q09')
def _(b, out):
    # a: File > New Easel; the board with its title selected, the row at the end of Pinned (Arc's: the pale teal theme)
    theme_on = theme(b, TEAL); theme_on.__enter__()
    b.front()
    try: osa(f'tell application "System Events" to tell (first process whose unix id is {b.pid}) to click menu item "New Easel" of menu 1 of menu bar item "File" of menu bar 1')
    except Exception: pass
    sleep(1.5)
    if not easel_ids(b): b.dispatch({'easel': {'_0': {'create': {}}}}); sleep(1.2)
    away(); sleep(0.5); out('a', 'window')
    eid = easel_ids(b)[-1]
    # c: Arc's delete confirmation over the page, the Easel's row still in Pinned
    b.focus('Visual fixture'); sleep(0.8)
    b.dispatch({'easel': {'_0': {'requestDelete': {'_0': eid}}}}); sleep(1.2); b.front(); away(); out('c', 'window')
    req = b.view().get('pendingEaselDeletion')
    if req: b.dispatch({'easel': {'_0': {'confirmDelete': {'_0': eid, 'token': req['token'], 'confirmed': True}}}}); sleep(0.5)
    for left in easel_ids(b): delete_easel(b, left)
    theme_on.__exit__()

@scene('P36')
def _(b, out):
    # the site controls popover: through the command the site icon sends (the icon's position moved with group 1)
    set_theme_doc(b, WHITE_THEME); load_pinned(b)
    b.front()
    try: b.dispatch({'site': {'_0': {'controls': {}}}})
    except Exception: mouse('click', 342, 133)
    sleep(1.5); away(); out('a', 'region'); key('tap', 'escape'); sleep(0.5)
    set_theme_doc(b, FIXTURE_THEME)
    for p in b.win_list():
        if 'Website controls' in p[1]:
            osa(f'tell application "System Events" to tell (first process whose unix id is {b.pid}) to tell (first window whose name is "Website controls") to click button 1')
    # b: the same popover over a real https page: the Arc reference was taken on example.com, so Brk opens the same
    # page (the native SiteSecurity scenarios prove the trusted test certificate; here the page content must match).
    # Falls back to the https fixture's page when example.com cannot be reached.
    # Arc's reference has the pale blue theme, Secondary reference archived and the pointer on the pill's site icon.
    with theme(b, SKY), without_today(b, 'Secondary reference'):
        k, v = b.send({'load': {'window': b.main, 'url': 'https://example.com/'}}); tab = v['tab']
        try:
            if not wait_titles(b, ('Example Domain',), 15):
                print('[scenes] P36 b: example.com did not load, using the https fixture', flush=True)
                if not HTTPS_FIXTURE: raise RuntimeError('https fixture not running, P36 b skipped')
                b.send({'load': {'window': b.main, 'url': HTTPS_FIXTURE + 'secure.html'}}); wait_titles(b, ('Secure fixture',), 10)
            sleep(1.0); b.front()
            try: b.dispatch({'site': {'_0': {'controls': {}}}})
            except Exception: mouse('click', 342, 133)
            sleep(1.0); mouse('move', X0 + 199, Y0 + 62); sleep(1.0); out('b', 'region'); key('tap', 'escape'); sleep(0.5); away()
        finally:
            b.dispatch({'tab': {'_0': {'close': {'_0': {'item': {'_0': tab}}}}}})

@scene('P38')
def _(b, out):
    seen = b.win_ids()
    def swid(pane):
        # the settings window: new since the scene began, titled with the pane (SettingsCopy.title: General, Max, …)
        p = b.find_window(seen, title=pane, minimum=(501, 301))
        if not p: print(f'[scenes] P38: windows now {[(q[1], q[2], q[4]) for q in b.win_list() if q[0] not in seen]}', flush=True)
        return p[0] if p else None
    # Arc's Links pane (f) shows its default "6 hours (default)"; the fixture keeps Little Arcs for 12 hours
    links = lambda setting: b.dispatch({'settings': {'_0': {'links': {'_0': setting}}}})
    links({'littleArcAutoArchive': {'_0': 'sixHours'}})
    # Arc's P38-a has Warn before quitting on; its P38-g restore windows off and the sites' theme data on. Set back below.
    b.dispatch({'settings': {'_0': {'general': {'_0': {'warnBeforeQuitting': {'_0': True}}}}}})
    advanced = lambda setting: b.dispatch({'settings': {'_0': {'advanced': {'_0': setting}}}})
    advanced({'restoreWindowsOnLaunch': {'_0': False}}); advanced({'themeToCSS': {'_0': True}})
    for letter, pane in (('a', 'general'), ('b', 'max'), ('d', 'profiles'), ('e', 'shortcuts'), ('f', 'links'), ('g', 'advanced'), ('h', 'icon')):
        try: b.send({'openSettings': {'pane': pane}})
        except Exception: continue
        sleep(1.3); b.front(); away(); w = swid(pane)
        if w: sh('screencapture', '-x', '-o', '-l', w, out.path(letter)); out.note(letter)
        else: print(f'[scenes] P38 {letter}: settings window for {pane} not found', flush=True)
    links({'littleArcAutoArchive': {'_0': 'twelveHours'}})
    b.dispatch({'settings': {'_0': {'general': {'_0': {'warnBeforeQuitting': {'_0': False}}}}}})
    advanced({'restoreWindowsOnLaunch': {'_0': True}}); advanced({'themeToCSS': {'_0': False}})
    def bottom(letter):
        # the Max pane scrolled to the bottom
        b.send({'openSettings': {'pane': 'max'}}); sleep(1); b.front(); w = swid('max')
        if not w: return
        for p in b.win_list():
            if p[0] == w:
                xy, wh = p[2].split(' '); x, y = map(int, xy.split(',')); ww, hh = map(int, wh.split('x'))
                mouse('move', x + ww // 2, y + hh // 2); tool('scroll', -10); tool('scroll', -10); tool('scroll', -10); sleep(0.8); away()
        sh('screencapture', '-x', '-o', '-l', w, out.path(letter)); out.note(letter)
    bottom('c')
    # max-on / max-list: Arc's six switches and "Automatically enable future Arc Max features" on, so the Enable card
    # says Turn Off Max (P38-max-on-arc.png at the top, P38-max-list-arc.png scrolled to the end). Brk's three own
    # features are set off first so the automatic switch does not turn them on.
    mx = lambda setting: b.dispatch({'settings': {'_0': {'max': {'_0': setting}}}})
    arcs = ('instantLinks', 'linkPreviews', 'downloadRename', 'commandBar')
    try:
        for f in ('askPage', 'browse', 'translation'): mx({'feature': {'_0': f, '_1': False}})
        for f in arcs: mx({'feature': {'_0': f, '_1': True}})
        mx({'tidyTabs': {'_0': True}}); mx({'renamePinnedTabs': {'_0': True}}); mx({'autoEnableFutureFeatures': {'_0': True}})
        b.send({'openSettings': {'pane': 'general'}}); sleep(0.6)
        b.send({'openSettings': {'pane': 'max'}}); sleep(1.3); b.front(); away(); w = swid('max')
        if w: sh('screencapture', '-x', '-o', '-l', w, out.path('max-on')); out.note('max-on')
        bottom('max-list')
    finally:
        mx({'autoEnableFutureFeatures': {'_0': False}}); mx({'tidyTabs': {'_0': False}}); mx({'renamePinnedTabs': {'_0': False}})
        for f in arcs: mx({'feature': {'_0': f, '_1': False}})
    b.dispatch({'settings': {'_0': {'closeWindow': {}}}})

@scene('Q06')
def _(b, out):
    # Links scrolled to the end, then Air Traffic Control's sheet over it with Arc's one route (meet.google.com,
    # Contains, Most Recent Space) and the default Little Arc
    links = lambda setting: b.dispatch({'settings': {'_0': {'links': {'_0': setting}}}})
    links({'addRoute': {'_0': {'id': 'q06-meet', 'pattern': 'meet.google.com', 'destination': {'mostRecentSpace': {}}, 'match': 'contains'}}})
    links({'externalLinksInLittleArc': {'_0': True}})
    links({'littleArcAutoArchive': {'_0': 'sixHours'}})   # Arc's default, "6 hours (default)" in the reference
    try:
        seen = b.win_ids(); b.send({'openSettings': {'pane': 'links'}}); sleep(1.3); b.front(); away()
        w = b.find_window(seen, title='Links', minimum=(501, 301))
        if not w: raise RuntimeError('settings window for links not found')
        x, y, ww, hh = geometry(w)
        # a Links pane opened for the first time in a run takes its first scroll before its content is in place: wait,
        # scroll, and scroll again (at the bottom the second batch changes nothing)
        mouse('move', x + ww // 2, y + hh // 2); sleep(1.0); tool('scroll', -10); tool('scroll', -10); tool('scroll', -10); sleep(0.6)
        tool('scroll', -10); tool('scroll', -10); sleep(0.8); away()
        sh('screencapture', '-x', '-o', '-l', w[0], out.path('links-bottom')); out.note('links-bottom')
        b.send({'click': {'view': {'settingsField': {'_0': 'airTrafficControl'}}, 'count': 1}}); sleep(1.5); away()
        # by window id, as Arc's: the sheet comes with its window and without the sheet's shadow
        sh('screencapture', '-x', '-o', '-l', w[0], out.path('a')); out.note('a')
        b.send({'click': {'view': {'settingsField': {'_0': 'routes-close'}}, 'count': 1}}); sleep(0.8)
    finally:
        links({'removeRoute': {'_0': 'q06-meet'}})
        links({'littleArcAutoArchive': {'_0': 'twelveHours'}})
        b.dispatch({'settings': {'_0': {'closeWindow': {}}}})

@scene('P39')
def _(b, out):
    seen = b.win_ids(); b.dispatch({'app': {'_0': {'showAbout': {}}}}); sleep(1.5); b.front(); away()
    p = b.find_window(seen, title=UNTITLED, minimum=(151, 101), maximum=(699, 499))
    if p: sh('screencapture', '-x', '-o', '-l', p[0], out.path('a')); out.note('a')
    key('tap', 'w', 'command'); sleep(0.5)

@scene('P43')
def _(b, out):
    with theme(b, WHITE): b.front(); key('tap', 'g', 'option,command'); sleep(1.5); away(); out('a', 'window'); key('tap', 'escape'); sleep(0.4)

@scene('Q01')
def _(b, out):
    # Arc's recent pages after the current tab: Inbox, Secondary reference, Long title…, GitHub; its page kept the
    # first paragraph's highlight. Window shots: the bar is in the window, and a region shot catches other apps'
    # notification banners at the screen's top right.
    recent(b, favorite(b, 'github.com'), TODAY[1], TODAY[2], TODAY[0])
    select_text(b, 'comparing')
    with theme(b, WHITE):
        b.front(); key('tap', 't', 'command'); sleep(1.2); away(); out('a', 'window')
        for ch in 'wiki': key('tap', ch); sleep(0.1)
        sleep(1.4); out('b', 'window'); key('tap', 'escape'); sleep(0.4)

@scene('Q03')
def _(b, out):
    seen = b.win_ids()
    before = set(b.windows()); b.dispatch({'window': {'_0': {'newIncognito': {}}}}); sleep(2.5)
    nw = [w for w in b.windows() if w not in before]
    def wid():
        p = b.find_window(seen, title=UNTITLED, size=(W, H))
        if not p: raise RuntimeError('the incognito window is not on screen')
        return p[0]
    if nw:
        b.send({'setWindowFrame': {'window': nw[0], 'frame': [[X0, SCREEN_H - Y0 - H], [W, H]]}}); sleep(0.5); away()
        cap_window(b, out.path('a'), wid()); out.note('a')
        b.send({'load': {'window': nw[0], 'url': SITE + 'home.html'}}); sleep(2.5); cap_window(b, out.path('b'), wid()); out.note('b')
        b.send({'activate': {'window': nw[0]}}); sleep(0.4); key('tap', 'w', 'shift,command'); sleep(1.2)

@scene('Q05')
def _(b, out):
    # Arc's reference: 对照 near-white, Arc's own visits, and two History tabs at the top of Today (Cmd+Y's and an
    # earlier one), the new one selected
    relaunch_with_arc_history(b); set_theme(b, '对照', WHITE_COLORS)
    try:
        # Brk keeps one History tab per space (Cmd+Y shows it again): the earlier one waits in Space 1 while Cmd+Y
        # opens the new one, then comes back under it. Nothing here types an address (a typed brk:// is a search).
        b.front(); key('tap', 'y', 'command'); sleep(1.5)
        first = next(i for kind, t, i, d in b.rows('today') if (d.get('url') or '').startswith('brk://history'))
        doc = fixture_doc()['doc']; here = b.space_id('对照'); other = next(s for s in doc['spaceOrder'] if s != here)
        b.dispatch({'item': {'_0': {'move': {'_0': first, 'to': {'space': {'_0': other}}}}}}); sleep(0.8)
        b.front(); key('tap', 'y', 'command'); sleep(1.5)
        b.dispatch({'item': {'_0': {'move': {'_0': first, 'to': {'into': {'parent': doc['spaces'][here]['todayRoot'], 'index': 1}}}}}}); sleep(1.5)
        away(); out('a', 'region')
    finally:
        b.dispatch({'library': {'_0': {'close': {}}}}); reset_theme(b, '对照')

@scene('Q07')
def _(b, out):
    with theme(b, TEAL):   # Arc's references: the pale teal theme
        b.focus('Home'); b.front(); mouse('rightclick', 1100, 400); sleep(1.2); out('a', 'menu'); key('tap', 'escape'); sleep(0.4)
        # Arc's menu starts 6 points further left and a point higher: its pointer was there (the same word, Open reference)
        b.front(); mouse('rightclick', 871, 155); sleep(1.2); out('b', 'menu'); key('tap', 'escape'); sleep(0.4)

def _boost_panel(b, seen):
    """The Boost panel window (a floating untitled panel, 183x588, or 480x588 with the code page): (wid, x, y, w, h)."""
    p = b.find_window(seen, title=UNTITLED, minimum=(183, 588), maximum=(480, 588), layers=('layer 0', 'layer 3'))
    if not p: raise RuntimeError('Boost panel not on screen')
    return (p[0],) + geometry(p)

@scene('P37')
def _(b, out):
    # Arc's P37 references are 1400x850 regions from the window origin plus the panel alone (-editor)
    # (P37-<letter>-arc-editor.png, paired by the station with P37-<letter>-brk-editor.png). Arc's theme was the
    # Greyscale white then (the white sidebar), and its c has the pointer off the page while c2 hovers a paragraph.
    def wide(letter): cap_stack(b, out.path(letter), X0, Y0, 1400, 850); out.note(letter)
    def panel_shot(letter):
        # by window, like Arc's (transparent corners), so a notification over the panel is not in the shot
        wid, x, y, w, h = _boost_panel(b, seen); sh('screencapture', '-x', '-o', '-l', wid, os.path.join(out.outdir, f'P37-{letter}-brk-editor.png')); out.note(letter + '-editor')
    set_theme_doc(b, WHITE_THEME); load_pinned(b)
    seen = b.win_ids()
    try:
        b.front(); b.dispatch({'boost': {'_0': {'create': {}}}}); sleep(1.5); away()
        wide('a'); panel_shot('a')
        wid, x, y, w, h = _boost_panel(b, seen)
        print(f'[scenes] P37 panel at {x},{y} {w}x{h}; windows: ' + ' / '.join('|'.join(p[1:4]) for p in b.win_list() if p[4] == 'onscreen 1'), flush=True)
        mouse('click', x + 91, y + 512); sleep(1.2); away()          # Make a Boost
        wide('b'); panel_shot('b')
        mouse('click', x + 91, y + 480); sleep(1.5)                   # Zap on
        panel_shot('c'); away(); sleep(0.6); wide('c')
        mouse('move', X0 + 600, Y0 + 218); sleep(0.4); mouse('move', X0 + 610, Y0 + 220); sleep(1.2)
        wide('c2')
        mouse('click', x + 91, y + 480); sleep(0.8)                   # Zap off
        max_switch(b, 'tidyTabs', True)                               # Arc's d retake has Max on, the rows 8 points lower
        mouse('click', x + 91, y + 533); sleep(1.2); away()           # Code page
        wide('d'); panel_shot('d')
        # Arc's retake also has the main window alone (P37-d-arc-main.png, by window id), free of what lies behind it
        cap_window(b, os.path.join(out.outdir, 'P37-d-brk-main.png')); out.note('d-main')
        b.dispatch({'boost': {'_0': {'discard': {}}}}); sleep(0.5)
    finally: max_switch(b, 'tidyTabs', False); set_theme_doc(b, FIXTURE_THEME)

@scene('P33')
def _(b, out):
    import subprocess as _sp
    set_theme(b, '对照', WHITE_COLORS); sleep(2)   # Arc's references: 对照 near-white; the pill's Translation Available back
    try: _p33(b, out, _sp)
    finally: reset_theme(b, '对照')

def _p33(b, out, _sp):
    b.front(); b.dispatch({'capture': {'_0': {'begin': {'_0': 'area'}}}}); sleep(1.0)
    mouse('move', X0 + 1178, Y0 + 726); sleep(1.0); out('a', 'window')
    drag = _sp.Popen([os.path.join(BIN, 'mouse'), 'drag', str(X0 + 577), str(Y0 + 227), str(X0 + 984), str(Y0 + 534), '2.5'])
    sleep(2.9); out('b', 'window'); drag.wait(); sleep(1.5); out('c', 'window')
    b.dispatch({'capture': {'_0': {'cancel': {}}}}); sleep(0.5)
    b.dispatch({'capture': {'_0': {'begin': {'_0': 'fullPage'}}}})
    deadline = time.time() + 15
    while time.time() < deadline and (b.view()['tabTools'].get('toast') or {}).get('text') != 'Screenshot Copied to Clipboard': sleep(0.3)
    away(); sleep(0.3); out('d', 'window')
    try: b.dispatch({'tabTools': {'_0': {'dismissToast': {}}}})
    except Exception: pass
    b.dispatch({'capture': {'_0': {'cancel': {}}}}); sleep(0.5)

# ---- AI scenes (P45-P50). The answers come from tools/fake-ai.py (BRK_AI_FIXTURE_EXECUTABLE), so they are the same
# every run. Each scene turns on only the Max switches it needs and turns them off again; they run after every other
# scene, so the Max switches the earlier scenes see are the fixture's own.
def max_feature(b, feature, on):
    b.dispatch({'settings': {'_0': {'max': {'_0': {'feature': {'_0': feature, '_1': on}}}}}})
def max_switch(b, name, on):   # renamePinnedTabs, tidyTabs
    b.dispatch({'settings': {'_0': {'max': {'_0': {name: {'_0': on}}}}}})
def ai_answer(b):
    return b.view().get('ai')
def ai_wait(b, ready, timeout):
    """Polls the window's AI answer until `ready(answer)`; the last answer either way."""
    deadline = time.time() + timeout
    while True:
        a = ai_answer(b)
        if a and ready(a): return a
        if time.time() >= deadline:
            print(f'[scenes] AI answer not ready after {timeout} s: {json.dumps(a)[:200] if a else None}', flush=True); return a
        sleep(0.3)
def ai_dismiss(b):
    try: b.dispatch({'assist': {'_0': {'dismiss': {}}}})
    except Exception: pass
FRESH = False
def fixture_today(b):
    """Today as in the Arc references: Inbox, Long title…, Secondary reference, Visual fixture, in that order, Visual
    fixture selected. Brk's archive sweep (every 60 s) takes the fixture tabs no scene has shown yet, their last use
    being the fixture's timestamps from 2026-11-03, past the 12-hour threshold; the earlier scenes' restores bring
    them back in another order. Missing ones come back from the archive; each tab is shown once per run, so the sweep leaves them."""
    global FRESH
    have = {t for kind, t, i, d in b.rows('today') if kind == 'tab'}
    missing = [t for t in TODAY if t not in have]
    if missing:
        b.dispatch({'library': {'_0': {'open': {'_0': 'archive'}}}}); sleep(1.0)
        try:
            library = (b.view().get('overlay') or {}).get('library') or {}; library = library.get('_0', library)
            entries = [e for g in ((library.get('archive') or {}).get('groups') or []) for e in g['entries']]
            for t in missing:
                e = next((e for e in entries if e['title'] == t), None)   # newest first
                if e: b.dispatch({'archive': {'_0': {'restore': {'_0': e['id']}}}})
                else: print(f'[scenes] fixture tab {t} is neither in Today nor in the archive', flush=True)
        finally:
            b.dispatch({'library': {'_0': {'open': {'_0': 'media'}}}}); b.dispatch({'library': {'_0': {'close': {}}}})
    root = b.view()['space']['today']['root']
    for n, t in enumerate(TODAY):
        try: b.dispatch({'item': {'_0': {'move': {'_0': b.find(t, 'today'), 'to': {'into': {'parent': root, 'index': n}}}}}})
        except KeyError: pass
    if not FRESH:
        for t in TODAY:
            try: b.focus(t)
            except KeyError: pass
        FRESH = True
    b.focus('Visual fixture'); away()

def wait_titles(b, titles, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        have = {t for kind, t, i, d in b.rows('today')}
        if all(t in have for t in titles): return True
        sleep(0.3)
    return False

@scene('P45')
def _(b, out):
    """Max's 5-Second Previews. Arc holds Shift over Preview reference on the Visual fixture page; about two seconds
    later a card with the AI summary opens under the link. Brk (R4-11): the same pointer and Shift, Max's 5-Second
    Previews on; the card opens under the link with fake-ai.py's answer card (Arc's title and four details). With Shift
    held Brk's plain link card stays away."""
    fixture_today(b)
    max_feature(b, 'linkPreviews', True); max_switch(b, 'tidyTabs', True); theme_on = theme(b, SKY); theme_on.__enter__()
    try:
        b.focus('Visual fixture'); b.front(); key('down', 'shift')
        # Brk gives the preview's hidden page 5 s to load; on a busy machine it can miss that and the card says so:
        # the hover is tried again from scratch, up to three times
        for attempt in (1, 2, 3):
            mouse('move', 1100, 700); sleep(1.0); mouse('move', 760, 157); sleep(0.2); mouse('move', 764, 157)
            deadline = time.time() + 15
            card = None
            while time.time() < deadline:
                card = b.view().get('aiPreview')
                if card and not card.get('busy'): break
                sleep(0.3)
            if card and 'Synthetic page' in (card.get('title') or ''): break
            print(f'[scenes] P45: preview attempt {attempt} ended without the summary: {json.dumps(card)[:200] if card else None}', flush=True)
        sleep(0.8); out('a', 'window')
    finally:
        key('up', 'shift'); away(); max_feature(b, 'linkPreviews', False); max_switch(b, 'tidyTabs', False); theme_on.__exit__()

@scene('P46')
def _(b, out):
    """Today with more than six tabs: Arc opened Design notes, Docs and Interaction states above the four fixture tabs
    (Design notes selected), Max's Tidy Tabs on. a: as opened; b: the pointer on the Today divider, where Arc shows
    Tidy (49 points left of Clear's centre) and Brk now does too; c: a click on Tidy (fake-ai.py's plan: Design and
    Reading groups and the undo toast). Undone after."""
    fixture_today(b)
    max_switch(b, 'tidyTabs', True); theme_on = theme(b, SKY); theme_on.__enter__()
    try:
        for page in ('interaction', 'docs', 'design'):
            b.send({'load': {'window': b.main, 'url': SITE + page + '.html'}}); sleep(0.8)
        wait_titles(b, ('Design notes', 'Docs', 'Interaction states')); sleep(1.5); away(); out('a', 'window')
        act = _native(b)['actual']; clear = act.get('today-clear')
        if clear and clear.get('frame'):
            (cx, cy), (cw, ch) = clear['frame']; px, py = X0 + cx + cw / 2 - 49, Y0 + cy + ch / 2
        else:
            (sx, sy), (sw, sh) = act['section-today']['frame']; px, py = X0 + 147, Y0 + sy
        tidy = _native(b)['actual'].get('today-tidy')
        if tidy and tidy.get('frame'):
            (tx, ty), (tw, th) = tidy['frame']; px, py = X0 + tx + tw / 2, Y0 + ty + th / 2
        print(f'[scenes] P46 b: pointer on Tidy at {px},{py} (Tidy {tidy and tidy.get("frame")}, Clear {clear and clear.get("frame")})', flush=True)
        # The tooltip needs the pointer to rest: Arc's reference shows Organize Today Tabs under it.
        # Along the divider first, as a hand does: Tidy only takes the pointer once the divider has shown it.
        b.front(); mouse('move', px - 60, py); sleep(0.4); mouse('move', px - 4, py); sleep(0.3); mouse('move', px, py); sleep(4); out('b', 'window')
        mouse('click', px, py)
        deadline = time.time() + 15
        while time.time() < deadline:
            rows = b.view()['space']['today']['rows']
            if rows and 'folder' in rows[0]: break
            sleep(0.3)
        sleep(1.0); away(); out('c', 'window')
    finally:
        try: b.dispatch({'assist': {'_0': {'undoOrganize': {}}}}); sleep(0.5)
        except Exception: pass
        max_switch(b, 'tidyTabs', False); theme_on.__exit__()

@scene('P47')
def _(b, out):
    """Tidy Tab Titles. Arc: Long title for truncation… dragged into Pinned under Home (and selected) became Sidebar
    Ellipsis within about five seconds. a: the same drag with the real pointer, Max's Tidy Tab Titles on, captured six
    seconds after the drop. pin (Brk-only): the tab pinned with Pin Tab instead, Brk's path that asks fake-ai.py for
    the title. Afterwards the tab goes back to Today under Inbox with its own title."""
    fixture_today(b)
    theme_on = theme(b, SKY); theme_on.__enter__()   # the reference P47-a (not retaken) has the pale blue theme and Max on
    max_switch(b, 'tidyTabs', True)
    tab = b.find(TODAY[1], 'today'); home = b.find('Home', 'pinned')
    today_root = b.view()['space']['today']['root']; pinned_root = b.view()['space']['pinned']['root']
    max_switch(b, 'renamePinnedTabs', True)
    try:
        b.focus(TODAY[1]); sleep(0.6)
        act = _native(b)['actual']
        (sx, sy), (sw, sh) = act['row-' + tab]['frame']; (hx, hy), (hw, hh) = act['row-' + home]['frame']
        docs = act.get('row-' + b.find('Docs', 'pinned'), {}).get('frame')
        drop_y = (hy + hh + docs[0][1]) / 2 if docs else hy + hh + 4
        b.front(); mouse('drag', X0 + sx + 60, Y0 + sy + sh / 2, X0 + hx + 60, Y0 + drop_y, 0.4); sleep(0.8); away()
        if not any(i == tab for kind, t, i, d in b.rows('pinned')):
            print('[scenes] P47: the drag did not land in Pinned; moved there instead', flush=True)
            b.dispatch({'item': {'_0': {'move': {'_0': tab, 'to': {'into': {'parent': pinned_root, 'index': 1}}}}}})
        sleep(6); out('a', 'window')
        b.dispatch({'item': {'_0': {'move': {'_0': tab, 'to': {'into': {'parent': today_root, 'index': 1}}}}}})
        b.dispatch({'item': {'_0': {'rename': {'_0': tab, 'title': ''}}}}); sleep(0.5)
        b.dispatch({'tab': {'_0': {'togglePin': {'_0': {'item': {'_0': tab}}}}}})
        deadline = time.time() + 8
        while time.time() < deadline and not any(i == tab and t == 'Sidebar Ellipsis' for kind, t, i, d in b.rows('pinned')): sleep(0.3)
        sleep(0.6); away(); out('pin', 'window')
    finally:
        max_switch(b, 'renamePinnedTabs', False); max_switch(b, 'tidyTabs', False); theme_on.__exit__()
        b.dispatch({'item': {'_0': {'move': {'_0': tab, 'to': {'into': {'parent': today_root, 'index': 1}}}}}})
        b.dispatch({'item': {'_0': {'rename': {'_0': tab, 'title': ''}}}})

@scene('P48')
def _(b, out):
    """Instant Links. Arc: wikipedia arc browser in the command bar, Shift+Enter; the bar closes and a Searching the web
    for you… row heads Today while Max looks. Brk (R4-11) the same: Cmd+T, the words, Shift+Return; fake-ai.py holds its
    answer back, so the row stays; afterwards the row's search is closed."""
    fixture_today(b)
    max_feature(b, 'instantLinks', True); max_switch(b, 'tidyTabs', True); theme_on = theme(b, SKY); theme_on.__enter__()
    try:
        b.front(); key('tap', 't', 'command'); sleep(1.0)
        b.type('wikipedia arc browser'); sleep(0.8); key('tap', 'return', 'shift')
        deadline = time.time() + 6
        while time.time() < deadline:
            rows = b.view()['space']['today']['rows']
            if rows and (rows[0].get('tab') or {}).get('_0', {}).get('instant'): break
            sleep(0.3)
        sleep(1.5); away(); out('a', 'window')
    finally:
        try:
            for row in b.view()['space']['today']['rows']:
                tab = (row.get('tab') or {}).get('_0', {})
                if tab.get('instant'): b.dispatch({'tabTools': {'_0': {'bulk': {'_0': {'items': {'_0': [tab['id']]}}, '_1': {'close': {}}}}}})
        except Exception as e: print(f'[scenes] P48: closing the row failed: {e}', flush=True)
        max_feature(b, 'instantLinks', False); max_switch(b, 'tidyTabs', False); theme_on.__exit__()
        try: b.dispatch({'commandBar': {'_0': {'dismiss': {}}}})
        except Exception: pass

@scene('P49')
def _(b, out):
    """A question in the command bar (Cmd+T, how do browsers render fonts). Arc 1.170 lists the search suggestions and
    one Ask ChatGPT → row. Brk with Max's Ask in Command Bar on, typed the same way; Arc's file is P49-cmd."""
    fixture_today(b)
    max_feature(b, 'commandBar', True); max_switch(b, 'tidyTabs', True); theme_on = theme(b, SKY); theme_on.__enter__()
    try:
        b.front(); key('tap', 't', 'command'); sleep(1.2); b.type('how do browsers render fonts'); sleep(2.0); away()
        out('cmd', 'region')
    finally:
        key('tap', 'escape'); sleep(0.4); max_feature(b, 'commandBar', False); max_switch(b, 'tidyTabs', False); theme_on.__exit__()

@scene('P50')
def _(b, out):
    """Translation of the Visual fixture page (French: Bonjour Monde), R4-11's entry points as Arc's: b: the page
    menu's Translate to English (chosen in process through captureContextMenu), the page turns English and the pill's
    second line reads Translated; c: the pointer on that line (underlined); d: a click on it opens the Translated from
    French popover (Arc's shot runs 78 points left of the window); f: the popover's Options menu with Choose Another
    Language open (120 points left); e: Use Original, the French back and Arc's toast."""
    fixture_today(b)
    max_feature(b, 'translation', True); max_switch(b, 'tidyTabs', True); theme_on = theme(b, SKY); theme_on.__enter__()
    translated = False
    try:
        sleep(0.5)
        card = _native(b)['computed']['cards'][0]['rect']
        (cx, cy), (cw, ch) = card
        b.send({'captureContextMenu': {'window': b.main, 'point': [cx + cw * 0.6, cy + 115], 'choose': 'Translate to English'}})
        translated = True
        deadline = time.time() + 20
        while time.time() < deadline:
            line = (b.view().get('urlPill') or {}).get('translation') or {}
            if 'translated' in line: break
            sleep(0.3)
        sleep(1.0); away()
        out('b', 'window')
        (px, py), (pw, ph) = _native(b)['actual']['url-pill']['frame']
        b.front(); mouse('move', X0 + px + 42, Y0 + py + 35); sleep(0.3); mouse('move', X0 + px + 42, Y0 + py + 25); sleep(1.2)
        out('c', 'window')
        mouse('click', X0 + px + 42, Y0 + py + 25); sleep(1.2); cap_region(out.path('d'), X0 - 78, Y0, W + 78, H); out.note('d')
        # The popover's body (237 x 101) is centred under the line's middle; Options and Use Original sit 58.5 into it.
        body_x, body_y = X0 + px + 42 - 118.5, Y0 + py + 25 + 18
        mouse('click', body_x + 62.5, body_y + 74.5); sleep(0.8)
        # Arc's reference has the first row hovered and its languages open: the row is centred at y 178 of the window
        mouse('move', X0 + 105, Y0 + 178); sleep(0.3); mouse('move', X0 + 108, Y0 + 178); sleep(1.5)
        cap_region(out.path('f'), X0 - 120, Y0, W + 120, H); out.note('f')
        key('tap', 'escape'); sleep(0.3); key('tap', 'escape'); sleep(0.5)
        # A click right after the menus close can be taken as closing the popover: try until the page is back.
        for attempt in range(3):
            if not any('Popover' in w.get('className', '') and w.get('isVisible') for w in _native(b).get('appWindows', [])):
                mouse('click', X0 + px + 42, Y0 + py + 25); sleep(1.0)
            mouse('click', body_x + 174.5, body_y + 74.5); sleep(1.0)
            if 'translated' not in ((b.view().get('urlPill') or {}).get('translation') or {}): break
            print(f'[scenes] P50 e: Use Original attempt {attempt + 1} left the page translated', flush=True)
        away()
        translated = False; out('e', 'window')
    finally:
        if translated: b.dispatch({'page': {'_0': {'reload': {'_0': {'focused': {}}, 'ignoringCache': False}}}}); sleep(1.5)
        max_feature(b, 'translation', False); max_switch(b, 'tidyTabs', False); theme_on.__exit__()
        try: b.dispatch({'commandBar': {'_0': {'dismiss': {}}}})
        except Exception: pass

class Out:
    def __init__(self, b, scene, outdir): self.b, self.scene, self.outdir, self.done = b, scene, outdir, []
    def path(self, letter):
        if letter.startswith('P') and len(letter) > 3 and letter[1:3].isdigit(): return os.path.join(self.outdir, f'{letter[:3]}-{letter[3:]}-brk.png')
        return os.path.join(self.outdir, f'{self.scene}-{letter}-brk.png')
    def note(self, letter): self.done.append(letter)
    def __call__(self, letter, kind):
        p = self.path(letter)
        {'window': lambda: cap_window(self.b, p), 'region': lambda: cap_stack(self.b, p), 'menu': lambda: cap_menu(self.b, p)}[kind]()
        self.note(letter)

# Arc's list in P49-cmd: its engine returned the question itself and these three (R5-2).
ARC_SUGGESTIONS = {'how do browsers render fonts': ['how do browsers render fonts', 'how do browsers render text', 'browser font rendering', 'how do browsers render html']}
def suggest_fixture():
    """A local endpoint for BRK_SUGGEST_URL: the three suggestions Arc's P49-cmd shows for its question, the real engine
    for every other query (Q01, P02 keep what they had), an empty list when that cannot be reached."""
    import http.server, threading, urllib.parse
    class Handler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            q = urllib.parse.parse_qs(urllib.parse.urlparse(self.path).query).get('q', [''])[0]
            if q in ARC_SUGGESTIONS: body = json.dumps([q, ARC_SUGGESTIONS[q]]).encode()
            else:
                try: body = urllib.request.urlopen('https://suggestqueries.google.com/complete/search?client=firefox&q=' + urllib.parse.quote(q), timeout=3).read()
                except Exception: body = json.dumps([q, []]).encode()
            self.send_response(200); self.send_header('Content-Type', 'application/json'); self.end_headers(); self.wfile.write(body)
        def log_message(self, *a): pass
    server = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    return f'http://127.0.0.1:{server.server_address[1]}/suggest'

def https_fixture(work):
    """The https fixture (Tests/Fixtures/https-fixture/serve.py) at https://127.0.0.1:8781/: the one already
    running there, else one started here on 8781/8782 (on free ports when those are taken). (base URL, process or None)."""
    def answers(base):
        try:
            context = ssl.create_default_context(); context.check_hostname = False; context.verify_mode = ssl.CERT_NONE
            return urllib.request.urlopen(base + 'secure.html', timeout=3, context=context).status == 200
        except Exception: return False
    if answers('https://127.0.0.1:8781/'): return 'https://127.0.0.1:8781/', None
    ready = os.path.join(work, 'https-ready.json')
    for ports in (('8781', '8782'), ('0', '0')):
        if os.path.exists(ready): os.remove(ready)
        proc = subprocess.Popen([sys.executable, '-I', os.path.join(HTTPS_DIR, 'serve.py'), '--port', ports[0], '--http-port', ports[1], '--ready', ready],
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        deadline = time.time() + 5
        while time.time() < deadline and not os.path.exists(ready) and proc.poll() is None: sleep(0.1)
        if os.path.exists(ready):
            base = f'https://127.0.0.1:{json.load(open(ready))["https"]}/'
            if answers(base): return base, proc
        proc.terminate()
    return None, None

# ---- Q18: the Library and the sidebar under Arc's navy preset (the dark presets' page, 9th swatch, the slider where
# Arc's reference had it: Brk's intensity 0.25), the Clear label by where the current tab is, the current Favorite's rim.
NAVY_THEME = dict(FIXTURE_THEME, colors=[{'red': 0x2D / 255, 'green': 0x44 / 255, 'blue': 0x68 / 255, 'alpha': 1}])

def _q18_navy(b, out):
    set_theme_doc(b, NAVY_THEME)
    try:
        b.focus('Visual fixture'); b.front(); away(); sleep(0.8); out('navy-window', 'window'); out('navy-window-flat', 'window')
        # the pointer on a Today row and on the divider, as in Arc's two hover pictures
        mouse('move', X0 + 100, Y0 + row_center(b, 'Long title for truncation and readable sidebar ellipsis')[1]); sleep(0.8); cut(b, out, 'navy-row-hover', 236, 776)
        mouse('move', X0 + 100, Y0 + 396); sleep(0.8); cut(b, out, 'navy-divider-hover', 236, 776); away()
        for name, page in (('media', 'media'), ('downloads', 'downloads'), ('spaces', 'spaces')):
            b.dispatch({'library': {'_0': {'open': {'_0': page}}}}); sleep(1.5); b.front(); mouse('move', X0 + 24, Y0 + 752); sleep(0.5); out('navy-library-' + name, 'window')
        # two Untitled Easels and the archived tabs, as for P32
        for _n in range(2):
            b.dispatch({'easel': {'_0': {'create': {}}}}); sleep(0.4)
        made = easel_ids(b)
        for kind, t, i, d in b.rows('pinned'):
            if (d.get('url') or '').startswith('brk://easel/'): b.dispatch({'tab': {'_0': {'archive': {'_0': {'item': {'_0': i}}}}}})
        b.focus('Visual fixture'); sleep(0.6)
        b.dispatch({'library': {'_0': {'open': {'_0': 'easelsAndNotes'}}}}); sleep(1.5); b.front(); mouse('move', X0 + 24, Y0 + 752); sleep(0.5); out('navy-library-easels', 'window')
        for eid in made: delete_easel(b, eid)
        b.dispatch({'library': {'_0': {'close': {}}}}); b.dispatch({'archive': {'_0': {'clear': {}}}})
        archive_pages(b, ARC_ARCHIVE); sleep(0.6)
        b.dispatch({'library': {'_0': {'open': {'_0': 'archive'}}}}); sleep(1.5); b.front(); mouse('move', X0 + 24, Y0 + 752); sleep(0.5); out('navy-library-archive', 'window')
        b.dispatch({'library': {'_0': {'open': {'_0': 'media'}}}}); b.dispatch({'library': {'_0': {'close': {}}}})
    finally:
        reset_theme(b, '对照')
        try: b.dispatch({'archive': {'_0': {'clear': {}}}})
        except Exception: pass

def _q18_clear(b, out):
    def label_center():
        k, v = b.send({'native': {'window': b.main}})
        (x, y), (w, h) = v['_0']['actual']['today-clear']['frame']
        return X0 + int(x + w - 12), Y0 + int(y + h / 2)
    tiles = b.view()['favorites']['tiles']
    with theme(b, SKY):
        b.focus('Visual fixture'); b.front(); mouse('move', X0 + 100, Y0 + 660); sleep(0.8); cut(b, out, 'clear-today-current', 236, 776)
        mouse('move', *label_center()); sleep(2.6); cut(b, out, 'clear-today-current-on-label', 236, 776)
        b.focus('Home'); mouse('move', X0 + 100, Y0 + 660); sleep(0.8); cut(b, out, 'clear-pinned-current-resting', 236, 776)
        mouse('move', *label_center()); sleep(2.6); cut(b, out, 'clear-pinned-current-on-label', 236, 776); cut(b, out, 'clear-pinned-current', 236, 776)
        b.dispatch({'tab': {'_0': {'focus': {'_0': tiles[2]['id']}}}}); sleep(1.5)
        mouse('move', X0 + 100, Y0 + 660); sleep(0.8); cut(b, out, 'clear-favorite-current', 236, 776)
        away(); sleep(0.8); cut(b, out, 'ring-github-current', 236, 776)
        b.focus('Visual fixture'); away()

@scene('Q18')
def _(b, out):
    # Two tasks each registered a Q18 scene and the later one replaced the earlier: the media part did not run in the
    # first whole-main station after both merged (main aaa431a1). One scene now, the baseline restored in between.
    _q18_media(b, out)
    baseline(b)
    _q18_clear(b, out)
    _q18_navy(b, out)

# ---- Q19: the Space swipe as Arc's does it (r5-7). The gestures are the ones Arc's references were taken under: real scroll
# events at the same spot, the column held with the fingers down. Arc's Space 1 has Arc's lavender theme and 对照 its pale blue.
LAVENDER = [{'red': 0xC7 / 255, 'green': 0xC9 / 255, 'blue': 0xF0 / 255, 'alpha': 1}, {'red': 0xE2 / 255, 'green': 0xD3 / 255, 'blue': 0xD9 / 255, 'alpha': 1}]
@scene('Q19')
def _(b, out):
    def steps(dx, n): return ';'.join([f'{dx},0'] * n)
    def gest(*args): sh(os.path.join(BIN, 'gest'), '420', '710', '16', *[str(a) for a in args])
    def held(letter): out.note(letter); return ['--wait', '0.3', '--shot', out.path(letter), str(b.main_wid())]
    fixture = fixture_state()['doc']['spaces']
    first = b.view()['dock'][0]['id']
    theme_doc = dict(fixture[first]['theme']); original = dict(theme_doc)
    theme_doc['colors'] = LAVENDER
    b.dispatch({'space': {'_0': {'update': {'_0': first, 'theme': theme_doc}}}})
    with theme(b, SKY):
        b.front(); mouse('move', 420, 710); sleep(0.5)
        gest('--may', '--began', '4,0', steps(15, 10), *held('mid-right-150'), steps(15, 10), *held('mid-right-300'), steps(15, 8), *held('mid-right-420'), steps(-15, 28), '--wait', '0.5', '--end')
        sleep(1)
        gest('--may', '--began', '-4,0', steps(-15, 14), *held('edge-210'), steps(-15, 7), '-5,0', *held('edge-320'), steps(15, 21), '5,0', steps(15, 14), '--wait', '0.5', '--end')
        sleep(1)
        gest('--may', '--began', '-4,0', steps(-15, 27), *held('edge-armed-405'), '--wait', '0.1', '--end')
        sleep(1.5); out('edge-create-space', 'window')
        # The drawn Cancel button with the real mouse: the flow the gesture opened leaves as any other.
        mouse('click', 320 + 114, 70 + 702); sleep(0.8)
        if b.view().get('dialog'): raise RuntimeError('Cancel did not close Create a Space')
        mouse('move', 420, 710); sleep(0.3)
        # To Space 1, and toward the Library from there.
        gest('--may', '--began', '4,0', steps(15, 6), '--end')
        sleep(1.2); out('space1', 'window')
        gest('--may', '--began', '4,0', steps(15, 7), *held('library-105'), steps(15, 7), *held('library-210'), steps(15, 6), *held('library-300'),
             steps(15, 20), *held('library-600'), steps(15, 16), *held('library-840'), steps(-15, 56), '--wait', '0.5', '--end')
        sleep(1.2)
        gest('--may', '--began', '4,0', steps(15, 6), '--end')
        sleep(1.2); out('library-open', 'window')
        gest('--may', '--began', '-4,0', steps(-15, 6), '--end')
        sleep(1.2)
        gest('--may', '--began', '-4,0', steps(-15, 6), '--end')
        sleep(1.2)
        if os.environ.get('Q19_RECORD'):
            # The settles Arc was recorded under (Q19/arc-frames), for tools like r5-7/tools/framepos.swift.
            def record(name, run):
                rec = subprocess.Popen(['screencapture', '-x', '-v', '-V', '4', '-R320,70,360,776', out.path(name).replace('.png', '.mov')])
                sleep(1.5); run(); rec.wait()
            record('settle-c3', lambda: gest('--may', '--began', '4,0', steps(15, 6), '--wait', '0.4', '--end'))
            record('settle-h1', lambda: gest('--may', '--began', '4,0', steps(15, 6), '--end'))
            record('settle-h2', lambda: gest('--may', '--began', '-4,0', steps(-15, 6), '--end'))
            record('settle-k1', lambda: key('tap', 'left', 'option,command'))
            record('settle-k2', lambda: key('tap', 'right', 'option,command'))
    b.dispatch({'space': {'_0': {'update': {'_0': first, 'theme': original}}}})

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('app'); ap.add_argument('outdir'); ap.add_argument('--scenes', default='all'); ap.add_argument('--list', action='store_true'); ap.add_argument('--keep', action='store_true')
    a = ap.parse_args()
    if a.list: print(' '.join(SCENES)); return
    wanted = list(SCENES) if a.scenes == 'all' else [s[:3] for s in a.scenes.split(',')]
    wanted = list(dict.fromkeys(wanted))
    os.makedirs(a.outdir, exist_ok=True)
    sh(os.path.join(HERE, 'build-helpers.sh'))
    work = os.path.join('/tmp', f'brk-scenes-{os.getpid()}'); os.makedirs(work, exist_ok=True)
    global GITHUB_FIXTURE
    feed = os.path.join(work, 'github', 'repos', 'fixture', 'repo'); os.makedirs(feed, exist_ok=True)
    with open(os.path.join(feed, 'notifications'), 'w') as f: f.write('[{"unread":true},{"unread":true},{"unread":true}]')
    probe = socket.socket(); probe.bind(('127.0.0.1', 0)); port = probe.getsockname()[1]; probe.close()
    github = subprocess.Popen([sys.executable, '-m', 'http.server', str(port), '--bind', '127.0.0.1', '--directory', os.path.join(work, 'github')],
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    GITHUB_FIXTURE = f'http://127.0.0.1:{port}/'
    global SUGGEST_FIXTURE
    SUGGEST_FIXTURE = suggest_fixture()
    global HTTPS_FIXTURE
    https = None
    if 'P36' in wanted:
        HTTPS_FIXTURE, https = https_fixture(work)
        print(f'[scenes] https fixture {HTTPS_FIXTURE or "unavailable"}{" (started here)" if https else ""}', flush=True)

    b = Brk(a.app, work); report = {}
    try:
        b.launch(); baseline(b); warm(b); baseline(b)
        for name in wanted:
            fn = SCENES.get(name)
            if not fn: report[name] = 'unknown scene'; continue
            out = Out(b, name, a.outdir)
            try:
                fn(b, out); report[name] = 'ok ' + ' '.join(out.done)
            except Exception as e:
                report[name] = f'FAILED {e}'
            print(f'[scenes] {name}: {report[name]}', flush=True)
            try: baseline(b)
            except Exception as e: print(f'[scenes] baseline after {name}: {e}', flush=True)
    finally:
        b.report_shortcut()
        b.quit()
        github.terminate()
        if https: https.terminate()
        try: shutil.copy(os.path.join(work, 'app.log'), os.path.join(a.outdir, 'app.log'))
        except OSError: pass
        if not a.keep: shutil.rmtree(work, ignore_errors=True)
    json.dump(report, open(os.path.join(a.outdir, 'scenes.json'), 'w'), indent=1, ensure_ascii=False)
    bad = [k for k, v in report.items() if not v.startswith('ok')]
    print(f'[scenes] {len(report) - len(bad)} scenes captured, {len(bad)} failed: {" ".join(bad)}')

if __name__ == '__main__': main()
