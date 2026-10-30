# Arc shell spike: results on a real display (2026-10-30)

Machine: macOS 26.6.2, display 3840x2160 at 2x (1920x1080 pt). CEF 154.0.34 / Chromium 154.0.8037.98 (minimal, arm64).
Both apps were run and driven from this shell through `ctl.sh`; every screenshot below is either the app's own
`screenshot` (CGWindowListCreateImage of its window) or a real `screencapture -x` of the whole screen.
All evidence is in `shots/` (`*.txt` = console output of the scripts in `tools/`, `*.png` = images, `*.log` = app logs,
`crash-*.ips` = crash reports). Every check is a script in `tools/` that can be re-run:

| script | what it does |
|---|---|
| `tools/launch-check.sh a\|b App tag` | launch, time to first `metrics` answer, geometry, own-window screenshot, real-screen corner check, real click/scroll (CGEvent) + injected key |
| `tools/corners.py metrics.json screen.png` | converts `metrics` window/card frames to screen pixels and samples 1 px inside each card corner (must be gradient) and 16 px inside (must be page) |
| `tools/u2-bar.sh`, `u3-keys.sh`, `u4-split.sh`, `u5-chrome.sh`, `u6-titlebar.sh` | unknowns 2 to 6 |
| `tools/bar-over-page.sh`, `resize-drag.sh`, `viewport-lag.sh`, `tail-check.sh` | bar visibility on the real screen, mouse drag-resize, viewport after a one-step resize, process model + unsplit + quit |
| `tools/mouse` (CGEvent click/scroll/drag), `tools/pix` (read PNG pixels), `tools/ax.sh` (System Events resize/move by window title) | helpers |

Modes: **A** = Alloy runtime, CEF view inside our NSView. **B embed** = Chrome runtime, Chromium's two page views moved
into our card (default). **B child** = Chrome runtime, CEF window kept as a child window over the card (`SPIKE_HOST=child`).

## Table

| # | Unknown | Mode A (Alloy) | Mode B embed | Mode B child |
|---|---|---|---|---|
| 1 | Rounded card clips the page; page takes clicks and scroll | **VERIFIED** `a-01-single-screen.png`, `a-01-corner-bl-zoom.png`, `a-07-split-resized-corners.txt` (PASS), `a-u4-split.txt` | **VERIFIED** `b-01-corners.txt` (PASS), `b-01-single-screen.png`, `b-launch-check.txt` | **NOT VERIFIED** `b-child-01-corners.txt` (FAIL), `b-child-u4-split.txt`: page paints over the card toolbar and outside the corners |
| 2 | Native bar over the page, takes focus, focus returns | **VERIFIED** `a-u2-bar.txt`, `a-04-bar-view-app.png`, `a-05-bar-panel-screen-crop.png` | **VERIFIED** `b-u2-bar.txt`, `b-20-bar-view-crop.png` | **NOT VERIFIED** (in-window view hidden behind the page: `b-child-20-bar-view-crop.png` blank); NSPanel variant works `b-child-20-bar-panel-crop.png` |
| 3 | Key routing cmd+T/S/W, priority, swallow page, typing | **VERIFIED** `a-u3-keys.txt`, `a-pass2.txt` | **VERIFIED** `b-u3-keys.txt` (same log order) | **VERIFIED** `b-child-u3-keys.txt` |
| 4 | Split, both pages live, live resize | **VERIFIED** `a-u4-split.txt`, `a-06-split-app.png`, `a-07-split-resized-screen.png` | **VERIFIED** `b-u4-split-run2.txt`, `b-resize-drag.txt`, `b-viewport-lag.txt`, `b-06-split-app.png` | **NOT VERIFIED** `b-child-viewport-lag.txt`: page size lags one layout behind; split corners FAIL |
| 5 | chrome://version, chrome://extensions | **NOT VERIFIED** (expected): version OK, extensions `ERR_ABORTED` `a-u5-chrome.txt`, `a-09-version-app.png` | **VERIFIED** both render `b-u5-chrome.txt`, `b-09-extensions-app.png` | **VERIFIED** `b-child-u5-chrome.txt` |
| 6 | Traffic lights over the sidebar, transparent title bar, vibrancy, drag | **VERIFIED** `a-u6-titlebar.txt` (run 2 in `a-pass2.txt`), `a-10-titlebar-zoom.png`, `a-11-vibrancy-*-sidebar.png`, `a-pass3.txt` (drag) | **VERIFIED** `b-u6-titlebar.txt`, `b-10-titlebar-zoom.png`, `b-11-vibrancy-*` | **INCONCLUSIVE** (not re-run; our window is never key, traffic lights draw inactive: `b-child-01-single-app.png`) |
| 7 | Processes, memory with two pages, launch time | **VERIFIED** `a-pass3.txt`, `a-u7-process.txt`; 0 crashes | **VERIFIED** `b-tail-check.txt`, `b-launch-check.txt`; **crashes at quit every run** `crash-ModeB-*.ips` | **VERIFIED** `b-child-tail-check.txt`; crashes at quit too |
| 8 | `screenshot` without permission; `metrics` frames match the screen | **VERIFIED** `a-14-open-launched-app.png` (launched by `open`, preflight false, page pixels present), `corners.py` PASS runs | **VERIFIED** `b-launch-check.txt`, `b-01-corners.txt` | **NOT VERIFIED** own-window capture misses the page (`b-child-01-single-app.png` empty card) |

