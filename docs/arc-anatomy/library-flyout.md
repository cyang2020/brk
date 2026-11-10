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
The Arc | Brk pictures, the frame-by-frame timing tables and the probe scripts are outside the repo, in
`~/brk-evidence/library-hover-preview/`.

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
  bold and its age in grey, … and "Open in <app> ↗". Images and PDFs both opened there. The card's grey and the … menu
  are in "The preview" below.
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
  (bin:0x1026b0b30) from scale 1.5 (bin:0x1026b1510); the old one fades over 0.14 s linear (bin:0x1026ada9c). At the same
  moment the download's icon is thrown into the button ("The download flight" below).

## Light and dark

- The rows have no background of their own. Behind them the sidebar's rows above fade out: opaque at the top row, 0.89
  at 26 pt above it, 0.69 at 50, 0.36 at 86, 0.2 at 116, nothing at 140 (probe, measured from the selected tab above).
- The user's Arc has no dark Space (the second Space is a light lavender), so dark was not probed. Brk draws white ink at
  the same strengths and the dark `itemBackground`, following Arc's asset catalog, whose HomeButton colours all have
  DarkAqua variants of white at the light ones' strengths.

## The download flight

When a download starts, Arc throws a download icon from the pointer into the bottom left corner of the window: into the
Library button while the sidebar shows, into a bin it slides in at the corner while the sidebar is hidden. Arc's code is
`DownloadsUI.DownloadToLibrary` (`WindowController`, `ViewModel`, `DownloadViewModel`), started from
`WindowViewController` (`downloadToLibraryWindowController`, `downloadToLibrarySubscription`,
`downloadToLibraryAnimationSubscription`). Brk rebuilds it in `Sources/BrkDomain/Rules/DownloadFlight.swift` (the path)
and `Sources/BrkSidebar/DownloadFlightView.swift` (Core Animation); the numbers are `Metrics.downloadFlight`.

The facts below were found on 2026-11-10. Addresses are in the same arm64 slice, read with llvm-objdump and Ghidra 12
headless with `-noanalysis` (function starts from `llvm-objdump --function-starts`, field names from
`__swift5_fieldmd`). Probes r1 to r7 are screen recordings of the signed-in Arc at 320,70 (1280 x 776) clicking links on
a local fixture page that sends files as attachments; positions are window points from the top left unless the text
says "y up". The recordings, the frame tables and the Arc | Brk strips are in `~/brk-evidence/library-download-flight/`.

When and where:
- It starts when a download starts, on the same frame as the badge (r1). A 20 s download flies at its start, while it
  still runs (r5). Every download flies: `downloadMagnetAnimationTheatricalPlayCount` is a case of
  `ArcUserDefaultSettings`, but after seven flights the key is still absent from `company.thebrowser.Browser`, where
  the other counters (`littleBrowserNUXPresentationCount`) are; 1.170 does not count plays.
- Arc draws it in a borderless, transparent child window with the browser window's frame and a SwiftUI view
  (bin:0x101ce4ba8). Several downloads share it; each has its own path (r4: two links clicked 0.76 s apart both fly).
- The start is where the click that started the download happened, moved 15 right and 15 down (bin:0x101ce4e7c for the
  first flight, 0x101ce5120 for later ones). Arc's download event carries a rectangle and Arc takes its middle; without
  one it takes the pointer (`NSEvent.mouseLocation`, bin:0x1002f0d54); a point that is not finite becomes (70, 70) up
  from the bottom left. r8 clicked a link 60 points left of its middle: the icon moved 11 points per frame and passed
  y 353 at x 688, as from the click (model 355); from the link's middle it would pass y 274. In r1 the pointer had moved
  100 points away before the download started and the icon still left from the click. Brk keeps the window's last
  mouse press for 5 s (`pressMemory`, ours) and otherwise takes the pointer.
- Toolbar mode (View > Show Toolbar): the same flight into the button (r7). Little Arc: no flight; Little Arc shows its
  own download pill (icon, name, "1/1 KB") at the window's bottom left instead (r6). Incognito windows were not probed;
  Brk's have no Library list, so they throw nothing.

