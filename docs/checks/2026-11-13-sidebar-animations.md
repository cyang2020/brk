# 2026-11-13 Tab list animations

## Report

"现在brk缺失很多animation，比如folder打开icon和tabs的animation": a folder's glyph and rows jumped when it opened or closed,
and every other change of the tab list jumped too.

## What Arc 1.170 does

Read from the arm64 slice of `Arc.app/Contents/MacOS/Arc` (Ghidra headless without analysis, llvm-objdump), then timed on
screen recordings of the real app (`screencapture -v`, 60 frames a second, the sidebar strip; rows tracked by matching a
band of pixels frame to frame, curves fitted by least squares). Percentages are how far the rows below had moved in
successive frames.

| Change | Arc | Where |
| --- | --- | --- |
| Folder opens | rows come out from under the folder's row, rows below follow; 0.2 s ease-out; same for 2 and 6 rows (24, 36, 57, 67, 75, 83, 90, 95, 98, 100) | `animator().expandItem` bin:0x1002a8798 |
| Folder closes | titles go at once, rows slide up under the folder's row; 0.25 s default curve (6, 17, 31, 46, 59, 70, 78, 84, 89, 93, 96, 98, 99, 100) | `animator().collapseItem` in a group, bin:0x1002a8720 |
| Clicked again half-way | turns back from where the rows are | recorded at 100 and 180 ms |
| Folder glyph | one drawing turned in 3D: both halves 3 pt right and 32° about the vertical axis, back +28°, front −30° about their bottom edge, perspective 1/350; 17 pt; turns with the rows, 0.25 s | `FolderIcon.FolderIconView`, bin:0x10166c6a8, 0x10166cc40, 0x1003eef90 |
| Any other change | 0.12 s, default curve (32, 60, 79, 90, 96, 100): added rows fade in, one removed row fades in place, two or more slide up under the row above and fade, moved rows slide | `OutlineViewDiffableDataSource` bin:0x100969f8c (0.12), bin:0x1009687a4 (the count) |
| New tab, link in new tab, restore | fade in, rows below slide down, 0.12 s | recorded |
| Close or archive one row | fades in place, rows below slide over it, 0.12 s | recorded |
| Clear, Pinned collapsing | titles go, rows slide up and fade, 0.12 s; Pinned expanding: rows fade in, the folder's rows come out from under it (0.2 s) | recorded |
| Pin, unpin, into a folder | the row slides over the others, 0.12 s | recorded |
| Drop after a drag | the image glides into the row's place, 0.29 s ease-out; the other rows 0.12 s | recorded |
| Clear and Tidy on the divider | fade in and out, 0.1 s ease-out; Clear's ↓ sinks 3 pt while pressed, 0.175 s | bin:0x1001aca1c, bin:0x10030f764 |
| Space name strip | hovered: the chevron fades in as its slot opens and pushes the name over, 0.1 s ease-out; pill and "…" 0.07 s; a click turns the chevron a quarter | `SidebarSectionHeaderView` bin:0x1001c66c4, 0x1001c7910, 0x1001cace0 |
| Row × / − | two 14 × 2 bars, crossed ±45° for ×, level for −; spring(0.3, 0.6) when a pinned tab becomes or stops being current | `XMarkOrHyphenIcon` bin:0x100af3ef0, 0x100af41f0 |
| Row speaker | "speaker" symbol 14 pt, three drawn waves (8 × 12), a slash across 14 × 14 cutting a double-width gap; muting: waves slide in and fade at 0, 0.03, 0.06 s, slash and speaker (4 pt to the middle) at 0.072 s; unmuting: slash out and speaker back at once, waves at 0.06, 0.09, 0.12 s; springs (0.3, 0.6), (0.3, 0.65), (0.25, 0.7) | `SpeakerIcon` bin:0x100aed47c, 0x100aed80c, 0x10369d0e0 |
| Selection, rename field | no animation (one frame) | recorded |

## Brk before and after

Before: every row, the glyph (two separate pictures) and the divider's buttons changed in one frame; a dropped row's image
disappeared at the release. After: `TablistMotion` (BrkLayout) plans the change the way Arc's outline view applies it,
`TablistAnimator` moves the views with Core Animation offsets added on top of their final frames, `FolderIconView` is
Arc's glyph and its 3D turn. Recorded the same way on the station's fixture: close 9, 21, 38, 51, 63, 73, 81, 87, 94, 96,
98, 99, 100 (default curve 0.25 s); open 20, 32, 43, 54, 64, 73, 81, 88, 93, 98, 100 (ease-out 0.2 s); the second click
turns back like Arc's (Arc −134 → −108, −92, −78 px; Brk −130 → −99, −88, −76 px); drop glide 39, 36, 32 … 0 px (Arc
35, 31, 28 … 0).

## Performance

The 560-tab import (`~/brk-evidence/sidebar-lag/bigdata`), main 85f25f297 and the branch alternately, twice each, main
thread sampled every millisecond: 10 s of trackpad scrolls and Space swipes over the sidebar, busy 33 % / 47 % then
64 % / 53 % (main / branch; the shared machine makes single runs swing, the means are 48.5 % and 50 %); the 25-row folder
toggled 12 times, busy 11 % / 11 % and 13 % / 14 %. The planner and the animator take 1–2 ms and 5–6 ms over the 12
toggles and do not appear in the scroll and swipe samples.

## Checks

- `TablistMotionTests` (4): a folder closing and opening, one removed row against several, a pinned row.
- `R57-FolderMotion` (sidebar group): real clicks close and open a folder, then three clicks within 0.2 s; rows end in
  place with their titles drawn, the glyph follows, no row on its way out is reported.