Extra finding, Mode A only: **closing a page closes the whole window** (`a-pass2.txt`, `a-13-after-unsplit-screen.png`,
`a-15-after-unsplit-screen.png`). Mode B: every instance **segfaults on quit** (5 of 5, embed and child; never during a test).

## Evidence per unknown

### 1. Rounded card, clicks, scroll
- Command: `tools/launch-check.sh a ModeA a` / `... b ModeB b` / `SPIKE_HOST=child ... b-child`; `tools/corners.py` on the
  real `screencapture -x` image using the app's `metrics` frames (window 120,120 1400x900; card 0 at 338,10 1052x880, radius 6).
- A: real screen pixel 1 px inside the bottom-left corner = (176,147,104) gradient, 16 px inside = (255,254,255) page;
  all 8 samples PASS, also after a live resize (`a-07-split-resized-corners.txt`) and with `variant radius 10 / inset 8`
  (`a-pass2.txt`: "corner check radius 10 inset 8: RESULT PASS"). App's own `sample 339 889` = (174,144,100), `sample 346 882` = white.
  Real click (CGEvent at screen 700,250) -> page title `click:242,148:TEXTAREA`; real scroll wheel -> `scroll:600`;
  `key a` -> log `page0 title: key:a:seen` + `console page0: page keydown a`.
- B embed: `movedViews` = `ViewsCompositorSuperview window=309`, `WebContentsViewCocoa window=309` (our window);
  corner check PASS, click `click:242,148:TEXTAREA`, scroll `scroll:600`, key `key:a:seen` (`b-launch-check.txt`).
- B child: click/scroll/key work, but the CEF child window is 912 pt tall for an 848 pt web area, so it covers the card's
  toolbar (split check: "card 1 top-left inside(16px) rgb=[229,123,33]" = Hacker News orange where the toolbar should be) and
  the page is not clipped at the corners ("bottom-right outside(1px) rgb=[239,239,239]"). `b-child-01-corners.txt`: RESULT FAIL.

### 2. Native bar over the page
- Command: `tools/u2-bar.sh`. A and B embed, identical: `showbar` -> `firstResponder=NSTextView in window <ours>`;
  `key a`,`key b` -> page title stays `spike page 0`; `hidebar` -> `RenderWidgetHostViewCocoa`; `key b` -> `key:b:seen`;
  `showbar panel` -> `panelIsKey True`, keyWindow = `KeyablePanel`; `hidebar` -> keyWindow `isOurs True`; `key c` -> `key:c:seen`.
  Bar drawn above the page: `a-04-bar-view-app.png`, `b-20-bar-view-crop.png` (real screen crop).