What flies:
- SF Symbol arrow.down.circle, resizable in a 30 x 30 frame (bin:0x101cdeb24), in the palette's `maxContrastColor`
  (#4C4C4C on the light Space) on a disc in `backgroundExtra` (white), with a shadow of system blue at 0.25, radius 8,
  4 down (bin:0x101cde278). The ring spans 29.4 points and is 2.5 thick (r1 at the apex: 47 and 4 at scale 1.6).
- It starts transparent and turned -35 degrees (bin:0x101cde254); on appearing it fades in on spring(response 0.3,
  damping 1) and turns to +5 on spring(1.2, 1) (bin:0x101cdeec8, 0x101cdef10, 0x101ce0880).

The path (y up from the window's bottom left, one keyframe per 1/60 s, bin:0x101ce2b60):
- A thrown object: x = x0 + vx t, y = y0 + vy t - g t^2 / 2 with g = 2648.7 (bin:0x101ce29f8) and vy = 1600 - 1100 y0 / H
  for a window H tall (bin:0x101ce23a8). The flight lasts until the icon is back at the target's height (the first
  positive root, bin:0x101ce2510); vx = (target.x - x0) / that time.
- Target with the sidebar showing: (32, 40) (bin:0x101ce2a84), and the path runs 8 frames past it (bin:0x101ce2bac) while
  the scale falls below 0.1: the icon drops into the Library button and is gone.
- Target with the sidebar hidden: (62, 70), 8 short of the bin's corner (70, 70) (bin:0x101ce4e9c, 0x101ce2a78); from the
  landing a spring (response 0.48, damping ratio 0.72, bin:0x101ce2ea4) carries it to (70, 70) with the landing speed.
- Scale: before the apex (0.8 + 0.8 p, 1.2 + 0.4 p) for p = t / apex time (bin:0x103783310), so 1.6 at the top
  (bin:0x101ce2c2c); after it 1.6 - k (1 - f), f going from 1 at the apex to 0 at the landing, k = 1.3 without the bin
  (0.3 at the button) and 0.9 with it (0.7) (bin:0x101ce2d1c, 0x101ce2d48). The bounce keeps the last frame's scale.
- r1 against the model: a click at (772, 379) gives a first frame at (772, 372.5) 24 x 31 points, 12 points left per
  frame, the top at y 184 (model 182.5) 0.40 s in, 47 to 49 points wide; it reaches the button about 1.05 s in (model
  1.046). r2: the icon drops 58 points below the bin's corner before it settles (model 57.4).

The bin (sidebar hidden):
- A 46 point rounded square (corner 12, continuous; a 62 x 62 frame with padding 8, bin:0x101cdf438) in the palette's
  `background` (#EBEBEB), a black shadow at 0.3, radius 12 (white 0.15 on dark, bin:0x101cdf190), the Library glyph
  (#5C5C5C) in the middle. Its centre is at x 53 and 53 above the window's bottom (bin:0x101ce1c68, 0x101cddd2c); it hides
  at x -80 (bin:0x101ce1c28). It slides on Arc's Motion spring default, stiffness 300, damping 10 (bin:0x100b87810);
  leaving, it moves 5 then 11 points in its first two frames (model 5.2 and 14).
- Arc's overlay window draws its first frame some time after it is made, while its springs run from the making and the
  thrown path from the first frame: in r2 the bin first shows at x 37 and rises into place (spring time 0.40 s), in r3
  it first shows already in place (0.9 s); in r1 the icon is opaque in its first frame and upright at the top of its
  arc. A second flight while the window is up (r4) starts faint and turned. Brk gives the first flight of a run a lead
  of 0.4 s on the springs and the bin (`firstFlightLead`).

The end:
- Each flight keeps the overlay until its landing plus 1 s (bin:0x101ce1d9c). When the last one is done the bin slides
  out and the window closes about 0.23 s later (r2: the bin starts out at 3.20 s, the last frame with the icon is 3.43 s).
- The Library button itself plays nothing when the icon lands (r1: its glyph is unchanged and the screen stops changing
  0.05 s after the landing); its badge sprang in when the download started. ARC_HomeButton's `downloads.json` Lottie is
  the Library's Downloads page icon (hover frames 1 to 11, click to 35, the arrow and the circle bounce), not the
  button's.

## The preview

- Quick Look draws no background of its own (QLPreviewView, `.normal` and `.compact`, tested in a window). Arc's card
  is a radial grey: 20 readings on two rows of the 974 point card fit 214 - 0.00058 ((dx + 9)^2 + (dy / 2.76)^2) within 4
  levels, so #D6D6D6 in the middle (9 points left of the card's), #4D4D4D at half the card's width, its vertical radius
  2.76 times the horizontal. Two Arc pictures with different files and pointers read the same values. The left half is
  up to 11 levels lighter than the right at the same distance, which the 9 point shift absorbs.
- The 46 point toolbar is the same grey under white at 0.29 (five places across the card read 0.23 to 0.30), with no
  line below it.
- The … menu (HomeBadging, bin:0x1026b725c to 0x1026b7cf4) lists Send via iMessage and AirDrop, then Show in Finder for a
  download (seen on Arc) or a macOS screenshot, and Open Source URL and Copy Source URL for an Arc capture (from the code).
  It opens with its top left corner where the … was clicked.

## Not rebuilt

- macOS screenshots in the list (see above).
- Little Arc's own download pill (r6): it is a separate Little Arc feature, not part of the flight or the preview.
