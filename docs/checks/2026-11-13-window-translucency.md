# 2026-11-13 Window translucency

## Report

The user (2026-11-13): when the window is not full screen, Arc is see-through and Brk is not.

## What Arc does

Read from Arc 1.170's arm64 binary (MacOS/Arc) and its `ARC_WindowThemeUI.bundle` shader library, then measured on Arc with a solid black or white window placed directly behind Arc's window, in light and dark macOS. Samples are sRGB.

- The window background is an `NSVisualEffectView` (`WindowBackgroundTranslucencyViewAppKit`, bin 0x1015405c8): state "follows window active state", emphasized, blending mode left at "behind window". The material comes from the theme's style: 1 (`.light`), 2 (`.dark`) or 12 (`.windowBackground`), or by the window's appearance. Saved themes (Arc saves `translucencyStyle: "light"`) use `.light` in both macOS modes.
- Over it is the theme's Metal layer, set not opaque (bin 0x101535248). Its `GradientLayer` (bin 0x101530d98) is the gradient at alpha 0.2 + 0.55 x the slider (`intensityFactor`), over an underlay that is white at min(alpha, 0.5), or black at 35% of that when the window's appearance is dark. The shader (`gradientFragment`) blends the gradient over the underlay and writes premultiplied alpha; `renderFragment` leaves the page card's rectangle out.
- While the window is neither key nor main, the texture's alpha is multiplied by 0.25 (bin 0x101530cdc; `WindowActiveStateTracker` follows key and main, parent windows included).
- Arc's white theme at slider 0.78 (the test Space 对照), sidebar, the gap above the page card, the right gap and the bottom gap all read the same:

| | over black | over white | another app active |
| --- | --- | --- | --- |
| light macOS | 228 | 252 | 254 (either backdrop) |
| dark macOS | 193 | 235 | 238 (either backdrop) |

- A test window with only these layers (the `.light` material, then white at alpha 0.629 over white at 0.5) reads 228 and 252; with the black underlay 194 and 235; with the effect view set inactive 255 and 239. The raw `.light` material reads 95 over black and 241 over white, 218 in a window capture: a window capture (`screencapture -l`) shows it with nothing behind, so window captures are the same over any backdrop.
- The sun, moon and automatic buttons keep the same backdrop share (the 2026-11-12 probes: black theme 43 to 44 levels apart between the backdrops under each). The black underlay appears only for a theme that follows macOS in dark mode; under the moon black reads as grey 59 and white stays white.
- Full screen: the material stays; macOS shows the desktop picture behind the window (sidebar 234,242,246 full screen against 233,243,244 windowed over the same desktop).
- The Little Arc window's header is see-through too (185 over black, 220 over white, 224 inactive). Arc's Settings window and its incognito window are opaque (255 and 18,21,27 over both backdrops).
- The earlier stand-ins fit this: P01-d (another app active, #F7F2EE) is the inactive material under the fixture theme, and P19-b (websites set to Dark, #DCD6D3) is the black underlay.

## Before

Brk drew the theme opaque (the Metal layer and the window were opaque) with a wash over it standing in for the material: grey 94/255 in dark mode, white in light mode. A white 40% veil stood in for the inactive state and a black 8.6% veil for websites set to Dark.

## Fix

- `ThemeBackgroundView` holds the same `NSVisualEffectView` as Arc under the Metal canvas, which is no longer opaque. The renderer draws the gradient at the layer alpha over the underlay, premultiplied, and the texture at 0.25 while the window is inactive.
- `resolveTheme` gives each theme its layer alpha, underlay and material by Arc's rule; `wash` is now that layer over a stand-in for the material (with nothing behind in light mode, over black in dark mode), for the surfaces that cannot show the material: previews, the floating sidebar and the color before the first frame. Incognito stays opaque.
- Websites set to Dark make the window's theme take the dark underlay. The veil view is gone.