- B child: focus moves the same way, but the in-window bar is invisible (the CEF child window sits above our content view):
  `b-child-20-bar-view-crop.png` is blank page. The NSPanel variant is visible (`b-child-20-bar-panel-crop.png`).

### 3. Keyboard routing (`tools/u3-keys.sh`, same result in A, B embed, B child)
- priority on, test page, `key cmd+t` and real `osascript keystroke "t" using command down`:
  `inject` -> `cef.pre page0 cmd+t consumed=true` -> `ACTION cmd+t via cef.pre`; no `page keydown` console line, title unchanged.
  Same for cmd+s (sidebar toggles) and cmd+w.
- priority off, test page: `cef.pre consumed=false` -> `console page0: page keydown cmd+t` -> `cef.post consumed=true` ->
  `ACTION via cef.post`. The AppKit menu never fired (no `via menu`), so no double action.
- priority off, test-swallow page (preventDefault): `cef.pre consumed=false` -> `page keydown cmd+t swallowed` -> nothing else:
  the page swallows the app shortcut (no cef.post, no menu). priority on + test-swallow: `cef.pre` takes it, page never sees it.
- Plain typing: injected `h`,`i`,`shift+x` + real `keystroke "ok"` -> textarea value `"hiXok"`.
- `window.sendEvent` never logged a cmd keyDown in any run (0 lines in every log): CEF's NSApplication subclass hands the
  key to the Chromium view before our NSWindow.sendEvent. With the native bar field focused the menu path fires
  (`ACTION cmd+t via menu`, `a-pass2.txt`).

### 4. Split and live resize (`tools/u4-split.sh`, `resize-drag.sh`, `viewport-lag.sh`)
- A: two cards 521 wide, gap 10, page 1 `key:x:seen`; System Events resize to 1100x700 -> cards 371x680,
  `CefBrowserHostView` 371x648; corner check PASS; 1600x1000 (clamped to 929 by the Dock) PASS; back to 1400x900, page 1 `key:z:seen`.
- B embed: same with the window picked by title (`tools/ax.sh`); real mouse drag of the bottom-right corner 1400x900 -> 1200x750,
  corner check PASS (`b-resize-drag.txt`); page viewport right after a one-step resize = `752x648` = card web area
  (`b-viewport-lag.txt`). The emptied CEF host window's frame lags one layout call behind (harmless, it is empty).
- B child: the CEF window (and so the page) lags one layout pass: after 1100x700 the page still reports `1052x848`;
  after another layout it reports the previous target (`1080x648`); split corner checks FAIL (`b-child-viewport-lag.txt`, `b-child-u4-split.txt`).

### 5. Chrome runtime pages (`tools/u5-chrome.sh`)
- A: `chrome://version` renders (title `About Version`, body "CEF 154.0.34..."); `chrome://extensions` -> `load failed -3 ERR_ABORTED`.
- B (embed and child): both render; extensions page title `Extensions`, `extensions-manager` element present, Developer mode
  toggle visible (`b-09-extensions-app.png`). Loading an unpacked extension was not exercised.

### 6. Title bar (`tools/u6-titlebar.sh`)
- `metrics.trafficLights`: x 13/37/61, 14x14, superview `NSTitlebarView`, centre 24.0 pt from the top; `fullSizeContentView true`,
  `titlebarAppearsTransparent true`; crops `a-10-titlebar-zoom.png`, `b-10-titlebar-zoom.png` show lights over the sidebar, no title strip.
- Vibrancy measured on the real screen at sidebar point (150,600): `within` (229,222,217), `behind` (214,229,231) = blurred desktop,
  `none` (129,98,77) = bare gradient (`a-pass2.txt`, `b-u6-titlebar.txt`, `*-11-vibrancy-*-sidebar.png`).
- Drag with a real mouse drag from the title row over the sidebar (x 200, y 24): window x moved +150 exactly, y clamped by the
  Dock / menu bar (`a-pass3.txt`: 120,120 -> 270,150; `b-u6-titlebar.txt`). Dragging the sidebar body (y 600) does not move the window.

