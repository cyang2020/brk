# 2026-11-15 The ring past the last Space

## Report

On the user's Mac (dark mode, a navy/purple Space) Brk's ring past the last Space was a dark disc with a white ring and plus, white when full, over a light band along the sidebar's edge. The user said the button and the glow both differ from Arc. Brk's colours for a dark theme were a guess, the band was a linear white or black shade, and the disc stood still while the whole view faded in.

## What Arc 1.170 does

Read from the binary (addresses below) and recorded on real Arc with synthetic two-finger gestures through the window server, in the test Space 对照 with its white theme and with the Drab navy preset, macOS in light and in dark mode.

- The edge view (`EdgeFeedbackView`) is pinned to the sidebar's trailing edge, full window height, 85 wide (bin:0x100311a54).
- The fingers set two values directly, no spring (bin:0x100214f70, 0x1009ce640): presentation = pressed / 15 and ring progress = pressed / 22.5, both clamped to 0...1. After the fingers lift both follow the column's settle spring, so on a cancel the ring unwinds and the disc slides out in about 0.12 s (recording, frames 1.617 to 1.733 s).
- The button (`CircularProgressView`) is 30 by 30. Its x goes from 5 past the trailing edge (presentation 0) to 12 inside it (presentation 1), centred vertically (bin:0x1009cf1e0). Its alpha is presentation / 0.2 (bin:0x1009cf790).
- Inside: a disc in the palette's `cutoutColor`, clipped round; a ring 2.5 wide in `maxContrastColor`, round caps, starting at 12 o'clock and running anticlockwise (NSBezierPath roundedRect order), strokeEnd = progress, opacity progress / 0.05 (bin:0x1009bc3ec); a 16 pt medium plus tinted `maxContrastColor` (bin:0x100312fbc). Under it a shadow: black, opacity 0.3, radius 1.5, 1 pt down (bin:0x100312d70).
- Full (progress 1): the ring's line widens to 30 - 2.5 so it fills the disc, and the plus turns `cutoutColor`. The width is set before Arc's 0.05 s animation group (bin:0x1009bd3c4), so Core Animation animates it with its implicit default, 0.25 s on the default curve (the recorded widths 3.5, 7.5, 13.5, 16.5, 19.5 pt at 1/60 s steps fit that); only the plus's tint is in the group (bin:0x1009bd3d4). 0.05 s later the disc scales to 1.15 and back over 0.07 s each way, ease-out (bin:0x1009bd3a4 to 0x1009bd65c). A generic haptic each time the ring becomes full or stops being full (bin:0x1002152d8). Lifting after it has been full for more than 0.1 s opens Create a Space; the ring stays full until that page appears and then goes in the same frame.
- The glow is a radial `CAGradientLayer` (centre 0.5, 0.5 to end 0, 1: an ellipse filling its layer), twice the edge view's width, from the key colour to clear (bin:0x1009cec04, 0x1009cf508). Its x goes from 10 inside the edge to centred on the edge; its opacity is 2 x presentation. The key colour is `maxContrastColor` at 22% (bin:0x1003123f8), resolved with the light appearance: in the navy Space it is the navy shade under macOS light and dark mode alike (the band darkens the sidebar; measured near the edge -8/-7/-5 on #6A7991, -6/-4/-2 on #54627A).
- The colours come from the Space's palette (bin:0x100312298): ring, plus and glow `maxContrastColor`, disc and full plus `cutoutColor`. Light: `maxContrastColor` = `shadedDark`, `cutoutColor` = `tintedLight`; dark: the other way round (bin:0x100d80aac).
- `PrimaryColorPalette(color:)` (bin:0x100d80500) moves the theme colour's relative luminance into a band by HSL lightness steps of 0.01 in the colour's own space, Display P3 (bin:0x1009a5fa8, 0x1009a60ac); the luminance uses sRGB's formula with threshold 0.03928 on those components (bin:0x1009a7768). Bands: tintedLight 0.85...0.95, midTone 0.3...0.5, shaded 0...0.5, shadedDark 0...0.1. This reproduces all three palettes Arc saved on this Mac: white (P3 grey 0.97 and 0.34, the #F7F7F7 disc and #575757 ring of the 2026-11-05 references), a light teal ((0.88, 1, 1) and (0, 0.38, 0.38)) and Drab navy ((0.919, 0.937, 0.965) and the navy itself).

## Fix

`ThemeShades` (Brk's `PrimaryColorPalette`, the two shades used) is derived from the Space's primary colour. The edge view is the trailing 85 points of the sidebar with Arc's glow, disc, ring, plus, shadow, fill and bounce, laid out by `PageSwipeRule.edgeFeedback(pressed:in:)`. The haptic is the generic pattern. At a commit the ring is hidden at once, and each swipe starts unarmed.

Evidence (pictures, recordings, numbers): `~/brk-evidence/space-edge-ring/` on the test Mac.
