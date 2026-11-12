# 2026-11-12 Space colours imported from Arc

## Report

The user's navy Space (folders coffee and Career, a LinkedIn group, Google Meet) is deep navy with white text in Arc, but pale greyish lavender (#ADB2C2) in Brk. A second Space is dark purple in Arc and light blue in Brk. The user's Mac is in dark mode: Brk's settings window and menu bar in their screenshots are dark.

## What Arc does

Measured on Arc 1.170 on 2026-11-12, using the test Space 对照 (afterwards set back to white, slider 0.78). Arc's theme editor set each colour and slider position. macOS was switched between light and dark mode with System Events. A solid black or white window was put directly behind Arc's window, because Arc's sidebar shows part of whatever is behind the window. Samples are the sidebar's top-left corner, sRGB.

- Arc saves the slider position as `intensityFactor` (0.5 saved as 0.495). Moving it right shows more of the colour: navy at slider 0 is almost grey, at slider 1 almost navy.
- Arc saved `translucencyStyle: "light"` with the automatic button selected and again with the sun button. A saved theme with "light" changes with macOS's mode. Only the open editor holds the sun button.
- The sidebar is a straight mix of the theme colour with one grey, in sRGB: sidebar = (1 - B) x M + B x colour. Black, white and navy fit the same B on every channel.

| macOS mode, backdrop | slider 0 | slider 0.5 | slider 1 |
| --- | --- | --- | --- |
| light, white backdrop: B, M | 0.18, 244 | 0.44, 248 | 0.70, 248 |
| dark, black backdrop: B, M (white and navy fit) | 0.20, 93 | 0.47, 91 | 0.72, 107 |

The black theme in dark mode reads about 10 levels darker than this fit, so it was left out of the dark fit.

## Cause in Brk

1. The import kept `intensityFactor` as Brk's intensity. Brk's intensity is the opposite: how much wash goes over the colour. A navy Space at 0.73 got a 60% white wash.
2. The import turned Arc's saved "light" into Brk's sun button. In dark mode Brk therefore kept the light-mode white wash, where Arc uses a dark grey.
3. A light/dark pair (`appearanceBased`) was read by taking whichever style came first alphabetically. A style without readable colours (Arc's old named `basicColor`) fell back to Brk's default beige.

## Fix

- Import: intensity = 1 - intensityFactor. "light" and "auto" become automatic, "dark" stays dark. A pair becomes Brk's light/dark pair, set to follow the system. A style without colours takes the theme's `primaryColorPalette.shaded`. Display P3 colours are converted to sRGB.
- `resolveTheme`: whenever macOS is in dark mode and the theme is not set to light, the wash is grey 94/255 at 0.27 + 0.53 x intensity (the dark row above, with Brk's intensity = 1 - slider). Light mode is unchanged.
- Spaces imported before the fix are corrected once when Brk loads (`repairArcImportedThemes`, marked by `sidebarData.importedThemes`).

Brk draws no backdrop, so it assumes black behind the window in dark mode. Light mode keeps the earlier calibration, which falls between Arc's black-backdrop and white-backdrop readings.
