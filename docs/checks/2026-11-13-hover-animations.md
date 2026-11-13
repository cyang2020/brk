# 2026-11-13: Library button hover motion, Library page pictures, the + turning into ×

User report: "现在brk缺失很多animation … 比如左下角box hover之后的闪光" (the Library button's shine on hover is missing).

## What Arc 1.170 does

- The Library button's picture is ARCUI's `BoxOfThingsIcon` (a SwiftUI view, not a Lottie file), five pictures from
  ARCUI's asset catalog: box, star, triangle, dot, glow. Hover handler bin:0x100aeaab4, body bin:0x100ae93b4, created
  at bin:0x100aefbe4 with `spring(response: 0.5, dampingFraction: 1)`. On every hover change, in and out: the star turns
  from -9° to 105° and rises 1.5 pt, the triangle turns from 225° to 85° and moves out, the dot rises 2.5 pt; a twinkle
  flag toggled at 0, 0.15 and 0.3 s shrinks the triangle (0.15) and then blinks the dot (0.1) for 0.15 s. In a dark
  theme a white glow rises from the box and every piece gets a white halo; that is the shine. Nothing moves with Reduce
  Motion on. All numbers with addresses: `Draw.libraryIcon*` in Sources/BrkSidebar/SidebarStyle.swift.
- The six Lottie files in ARC_HomeButton are the Library window's page pictures. They play once, frames 1 to 35 (45
  for Boosts) at 60 fps, when the page becomes the open one (bin:0x10270a854), never on hover.
- The dock's + is two crossed bars that turn 45° into the × on `spring(response: 0.2, dampingFraction: 0.5)`
  (bin:0x100af267c).

## Checks

- Real Arc recorded with `screencapture -v` while the real pointer moved onto the Library button and away (light
  theme): same poses and timing as the code; Brk recorded the same way matches both poses. Arc's dark theme could not
  be recorded (its fixture Space is light and does not follow macOS); Brk's dark shine was checked in a dark Space.
- Brk's page pictures rendered frame by frame beside Arc's Lottie frames (lottie-web, outside the repo); playback
  recorded in the running app on real clicks.
- Unit tests: `LibraryIconMotionTests` (twinkle toggles end off after a quick in and out; Reduce Motion keeps it still),
  `LibraryPageArtTests` (every picture ends where it starts). Native: `LibraryIcon-HoverReal` in the sidebar group.
- Pictures, recordings and frame tables: ~/brk-evidence/hover-animations/ (not committed).
