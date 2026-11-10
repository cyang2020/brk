# Input rules: mouse buttons, swipes and Chrome's tab keys

Settled on 2026-11-10 after a real-input audit of Brk (main at 75d4fe4a) and Arc 1.170. Every input was posted at the
window server's HID level (CGEvent) to a normally launched app. The audit table and the pictures are kept outside the
repo in `~/brk-evidence/usability-input/`.

## Back and forward from the mouse

**State before.** Mouse buttons 4 and 5 worked only with the pointer over a page. Chromium's page view handles them
itself. Over the sidebar, the URL pill or the content margins they did nothing. The navigation swipe that mouse drivers
post for Back and Forward (Logi Options+, Mac Mouse Fix, and the three-finger trackpad swipe setting) did nothing
anywhere. AppKit delivers it as an `NSEventTypeSwipe`. Chrome handles that event in its own browser window, and an
embedded CEF page has no such window, so the event reached no one.

**Arc.** Over a page, both inputs go back and forward in that page's history. Over the sidebar they step to the
previous and next Space. There is no wrap, and back on the first Space stays on it (the Library page is not reached).

**Rule.** `PointerNavigation` (BrkDomain) maps the input to a command by where the pointer is:

- over a shown page, that page's history;
- over the sidebar column, the previous or next Space (Little Arc and incognito windows have no Spaces, so the focused
  page's history);
- anywhere else, the focused page's history;
- nothing while the Library or a Peek is open. The command bar closes on any press outside it and lets that press
  through, so a side button outside the bar closes the bar and then acts.

Over a page, side buttons stay Chromium's. Every other case goes through `HostWindow.hostEvent`. The command runs on the
button's release, as Blink does on a page.

## Two-finger swipe on a page

Brk already runs Chromium's own history swiper, the same code Arc uses. Arc's binary has `HistorySwiper`,
`HistoryOverlayView` and a per-pane `PaneHostHistoryOverlayContainerView`. Brk's CEF framework has the same classes, and
the starting indicator is identical in both apps (#C6C6C6 at the page's left edge).

- **Trackpad.** The swiper follows finger touches. It starts only when the page did not take the first scroll and the
  page edge reports an overscroll, so a horizontally scrollable element keeps the gesture.
- **Magic Mouse.** It uses AppKit's swipe tracking.
- **The indicator.** It is a black disc 140 pt across, centred vertically on the page. With progress it slides in up to
  70 pt and its alpha goes from 0.25 to 0.65. Once the swipe will complete, the alpha is 0.75 and the disc is 10 pt
  taller.
- **Testing limit.** Synthetic scroll events carry no touches, so a test can only show the swipe starting, in either
  app. Nothing was changed here. `Input-SwipeIndicator` guards that page gestures still reach Chromium.

## Other keys

- **⇧⌘] and ⇧⌘[** step to the next and previous tab in Arc, although Arc's menu does not list them. They are Chrome's
  reserved tab keys. Brk claims them before the page as second keys of Next Tab and Previous Tab. Arc ignores ⌃⇟ and ⌃⇞,
  and so does Brk.
- **Esc** does not stop a page loading in Arc, and not in Brk. ⌘. stops it in both.
- **Editing keys in a page's text field** stay the field's in both apps. ⌘← only moves the caret, although it is Go
  Back's second key, and ⌃D only deletes, although it toggles developer mode on the page. Chromium counts these as
  consumed, so CEF's after-page callback never fires for them. No rule was needed.

## Middle-click

- **On a link**, Chromium opens a background tab. It already worked.
- **On a sidebar tab row**, Arc archives the tab, the same as the row's ×. Brk now does the same for that row alone,
  ignoring any multi-selection.
- **On a Favorite**, Arc was not probed (it would open the user's sites), so a Favorite still ignores the middle button.