### 7. Process model
- A (`a-pass3.txt`): launch -> first `metrics` answer 1215 ms; `windowShownMs` 99, `firstLoadMs` 976. One page: 6 helpers, 544 MB.
  Two pages (example.com + Hacker News): browser footprint 127 MB + 3 `ModeA Helper` (102/83/66 MB) + 3 renderers (123/111/87 MB)
  = 700 MB. Bundle 326 MB. No crash reports.
- B embed (`b-launch-check.txt`, `b-tail-check.txt`): first launch 4305 ms to the first answer (profile creation), later launches 1.2-1.3 s;
  `windowShownMs` 109, `firstLoadMs` 1128; one page 578 MB; two pages 8 helpers, 854 MB (browser 138 MB).
  Every ModeB process (5/5: pids 94793, 96688, 97207, 98432, 98547) died with `EXC_BAD_ACCESS` on `CrBrowserMain` 0.5-4 s after its
  last command, i.e. during `quit` (NSApp.terminate -> CEF shutdown). Reports in `shots/crash-ModeB-*.ips`, stdout in `shots/b-*-stdout.txt`.

### 8. Control channel
- `screenshot` reply `method: CGWindowListCreateImage`, 2800x1800, page pixels present (A, B embed). Launched by `open -n`
  (parent launchd, so no permission inherited from the ssh session): `screenRecordingPreflight false`, capture still works, no
  prompt appeared (`a-14-open-launched-app.png`, `a-14-open-launched-screen.png`).
- `metrics` frames match the screen: `corners.py` turns the reported window and card frames into screen pixels and the samples
  land exactly on the card edges in every PASS run above.
- B child: the own-window capture does not include the CEF child window, so the page is missing (`b-child-01-single-app.png`).
- After Mode A's window was closed by `unsplit` the capture fell to `cacheDisplay fallback`.

### Mode A: closing a page closes the window
`split` then `unsplit` (page 1 closed with `CefBrowser.close(force: true)`): System Events window count 1 -> 0, `isKey False`,
`keyWindow none`, screenshot method `cacheDisplay fallback`; reproduced on two launches (`a-pass2.txt`, `a-run1-full.log`).
Cause: CefSwift's `do_close` returns 0, and CEF then sends `performClose:` to the browser's top-level parent window
(`cef_life_span_handler_capi.h`), which is our one window. Fix is at wrapper level: return 1 from DoClose and tear the view down ourselves.

## Recommendation

**Mode B embed** (Chrome runtime, Chromium's `ViewsCompositorSuperview` + `WebContentsViewCocoa` moved into our card) is the only
mode that gave all five: a clipped rounded page card over the gradient, a native bar drawn over the page with focus going and
coming back, Arc-style priority through `OnPreKeyEvent` (the page cannot swallow cmd+T/S/W), two cards with live resize, and
`chrome://extensions`. Mode A gives everything except extensions and additionally closes the app window when a page is closed
(wrapper bug, fixable). The B child variant should be dropped: the page covers the card toolbar and the in-window bar, corners are
not clipped, and its size lags one layout behind.

Main risks of B embed, in order:
1. **Crash on quit, every run** (SIGSEGV in CEF's browser main thread during shutdown). Nothing crashed while running; shutdown must
   close the browsers and wait for `on_before_close` before `CefShutdown`, and the moved views / swizzled host windows must be put back first.
2. It depends on Chromium's private view classes and on swizzling `CefNSWindow.canBecomeKeyWindow`; a CEF upgrade can break it silently.
3. One empty CEF host window per page stays alive as a child window (System Events sees 3 windows with two pages); its frame
   lags a layout call behind. The page viewport itself follows the card.
4. First launch 4.3 s to a working control socket (later 1.2 s); ~150 MB more memory than Alloy with two pages (854 vs 700 MB).
5. Key priority relies on `cef.pre`; the AppKit menu key equivalents never fire while a page is focused, so every app shortcut must
   go through the CEF key handler.
