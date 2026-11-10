# Arc 1.170: the Library button's flyout and badge

## Background

In Arc, resting the pointer on the Library button at the bottom left of the sidebar opens a short list of the newest
Library items above it, and the button carries a badge while a download runs or just after it finished. Arc's code for
this is the `HomeBadging` module (`HomeButton`, `HomeButtonHoverRegionTracker`, `HomeBadgingItemsState`,
`HomeBadgingCell`, `ItemPreviewPresenter`). Brk rebuilds it in `Sources/BrkDomain/Rules/LibraryFlyoutRules.swift`,
`Sources/BrkSidebar/LibraryFlyoutView.swift`, `LibraryFlyoutRow.swift` and `Sources/BrkContent/LibraryItemPreviewView.swift`;
the numbers are `Metrics.libraryFlyout`.

The facts below were found on 2026-11-10 in two ways. Addresses (`bin:0x…`) are in the arm64 slice of
`/Applications/Arc.app/Contents/MacOS/Arc` 1.170 (build 89123), read with llvm-objdump; short Swift strings were decoded
from mov/movk pairs. "Probe" means the user's signed-in Arc, driven with real window-server mouse events and a local file
server, captured with `screencapture` (window at 320,70, 1280 x 776, sidebar 228 wide, the Greyscale white fixture Space).
The probe pictures and videos are outside the repo, in `~/brk-evidence/library-hover-preview/`.

## When the list opens and closes

- The pointer must rest on the 32 x 32 button. Arc defines three hover regions in `HomeButtonHoverRegionTracker`
  (bin:0x1026b5460, 0x1026b64b4): the button (32 x 32, 0.15 s), the strip right of it as tall as the button (the Space
  dots, 0.5 s), and the whole expanded frame (0.15 s). Probe: passes of 0.10, 0.13, 0.17, 0.20, 0.22, 0.24, 0.25, 0.26
  and 0.28 s never opened it; 0.32 s did; it showed 0.29 to 0.30 s after the pointer arrived in every run. Brk opens after
  0.3 s.
- While open, the pointer may go anywhere in a frame as wide as the sidebar and 256 pt tall up from the button's bottom
  (bin:0x1026ab75c sets the expanded frame to min(width, 1000) x 256). Probe: open at y 600 and y 700, closed at y 560
  and above, with the button's bottom at 836. Leaving that frame closes the list within 0.05 to 0.08 s, the capture's own
  delay; there is no exit delay.
- Resting on the Space dots strip closes it: probe, closed 0.6 s after the pointer moved there; the region carries 0.5 s.
- The list fades in over about 0.1 s and out over about 0.06 s (three 1/60 s frames each way).
- With another app's window in front, the button still lights up under the pointer but the list never opens.
- With no item to show it does not open (`canExpand`).

## What it lists

- The newest items of the window's profile: downloads (Chromium's download history, running ones included) and Library
  captures; Arc also lists macOS screenshots when the Media page's "Show media from:" includes them (Brk's Media page has
  no system screenshots, so neither has its list).
- At most four: the expanded frame is n x 56 + 32 tall (bin:0x1026a9ffc) and 256 at most. Probe: with seven recent
  downloads Arc listed the newest four.
- Oldest of the four at the top, the newest next to the button.
- An item's date is when the download started: a 30 s download read "42 seconds ago" 42 s after it started.
- Neither opening nor closing the Library changes the list or the badge (probe: Shift+Cmd+L twice, list and badge the
  same). There is no age limit in this code: a probe download from the day before was listed as "1 day ago".

## A row

- 48 pt tall on a 56 pt pitch; the newest row's fill ends 1 pt above the button. 4 pt from the sidebar's left edge,
  sidebar width - 16 wide (bin:0x1026afaa0 computes min(width, 1000) - 16); corners follow a 12 pt circle.
- Icon: the file's 40 pt Finder icon, 4 pt into the row. Title: SF 14 regular, label colour (black 0.85). Subtitle: SF
  12 regular, secondary colour (black 0.5), "51 seconds ago", "2 minutes ago", "1 day ago". Both start 57 pt into the row.
- A running download: a 24 pt blue ring with a down arrow instead of the icon, "2.8/8.4 MB · 29s", and an × (11 pt,
  centred 18 pt before the row's end) that cancels it.
- Hover: the sidebar's item fill (black 0.05 on the light sidebar, Brk's `itemBackground`) and Arc's own tooltip with the
  file name beside the pointer.
- Right click on a file: Copy File (Copy Image for an image) | Send via iMessage, AirDrop | Open in <its default app>,
  Show in Finder | Hide from Arc, Move to Trash. On a running download: Cancel Download only. The titles are Swift small
  strings in HomeBadging (bin:0x10265e000 to 0x1026b6000); "Open in ChatGPT" for a CSV on this Mac shows the app name is
  the file's default app.
- Click: a preview over the window (`ItemPreviewPresenter`): the window dims to 70 % black, a card inset 12 % of the
  window's width and 13.3 % of its height shows the file through Quick Look; its 46 pt toolbar has ×, ‹ ›, the name in
  bold and its age in grey, … and "Open in <app> ↗". Images and PDFs both opened there.
- Rows can be dragged out as files (`useArcDragModifier`, `itemProvider` in `HomeBadgingCell`).

## The badge

- A new item younger than 300 s becomes the button's badge (`updateVisibleBadgeItemIfPossible`, bin:0x10269fb4c compares
  the age with 300): a download when it starts and again when it finishes, a capture when it is saved.
- A running download: a 20 pt disc (#E8E8F8) with a blue ring (#1828F8 on a #B8C0F8 track) and arrow, centred 10 pt right
  of and 11 pt above the button's centre. A finished item: its 32 pt icon, centred 10 right and 10 above.
- Opening the list puts a finished item's badge away (`onDidExpandFlyout` -> `dismissVisibleBadgeItem`); a running
  download's disc stays until the download ends, then its file icon replaces it (probe). The badge does not go by itself
  (inferred: the 300 s check runs when the items change, not on a timer).
- A new badge springs in on `interpolatingSpring(mass: 1, stiffness: 500, damping: 25, initialVelocity: 10)`
  (bin:0x1026b0b30) from scale 1.5 (bin:0x1026b1510); the old one fades over 0.14 s linear (bin:0x1026ada9c). Arc also
  flies a download arrow from the page into the button when a download starts; Brk does not.

## Light and dark

- The rows have no background of their own. Behind them the sidebar's rows above fade out: opaque at the top row, 0.89
  at 26 pt above it, 0.69 at 50, 0.36 at 86, 0.2 at 116, nothing at 140 (probe, measured from the selected tab above).
- The user's Arc has no dark Space (the second Space is a light lavender), so dark was not probed. Brk draws white ink at
  the same strengths and the dark `itemBackground`, following Arc's asset catalog, whose HomeButton colours all have
  DarkAqua variants of white at the light ones' strengths.

## Not rebuilt

- The download arrow that flies from the page into the button.
- The preview's radial grey behind Quick Look's view and its … menu beyond Show in Finder.
- macOS screenshots in the list (see above).
