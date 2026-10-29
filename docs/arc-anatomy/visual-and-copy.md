# Arc 1.170.0: visual system and English UI copy

Static read of `/Users/administrator/.cache/arc-target/Arc.app` (Arc 1.170.0, build 89123, bundle id `company.thebrowser.Browser`, minimum macOS 13.0). Nothing in the app was launched or executed. (ev: `b/app-info-plist.txt`; observed)

## How to read this report

- `b/` means `/Users/administrator/.t3/projects/brk/.audit/arc-evidence/b/`. Every raw tool output sits there, one file per run.
- `R/` means `Arc.app/Contents/Resources/`.
- `bin:0x...` is a string at that virtual address in the arm64 slice of `Arc.app/Contents/MacOS/Arc`, section `__TEXT,__cstring`. Look it up in `b/binary-cstring-arc-arm64.utf8.tsv` (all 36,337 non-empty strings) or `b/en-strings.tsv`.
- `nib:N` is object N in `R/Base.lproj/MainMenu.nib`, decoded with `rea decode-interface-builder` into `b/rea-decode-interface-builder.json` and flattened into `b/mainmenu-items.tsv`.
- `swift:Type` is a row in `b/swift-fieldmd-types.tsv`: the Swift type names and their field or enum case names, parsed from the binary's `__swift5_fieldmd` section with `b/scripts/swiftfields.py`. These are real names from the shipped code, not guesses. Types whose module could not be resolved show as `?ext`.
- Labels: **observed** means the fact is literally in the file. **inferred** means it follows from observed facts, with the reasoning given. **unknown** means the files do not say.
- Hex values are the stored color components times 255, in the color space the asset catalog declares (sRGB unless marked P3). P3 hex values are not sRGB hex values; convert them before use on the web.
- Arc's own copy sometimes contains an em dash. To keep this report free of that character, quotes show it as `{em dash}`. Everything else inside quotes is verbatim.

## Where things live (short version)

- Colors and images: 45 compiled asset catalogs, 857 color renditions forming 519 named colors, 338 of which have a dark variant. (ev: `b/assetutil/*.json`, `b/named-colors.tsv`; observed)
- English copy: the app ships almost no `.strings` files. There are no `.loctable`, `.stringsdict` or `.xcstrings` files anywhere in the bundle. The English UI copy is compiled into the main binary as string literals, usually right next to a translator-style comment that says what the string is for. (ev: `b/resources-file-list.txt`; observed)
- The 54 `*.lproj/MainMenu.strings` files each hold only two entries, the titles for the Edit menu and its Copy item; every other menu title exists only in English in `Base.lproj/MainMenu.nib`. So the app is effectively English only. (ev: `R/*.lproj/MainMenu.strings`, each with two `.title` lines; `R/fr.lproj/MainMenu.strings` is 183 bytes; observed)
- Important limit: Swift stores strings of 15 bytes or less inside machine instructions, not in the string table. So short labels such as section titles, pane names and button words often show up only as their comment, not as the visible text. Where that happens this report says so. (inferred from the pattern: long values are present and many comments have no value next to them, for example `bin:0x103956ac0`)

## 1. Color palette and theme system

### Base tokens

The shared token set lives in `ARCClients_BaseAssets` and is light/dark adaptive. (ev: `b/assetutil/ARCClients_BaseAssets.bundle.json`; observed)

| Role | Token | Light | Dark |
|---|---|---|---|
| Page background | BackgroundPrimary | #FFFFFF | #000000 |
| Main text | ForegroundPrimary | #0E0F10 @ 0.9 (P3) | #FFFFFF @ 0.8 |
| Secondary text | ForegroundSecondary | #000000 @ 0.5 | #FFFFFF @ 0.5 |
| Tertiary text | ForegroundTertiary | #000000 @ 0.3 | #FFFFFF @ 0.3 |
| Neutral scale | BasePrimary / BaseSecondary / BaseTertiary / BaseQuaternary | black @ 1 / 0.7 / 0.3 / 0.15 | white @ 1 / 0.7 / 1.0 / 0.15 |
| Popover | PopoverBackground | #FAFBFF (P3) | #151C30 (P3) |
| Popover shadow | PopoverShadow | #151C32 @ 0.3 | #151C32 @ 0.8 |
| Focus ring | FocusRing | #458AFF (P3) | same |
| Loading border, vibrant text | LoadingPageBorder, VibrantText | #0C50FF | #2AB6F6 |

Note that BaseTertiary is white at full opacity in dark mode while every other step keeps its alpha. That looks like a data quirk, not a design rule. (ev: `b/named-colors.tsv` row BaseTertiary; observed value, inferred quirk)

Brand colors (single appearance): BrandBlue #3139FB (P3), BrandRed #D74807, BrandMagenta #C0009F, BrandGreen #107A00, BrandLightBlue #00C7F3, BrandLightGreen #34E895, BrandYellow #FFD335, BrandGray #7E7E7E, plus an extended set: Cream #F2EAE4, LightPink #F29BBB, Purple #A6729D, VibrantRed #F53714, Orange #FF8558, Teal #6CBAD9, Navy #1C3648, Brown #8A5127, BrownPink #C4836A, BlueGray #666789. (ev: `b/named-colors.tsv`; observed) The primary button face is the same blue, #3139FB, with hover #2C33E2 and pressed #2A30D5. (ev: `b/assetutil/ARCUI_ARCUI.bundle.json` PrimaryButton*; observed)

`ARCUI_ARCUI` also carries three 12-step scales named Gray1-12, GrayA1-12 (alpha) and Indigo1-12, each with light and dark values. Gray1-12 light (#FCFCFC, #F8F8F8, #F3F3F3, #EDEDED, #E8E8E8, #E2E2E2, #DBDBDB, #C7C7C7, #8F8F8F, #858585, #6F6F6F, #171717) has the same values as the older Radix Colors gray scale. (ev: `b/named-colors.tsv`; values observed, Radix match inferred)

### Text colors

- General text: ForegroundPrimary / Secondary / Tertiary as above. (ev: `b/named-colors.tsv`; observed)
- Command Bar: CommandBarTextPrimaryColor black/white @ 0.8, CommandBarTextSecondaryColor @ 0.33, placeholder text in the URL pill CommandBarPlaceholderText @ 0.6, its own placeholder CommandBarPlaceholderPlaceholderText @ 0.3. (ev: `b/assetutil/ARC_CommandBar.bundle.json`, `b/assetutil/TopLevel.json`; observed)
- Rich text and Notes: BodyText black/white, HeaderText #6E678D / #CDCDFF, Link #220C7F / #E6E6FF, Cursor #2702C2 / #9380E0, SelectionTextBackground #CDCDFF / #5235CE. (ev: `b/assetutil/ARC_ArcRichTextEditor.bundle.json`; observed)
- Popovers: PopoverTitle #181B1F / #FFFFFF, PopoverMessage #060E2B @ 0.75 / #EEEEF6 @ 0.75. (ev: `b/assetutil/ARCUI_ARCUI.bundle.json`; observed)

### Sidebar and tab colors

The sidebar uses translucent black or white on top of the space theme, so the theme shows through. (inferred from every sidebar token being black or white at low alpha)

| Token | Light | Dark |
|---|---|---|
| SidebarForeground | #000000 @ 0.3 | #FFFFFF @ 0.45 |
| SidebarForegroundDarker | #000000 @ 0.45 | #FFFFFF @ 0.45 |
| SidebarItemBackground | #0E0F10 @ 0.05 (P3) | #FAFBFF @ 0.1 (P3) |
| SidebarItemHoveredBackground | #0E0F10 @ 0.1 | #FAFBFF @ 0.15 |
| SidebarSeparator | #000000 @ 0.15 | #FFFFFF @ 0.15 |
| SidebarBorderColor (top-level catalog) | #FFFFFF @ 0.3 | #FFFFFF @ 0.3 |
| TabListOverlapBorder (top-level) | #000000 @ 0.05 | #FFFFFF @ 0.05 |
| TabCellBackgroundCurrent (selected tab) | #FFFFFF @ 0.85 | #FAFBFF @ 0.2 |
| TabCellBackgroundContentVisible (page visible but not focused, for example in a split; inferred) | #FFFFFF @ 0.7 | #FAFBFF @ 0.15 |
| TabCellBackgroundPrevious | #FFFFFF @ 0.32 | #FAFBFF @ 0.08 |
| TabCellBackgroundPreviousHovered | #FFFFFF @ 0.5 | #FAFBFF @ 0.12 |
| TabCellBackgroundPressed | #0E0F10 @ 0.065 | #FAFBFF @ 0.065 |
| TabCellBackgroundMutiselected (sic) | #000000 @ 0.1 | #FAFBFF @ 0.1 |
| TabCellChildBackground | #000000 @ 0.07 | #FFFFFF @ 0.07 |
| TabCellShadowSelected | #000000 @ 0.2 | #000000 @ 0 |
| TabCellShadowBackgroundSelected | #FFFFFF @ 0.9 | #000000 @ 0 |
| TabCellSlash | #000000 @ 0.3 | #FFFFFF @ 0.3 |
| DragHint / DragHintHighlighted | #000000 @ 0.2 / 0.5 | #FFFFFF @ 0.2 / 0.5 |

(ev: `b/assetutil/ARCClients_BaseAssets.bundle.json`, `b/assetutil/TopLevel.json`; observed) The selected tab is a near-white card with a soft shadow in light mode, and a faint white fill with no shadow in dark mode. (inferred from the TabCellShadow* alphas)

### Content area background and corners

- The window content view carries fields named `cornerRadius`, `backgroundColor`, `shouldDisplayShadow`, `highlightBorderWidth`, `displayHighlightBorder` and `shouldHideScrimInsets`; the container that holds all content panes carries `contentInsets`, `hiddenScrimEdges` and `contentCornerRadius`. (ev: `swift:Arc.WindowContentsContainerViewController.ViewState` and two `?ext.State`/`?ext.ViewState` rows; observed)
- So the web page sits in an inset, rounded, optionally shadowed card over the themed window background, with a "scrim" edge treatment that can be hidden per edge. (inferred from the field names)
- The window background view takes `translucentAreaLayoutMode`, `canDisplayTranslucency`, `contentFillMode`, `shouldDim`, `cornerRadius` and `preferredRenderer`. (ev: `swift:WindowBackground.WindowBackgroundContainerViewRepresentable`; observed)
- The Metal shader that paints the theme takes `cutoutCoordinates`, which is where the content card is cut out of the background. (ev: `b/metallib-strings.txt`, `renderFragment`; observed name, inferred purpose)
- Colors that touch the content edge: PreviewBackgroundColor #FFFFFF / #212222, Shadow #000000 @ 0.2 / @ 0, FloatingScrimBorder #000000 @ 0.1 / #FFFFFF @ 0.2. Images CellDropShadow, CircleCutout and CircleCutoutRounded. (ev: `b/named-colors.tsv`, `b/image-asset-names.tsv`; observed)
- The actual radius, inset and shadow numbers are compiled into code. (unknown)

### Space theme system

Data model (ev: `swift:BaseModels.WindowTheme*`; observed):

- `WindowTheme` = `background`, `windowAppearance` (light, dark), `primaryColorPalette`, `semanticColorPalette`.
- `Background` = `style`, `contentOverBackgroundAppearance`, `isVibrant`. Style kinds: `basicColor`, `blendedSingleColor`, `blendedGradient`.
- `BlendedGradientConfiguration` = `baseColors`, `overlayColors`, `translucencyStyle` (light, dark, auto), `modifiers`, `wheel` (`complimentary` or `analogous`).
- `BlendedBackgroundModifiers` = `noiseFactor`, `intensityFactor`, `overlay`. Overlay textures: `grain`, `sand`, `denim`, `tweed`.
- `PrimaryColorPalette` = `tintedLight`, `midTone`, `shaded`, `shadedDark`. A semantic palette is generated from it; failure string "Failed to generate semantic color palette from primary palette." (`bin:0x1039d3be0`).

Theme editor (ev: `swift:SpaceStyleEditor.*`; observed):

- State: `primaryColor`, `numberOfColors`, `noiseFactor`, `overlay`, `intensityFactor`, `wheel`, `saturation`, `lightnessRange`, `appearance`, `currentPresetPage`, `darkModeBiasSetting`, `undoStack`.
- Controls: a color pad with draggable knobs (`SpaceStyleColorPadState.Knob`: `id`, `color`, `position`, `isSelected`; add and remove color buttons), a dial for noise (`SpaceStyleDialView`, gestures `slider`, `rotation`, `dialClick`, `scrollWheel`, `drag`), an intensity slider drawn as a sine wave (`SineSlider`, `SineWave` with `strength`, `frequency`, `phase`), a light / dark / automatic toggle animated with the `sun`, `moon` and `automatic` Lottie files, and paged color presets.
- The editor opens in two places: `setup` (onboarding) and `sidebar`. (ev: `swift:SpaceStyleEditor.SpaceStyleEditorView.Presentation`; observed)
- Editor copy: "Tap to pick a color for this space" (`bin:0x1039d3b70`), "Click to pick a color" (`bin:0x1039d4930`), "Cycle noise texture" (`bin:0x1039d3e20`), "Automatic Appearance" (`bin:0x1039d3cc0`), "Light Appearance" (`bin:0x1039d3ce0`), "Move to previous preset page." (`bin:0x1039d3d90`), "Move to next preset page." (`bin:0x1039d3db0`), "Set space color to " (`bin:0x1039d3dd0`, accessibility prefix). Comments: "Intensity slider label for the theme editor." (`bin:0x1039d3ec0`), "Tooltip for the button to choose the noise style in the theme picker" (`bin:0x1039d3e40`). (observed)

Rendering: `WindowThemeUI` paints the background with Metal (`R/ARC_WindowThemeUI.bundle/Contents/Resources/default.metallib`). Its three fragment shaders are `gradientFragment` (inputs `layerCount`, `underlayColor`, `gradientCount`, `colorCount`, `colors`, `gradients`, `progress`), `overlayFragment` (`fromOverlay`, `toOverlay`, `fromOverlayAlpha`, `toOverlayAlpha`, `progress`) and `renderFragment` (`gradientTexture`, `overlayTexture`, `overlayRepetitions`, `cutoutCoordinates`). (ev: `b/metallib-strings.txt`; observed) The background configuration is `single` or `transitioning`. (ev: `swift:WindowThemeUI.WindowThemeBackgroundConfiguration`; observed) So switching spaces crossfades both the gradient and the texture, and the texture is tiled (`overlayRepetitions`). (inferred)

### Space theme preset palette

The code loads four preset sets of nine colors each: `ColorPickerBrand1-9`, `ColorPickerDrab1-9`, `ColorPickerGreyscale1-9`, `ColorPickerPastel1-9` (36 "Unable to load color asset named ColorPicker..." strings in the binary). (ev: `b/binary-cstring-arc-arm64.utf8.tsv`; observed) All 36 are defined in `ARCClients_BaseAssets`; `ARC_SpaceStyleEditor` repeats the Drab, Greyscale and Pastel sets. Drab, Greyscale and Pastel are stored in Display P3; Brand is mostly sRGB with 6 to 9 in P3. (ev: `b/assetutil/ARCClients_BaseAssets.bundle.json`, `b/assetutil/ARC_SpaceStyleEditor.bundle.json`; observed)

| Set | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
|---|---|---|---|---|---|---|---|---|---|
| Brand | #F2EAE4 | #F29BBB | #A6729D | #F25E6B | #FF3C19* | #F2D66D | #73E59C | #7EB8D6 | #666786 |
| Drab | #4B3B58 | #623856 | #854444 | #A77048 | #D1B46A | #CDCCA8 | #84A885 | #34604B | #2D4468 |
| Greyscale | #FFFFFF | #E5E5E5 | #CCCCCC | #B2B2B2 | #808080 | #666666 | #333333 | #1A1A1A | #000000 |
| Pastel | #FDFBFA | #FBEAF3 | #ECD2EA | #F7CDD2 | #FAE1D5 | #FEF9E7 | #E4FCEC | #E0F2FB | #C5C6E2 |

\* Brand5 is stored as components (1, 0.235, 0.097) in "extended linear sRGB". The table shows those numbers times 255. If the declared linear space is honored, it renders close to #FF8558, which equals BrandExtendedOrange. (ev: `b/named-colors.tsv`; components observed, rendered value inferred by applying the sRGB transfer curve)

That the presets are paged in the editor follows from `currentPresetPage`, `setPresetPage`, `presetCount` and the "Move to next preset page." copy; the page order is not stored in resources. (ev: `swift:SpaceStyleEditor.SpaceStyleColorPickerView`; observed fields, order unknown)

Related palettes: Easel ink colors come in two sets, `Vibrant.Easel*` and `Chill.Easel*` (Black, DarkBlue, DarkGreen, Grey, LightBlue, LightGreen, Pink, Purple, Red, White, Yellow). Boosts have their own eight swatches (BoostsBlue #300EFF, Green #55B948, Magenta #DD0EFF, Orange #FF560E, Pink #FF0E82, Purple #860EFF, Red #FF0E0E, Yellow #F1A23C) and a color-wheel model (`primaryHueDegrees`, `primarySaturation`, `secondaryHueOffset`, `invertLightness`, `baseAppearance`), which can be wheel-driven or theme-driven. (ev: `b/named-colors.tsv`, `swift:BoostsClient.BoostColorWheelScheme`, `swift:BoostsClient.BoostColorScheme`; observed)

### Gradient and grain assets

| Asset | Catalog | Details | Label |
|---|---|---|---|
| grain, sand, denim, tweed | ARC_WindowThemeUI | Tileable textures: denim 300 px, sand 96 px, tweed 128 px, grayscale and opaque; grain 155 px ARGB with transparency; @2x versions exist | observed |
| grain_metal, sand_metal, denim_metal, tweed_metal | ARC_WindowThemeUI | Second copy of each texture (JPEG for denim, sand, tweed; ARGB for grain), 100 px and 200 px | observed; that these feed the Metal renderer is inferred from the name |
| GrainKnob, SandKnob, DenimKnob, TweedKnob | ARC_SpaceStyleEditor | 56 x 56 pt previews of each texture on the noise dial | observed |
| DotGrid | ARC_SpaceStyleEditor, ARC_BoostsEditor | 400 x 401 template image behind the color pad | observed |
| grain-1 to grain-4 | ARCUI_ARCUI | 2100 x 1500 template grain sheets | observed |
| grain | ARC_AskArc (500 px), ARC_AuthFeature (220 px), ARC_PreferencesFeature (683 x 557) | Per-feature grain | observed |
| grain-no-blend, glow, glow-video | ARC_WelcomeToArcFeature | Welcome screen grain and glow plates | observed |
| gradient | top-level Assets.car | 1110 x 381 ARGB gradient image | observed |
| ArcUpdatesGradient | ARCUI_ARCUI | 498 x 183 | observed |
| GradientBackdrop (light and dark), OneBoxGradient | ARC_AskArc | Ask Arc backgrounds | observed |
| fallback-gradient-1 to 8 | ARC_MembershipCard | 478 x 386 card backgrounds | observed |
| Gradient colors | ARCUI (Gradient1 #F19E9C @ 0.2, Gradient2 #1B46F5, GradientBlue #0047FF P3, GradientPeach #FF9999 P3), ARC_HomeButton (WelcomeGradientBlue #0047FF, WelcomeGradientPink #FF9999), ARC_AskArc (BackgroundGradientTopColor #EED1D1 @ 0.2, BackgroundGradientBottomColor #97A6CC @ 0.2) | Arc's blue-to-peach brand gradient pair | observed values; "brand gradient" inferred from repeated use |

(ev: `b/image-asset-names.tsv`, `b/assetutil/*.json`)

### Full named-color table

All 519 named colors, grouped by catalog. "Any" is the default rendition (used in light mode, and in dark mode when no dark rendition exists). A dash means no dark rendition. One color, `AuthFlowKeychainMessagingText`, points to the system `labelColor`. (ev: `b/named-colors.tsv`; observed) Colors appear in 30 of the 45 catalogs; the other 15 hold images only. "TopLevel" below means `Arc.app/Contents/Resources/Assets.car`. (ev: `b/assetutil/*.json`; observed)

#### ARCClients_BaseAssets (132 colors)

Source: `Arc.app/Contents/Resources/ARCClients_BaseAssets.bundle/Contents/Resources/Assets.car`, dumped to `b/assetutil/ARCClients_BaseAssets.bundle.json` (observed).

| Name | Any (light) | Dark |
|---|---|---|
| BackgroundPrimary | #FFFFFF | #000000 |
| BasePrimary | #000000 | #FFFFFF |
| BasePrimaryDark | #FFFFFF | - |
| BasePrimaryLight | #000000 | - |
| BaseQuaternary | #000000 @ 0.15 | #FFFFFF @ 0.15 |
| BaseSecondary | #000000 @ 0.7 | #FFFFFF @ 0.7 |
| BaseSecondaryDark | #FFFFFF @ 0.7 | - |
| BaseTertiary | #000000 @ 0.3 | #FFFFFF |
| BrandBlue | #3139FB (p3) | - |
| BrandExtendedBlueGray | #666789 | - |
| BrandExtendedBrown | #8A5127 (p3) | - |
| BrandExtendedBrownPink | #C4836A (p3) | - |
| BrandExtendedCream | #F2EAE4 | - |
| BrandExtendedLightPink | #F29BBB | - |
| BrandExtendedNavy | #1C3648 (p3) | - |
| BrandExtendedOrange | #FF8558 (p3) | - |
| BrandExtendedPurple | #A6729D (p3) | - |
| BrandExtendedTeal | #6CBAD9 (p3) | - |
| BrandExtendedVibrantRed | #F53714 (p3) | - |
| BrandGray | #7E7E7E (p3) | - |
| BrandGreen | #107A00 (p3) | - |
| BrandLightBlue | #00C7F3 (p3) | - |
| BrandLightGreen | #34E895 (p3) | - |
| BrandMagenta | #C0009F (p3) | - |
| BrandRed | #D74807 (p3) | - |
| BrandYellow | #FFD335 | - |
| Chill.EaselBlack | #000000 | #FFFFFF |
| Chill.EaselDarkBlue | #3139FB | - |
| Chill.EaselDarkGreen | #1D5914 | - |
| Chill.EaselGrey | #BBBBBB | - |
| Chill.EaselLightBlue | #55A2BD (p3) | - |
| Chill.EaselLightGreen | #D0D87F (p3) | - |
| Chill.EaselPink | #F2C2AC | - |
| Chill.EaselPurple | #A6729D | - |
| Chill.EaselRed | #D74807 | - |
| Chill.EaselWhite | #FFFFFF | #000000 |
| Chill.EaselYellow | #C2A12A | - |
| ColorPickerBrand1 | #F2EAE4 | - |
| ColorPickerBrand2 | #F29BBB | - |
| ColorPickerBrand3 | #A6729D | - |
| ColorPickerBrand4 | #F25E6B | - |
| ColorPickerBrand5 | #FF3C19 (ext-linear sRGB) | - |
| ColorPickerBrand6 | #F2D66D (p3) | - |
| ColorPickerBrand7 | #73E59C (p3) | - |
| ColorPickerBrand8 | #7EB8D6 (p3) | - |
| ColorPickerBrand9 | #666786 (p3) | - |
| ColorPickerDrab1 | #4B3B58 (p3) | - |
| ColorPickerDrab2 | #623856 (p3) | - |
| ColorPickerDrab3 | #854444 (p3) | - |
| ColorPickerDrab4 | #A77048 (p3) | - |
| ColorPickerDrab5 | #D1B46A (p3) | - |
| ColorPickerDrab6 | #CDCCA8 (p3) | - |
| ColorPickerDrab7 | #84A885 (p3) | - |
| ColorPickerDrab8 | #34604B (p3) | - |
| ColorPickerDrab9 | #2D4468 (p3) | - |
| ColorPickerGreyscale1 | #FFFFFF (p3) | - |
| ColorPickerGreyscale2 | #E5E5E5 (p3) | - |
| ColorPickerGreyscale3 | #CCCCCC (p3) | - |
| ColorPickerGreyscale4 | #B2B2B2 (p3) | - |
| ColorPickerGreyscale5 | #808080 (p3) | - |
| ColorPickerGreyscale6 | #666666 (p3) | - |
| ColorPickerGreyscale7 | #333333 (p3) | - |
| ColorPickerGreyscale8 | #1A1A1A (p3) | - |
| ColorPickerGreyscale9 | #000000 (p3) | - |
| ColorPickerPastel1 | #FDFBFA (p3) | - |
| ColorPickerPastel2 | #FBEAF3 (p3) | - |
| ColorPickerPastel3 | #ECD2EA (p3) | - |
| ColorPickerPastel4 | #F7CDD2 (p3) | - |
| ColorPickerPastel5 | #FAE1D5 (p3) | - |
| ColorPickerPastel6 | #FEF9E7 (p3) | - |
| ColorPickerPastel7 | #E4FCEC (p3) | - |
| ColorPickerPastel8 | #E0F2FB (p3) | - |
| ColorPickerPastel9 | #C5C6E2 (p3) | - |
| CommandBarPlaceholderIncognitoBackground | #FFFFFF @ 0.15 (p3) | - |
| CommandBarSuggestionHintPillBackground | #FFFFFF (p3) | #FFFFFF @ 0.1 (p3) |
| CommandBarSuggestionHintPillImageBackground | #000000 @ 0.03 (p3) | #FFFFFF @ 0.2 (p3) |
| DownloadProgressBarBackground | #CED7E7 | #717782 |
| FindInPageError | #C93333 (p3) | - |
| FindInPageSeparator | #000000 @ 0.1 (p3) | - |
| FloatingControlIconForeground | #000000 @ 0.5 | #FFFFFF @ 0.5 |
| FloatingScrimBorder | #000000 @ 0.1 | #FFFFFF @ 0.2 |
| FocusRing | #458AFF (p3) | - |
| ForegroundPrimary | #0E0F10 @ 0.9 (p3) | #FFFFFF @ 0.8 |
| ForegroundSecondary | #000000 @ 0.5 | #FFFFFF @ 0.5 |
| ForegroundTertiary | #000000 @ 0.3 | #FFFFFF @ 0.3 |
| FullOpacityBackgroundPrimary | #FFFFFF | #000000 |
| FullOpacityForegroundPrimary | #000000 | #FFFFFF |
| LoadingPageBorder | #0C50FF | #2AB6F6 |
| MoveButtonBackground | #FFFFFF | #000000 |
| NewTabPageButtonBackground | #000000 @ 0.04 | #FFFFFF @ 0.038 |
| NewTabPageButtonHoveredBackground | #000000 @ 0.06 | #FFFFFF @ 0.075 |
| PopoverBackground | #FAFBFF (p3) | #151C30 (p3) |
| PopoverShadow | #151C32 @ 0.3 (p3) | #151C32 @ 0.8 (p3) |
| PrivateCreativeToolPrimary | #107A00 (p3) | #34E895 (p3) |
| PrivateCreativeToolSecondary | #0B5000 @ 0.1 (p3) | #71EFB5 @ 0.1 (p3) |
| PrivateCreativeToolTertiary | #063100 @ 0.1 (p3) | #AEF6D5 @ 0.1 (p3) |
| ReadAndWriteCreativeToolPrimary | #C0009F | #F29BBB |
| ReadAndWriteCreativeToolSecondary | #7F0069 @ 0.1 | #F9CDDD @ 0.1 |
| ReadAndWriteCreativeToolTertiary | #4D0040 @ 0.1 | #FAD7E4 @ 0.1 |
| ReadOnlyCreativeToolPrimary | #3139FB | #00C7F3 |
| ReadOnlyCreativeToolSecondary | #2026A6 @ 0.1 | #57DAF7 @ 0.1 |
| ReadOnlyCreativeToolTertiary | #141764 @ 0.1 | #99E9FA @ 0.1 |
| Shadow | #000000 @ 0.2 | #000000 @ 0 |
| SidebarForeground | #000000 @ 0.3 | #FFFFFF @ 0.45 |
| SidebarForegroundDarker | #000000 @ 0.45 | #FFFFFF @ 0.45 |
| SidebarItemBackground | #0E0F10 @ 0.05 (p3) | #FAFBFF @ 0.1 (p3) |
| SidebarItemHoveredBackground | #0E0F10 @ 0.1 (p3) | #FAFBFF @ 0.15 (p3) |
| SidebarSeparator | #000000 @ 0.15 | #FFFFFF @ 0.15 |
| StandaloneButtonBackground | #000000 @ 0.08 | #FFFFFF @ 0.15 |
| TabCellBackgroundContentVisible | #FFFFFF @ 0.7 | #FAFBFF @ 0.15 (p3) |
| TabCellBackgroundCurrent | #FFFFFF @ 0.85 | #FAFBFF @ 0.2 (p3) |
| TabCellBackgroundMutiselected | #000000 @ 0.1 | #FAFBFF @ 0.1 (p3) |
| TabCellBackgroundPressed | #0E0F10 @ 0.065 (p3) | #FAFBFF @ 0.065 (p3) |
| TabCellBackgroundPrevious | #FFFFFF @ 0.32 | #FAFBFF @ 0.08 (p3) |
| TabCellBackgroundPreviousHovered | #FFFFFF @ 0.5 | #FAFBFF @ 0.12 (p3) |
| TabCellChildBackground | #000000 @ 0.07 | #FFFFFF @ 0.07 |
| TabCellShadowBackgroundSelected | #FFFFFF @ 0.9 | #000000 @ 0 |
| TabCellShadowSelected | #000000 @ 0.2 | #000000 @ 0 |
| TabCellSlash | #000000 @ 0.3 (p3) | #FFFFFF @ 0.3 (p3) |
| Vibrant.EaselBlack | #000000 | #FFFFFF |
| Vibrant.EaselDarkBlue | #3139FB | - |
| Vibrant.EaselDarkGreen | #107A00 | - |
| Vibrant.EaselGrey | #BBBBBB | - |
| Vibrant.EaselLightBlue | #00C7F3 (p3) | - |
| Vibrant.EaselLightGreen | #34E895 (p3) | - |
| Vibrant.EaselPink | #FF994E | - |
| Vibrant.EaselPurple | #C0009F | - |
| Vibrant.EaselRed | #F53714 | - |
| Vibrant.EaselWhite | #FFFFFF | #000000 |
| Vibrant.EaselYellow | #FFD335 | - |
| VibrantSecondaryText | #0C50FF @ 0.4 | #2AB6F6 @ 0.5 |
| VibrantText | #0C50FF | #2AB6F6 |

#### ARCUI_ARCUI (89 colors)

Source: `Arc.app/Contents/Resources/ARCUI_ARCUI.bundle/Contents/Resources/Assets.car`, dumped to `b/assetutil/ARCUI_ARCUI.bundle.json` (observed).

| Name | Any (light) | Dark |
|---|---|---|
| ButtonDisabledBorder | #333333 | #CCCCCC |
| ButtonDisabledFace | #B2B2B2 (p3) | #849096 (p3) |
| ContrastingButtonDropShadow | #D34955 @ 0.75 | - |
| ContrastingButtonFace | #F36672 | - |
| DestructiveButtonBorder | #FFFFFF @ 0 | - |
| DestructiveButtonDisabledFace | #FFC7BD | #673229 |
| DestructiveButtonDisabledForeground | #F53714 @ 0.3 | #FFFFFF @ 0.172 |
| DestructiveButtonDisabledIconBackground | #FFCDC4 | #703F36 |
| DestructiveButtonDisabledIconBorder | #FFFFFF @ 0.2 | #FFFFFF @ 0.1 |
| DestructiveButtonDisabledShadow | #DC2A09 @ 0.3 | #B4250A @ 0.3 |
| DestructiveButtonFace | #F53714 | - |
| DestructiveButtonForeground | #FFFFFF | - |
| DestructiveButtonHovered | #DD3112 | - |
| DestructiveButtonIconBackground | #FFFFFF @ 0.1 | - |
| DestructiveButtonIconBorder | #FFFFFF @ 0.2 | - |
| DestructiveButtonIconForeground | #FFFFFF @ 0.9 | - |
| DestructiveButtonPressed | #D02F11 | - |
| DestructiveButtonShadow | #B4250A @ 0.3 | - |
| DimmedWindowControls | #000000 | #F3F3EA |
| Gradient1 | #F19E9C @ 0.2 | - |
| Gradient2 | #1B46F5 | - |
| GradientBlue | #0047FF (p3) | - |
| GradientPeach | #FF9999 (p3) | - |
| Gray1 | #FCFCFC | #161616 |
| Gray10 | #858585 | #7E7E7E |
| Gray11 | #6F6F6F | #A0A0A0 |
| Gray12 | #171717 | #EDEDED |
| Gray2 | #F8F8F8 | #1C1C1C |
| Gray3 | #F3F3F3 | #232323 |
| Gray4 | #EDEDED | #282828 |
| Gray5 | #E8E8E8 | #2E2E2E |
| Gray6 | #E2E2E2 | #343434 |
| Gray7 | #DBDBDB | #3E3E3E |
| Gray8 | #C7C7C7 | #505050 |
| Gray9 | #8F8F8F | #707070 |
| GrayA1 | #000000 @ 0.012 | #000000 |
| GrayA10 | #000000 @ 0.478 | #FFFFFF @ 0.446 |
| GrayA11 | #000000 @ 0.565 | #FFFFFF @ 0.592 |
| GrayA12 | #000000 @ 0.91 | #FFFFFF @ 0.923 |
| GrayA2 | #000000 @ 0.027 | #FFFFFF @ 0.026 |
| GrayA3 | #000000 @ 0.047 | #FFFFFF @ 0.056 |
| GrayA4 | #000000 @ 0.071 | #FFFFFF @ 0.077 |
| GrayA5 | #000000 @ 0.09 | #FFFFFF @ 0.103 |
| GrayA6 | #000000 @ 0.114 | #FFFFFF @ 0.129 |
| GrayA7 | #000000 @ 0.141 | #FFFFFF @ 0.172 |
| GrayA8 | #000000 @ 0.22 | #FFFFFF @ 0.249 |
| GrayA9 | #000000 @ 0.439 | #FFFFFF @ 0.386 |
| Indigo1 | #FFFFFF | #141421 |
| Indigo10 | #393ECC | #5458E8 |
| Indigo11 | #3438B2 | #8589FF |
| Indigo12 | #101245 | #EDEEFC |
| Indigo2 | #F7F8FF | #16162E |
| Indigo3 | #F0F0FF | #191A40 |
| Indigo4 | #E8E9FF | #1C1D4F |
| Indigo5 | #D9DAFC | #1F215C |
| Indigo6 | #C8CAFA | #22246E |
| Indigo7 | #AEB0F5 | #272A8A |
| Indigo8 | #8E91F0 | #2E32B2 |
| Indigo9 | #3138F9 | #3239FA |
| InputFieldBackgroundColor | #FFFFFF | #FFFFFF @ 0.15 |
| InputFieldBorderColor | #DBDBDB | #FFFFFF @ 0.3 |
| NeutralButtonBorder | #DBDBDB | #6362AE |
| NeutralButtonFace | #FFFFFF | #302F63 |
| NeutralButtonForeground | #171717 | #FFFFFF @ 0.9 |
| NeutralButtonHovered | #F2F2F2 | #454473 |
| NeutralButtonIconBackground | #000000 @ 0.1 | #C7C0D7 @ 0.2 |
| NeutralButtonIconForeground | #727272 | #D7D7FF @ 0.77 |
| NeutralButtonPressed | #E5E5E5 | #2B2A59 |
| NeutralButtonShadow | #E2E2E2 | #FFFFFF @ 0 |
| PopoverArrowIcon | #1E2E69 @ 0.3 | #EEEEF6 @ 0.3 |
| PopoverBackground | #FAFBFF | #151C30 |
| PopoverBorder | #FFFFFF @ 0 | #D3CEED @ 0.2 |
| PopoverIconBackground | #10134D @ 0.1 | #C3C2FD @ 0.2 |
| PopoverIconColor | #FAFBFF | #F4F6FD @ 0.95 |
| PopoverInputText | #0E0F10 @ 0.8 (p3) | #FAFBFF @ 0.9 (p3) |
| PopoverLogoBackground | #FFFFFF @ 0.9 | #FFFFFF @ 0.6 |
| PopoverLogoShadow | #000000 @ 0.15 | #FFFFFF @ 0 |
| PopoverMessage | #060E2B @ 0.75 | #EEEEF6 @ 0.75 |
| PopoverTitle | #181B1F | #FFFFFF |
| PrimaryButtonBorder | #FFFFFF @ 0 | #FFFFFF @ 0.2 |
| PrimaryButtonFace | #3139FB | - |
| PrimaryButtonForeground | #FFFFFF | - |
| PrimaryButtonHovered | #2C33E2 | - |
| PrimaryButtonIconBackground | #FFFFFF @ 0.1 | #FFFFFF @ 0.1 |
| PrimaryButtonIconBorder | #FFFFFF @ 0.2 | #FFFFFF @ 0.2 |
| PrimaryButtonIconForeground | #FFFFFF @ 0.9 | #FFFFFF @ 0.9 |
| PrimaryButtonPressed | #2A30D5 | - |
| PrimaryButtonShadow | #3438B2 | #5A61FC @ 0.5 |
| SecondaryTextForeground | #515151 | - |

#### TopLevel (18 colors)

Source: `Arc.app/Contents/Resources/Assets.car`, dumped to `b/assetutil/TopLevel.json` (observed).

| Name | Any (light) | Dark |
|---|---|---|
| AddSpacePlusBackgroundColor | #FFFFFF | #000000 |
| AddSpacePlusIconActivatedTintColor | #FFFFFF | #000000 |
| AddSpacePlusIconDeactivatedColor | #000000 @ 0.45 | #FFFFFF @ 0.45 |
| AddSpacePlusIconTintColor | #2702C2 (p3) | #FFFFFF |
| AddSpacePlusProgressColor | #2702C2 (p3) | #FFFFFF |
| CommandBarIconActiveBackground | #FFFFFF | #1A1A1A (p3) |
| CommandBarPlaceholderIconLockInsecure | #F53714 (p3) | #F25E6B (p3) |
| CommandBarPlaceholderIconLockSecure | #000000 (p3) | #FFFFFF (p3) |
| CommandBarPlaceholderPlaceholderText | #000000 @ 0.3 | #FFFFFF @ 0.3 |
| CommandBarPlaceholderText | #000000 @ 0.6 | #FFFFFF @ 0.6 |
| DragHint | #000000 @ 0.2 | #FFFFFF @ 0.2 |
| DragHintHighlighted | #000000 @ 0.5 | #FFFFFF @ 0.5 |
| EaselBackground | #FFFFFF @ 0.85 | #000000 @ 0.5 |
| NewTabButtonPulsingTextColor | #000000 @ 0.3 | - |
| NotesBackground | #FFFFFF @ 0.85 | #000000 @ 0.5 |
| PreviewBackgroundColor | #FFFFFF | #212222 |
| SidebarBorderColor | #FFFFFF @ 0.3 | #FFFFFF @ 0.3 |
| TabListOverlapBorder | #000000 @ 0.05 | #FFFFFF @ 0.05 |

#### ARC_SpaceStyleEditor (27 colors)

Source: `Arc.app/Contents/Resources/ARC_SpaceStyleEditor.bundle/Contents/Resources/Assets.car`, dumped to `b/assetutil/ARC_SpaceStyleEditor.bundle.json` (observed).

| Name | Any (light) | Dark |
|---|---|---|
| ColorPickerDrab1 | #4B3B58 (p3) | - |
| ColorPickerDrab2 | #623856 (p3) | - |
| ColorPickerDrab3 | #854444 (p3) | - |
| ColorPickerDrab4 | #A77048 (p3) | - |
| ColorPickerDrab5 | #D1B46A (p3) | - |
| ColorPickerDrab6 | #CDCCA8 (p3) | - |
| ColorPickerDrab7 | #84A885 (p3) | - |
| ColorPickerDrab8 | #34604B (p3) | - |
| ColorPickerDrab9 | #2D4468 (p3) | - |
| ColorPickerGreyscale1 | #FFFFFF (p3) | - |
| ColorPickerGreyscale2 | #E5E5E5 (p3) | - |
| ColorPickerGreyscale3 | #CCCCCC (p3) | - |
| ColorPickerGreyscale4 | #B2B2B2 (p3) | - |
| ColorPickerGreyscale5 | #808080 (p3) | - |
| ColorPickerGreyscale6 | #666666 (p3) | - |
| ColorPickerGreyscale7 | #333333 (p3) | - |
| ColorPickerGreyscale8 | #1A1A1A (p3) | - |
| ColorPickerGreyscale9 | #000000 (p3) | - |
| ColorPickerPastel1 | #FDFBFA (p3) | - |
| ColorPickerPastel2 | #FBEAF3 (p3) | - |
| ColorPickerPastel3 | #ECD2EA (p3) | - |
| ColorPickerPastel4 | #F7CDD2 (p3) | - |
| ColorPickerPastel5 | #FAE1D5 (p3) | - |
| ColorPickerPastel6 | #FEF9E7 (p3) | - |
| ColorPickerPastel7 | #E4FCEC (p3) | - |
| ColorPickerPastel8 | #E0F2FB (p3) | - |
| ColorPickerPastel9 | #C5C6E2 (p3) | - |

#### ARC_AdBlocking (4 colors)

Source: `Arc.app/Contents/Resources/ARC_AdBlocking.bundle/Contents/Resources/Assets.car`, dumped to `b/assetutil/ARC_AdBlocking.bundle.json` (observed).

| Name | Any (light) | Dark |
|---|---|---|
| CheckboxColor | #3139FB | #B0B3FF |
| ComponentBackgroundColor | #FFFFFF | #302F63 |
| ComponentBorderColor | #E5E5E5 | #6362AE |
| ProfileIndicatorBackgroundColor | #181B1F @ 0.07 | #FFFFFF @ 0.12 |

#### ARC_AppTray (9 colors)

Source: `Arc.app/Contents/Resources/ARC_AppTray.bundle/Contents/Resources/Assets.car`, dumped to `b/assetutil/ARC_AppTray.bundle.json` (observed).

| Name | Any (light) | Dark |
|---|---|---|
| GCalSubtitleBackgroundSecondary | #000000 @ 0.07 | #FFFFFF @ 0.07 |
| GCalSubtitleBackgroundSelected | #F6F9FE @ 0.9 | - |
| GCalSubtitleTextColorSecondary | #212121 | #DEE3EB @ 0.7 |
| GCalSubtitleTextColorSelected | #212121 | - |
| GMailBadgeRed | #EA4335 | - |
| GithubBadgeBlack | #000000 | - |
| IconViewBackground | #FFFFFF | #FFFFFF @ 0.2 |
| TwitterBadgeGray | #444444 | #FFFFFF |
| WhatsAppBadgeRed | #EA4335 | - |

#### ARC_ArcMenu (8 colors)

Source: `Arc.app/Contents/Resources/ARC_ArcMenu.bundle/Contents/Resources/Assets.car`, dumped to `b/assetutil/ARC_ArcMenu.bundle.json` (observed).

| Name | Any (light) | Dark |
|---|---|---|
| MenuBackground | #FAFBFF | #393841 |
| MenuDisabledText | #ABABAB | #797881 |
| MenuHoverBackground | #B7D1FF | #3970C5 |
| MenuSeparator | #C4C4C4 | - |
| MenuSubtitle | #ABABAB | #797881 |
| MenuSubtitleHover | #797881 | #FFFFFF |
| MenuText | #494949 | #EBEBEC |
| MenuTextHover | #151515 | #FFFFFF |

#### ARC_ArcRichTextEditor (14 colors)

Source: `Arc.app/Contents/Resources/ARC_ArcRichTextEditor.bundle/Contents/Resources/Assets.car`, dumped to `b/assetutil/ARC_ArcRichTextEditor.bundle.json` (observed).

| Name | Any (light) | Dark |
|---|---|---|
| BodyText | #000000 | #FFFFFF |
| Cursor | #2702C2 | #9380E0 |
| FormatMenuBackground | #FFFFFF | #120F2E |
| FormatMenuBorder | #CDCCDF | #34334D |
| FormatMenuIcon | #6E678D | #6E678D |
| FormatMenuText | #6E678D | #8795C1 |
| HeaderText | #6E678D | #CDCDFF |
| HoveredMenuItemBackground | #EBEBEC | #FFFFFF @ 0.15 |
| Link | #220C7F | #E6E6FF |
| ListMarker | #6E678D | #CDCDFF |
| PlaceholderBodyText | #000000 @ 0.4 | #FFFFFF @ 0.4 |
| SelectedMenuItem | #2702C2 | #B6C9FA |
| SelectedMenuItemBackground | #2702C2 @ 0.1 | #062E79 |
| SelectionTextBackground | #CDCDFF | #5235CE |

#### ARC_AskArc (29 colors)

Source: `Arc.app/Contents/Resources/ARC_AskArc.bundle/Contents/Resources/Assets.car`, dumped to `b/assetutil/ARC_AskArc.bundle.json` (observed).

| Name | Any (light) | Dark |
|---|---|---|
| AccentColor | #3139FB (p3) | #5585FF (p3) |
| BackgroundColor | #FFFFFF | #000000 |
| BackgroundGradientBottomColor | #97A6CC @ 0.2 | - |
| BackgroundGradientTopColor | #EED1D1 @ 0.2 | - |
| CloseButtonBackground | #767680 @ 0.12 | - |
| ContainerBackground | #000000 @ 0.06 (p3) | - |
| DarkAccentColor | #2404AA (p3) | #5585F7 (p3) |
| FollowUpBottomQuestionBackground | #FFFFFF | #000000 |
| FollowUpButtonBackground | #E1E1FB | #000000 |
| FooterSectionBackgroundColor | #97A6CC @ 0.2 | #000000 |
| ForegroundColor | #000000 | #FFFFFF |
| LoadingBackgroundColor | #3204CA (p3) | - |
| OneBoxBackground | #E1E1FB | #272727 |
| PageBackgroundColor | #F1F0F5 | #1F2128 |
| PrimaryText | #000000 (p3) | #FFFFFF (p3) |
| QuoteBackgroundColor | #F8F8FA | #0A0A14 |
| SearchEngineLinkBackground | #F7F7F7 | #0A0A0F |
| SearchEngineLinkStroke | #EDEDED | #30303B |
| SecondaryColor | #F0F0F0 | #FFFFFF @ 0.941 |
| SecondarySurfaceColor | #F0F0F0 | #FFFFFF @ 0.08 |
| SecondaryText | #000000 @ 0.7 (p3) | #FFFFFF @ 0.7 (p3) |
| ShareCardColor | #FFFFFF | #000000 |
| ShareCardSubtitleColor | #3D3D42 @ 0.6 | #FFFFFF @ 0.6 |
| ShareCardTitleColor | #000000 | #FFFFFF |
| ShareIconColor | #3D3D42 @ 0.6 | #EBEBF5 @ 0.6 |
| ShareTextColor | #000000 @ 0.5 | #FFFFFF @ 0.5 |
| ShareTitleColor | #290A9E | #FFFFFF |
| SourcesTogglePressedColor | #5E5FEA @ 0.1 | #272727 |
| ToastColor | #0F17E8 | - |

#### ARC_AuthFeature (27 colors)

Source: `Arc.app/Contents/Resources/ARC_AuthFeature.bundle/Contents/Resources/Assets.car`, dumped to `b/assetutil/ARC_AuthFeature.bundle.json` (observed).

| Name | Any (light) | Dark |
|---|---|---|
| Accent | #3139FB | - |
| ArcMaxDarkModeBackground | #9091AD | - |
| AuthPrimaryText | #000000 @ 0.733 | #FFFFFF @ 0.8 |
| AuthSecondaryText | #000000 @ 0.5 | #FFFFFF @ 0.61 |
| BackButton | #C4C4C4 | #FFFFFF |
| ButtonBackground | #3139FB | - |
| ButtonText | #FFFFFF | - |
| CardBackground | #E6E7FF | #8C8DAB |
| CardInnerBorder | #FFFFFF @ 0 | #FFFFFF @ 0.2 |
| CardOuterBorder | #000000 @ 0 | #000000 @ 0.61 |
| Error | #F25E6B | - |
| FooterText | #FFFADD | - |
| Legacy/Accent | #3039FA | - |
| Legacy/Error | #EB4D3D (p3) | - |
| Legacy/FooterText | #000000 @ 0.66 | - |
| Logo | #3139FB | #6CBAD9 |
| MessagingText | #767676 | #FFFFFF |
| RecoveryCardBackdrop | #F4F4F4 | - |
| RecoveryCardLeftContentBackground 1 | #202020 | #202020 |
| SplitViewLeftBackground | #FFFFFF | #1E1E1E |
| TextFieldBackground | #FFFFFF @ 0 | #FFFFFF @ 0.05 |
| TextFieldBorder | #000000 @ 0.2 | #000000 @ 0.3 |
| TextFieldFocusedBorder | #3139FB | - |
| TextFieldPlaceholder | #000000 @ 0.5 | #FFFFFF @ 0.5 |
| TextFieldText | #000000 | #FFFFFF |
| Title | #000000 | #FFFFFF |
| WindowBackground | #3139FB | - |

#### ARC_BaseHomeComponents (4 colors)

Source: `Arc.app/Contents/Resources/ARC_BaseHomeComponents.bundle/Contents/Resources/Assets.car`, dumped to `b/assetutil/ARC_BaseHomeComponents.bundle.json` (observed).

| Name | Any (light) | Dark |
|---|---|---|
| Background | #000017 @ 0.07 | #FFFFFF @ 0.1 |
| Background2 | #000017 @ 0.12 | #FFFFFF @ 0.15 |
| CoolShadow | #000014 | #000014 |
| Foreground2 | #000017 @ 0.6 | #FFFFFF @ 0.6 |

#### ARC_BoostsEditor (22 colors)

Source: `Arc.app/Contents/Resources/ARC_BoostsEditor.bundle/Contents/Resources/Assets.car`, dumped to `b/assetutil/ARC_BoostsEditor.bundle.json` (observed).

| Name | Any (light) | Dark |
|---|---|---|
| BoostsBlue | #300EFF | - |
| BoostsGreen | #55B948 (p3) | - |
| BoostsLabel | #FFFFFF | #000000 @ 0.8 |
| BoostsMagenta | #DD0EFF | - |
| BoostsOrange | #FF560E | - |
| BoostsPink | #FF0E82 | - |
| BoostsPurple | #860EFF | - |
| BoostsRed | #FF0E0E | - |
| BoostsYellow | #F1A23C (p3) | - |
| DarkModeBackground | #3B3B3C | - |
| DarkModeForeground | #FBFBFF | - |
| DisabledToolButtonForeground | #F3F1FD @ 0.3 | - |
| GrayButtonForeground | #3A3A3B | - |
| InterstitialFooter | #CEDBFC | - |
| InterstitialForeground | #2E2740 | - |
| PuckBackground | #FAFBFF | - |
| SegmentedControlBackground | #000000 @ 0.07 | #FFFFFF @ 0.1 |
| SegmentedControlSelectionBackdrop | #FFFFFF | #FFFFFF @ 0.3 |
| SliderBackground | #3B3746 @ 0.05 | - |
| SliderTint | #017AFF | - |
| WarningBackground | #FF5A5F | - |
| ZapPreviewBackground | #D9D9D9 | - |

#### ARC_Capture (14 colors)

Source: `Arc.app/Contents/Resources/ARC_Capture.bundle/Contents/Resources/Assets.car`, dumped to `b/assetutil/ARC_Capture.bundle.json` (observed).

| Name | Any (light) | Dark |
|---|---|---|
| Background | #FFFFFF | #120F2E |
| BlurredBackground | #FFFFFF @ 0.33 | #000000 @ 0.25 |
| ButtonText | #000000 @ 0.3 | #FFFFFF |
| HoveredAndKeyboardSelectedBackground | #292EC1 (p3) | #292EC1 (p3) |
| HoveredCellBackground | #111455 @ 0.1 | #3A3868 |
| ImageViewBackground | #FFFFFF | #151C30 |
| OverlayBubbleBlue | #0047FF @ 0.5 (p3) | #0047FF @ 0.5 (p3) |
| OverlayBubblePink | #FF9999 @ 0.5 (p3) | #FF9999 @ 0.5 (p3) |
| OverlayBubbleText | #340594 (p3) | #340594 (p3) |
| SeeMoreEaselTextColor | #000000 @ 0.45 | #FFFFFF @ 0.45 |
| TextColor | #000000 | #FFFFFF @ 0.9 |
| TextColorForSelectedCells | #FFFFFF @ 0.95 | #FFFFFF |
| TextFieldBackground | #000000 @ 0.07 | #FFFFFF @ 0.07 |
| ToggleCellTextColor | #3139FB (p3) | #D6D7FB (p3) |

#### ARC_CommandBar (14 colors)

Source: `Arc.app/Contents/Resources/ARC_CommandBar.bundle/Contents/Resources/Assets.car`, dumped to `b/assetutil/ARC_CommandBar.bundle.json` (observed).

| Name | Any (light) | Dark |
|---|---|---|
| CommandBarAccessoryBackgroundColor | #000000 @ 0.05 | #FFFFFF @ 0.05 |
| CommandBarAccessoryForegroundColor | #000000 @ 0.5 | #FFFFFF @ 0.66 |
| CommandBarBannerBackground | #FDFDFE | #161616 |
| CommandBarBannerSecondaryButtonBackground | #FFFFFF | #232323 |
| CommandBarBannerSecondaryButtonBorder | #DBDBDB | #6F6F6F |
| CommandBarBannerSecondaryButtonText | #171717 | #FFFFFF |
| CommandBarHairlineDividerColor | #000000 @ 0.1 | #FFFFFF @ 0.1 |
| CommandBarRowHoverBackgroundColor | #000000 @ 0.05 | #FFFFFF @ 0.05 |
| CommandBarSuggestionHintPillText | #458AFF (p3) | #FAFBFF @ 0.33 (p3) |
| CommandBarTextPrimaryColor | #000000 @ 0.8 | #FFFFFF @ 0.8 |
| CommandBarTextSecondaryColor | #000000 @ 0.33 | #FFFFFF @ 0.33 |
| SecondaryWindowInputBackground | #FAFBFF (p3) | #0E0F10 (p3) |
| SecondaryWindowInputBorder | #0E0F10 @ 0.1 (p3) | #FAFBFF @ 0.2 (p3) |
| TypeTravelCapsuleBackground | #EBEBEB | #111B31 |

#### ARC_CustomInfoPicker (1 color)

Source: `Arc.app/Contents/Resources/ARC_CustomInfoPicker.bundle/Contents/Resources/Assets.car`, dumped to `b/assetutil/ARC_CustomInfoPicker.bundle.json` (observed).

| Name | Any (light) | Dark |
|---|---|---|
| CustomizationBackground | #86888D @ 0.25 (p3) | #FFFFFF @ 0.25 (p3) |

#### ARC_DeleteAccountFeature (1 color)

Source: `Arc.app/Contents/Resources/ARC_DeleteAccountFeature.bundle/Contents/Resources/Assets.car`, dumped to `b/assetutil/ARC_DeleteAccountFeature.bundle.json` (observed).

| Name | Any (light) | Dark |
|---|---|---|
| ErrorMessageForegroundColor | #C93333 | #FF5A5F |

#### ARC_EaselUI (18 colors)

Source: `Arc.app/Contents/Resources/ARC_EaselUI.bundle/Contents/Resources/Assets.car`, dumped to `b/assetutil/ARC_EaselUI.bundle.json` (observed).

| Name | Any (light) | Dark |
|---|---|---|
| AvatarIcon | #5F5880 @ 0.3 | #85878E (p3) |
| CaptureButtonHovered | #F0F1F3 | #373C4B |
| CaptureButtonNormal | #FFFFFF | #252832 |
| CaptureButtonPressed | #E3E6E7 | #495064 |
| CaptureLinkIconBackground | #090909 @ 0.07 | #F6F6F6 @ 0.11 |
| CommentBackground | #F0EFF4 | #F0EFF4 |
| EaselLightText | #2702C2 @ 0.25 | #2702C2 @ 0.25 |
| EaselSelectionColor | #6CBAD9 | #6CBAD9 |
| EaselUnreadCommentText | #2702C2 | #2702C2 |
| ErrorBorder | #D13B23 (p3) | #D18881 (p3) |
| FloatingElementBackground | #FFFFFF | #000000 |
| HighlightedTextColor | #FFFFFF | #FFFFFF |
| ImageViewFillerBackground | #000000 @ 0.1 (p3) | #686A6B (p3) |
| LoadingStateForeground | #5F5880 | #FFFFFF |
| ModalBackground | #FFFFFF | #120F2E |
| ModalOutline | #120F2E @ 0.03 | #FCFFFF @ 0.1 |
| TextColor | #000000 | #FFFFFF |
| ToolbarIcon | #5F5880 | #85878E (p3) |

#### ARC_HomeButton (18 colors)

Source: `Arc.app/Contents/Resources/ARC_HomeButton.bundle/Contents/Resources/Assets.car`, dumped to `b/assetutil/ARC_HomeButton.bundle.json` (observed).

| Name | Any (light) | Dark |
|---|---|---|
| Background | #000017 @ 0.07 | #FFFFFF @ 0.1 |
| Background2 | #000017 @ 0.12 | #FFFFFF @ 0.15 |
| Background3 | #000017 @ 0.2 | #FFFFFF @ 0.2 |
| CoolShadow | #000014 | #000014 |
| EaselTitleText | #101118 @ 0.8 | #FFFFFF @ 0.8 |
| Foreground | #000017 | #FFFFFF |
| Foreground2 | #000017 @ 0.6 | #FFFFFF @ 0.6 |
| Foreground3 | #000017 @ 0.45 | #FFFFFF @ 0.45 |
| LibraryItemOutline | #000000 @ 0.03 | #FFFFFF @ 0.08 |
| NoteContentText | #000000 @ 0.3 | #FFFFFF @ 0.3 |
| NoteTitleText | #1C177A @ 0.8 | #FFFFFF |
| PreviewToolbarBackground | #F8F8F8 @ 0.66 | #000000 @ 0.66 |
| PreviewToolbarButtonBackground | #596069 @ 0.7 | #FFFFFF @ 0.5 |
| WelcomeGradientBlue | #0047FF (p3) | #0047FF (p3) |
| WelcomeGradientPink | #FF9999 (p3) | #FF9999 (p3) |
| WelcomeScreenButtonText | #FFFFFF | #FFFFFF |
| WelcomeScreenCardBackground | #FFFFFF | #131418 |
| WelcomeScreenText | #704067 | #E1CEDE |

#### ARC_ImportFeature (13 colors)

Source: `Arc.app/Contents/Resources/ARC_ImportFeature.bundle/Contents/Resources/Assets.car`, dumped to `b/assetutil/ARC_ImportFeature.bundle.json` (observed).

| Name | Any (light) | Dark |
|---|---|---|
| AuthFlowDropTargetBackground | #E0E1FF | #191B4C |
| AuthFlowDropTargetBackgroundCompleted | #C5E5C0 | - |
| AuthFlowDropTargetBorder | #2C33E1 | #3239FB |
| AuthFlowDropTargetError | #C93333 | - |
| AuthFlowDropTargetForeground | #2C33E2 | #FFFFFF (p3) |
| AuthFlowDropTargetForegroundCompleted | #3EA82E | - |
| AuthFlowDropTargetKeyForeground | #2C33E2 | #8488FF |
| AuthFlowFolderBackgroundFill | #C0C1F4 | - |
| AuthFlowFolderForegroundFill | #F0F0EF | - |
| AuthFlowFolderStrokeColor | #3138FC | - |
| AuthFlowKeychainHelpText | #848484 (ext sRGB) | - |
| AuthFlowKeychainMessagingText | #000000 @ 0.847 (srgb  system labelColor) | #FFFFFF (p3) |
| BrowserSelectionShadowIndicator | #FFFFFF | #000000 @ 0 |

#### ARC_LittleBrowser (4 colors)

Source: `Arc.app/Contents/Resources/ARC_LittleBrowser.bundle/Contents/Resources/Assets.car`, dumped to `b/assetutil/ARC_LittleBrowser.bundle.json` (observed).

| Name | Any (light) | Dark |
|---|---|---|
| DownloadItemBackground | #FFFFFF | #0D0D0D (p3) |
| DownloadItemBackgroundHovered | #F5F5F5 (p3) | #1F1F1F (p3) |
| LittleBrowserCommandBarPlaceholderBackground | #0E0F10 @ 0.06 (p3) | #FAFBFF @ 0.1 (p3) |
| LittleBrowserCommandBarPlaceholderBackgroundHovered | #0E0F10 @ 0.1 (p3) | #FAFBFF @ 0.15 (p3) |

#### ARC_MediaControlsFeature (1 color)

Source: `Arc.app/Contents/Resources/ARC_MediaControlsFeature.bundle/Contents/Resources/Assets.car`, dumped to `b/assetutil/ARC_MediaControlsFeature.bundle.json` (observed).

| Name | Any (light) | Dark |
|---|---|---|
| PlaybackControlForeground | #000000 @ 0.5 | #FFFFFF @ 0.66 |

#### ARC_PictureInPicture (2 colors)

Source: `Arc.app/Contents/Resources/ARC_PictureInPicture.bundle/Contents/Resources/Assets.car`, dumped to `b/assetutil/ARC_PictureInPicture.bundle.json` (observed).

| Name | Any (light) | Dark |
|---|---|---|
| DocumentPiPHairlineColor | #FFFFFF @ 0.2 | #FFFFFF @ 0.2 |
| DocumentPiPTopBarBackgroundColor | #212123 | #212123 |

#### ARC_PreferencesFeature (25 colors)

Source: `Arc.app/Contents/Resources/ARC_PreferencesFeature.bundle/Contents/Resources/Assets.car`, dumped to `b/assetutil/ARC_PreferencesFeature.bundle.json` (observed).

| Name | Any (light) | Dark |
|---|---|---|
| EmailChangePendingVerificationBackground | #FFFFFF | #36363A |
| EmailChangePendingVerificationOutline | #000000 @ 0.3 | #FFFFFF |
| EmailChangePendingVerificationTextForeground | #3D3D3D | #FFFFFF |
| EnableSyncDialogDescriptionTextColor | #060E2B @ 0.75 | #EEEEF6 @ 0.75 |
| EnableSyncDialogTitleTextColor | #181B1F | #FFFFFF |
| ErrorMessageBackgroundColor | #C93333 @ 0.1 | #C93333 @ 0.33 |
| ErrorMessageBorderColor | #FFFFFF @ 0 | #FFCECE @ 0.2 |
| ErrorMessageForegroundColor | #C93333 | #FF5A5F |
| FirebaseSidebarSyncBorderColor | #6F6F6F | #6F6F6F |
| FirebaseSyncDialogIconBackgroundColor | #10134D | - |
| FirebaseSyncSecondaryTextColor | #8A8A8A | #9F9EA0 |
| InfoMessageBackgroundColor | #3EA82E @ 0.1 | #000000 @ 0.4 |
| MakeDefaultViewBackgroundColor | #FFFFFF | #656068 |
| MaxBannerColor | #484FFF | - |
| MemberCardActionButtonColor | #6F6F6F | #6F6F6F |
| PanelFontColor | #3D3D3D | #FFFFFF |
| PreferencesButtonBackgroundColor | #000000 @ 0.15 | #E0DFE0 @ 0.07 |
| PreferencesButtonForegroundColor | #5F5F5F | #E0DFE0 |
| PreferencesIconButtonBackgroundColor | #DBDFE5 | #515671 |
| PreferencesLinkBackgroundColor | #C2D9FF | #C2D9FF @ 0.25 |
| PreferencesLinkColor | #458AFF | #458AFF |
| PreferencesLoadableButtonBackgroundColor | #FFFFFF | #FFFFFF @ 0.15 |
| PreferencesSectionHighlightBackgroundColor | #F5E8C7 | #FFFFFF @ 0.077 |
| PreferencesSectionHighlightTextColor | #7D5E0F | #FFFFFF |
| PreferencesSectionPrimaryForegroundColor | #000000 @ 0.66 | #F3F3F3 |

#### ARC_ProfilesUI (2 colors)

Source: `Arc.app/Contents/Resources/ARC_ProfilesUI.bundle/Contents/Resources/Assets.car`, dumped to `b/assetutil/ARC_ProfilesUI.bundle.json` (observed).

| Name | Any (light) | Dark |
|---|---|---|
| ProfilePicker | #3139FB @ 0.1 | #3139FB @ 0.898 |
| ProfilePickerText | #060E2B | #E3E2EE |

#### ARC_ReferralCodeFeature (11 colors)

Source: `Arc.app/Contents/Resources/ARC_ReferralCodeFeature.bundle/Contents/Resources/Assets.car`, dumped to `b/assetutil/ARC_ReferralCodeFeature.bundle.json` (observed).

| Name | Any (light) | Dark |
|---|---|---|
| ReferralDaysLeftTextColor | #196442 | #23B573 |
| ReferralDialogBackgroundColor | #FFFFFF | #151C30 |
| ReferralDialogHeaderColor | #3139FB | #FFFFFF |
| ReferralDialogParagraphColor | #171717 | #FCFCFC |
| ReferralToastBackgroundColor | #F1FCF7 | #234435 |
| ReferralToastTextColor | #16A563 | #75E2B0 |
| TicketBackgroundColor | #75E2B0 @ 0.1 | #75E2B0 @ 0.1 |
| TicketBottomStubBackgroundColor | #75E2B0 | #75E2B0 |
| TicketIconColor | #24B573 | #23B573 |
| TicketStrokeColor | #46C88D | #46C78D |
| TicketTextColor | #196442 | #196442 |

#### ARC_SidebarSyncCloudKit (3 colors)

Source: `Arc.app/Contents/Resources/ARC_SidebarSyncCloudKit.bundle/Contents/Resources/Assets.car`, dumped to `b/assetutil/ARC_SidebarSyncCloudKit.bundle.json` (observed).

| Name | Any (light) | Dark |
|---|---|---|
| FAQTextColor | #FFFFFF | #E1E1E1 |
| RecoveryCardBackgroundColor | #202020 | - |
| RecoveryPhraseTextColor | #D3D3D3 | - |

#### ARC_SoftwareUpdaterClient (1 color)

Source: `Arc.app/Contents/Resources/ARC_SoftwareUpdaterClient.bundle/Contents/Resources/Assets.car`, dumped to `b/assetutil/ARC_SoftwareUpdaterClient.bundle.json` (observed).

| Name | Any (light) | Dark |
|---|---|---|
| UpdaterButtonBackgroundColor | #FFFFFF | #000000 |

#### ARC_TextEditor (3 colors)

Source: `Arc.app/Contents/Resources/ARC_TextEditor.bundle/Contents/Resources/Assets.car`, dumped to `b/assetutil/ARC_TextEditor.bundle.json` (observed).

| Name | Any (light) | Dark |
|---|---|---|
| GutterMenuItemSelected | #D9D9E0 | #FFFFFF @ 0.3 |
| TitlePlaceholderText | #220C7F @ 0.4 | #E6E6FF @ 0.4 |
| TitleText | #220C7F | #E6E6FF |

#### ARC_Translation (1 color)

Source: `Arc.app/Contents/Resources/ARC_Translation.bundle/Contents/Resources/Assets.car`, dumped to `b/assetutil/ARC_Translation.bundle.json` (observed).

| Name | Any (light) | Dark |
|---|---|---|
| Background | #FFFFFF | #1A1A1A (p3) |

#### ARC_URLInputter (4 colors)

Source: `Arc.app/Contents/Resources/ARC_URLInputter.bundle/Contents/Resources/Assets.car`, dumped to `b/assetutil/ARC_URLInputter.bundle.json` (observed).

| Name | Any (light) | Dark |
|---|---|---|
| Background | #FFFFFF | #120F2E |
| FontColor | #000000 | #FFFFFF |
| PlaceholderBackground | #3D3E40 @ 0.33 | #3D3E40 @ 0.33 |
| TextFieldBackground | #EBEBEC | #3139FB @ 0.15 |

## 2. Iconography, fonts, motion and sound

### What ARCClients_Icons.bundle actually contains

The bundle holds no images and no asset catalog, only two icon fonts. (ev: `b/resources-file-list.txt`; observed)

- `icomoon.ttf`: 285 glyphs at U+E900 to U+EA19, family name "icomoon", and no glyph names (its `post` table is version 3, which stores none). (ev: `b/icon-fonts-glyphs.txt`, `b/icomoon-codepoints.txt`; observed) The code's font enum is `IconFontType` = `feather`, `ionicons`, `emoji`, `mobileEmoji`, and the type wrappers are `Icons.FeatherIcon` and `Icons.Ionicon`. (ev: `swift:Icons.IconFontType`; observed) So icomoon.ttf is the Feather icon set exported through IcoMoon; Feather has about 287 icons, which matches the glyph count. (inferred)
- `ionicons.ttf`: 1,180 named glyphs at U+F101 to U+F5CB, 456 base names, most in three styles (plain, `-outline`, `-sharp`), plus 72 `logo-*` glyphs. These are standard Ionicons names such as `add-circle-outline`, `archive-sharp`, `airplane`. (ev: `b/icon-fonts-glyphs.txt`; observed)
- Which Feather glyph Arc uses for which action cannot be read from the resources. The names exist only as static constants in the stripped binary. (unknown)
- The space and folder icon picker writes `updateSpaceIcon` / `updateSidebarItemIcon` and a space icon can be an emoji (`R/ARC_Emojis.bundle/Contents/Resources/emojis.json`, 1,870 emoji with names, categories and tags) or a symbol (`R/ARCFoundation_ARCFoundationBase.bundle/Contents/Resources/SFSymbolEmojiLookupTable.json`, 4,491 SF Symbol to emoji pairs). (ev: `swift:Arc.CustomInfoPickerHostingView.Action`; observed) That the Ionicons set backs the icon picker is inferred from it being the only full general-purpose icon set shipped.

### Icons grouped by purpose

These come from image assets, Lottie files and SF Symbol names found in the binary. (ev: `b/image-asset-names.tsv`, `b/binary-sfsymbol-names.tsv`, `b/swift-fieldmd-types.tsv`)

| Purpose | Icons | Source | Label |
|---|---|---|---|
| Sidebar "+" menu | add-tab, tab, add-space, space, folder, easel, note, boost, boost_legacy, split-add-right, split-add-bottom | ARC_SidebarPlusButton Assets.car | observed |
| Sidebar bottom / Library ("Home") | archive, boosts, downloads, easels, screenshots, spaces (animated Lottie); BoostLarge, boost, easel, note images; LibraryIcon, ArchiveIcon, SettingsIcon | ARC_HomeButton, ARCClients_BaseAssets | observed |
| Sidebar top controls | icon-browser-navigation-sidebar, icon-browser-navigation-reload, icon-browser-navigation-force-reload, icon-browser-navigation-clear-cookies, icon-arc, cmd-t | top-level Assets.car | observed |
| Reload button states | `ReloadIcon.Icon` = reload, stop; animated button icons `TranslucentButtonIconAnimation` = arrow, crossOrHyphen, moreMenu, plusMenu, speaker, reload, forceReload, copyLink, cross, things | `swift:ARCUI.*` | observed |
| Tab states | Selected, previous, hovered, pressed, multi-selected and content-visible states are drawn with fills, not icons (TabCell* colors). Audio uses SF Symbols speaker.wave.1/2/3.fill and speaker.slash.fill; MusicSprite1/2 images; SmallCloseButton | BaseAssets, ARCUI, binary | colors and names observed; audio use inferred from names |
| Folders | FolderEllipsesLight / Dark; SF folder, folder.badge.plus | BaseAssets, binary | observed |
| Spaces and profiles | add-space, space, smiley (space creation), icon-archie, icon-archie-add, -delete, -move, -question, -space (profile mascot "Archie"), MoonLight/Dark, SunLight/Dark | SidebarPlusButton, SpaceCreation, ProfilesUI, BaseAssets | observed |
| Theme editor | GrainKnob, SandKnob, DenimKnob, TweedKnob, DotGrid; Lottie sun, moon, automatic | ARC_SpaceStyleEditor | observed |
| Command bar | `CommandBarIconView.IconType` = none, infoOutline, searchOutline, linkOutline, insecureLock, secureLock, closeFullscreen, globe, people, close; `SymbolIconType` = address, archive, back, bidirectional, bolt, creditCard, devtools, document, download, email, extensions, folder, generic, password, play, share, sidebarLeading, warning; OpenAIIconTemplate, LinearIconTemplate | `swift:Arc.CommandBarIconView.IconType`, `swift:ARCFoundationModels.SymbolIconType`, ARC_CommandBar | observed |
| URL pill buttons | copyLink, copyQuoteLink, shareSplit, siteControlCenter; site control center images boost.fill, boost.sparkle, boost.sparkle.fill, capture-full-page, copy-url, icon-control-center, icon-control-center-fill, share, window-screenshot-icon | `swift:Arc.CommandBarPlaceholderButtonID.StaticButton`, ARC_SiteControlCenter | observed |
| Split view | icon-split-add-top / bottom / left / right, icon-split-move-*, icon-split-horizontal, icon-split-vertical, icon-split-close, icon-split-x, icon-split-share-horizontal / vertical, icon-separate-from-split(-menu-bottom, -opaque) | ARC_ContextMenus | observed |
| Easel tools | EaselIconPointer, Freehand, Line, Arrow, Rectangle, Ellipse, Triangle, Shapes, Text, Image; FontStyleSystem / Fancy / Hip / Mono; FontSizeH1 / H2 / Body; PaintBucketIcon; cursor images | ARC_EaselUI | observed |
| App icons (Settings) | `ArcAppIcon` = original, candy, hologram, neon, flutedGlass, schoolbook, colorful; image previews AppIconOriginal, Candy, Colorful, Hologram, Neon, FlutedGlass, Schoolbook, EarlyBirds, Canary, Dev | `swift:BaseModels.ArcAppIcon`, BaseAssets | observed |

### Fonts

`ARCClients_FontsManager.bundle` ships 83 font files. (ev: `b/fonts-inventory.tsv`; observed)

| Family | Styles shipped |
|---|---|
| ABC Favorit | Regular, Regular Italic, Bold |
| ABC Favorit Lining | Medium, Bold |
| ABC Favorit Mono | Regular, Medium, Bold, each with Italic |
| ABC Oracle | Book |
| EB Garamond | Regular, Italic (variable weight) |
| GT Ultra | GT-Ultra-VF and a second "Ultra" variable file |
| Inconsolata | Light, Regular, Medium, Bold |
| Inter | Regular, Medium, SemiBold, Bold |
| Marlin Soft | Medium, Extra Black |
| Marlin Soft SQ | Regular, Medium, Bold, Bold Italic, Extra Bold, Extra Bold Italic, Black |
| National 2 (Test) | Light, Regular, Bold |
| Nunito | ExtraLight to Black, each with Italic (14 files) |
| Pitch, Pitch Sans | Light, Regular, Medium, Semibold, Bold, each with Italic |
| Söhne (Test) | Leicht, Buch, Halbfett |
| Söhne Breit | Buch, Dreiviertelfett, Extrafett, each with Kursiv |
| Space Mono | Regular, Italic, Bold, Bold Italic |

- National 2 and Söhne ship as "Test" (trial) cuts, for example `National2Test-Regular.otf`, `SoehneTest-Buch.otf`. (ev: `R/ARCClients_FontsManager.bundle/Contents/Resources/`; observed)
- The user-facing font switch is `FontsOptions` = system, national, sohne, chalkboard, inconsolata. A `FontSet` has the roles label, subLabel, listHeader, sectionHeader, boldSectionHeader, sectionEntry, sectionHeaderButton, title, smallCaps, searchHeader, chatStatusText, chatTimestamp. (ev: `swift:FontsManager.FontsOptions`, `swift:FontsManager.FontSet`; observed) So the default sidebar and command bar UI uses the system font (SF Pro), and the bundled faces are for optional UI fonts, Easel text styles, membership cards and marketing surfaces. (inferred: `system` is the first option and no other resource names a default)
- Which family backs each Easel style (System, Fancy, Hip, Mono) is not stated in resources. (unknown)

### Lottie animations

All are Lottie 5.9.4. (ev: `b/lottie-inventory.txt`; observed)

| File | Size, rate, length | Markers / layers | Used for |
|---|---|---|---|
| ARC_HomeButton/archive.json | 128 px, 60 fps, 2.0 s | hover-start f1, hover-end f11, selection-end f35 | Library Archive icon (observed name) |
| ARC_HomeButton/boosts.json | 128 px, 60 fps, 1.0 s | f1, f11, selection-end f45 | Library Boosts icon |
| ARC_HomeButton/downloads.json, easels.json, screenshots.json, spaces.json | 128 px, 60 fps, 1.0 s | f1, f11, selection-end f35 | Library Downloads, Easels and Notes, Screenshots, Space Manager icons |
| ARC_SpaceStyleEditor/sun.json | 500 px, 60 fps, 1.0 s | circle, rays | Light appearance toggle |
| ARC_SpaceStyleEditor/moon.json | 500 px, 60 fps, 1.5 s | moon, star-big, star-small | Dark appearance toggle |
| ARC_SpaceStyleEditor/automatic.json | 500 px, 60 fps, 1.5 s | star-big, star-big 2, star-small | Automatic appearance toggle |
| ARC_SidebarBanner/update-heart-animation.json | 350 px, 60 fps, 2.0 s | heart, ring-1 | Update banner in the sidebar |
| ARCUI_ARCUI/logo-wave.json | 225 px, 60 fps, 3.0 s | two stroke vectors | Animated Arc logo |
| ARC_PreferencesFeature/smiley.json | 100 px, 30 fps, 5.0 s | left-eye, right-eye, smile | Settings illustration |

The "Used for" column is inferred from bundle and file names, and for the six Library icons from the Library categories in the code (`LibraryCategory` = all, screenshots, downloads, desktop, documents, links, notesAndEasels, spaceManager, archive, boosts; ev: `swift:AnalyticsClient.AnalyticsEventProperties.LibraryCategory`; observed).

- The six Library icons share one timing model: hover plays frames 1 to 11 (about 0.17 s at 60 fps), a click plays on to frame 35 (about 0.57 s; Boosts to frame 45, 0.73 s). Their layers are all named `primaryColor` or `secondaryColor`. (ev: `b/lottie-inventory.txt`; observed) So the icons are recolored at runtime to match the space theme. (inferred from layer names)
- The appearance toggles map to `LoopingToggleView.Animation` = sun, moon, automatic. (ev: `swift:SpaceStyleEditor.LoopingToggleView.Animation`; observed)
- Purposes for update-heart, logo-wave and smiley come from their bundle and file names. (inferred)

### Videos

| File | Length, size | Purpose |
|---|---|---|
| ARC_WelcomeToArcFeature/new_tab.mp4, pinning.mp4, space_swiping.mp4, split_view.mp4 | 8.5 s each, 1920 x 1200 | The four "Arc 101" welcome steps `newTab`, `pinTabs`, `spaces`, `splitView` (ev: `swift:WelcomeToArcFeature.Arc101Step`; observed) |
| ARC_AuthFeature/demo.mov, intro-music.mp3, static-bg.png | 18.3 s at 1920 x 1280; music 21.3 s | First-run intro before sign-up (inferred from bundle) |
| ARCUI_ARCUI/background.mp4, orb.mp4 | 8.0 s and 6.0 s, 100 x 100 | Small looping orb, likely for AI features next to `animatingOrbBlob1/2` images (inferred) |

(ev: `b/video-inventory.txt`; observed lengths and sizes)

### Sound effects

| File | Format | Purpose | Label |
|---|---|---|---|
| ARC_SoundEffects/capture.wav | 0.63 s, 48 kHz, 24-bit stereo PCM | The only case of `SoundEffects.SoundEffect` is `capture`, so this plays when you take a Capture (screenshot) | enum observed; trigger inferred |
| ARC_SoundEffects/event.m4a | 3.52 s, 44.1 kHz AAC stereo | Not referenced by the sound-effect enum; the binary has calendar reminder options (`LiveCalendarInterval` = never, onStart, twoMinutesBefore, fiveMinutesBefore, tenMinutesBefore) | file observed; purpose unknown, a meeting alert is a guess |
| ARC_AuthFeature/intro-music.mp3 | 21.3 s, 48 kHz MP3 | Intro soundtrack | inferred |

Sound playback is gated by the setting "Play Arc sound effects" (`bin:0x1039f78e0`) and the default key `playUserInterfaceSoundsDisabled` (`bin:0x10396b1b0`). (ev: `b/sound-afinfo.txt`, `swift:SoundEffects.SoundEffect`; observed)

## 3. UI copy (English)

### Where the English copy came from

`b/en-strings.tsv` (columns bundle, key, value; 11,816 rows) merges every English string source in the bundle (ev: `b/scripts/merge_strings.py`; observed):

| Source | Rows | Notes |
|---|---|---|
| `ARC_AskArc.bundle/.../en.lproj/Localizable.strings` | 6 | "Dive Deeper", "Entities: %@", "Read %d pages", "Reading %d web pages", "Making a website for you", "Top Search Results" |
| `Settings_Settings.bundle/.../en, en-GB, en-AU.lproj/Localizable.strings` | 6 | "Preferences", "Settings" (a third-party settings-window package; inferred from bundle name) |
| `en-GB.lproj/MainMenu.strings` | 2 | "Copy", "Edit" |
| `Base.lproj/MainMenu.nib` (decoded) | 189 | Every menu title, with its shortcut in the key column |
| `Contents/Info.plist` | 9 | Permission prompts, for example "Websites may use your camera for features on their site." |
| `Arc.sdef` | 98 | AppleScript dictionary names and descriptions |
| `MacOS/Arc` `__TEXT,__cstring` | 11,506 | Strings that contain a space and are mostly letters; code, paths and JavaScript removed. Includes translator comments such as "Tooltip for the button to close a folder." |

The binary keeps each long English value directly before its comment, for example "Add some flair with a theme." (`bin:0x1039d4ae0`) followed by "Title for theme step in onboarding" (`bin:0x1039d4b00`). (observed) When a comment has no value in front of it, the value was 15 bytes or shorter and lives in code. (inferred) In the lists below, plain quotes are visible UI text; lines starting with "comment:" are the developer's description of a string whose visible text could not be recovered.

### Sidebar sections

Model: the sidebar has `topApps` (Favorites) and `spaceItems`; each space has `pinned` and `unpinned` containers, and the unpinned container can be `desktop` or `shared`. List accessories are `pinnedTabsHeader`, `pinnedTabsFooter`, `unpinnedTabsHeader`, `newTabButton`, `exploreSectionDivider`. AppleScript describes tab location as "Represents the location of the tab in the sidebar. Can be 'topApp', 'pinned', or 'unpinned'." (ev: `swift:BaseModels.SidebarItemContainer.ContainerType`, `swift:BaseModels.SpaceModel.ContainerType`, `swift:BaseModels.TablistAccessoryViewType`, `b/en-strings.tsv` Arc.sdef; observed) In the UI, "Favorites", "Top Apps" and "Today" all name these sections. (observed in the strings below)

Favorites / Top Apps:
- "Drag to add Favorites" (`bin:0x1039eac10`, observed); comment: "Empty state title for the Top Apps tray" (`bin:0x1039eac30`, observed)
- "Favorites keep your most used sites and apps close" (`bin:0x1039eaba0`, observed), the empty-state subtitle
- "Move to Top Apps" (`bin:0x1039ed0b0`), "Remove from Top Apps" (`bin:0x1039ed180`), "Unpin from Top Apps" (`bin:0x1039ed1e0`) (observed)
- comment: "Remove current item from Favorites." / "Move current item to Favorites." (`bin:0x1039eca70`, `bin:0x1039ecaa0`, observed)

Pinned:
- "Collapse Pinned Tabs" (`bin:0x103958880`), "Expand Pinned Tabs" (`bin:0x1039588d0`); menu "Expand Pinned Section" (`nib:617`), "Collapse Pinned Section" (`nib:840`) (observed)
- "Back to Pinned URL" (`bin:0x1039568f0`), "Separate From Pinned Tab" (`bin:0x103956950`), "Close and Keep Pinned" (`bin:0x103956b80`), "Replace Pinned Tab with the Current Site" (`bin:0x1039ecb40`) (observed)
- "Move to Pinned in " (`bin:0x1039ed050`), with the space name appended (observed; appending inferred from trailing space)
- Toasts: "Pinned Tab to “%@”" (`bin:0x1039db120`), "Un-Pinned Tab from “%@”" (`bin:0x1039db0b0`) (observed)
- "Like a bookmarks bar, your Pinned Tabs keep the things you need within reach." (`bin:0x1039fdc70`, observed)

Today / unpinned:
- "Clear Today tabs" (`bin:0x10394f670`), "Clear unselected Today tabs" (`bin:0x10394f6c0`) (observed); comment: "Button Title; Clear unpinned tabs in this space" (`bin:0x10394f5b0`, observed)
- "Organize Today Tabs" (`bin:0x10394f5e0`, observed); comment: "Tooltip; Use LLM to organize unpinned tabs in this space" (`bin:0x10394f600`, observed)
- "Move to Today in " (`bin:0x1039ecfd0`, observed)
- comment: "Title for unpinned tabs in the sidebar." (`bin:0x103a068c0`, observed); the visible title itself is short and not recoverable (unknown)
- comment: "Section title for Home items bucked into a “Today” section." (`bin:0x103a0faf0`, observed)

Folders:
- "New Folder from Selection…" (`bin:0x1039585f0`), "Create New Folder" (`bin:0x1039ed430`), menu "New Folder…" (`nib:959`) (observed)
- "Close This Folder" (`bin:0x103956190`), "Close All Folders" (`bin:0x1039ed500`), "Reveal All Folders" (`bin:0x1039ed580`), "Clean up Folders" (`bin:0x1039ed490`), "Expand All Folders" (`bin:0x1039ec900`), "Collapse All Folders" (`bin:0x1039ec940`) (observed)
- "Deleting this folder will archive the tabs inside it." (`bin:0x103a18060`), "This will archive all the tabs and folders inside it." (`bin:0x103a18780`) (observed)
- "Creates a new folder for your tabs, Easels, Notes, and everything else you can squeeze in. Supports multiselect to prefill the created folder." (`bin:0x1039fb7d0`, observed)
- Live folders: "Automatic Live Folders" (`bin:0x103952800`), "Live Folder Created" (`bin:0x103a0a940`), "Login with SSO to unlock this folder" (`bin:0x10395ed40`) (observed)

### Spaces

- Create: menu "New Space…" (`nib:1195`); "Creates a new Space {em dash} for your work tabs, personal tabs, or otherwise." (`bin:0x1039fb900`); "Create new space?" (`bin:0x103952d40`); toast "New Space Created" (`bin:0x1039db000`) (observed)
- Creation flow fields: `title`, `selectedProfile`, `customInfo` (icon), `spaceStyleEditor` (theme), phases `editing`, `animating`, `complete`; cards for theme and profile (`ThemeCardView`, `ProfileCardView`, `TextAndIconPicker`) (ev: `swift:SpaceCreation.*`; observed)
- Purpose copy: "Spaces give you separate sidebars for projects, work, life, and hobbies." (`bin:0x1039fdc20`), "Spaces for work and life" (`bin:0x1039fdd40`) (observed)
- Rename: menu "Rename Space" (`nib:442`); comments "Button that updates the Space name" (`bin:0x103a15bc0`), "Cancel updating Space name" (`bin:0x103a15bf0`), "Title for the 'Rename' menuItem in the Space Context Menu." (`bin:0x103a37b50`) (observed). Fallback name comment: "Fallback title for a space, with the index of the space. e.g "Space N"" (`bin:0x103986440`, observed)
- Color: menu "Edit Theme…" (`nib:1424`); "Edit Theme Color…" (`bin:0x103a37d70`); "Edit Space theme" (`bin:0x10395fb00`); "Tap to pick a color for this space" (`bin:0x1039d3b70`) (observed)
- Emoji / icon: "Change Space Icon…" (`bin:0x103a37dc0`); "Default Space Icon" (`bin:0x103a03d90`); comment "Tooltip; Button that reveals a control to edit a space's icon." (`bin:0x103952990`) (observed)
- Switch: menu "Next Space" ⌥⌘→ (`nib:808`), "Previous Space" ⌥⌘← (`nib:1108`); "Slides to the next Space in your Sidebar." (`bin:0x1039fbc80`); "Jumps over to your %@ Space without needing to swipe." (`bin:0x1039fa870`, with an ordinal such as “1st”) (observed). Spaces are pages you swipe between in the sidebar. (inferred from "swipe" copy and `space_swiping.mp4`)
- Manage: "Manage Spaces…" (`bin:0x103a37c40`), "Search Spaces…" (`bin:0x103a05d40`), "Drag to Reorder Space" (`bin:0x103952bb0`), "Show Space Header" / "Hide Space Header" (`bin:0x103a37c80`, `bin:0x103a37cd0`), "Export “%@” into Folder" (`bin:0x103a37e10`), toast "Space turned into folder" (`bin:0x103a186f0`), "Delete your “%@” Space?" (`bin:0x103a18710`) (observed)

### Tabs

| Action | Copy | Evidence | Label |
|---|---|---|---|
| New | Menu "New Tab…" ⌘T; "Creates a new tab."; "Open the Command Bar to create a new tab"; toast "New Tab Created in %@" | `nib:830`, `bin:0x1039fb950`, `bin:0x1039f1830`, `bin:0x1039dc090` | observed |
| Close = archive | Menu "Archive Tab" ⌘W; "Closes the tab or window that’s in focus."; hover button "Archive this tab" with comment "Tooltip; closes the tab the user is hovering over, then removes it from the sidebar and archives it." | `nib:968`, `bin:0x1039fae70`, `bin:0x103956af0`, `bin:0x103956b10` | observed |
| Bulk archive | "Archive Other Tabs", "Archive Tabs Below", "Archive Tabs Above" | `bin:0x103a37520`, `bin:0x103a37580`, `bin:0x103a375f0` | observed |
| Pin / unpin | Menu "Pin/Unpin Tab" ⌘D; "Adds or removes the current tab from the pinned section of your Sidebar." | `nib:181`, `bin:0x1039fbaa0` | observed |
| Rename | Menu "Rename Current Item"; "Rename Current Tab…"; hover hint "Double-click to rename"; "Rename the current tab." | `nib:142`, `bin:0x1039ec9a0`, `bin:0x103956a30`, `bin:0x1039fc0e0` | observed |
| Restore | Menu "Restore Last Closed Tab" ⇧⌘T; "Reopens the most recently closed tab."; toasts "Tab restored to ", "Folder restored to " | `nib:717`, `bin:0x1039fbbd0`, `bin:0x1039da130`, `bin:0x1039da090` | observed |
| Clear | Menu "Clear Unpinned Tabs" ⇧⌘K; "Moves all your unpinned tabs to the Archive."; "Clear Today tabs" | `nib:498`, `bin:0x1039faf70`, `bin:0x10394f670` | observed |
| Reset | Menu "Reset Tab to Original URL"; "Reset tab to original URL."; "Resets all your pinned tabs in the current Space." | `nib:1348`, `bin:0x1039fc120`, `bin:0x1039fbc00` | observed |
| Duplicate | "Duplicate Current Tab"; "Duplicates selected tabs." | `bin:0x1039ec8c0`, `bin:0x1039fc0c0` | observed |
| Archive page | "Opens the Archive, where all your closed tabs live."; empty state "Hover your mouse over a tab and press the × to archive it."; "Filter Archived Tabs"; "How was the tab closed?"; "Earlier This Week"; menu "Clear Archive"; "Are you sure you'd like to Clear Archive?" | `bin:0x1039fbd00`, `bin:0x103a0fc80`, `bin:0x103a0ff90`, `bin:0x103a0feb0`, `bin:0x103a0fa20`, `nib:1171`, `bin:0x103a12f40` | observed |

Archive grouping buckets are `today`, `yesterday`, `pastWeek`, `pastMonth`, `beyond`; archive reasons are `auto`, `manual`, `clearButton`, `clearTabGroup`; archive sources are `space`, `littleArc`, `standaloneSidebar`. (ev: `swift:AnalyticsClient.AnalyticsEventProperties.ArchiveUiTimeBucket`, `swift:ArchiveDataStoreClient.ArchiveReason`, `swift:ArchiveDataStoreClient.ArchivedItemSource`; observed)

### Auto-archive options and durations

- Setting label: "Archive tabs after" (`bin:0x1039f7e90`); Little Arc has its own: "Archive Little Arcs after:" (`bin:0x1039f8520`) (observed)
- Options (comments for each menu choice, in binary order): "Auto archive threshold; never", "Auto archive threshold; 30 days", "Auto archive threshold; 7 days", "Auto archive threshold; 24 hours", "Auto archive threshold; 12 hours", "Auto archive threshold; 6 hours", "Auto archive threshold; 1 hour" (`bin:0x1039c8140` to `bin:0x1039c8220`, observed). So the picker offers 1 hour, 6 hours, 12 hours, 24 hours, 7 days, 30 days and Never. (inferred: the visible labels are short and live in code)
- Default: the education banner says "Arc archives tabs that you haven’t used in the past 12 hours. You can adjust this in %@Settings%@." (`bin:0x103a0cc20`, observed), so the default is 12 hours. (inferred)
- Confirmations: "Arc will now archive your tabs after %@" (`bin:0x1039f6250`), "Arc will never auto-archive your tabs." (`bin:0x1039f62f0`) (observed)
- Per profile: "Manage your default search engine, Auto-Archive, and downloads in Profile Settings." (`bin:0x1039f7de0`); "Would you like to apply this change to all of your Profiles, or only your %@ Profile?" (`bin:0x1039f60a0`); "Only this Profile" (`bin:0x1039f61d0`) (observed). Settings keys: `autoArchiveTimeThreshold`, `autoArchiveLittleArcTimeThreshold`, `autoArchiveTimeThresholdsPerProfile` (ev: `swift:ARCFoundationModels.ArcUserDefaultSettings`; observed)
- Toast: "Auto archived %d tabs" (`bin:0x1039d90e0`); help link "Learn more about auto-archiving" (`bin:0x1039f94c0`) (observed)
- Applies to Today tabs only: "Moves all your unpinned tabs to the Archive." describes the manual clear, and auto-archive targets the same unpinned list. (inferred; the files do not state the scope of auto-archive directly)
- A separate enum `CleanTabsInactivityThreshold` = twentySeconds, oneHour, fourHours, twelveHours, twentyFourHours, threeDays, sevenDays sits in the analytics module next to tab-group settings (`autoCleanTabs`, `autoCleanInactiveTabs`). (ev: `swift:AnalyticsClient.AnalyticsEventProperties.CleanTabsInactivityThreshold`, `swift:AnalyticsClient.AnalyticsEventProperties.TabsPreferencePaneBooleanPreference`; observed) It does not match Arc's archive picker, so it probably belongs to shared code for another product. (inferred)

### Command bar and URL inputter

- Top bar placeholder: "Search or Enter URL…" (`bin:0x10394a670`) with comment "Full placeholder for empty Top Bar"; a "Short placeholder for empty Top Bar" also exists but its text is short and not recoverable. (observed; short text unknown)
- What it does: "Opens the Command Bar to search the web, navigate to recent tabs, launch an extension, and more." (`bin:0x1039fae00`, observed); menu "Open Command Bar" ⌘L (`nib:240`, observed)
- Command search: "Type a feature name or shortcut (like “Command E”)" (`bin:0x1039fcb70`, observed)
- AI modes: "Browse for Me…" (`bin:0x103a024e0`), "Browse for Me - Tell us what you're looking for!" (`bin:0x103a02530`), "Send a Message…" (`bin:0x103a02570`, comment "Placeholder text when site searching GPT."), "Add ChatGPT to your Search suggestions, or start typing “ChatGPT”, hit Tab, to ask any question instantly." (`bin:0x1039f8820`) (observed)
- Site Search: "Remove “%@” Site Search" (`bin:0x103a02b80`), "Change Site Search" (`bin:0x103a02c30`); comments "Hint for using the Tab key to enter Site Search" (`bin:0x103a02ce0`), "Hint for using the Space key to enter Site Search." (`bin:0x103a02d10`), "“or” in between “Space or Tab” in Site Search hint." (`bin:0x103a02d50`) (observed)
- Result captions: "Switch to Split View" (`bin:0x103a02450`, for switch-to-tab results inside a split); comments "Caption for an Instant Open Command Bar result." (`bin:0x103a02360`), "Caption for an Ask ChatGPT Command Bar result." (`bin:0x103a023d0`), "Caption for switch-to-tab results that do not change spaces in the updated UI" (`bin:0x103a02400`) (observed)
- Suggestion sources: `sidebar`, `chromium`, `topDomains`, `searchOrNavigateWhatYouTyped`, `documents`, `easels`, `typeTravel`, `askGPT`, `instantLinks`, `recentAssistantQueries`, `onboardingSuggestions`, `staticQuerySuggestions`, `memorySearch`. Chromium sub-types: search what you typed, navigate what you typed, search suggestion, search history, navigate suggestion, history, other engine, calculator answer, bookmark. (ev: `swift:ASE2.SourceType`, unnamed `?ext` enum with 9 `chromium*` cases; observed)
- Commands ("type travel") include focusSpace, moveToSpace, moveToTopApps, removeFromTopApps, moveToFolder, moveToNewFolder, createNewFolder, collapseAllFolders, expandAllFolders, undoAction, redoAction, joinNextMeeting, toggleSidebar, renameCurrentTab, duplicateCurrentTab, resetCurrentTab, replacePinnedTab, openPreferencePane and more (35 cases). (ev: `swift:ASE2.TypeTravelCandidate.CodingKeys`; observed)
- Where it opens: `topLeftCommandBar`, `centeredInView`, `onContentPanel`; layout `overCommandBarPlaceholder`, `overFocusedContent`, `centered`, `overContentPanel`; result target `overrideCurrentTab`, `createNewTab`, `noop`. (ev: `swift:Arc.WindowViewController.CommandBarPresentationAndPlacement.Placement`, `swift:CommandBar.CommandBarLayoutDisposition`, `swift:CommandBar.CommandBarDestinationType`; observed) So ⌘L edits the current tab from the URL pill and ⌘T opens a centered bar that creates a new tab. (inferred)
- Remote config: `R/ARC_CommandBar.bundle/Contents/Resources/command_bar_behavior.json` has one key, `dedupByTitleAndHostList`. (observed)

### Split view

- Menu: "Add Split View" ⌃⇧= (`nib:194`), "Close this Split Pane" ⌃⇧- (`nib:228`), "Separate Page from Split View" (`nib:1300`), "Expand Current Split" (`nib:629`), "New Note (in Split)" ⌃⌥N (`nib:1220`) (observed)
- Teaching copy: "Drag a tab from your sidebar into the middle of the screen to create a Split View." (`bin:0x1039fdbc0`), "Multitask with Split View" (`bin:0x1039fdd20`) (observed)
- Actions: "Create Split View" (`bin:0x1039cf960`), "Add to Split View" (`bin:0x1039cf980`), "Open in Split View" (`bin:0x10394eca0`), "Convert to Horizontal Split View" (`bin:0x1039ec720`), "Convert to Vertical Split View" (`bin:0x1039ec790`), "Add Bottom Split" (`bin:0x1039ec490`), "Remove Tab from Split View" (`bin:0x1039602d0`), "Separate All Tabs" (`bin:0x103a37460`), "Share Split View…" (`bin:0x103957ae0`) (observed)
- Navigation: "Adds a new page to your current Split View." (`bin:0x1039fadd0`), "Jumps to the first Split View page in your current window." (`bin:0x1039fbe10`) through fourth, next and previous (observed)

### Little Arc

- Menu "New Little Arc Window" ⌥⌘N (`nib:463`); "Open Little Arc or Peek in…" ⌘O (`nib:1495`) (observed)
- "Little Arc is a smaller, simpler Arc window. It’s perfect for quick lookups and reading funny tweets your friends send you." (`bin:0x1039f8640`, observed)
- Settings: "Links from other apps open in Little Arc" (`bin:0x1039f8540`), "Open Little Arc when clicking on links with ⌥⌘ held" (`bin:0x1039f8570`), "Open Little Arc when I press " followed by a shortcut (`bin:0x1039f8500`), "Archive Little Arcs after:" (`bin:0x1039f8520`) (observed)
- Window: title "Little Arc {em dash} %@" (`bin:0x103956e80`); hint "Click “Open in” to move this page in a full window, or ⌘W to close" (`bin:0x103a05b60`); first-run title "Links Open in Little Arc" (`bin:0x103a05be0`); "Show Little Arc “Open In” Menu" (`bin:0x10394a060`) (observed)

### Peek

- "Peek is a way to preview a link without opening a new tab. It’s perfect for quickly looking at a link from an email, news article, or tweet." (`bin:0x1039f85b0`, observed)
- Settings: "Open a Peek window when clicking on links to other sites" (`bin:0x1039f8440`) with "Note: This only affects Favorites and Pinned tabs" (`bin:0x1039f8480`); "Open a Peek window when clicking on links with Shift held" (`bin:0x1039f84c0`) (observed)
- Email peek: menu "Peek Email…" ⇧⌘E (`nib:219`); "Make sure Gmail is favorited and you’re signed in." (`bin:0x1039d9220`) (observed)
- Closing: "Exit the current context. Such as closing a Peek window or exiting fullscreen." (`bin:0x1039fc210`), which matches the View menu item "Exit", whose key in the nib is Esc (`nib:1324`) (observed)

### Boosts

- Menu: "New Boost", "New Legacy Boost (Advanced)", "Edit Boost", "Boost Gallery", "View Boosts" (`nib:879`, `nib:1182`, `nib:416`, `nib:8`, `nib:862`) (observed)
- "Edit the Internet with Boosts" (`bin:0x1039b82d0`), "Zap all related elements" (`bin:0x1039b85e0`), "Manage Boosts…" (`bin:0x1039bbf40`), "Enable Boosts on websites you visit" (`bin:0x1039f76a0`), "Nothing Boosted Yet!" (`bin:0x103a10010`) (observed)
- Rules: "Boosts can’t be installed or used in Incognito Mode." (`bin:0x10394ed80`), "FYI: for security reasons, Boosts with JavaScript can’t be shared." (`bin:0x1039b8180`), "Add this Boost to Arc?" (`bin:0x103a0e4b0`), "Boost installed!" (`bin:0x1039da040`), "Delete this Boost?" (`bin:0x10394ef00`) (observed)

### Easels and Notes

- Menu "New Easel" ⌃⇧E (`nib:1263`), "New Note" ⌃⇧N (`nib:690`), "View Easels & Notes" (`nib:1516`), "Export Arc Notes" (`nib:1061`) (observed)
- "Creates a new Easel – your scrapbook for the web. Capture, create, and share stuff you find on websites in Arc." (`bin:0x1039fb750`), "Click the + sign in the Sidebar to create a new Easel or Note." (`bin:0x1039511b0`), "Once shared, Easels can be viewed in any browser but only edited in Arc. Your name will be visible to anyone with the link." (`bin:0x1039d8440`), "See Older Easels" (`bin:0x1039e9fc0`) (observed)
- Notes are being retired: "We’re saying goodbye to Arc Notes" (`bin:0x10395e170`), "We’ve phased out Arc Notes" (`bin:0x10395e3e0`) (observed)

### Air Traffic Control

- Settings button "Air Traffic Control…" (`bin:0x1039f8420`) under "Choose where links open inside Arc." (`bin:0x1039f83f0`) (observed)
- "Routes let you choose where specific sites open inside Arc. For example, you can route Spotify links to always open inside your Personal space." (`bin:0x1039f8240`, observed)
- "Most Recent Space" (`bin:0x1039f82d0`, observed) appears in the same block, so it is a route destination choice. (inferred)
- Command bar entry "Air Traffic Control" with trigger phrases "air traffic control", "air traffic controller" (`bin:0x1039ec550`, `bin:0x1039ece80`, `bin:0x1039ecea0`) (observed)
- Related toast: "Meet links now open in your current Space!" (`bin:0x1039d9f00`, observed)

### Profiles

- Menu "New Profile" (`nib:393`), "Change Profile" (`nib:84`) (observed)
- "Create a new Profile" (`bin:0x1039c6380`), "Edit Space profile" (`bin:0x1039c67b0`), "Rename your Profile" (`bin:0x1039f8de0`), "Delete this Profile" (`bin:0x1039c68a0`) (observed)
- "Each Profile has different browser data, so you might get logged out of some websites, see different Favorites up top, or need to re-install extensions." (`bin:0x1039c65a0`, observed)
- "You can use a Profile to give\nthis Space its own logins,\nhistory, and browsing data." (`bin:0x103a0d020`, observed)
- Rules: "Only Profiles not assigned to any Spaces can be deleted." (`bin:0x1039f9520`), "The Default Profile cannot be deleted." (`bin:0x1039f9560`), "A Profile with that name already exists." (`bin:0x1039c6200`), "This won’t affect the names of any of the Spaces associated with this Profile." (`bin:0x1039f8ca0`) (observed)

### Hide sidebar and toolbar

- Menu "Show/Hide Sidebar" ⌘S (`nib:33`); "Shows or hides your Sidebar from the left edge of your window." (`bin:0x1039fbd70`) (observed)
- Hint ending "to easily show and hide your Sidebar!" (`bin:0x1039d9680`) between comments "Beginning of the copy for sidebar shortcut" and "End of the copy for sidebar shortcut" (observed); the start of the sentence and the shortcut glyph are filled in at runtime. (inferred)
- Sidebar states: presentation `locked`, `floating`, `hidden`; mode `anchored`, `noChrome`; default key `hasHiddenSidebarWithGesture`. (ev: `swift:BaseModels.SidebarPresentation`, `swift:BaseModels.SidebarMode`; observed) So a hidden sidebar slides in as a floating panel when you point at the left edge. (inferred from `floating` and "from the left edge")
- Toast comment: "Letting the user know a new tab has been created when the sidebar is hidden." (`bin:0x1039db900`, observed)
- Toolbar: menu "Show/Hide Toolbar" ⇧⌘D (`nib:1095`); "Shows or hides the toolbar at the top of your window." (`bin:0x1039fbdb0`); "Show full URL when Toolbar is enabled" (`bin:0x1039f7820`) (observed)

### Window themes

- Menu "Edit Theme…" (`nib:1424`); context menu "Edit Theme Color…" (`bin:0x103a37d70`); "Edit Space theme" (`bin:0x10395fb00`) (observed)
- Onboarding step: "Add some flair with a theme." (`bin:0x1039d4ae0`), "Pick a color, any color{em dash}add your favorite shade to your new home on the internet." (`bin:0x1039d4a50`) (observed)
- Appearance pop-up for web content: "Websites, Easels, and Notes will use:" with "Automatic", "Light", "Dark" (`nib:2286`, `nib:640`, `nib:1121`, `nib:305`; observed)
- Theme sharing with sites: "Allow websites to get your theme data" (`bin:0x1039f76d0`, observed); key `themeToCSSSharingAllowed` (ev: `swift:ARCFoundationModels.ArcUserDefaultSettings`; observed)
- Editor copy and controls are listed in section 1.

### Keyboard shortcut hints inside copy

- "Click New Tab or press ⌘T to open the Command Bar and create your very first tab in Arc." (`bin:0x10394aa30`)
- "Start browsing by clicking New Tab in your sidebar or typing" (`bin:0x1039fdcc0`)
- "Press ⌘T, and type "update"." (`bin:0x1039f1430`) and "Press ⌘E, and type "update"." (`bin:0x1039e7260`)
- "Open Little Arc when clicking on links with ⌥⌘ held" (`bin:0x1039f8570`)
- "Click “Open in” to move this page in a full window, or ⌘W to close" (`bin:0x103a05b60`)
- "Press Command + F on any page to ask a question and let Max answer it for you in seconds." (`bin:0x1039f8a00`)
- "Opens the tab switcher, where you can cycle through recent tabs {em dash} like Command+Tab on your computer!" (`bin:0x1039fb110`; the space after the dash is a no-break space)
- "Type a feature name or shortcut (like “Command E”)" (`bin:0x1039fcb70`)
- "Change shortcuts for your favorite actions, and even choose whether Arc or a website takes priority." (`bin:0x1039fc850`), so shortcuts are user-editable. (observed copy; editability inferred)

All quotes in this list: observed. The Settings shortcut list has 123 description strings between `bin:0x1039fa790` and `bin:0x1039fc3c0`, for example "Jumps to the first item" through "Jumps to the ninth item" and "Jumps to the last item at the bottom of your Sidebar." (ev: `b/topics/shortcut-descriptions.txt`; observed)

Main menu items that carry a key equivalent in the nib (78 rows). These are the nib defaults; the running app can rebind them, and two items share ⇧⌘N in the nib (New Folder… and New Incognito Window), which shows the nib is not the final binding table. (ev: `b/mainmenu-items.tsv`; observed values, runtime remapping inferred)

| Menu | Item | Shortcut in nib | Nib object |
|---|---|---|---|
| Arc | Hide Arc | ⌘H | 477 |
| Arc | Hide Other Windows | ⌥⌘H | 731 |
| Arc | Preferences… | ⌘, | 1009 |
| Arc | Quit Arc | ⌘Q | 988 |
| Arc | Set as Default Browser | (modifier only, no key) | 249 |
| Archive | Go Back | ⌘← | 361 |
| Archive | Go Back | ⌘[ | 946 |
| Archive | Go Forward | ⌘] | 61 |
| Archive | Go Forward | ⌘→ | 1447 |
| Archive | View History | ⌘Y | 1144 |
| Developer | Developer Tools | ⌘F12 | 285 |
| Developer | Developer Tools | ⌥⌘I | 1473 |
| Developer | Inspect Elements | ⌥⌘C | 1380 |
| Developer | JavaScript Console | ⌥⌘J | 1312 |
| Developer | Toggle Developer Mode | ⌃D | 1276 |
| Developer | View Source | ⌥⌘U | 655 |
| Edit | Copy | ⌘C | 1465 |
| Edit | Copy URL | ⇧⌘C | 890 |
| Edit | Copy URL as Markdown | ⌥⇧⌘C | 402 |
| Edit | Copy URL as Quote | ⌃⇧⌘C | 1412 |
| Edit | Cut | ⌘X | 1393 |
| Edit | Paste | ⌘V | 1074 |
| Edit | Paste and Match Style | ⇧⌘V | 740 |
| Edit | Redo | ⇧⌘Z | 124 |
| Edit | Select All | ⌘A | 533 |
| Edit | Undo | ⌘Z | 1992 |
| File | Archive Tab | ⌘W | 968 |
| File | Blank Window | ⌃⌘N | 1485 |
| File | Capture… | ⇧⌘2 | 263 |
| File | Close Window | ⇧⌘W | 574 |
| File | New Easel | ⌃⇧E | 1263 |
| File | New Incognito Window | ⇧⌘N | 1029 |
| File | New Little Arc Window | ⌥⌘N | 463 |
| File | New Note | ⌃⇧N | 690 |
| File | New Note (in Split) | ⌃⌥N | 1220 |
| File | New Tab… | ⌘T | 830 |
| File | New Window | ⌘N | 678 |
| File | Open Command Bar | ⌘L | 240 |
| File | Print | ⌘P | 901 |
| File | Restore Last Closed Tab | ⇧⌘T | 717 |
| File | Save Page As | ⇧⌘S | 1207 |
| Spaces | Next Space | ⌥⌘→ | 808 |
| Spaces | Previous Space | ⌥⌘← | 1108 |
| Tabs | Clear Unpinned Tabs | ⇧⌘K | 498 |
| Tabs | Cycle Tab Backward | ⌃⌘← | 172 |
| Tabs | Cycle Tab Forward | ⌃⌘→ | 871 |
| Tabs | Join Meeting | ⌃⌘J | 1136 |
| Tabs | New ChatGPT Message… | ⌥⌘G | 52 |
| Tabs | New Folder… | ⇧⌘N | 959 |
| Tabs | New Tab… | ⌘T | 1693 |
| Tabs | Next Tab | ⌥⌘↓ | 1402 |
| Tabs | Open Little Arc or Peek in… | ⌘O | 1495 |
| Tabs | Peek Email… | ⇧⌘E | 219 |
| Tabs | Pin/Unpin Tab | ⌘D | 181 |
| Tabs | Previous Tab | ⌥⌘↑ | 852 |
| Tabs | Tab Switcher (backward) | ⌃⇧Tab | 207 |
| Tabs | Tab Switcher (forward) | ⌃Tab | 1018 |
| View | Add Split View | ⌃⇧= | 194 |
| View | Cast | (modifier only, no key) | 1371 |
| View | Close this Split Pane | ⌃⇧- | 228 |
| View | Developer | (modifier only, no key) | 2296 |
| View | Enter/Exit Full Screen | ⌃⌘F | 428 |
| View | Exit | ⌘Esc | 1324 |
| View | Force Refresh the Page | ⇧⌘R | 1039 |
| View | Refresh the Page | ⌘R | 704 |
| View | Reveal Current Tab | ⌃Space | 778 |
| View | Show/Hide Sidebar | ⌘S | 33 |
| View | Show/Hide Toolbar | ⇧⌘D | 1095 |
| View | Stop Loading | ⌘. | 512 |
| View | Zoom In | ⌘+ | 1051 |
| View | Zoom In | ⌘= | 2070 |
| View | Zoom In | ⌘= | 2083 |
| View | Zoom Out | ⌘- | 93 |
| View | Zoom Out | ⇧⌘- | 1881 |
| View | Zoom to Actual Size | ⌘0 | 764 |
| Window | Minimize Window | ⌘M | 999 |
| Window | View Downloads | ⇧⌘J | 150 |
| Window | View Library | ⇧⌘L | 451 |

### Onboarding ("welcome")

- First-run steps in order of the code enum: sellCompleted, welcome, signUp, signIn, accountConfirmation, spaceStyleEditor, topApps, adBlockers, arcMax, importSource, importFromSafari, safariPasswordImportOptions, importSelectedBookmarks, importSafariKeychain, defaultBrowser, finished. (ev: `swift:AnalyticsClient.AnalyticsEventProperties.OnboardingStepName`; observed names; that enum order equals screen order is inferred)
- Greeting: "Welcome to Arc, %@" (`bin:0x1039d57d0`), "Welcome back to Arc." (`bin:0x1039d6950`) (observed)
- Theme: "Add some flair with a theme." (`bin:0x1039d4ae0`) (observed)
- Favorites: "Choose the apps you use most." / "Select your favorite apps to keep them handy in your sidebar." (`bin:0x1039d4ba0`, `bin:0x1039d4b30`) (observed)
- Ad blocker: "No more ads or trackers." / "We include an ad blocker so you don’t need to worry about invasive trackers or intrusive pop-ups." (`bin:0x1039d4d60`, `bin:0x1039d4cc0`) (observed)
- Arc Max: "Move faster with AI in Arc?" (`bin:0x1039d4db0`) (observed)
- Import: "Get us up\nto speed." / "78% of people import from their ex-browser, too." / "Import from Safari." (`bin:0x1039d51a0`, `bin:0x1039d5050`, `bin:0x1039d52b0`) (observed)
- Default browser: "Make Arc your default browser so links open here. We’ll treat your links nicely{em dash}you won’t regret it, we promise!" (`bin:0x1039d55f0`, observed)
- After setup, "Arc 101" in the first window: header "Let’s settle in!\nHere are the basics." (`bin:0x1039fdd80`); steps "Open your first tab", "Pin tabs to save for later", "Spaces for work and life", "Multitask with Split View" (`bin:0x1039fdd00`, `bin:0x1039fdd60`, `bin:0x1039fdd40`, `bin:0x1039fdd20`), each with one of the four 8.5 s videos; buttons "Learn Essential Shortcuts" and "Help & Resources" (`bin:0x1039fdde0`, `bin:0x1039fde00`) (observed)
- Default sidebar content for new users includes tabs titled for 'Get Started', 'Arc Resources', 'Import Logins & Bookmarks', an Arc Max tutorial, and The Browser Company's YouTube, Substack and Twitter (comments `bin:0x103a0d670` to `bin:0x103a0d800`, observed), with favicons GettingStartedFavicon, ResourcesFavicon, ImportFavicon, YouTubeFavicon, SubstackFavicon, WikipediaFavicon, GoogleFavicon (ev: `b/image-asset-names.tsv` ARC_StorableSidebar; observed)

### Settings page labels

- Pane names, from comments "Preferences pane title; ...": General, Profiles, Links, Shortcuts, Max, Account, Advanced, App Icon, and an internal Staff pane. (ev: `b/binary-cstring-arc-arm64.utf8.tsv`, grep "Preferences pane title"; observed comments; the exact visible tab text is short and unknown)
- Window titles: "General Preferences", "Profile Preferences", "Link Preferences", "Little Arc Preferences", "Account Preferences", "Advanced Preferences" (`bin:0x1039f7d50`, `bin:0x1039f8ea0`, `bin:0x1039f8e80`, `bin:0x1039f8350`, `bin:0x1039f8ec0`, `bin:0x1039f74d0`) (observed)

| Pane (inferred from position) | Labels | Evidence | Label |
|---|---|---|---|
| General | "Warn before quitting", "Automatically update my Arc", "When opening Arc, restore windows from previous session", "Haptic feedback when reordering tabs", "Play Arc sound effects", "Enable Boosts on websites you visit", "Allow websites to get your theme data", "Enable Picture in Picture when you leave a video tab", "Allow window dragging from the top of webpages", "Enable Shared Quotes when highlighting text.", "Show full URL when Toolbar is enabled", "Profile Settings…", "Previews Settings…", "Show Arc Previews:", "Sync Sidebar with iCloud" | `bin:0x1039f8150`, `0x1039f8170`, `0x1039f7850`, `0x1039f78b0`, `0x1039f78e0`, `0x1039f76a0`, `0x1039f76d0`, `0x1039f7700`, `0x1039f7780`, `0x1039f77b0`, `0x1039f7820`, `0x1039f7e40`, `0x1039f8130`, `0x1039f90b0`, `0x1039f6e50` | observed |
| Profiles | "Archive tabs after", "Default Search Engine", "Include search engine suggestions", "Search Settings…", "Default Document App", "Download Location", "Privacy and Security", "Clear Browsing Data", "Block Cookie Banners", "Ad Block Settings…" | `bin:0x1039f7e90`, `0x1039f9670`, `0x1039f9620`, `0x1039f9650`, `0x1039f9600`, `0x1039f9270`, `0x1039f9690`, `0x1039f96d0`, `0x1039f8070`, `0x1039f8020` | observed |
| Links | "Choose where links open inside Arc.", "Air Traffic Control…", Peek and Little Arc toggles listed above | `bin:0x1039f83f0`, `bin:0x1039f8420` | observed |
| Max | "Enable AI Features", "Automatically enable future Arc Max features", "ChatGPT in the Command Bar", "5-Second Previews", "Have your tabs automatically renamed with tidier, shorter titles when you Pin them." | `bin:0x1039f8ee0`, `0x1039f8b60`, `0x1039f8b90`, `0x1039f8bb0`, `0x1039f8910` | observed |
| Shortcuts | "Edit Keyboard Shortcuts", the 123 shortcut descriptions | `bin:0x103a1af30`, `b/topics/shortcut-descriptions.txt` | observed |
| Advanced | "More Settings…" (opens arc://settings), "Reset Translated-site Prompts" | `bin:0x1039f7590`, `bin:0x1039f75e0` | observed |
| App Icon | "Unlock app icons by sharing Arc with friends!", "Refer %d friends to unlock" | `bin:0x1039f7bd0`, `bin:0x1039f7930` | observed |

Which pane each label sits in is inferred from the order of strings in the binary and from "Manage your default search engine, Auto-Archive, and downloads in Profile Settings." (`bin:0x1039f7de0`, observed).

## 4. Layout constants

No plist, `.strings`, JSON or asset in the bundle defines sidebar width, corner radius, insets or UI animation durations. (ev: `b/resources-file-list.txt`, all 84 plists are `Info.plist`; observed) The code has the right fields but their values are compiled into machine code:

- Sidebar width: fields `sidebarWidth`, `sidebarBreakpoints`, `SidebarResizeState` = `sidebarWidthOnBeginResize`, `canSnapToDefaultWidth`, `breakpointIndex`, `timeOfSnap`. (ev: `swift:Arc.WindowLayoutController.ViewState`, `swift:Arc.WindowLayoutController.SidebarResizeState`; observed) So the sidebar resizes by drag and snaps back to a default width at breakpoints. (inferred) The numbers: unknown.
- Corner radii: `contentCornerRadius`, `cornerRadius`, `ExtraRoundedCornerRadiusDescriptor`, `cornerCurve`, `maskedCorners`. (ev: `b/swift-fieldmd-types.tsv`; observed names) Values: unknown.
- Other width keys: `assistantOverlayPreferredRightSidebarWidth`, `extensionSidePanelPreferredWidth` (ev: `swift:ARCFoundationModels.ArcUserDefaultSettings`; observed names). Values: unknown.
- Animation: a user default `fastAnimations` exists (observed name). UI animation durations in code: unknown.

Numbers that are in the resources:

| Constant | Value | Evidence | Label |
|---|---|---|---|
| Library icon hover animation | frames 1 to 11 at 60 fps (about 0.17 s) | `b/lottie-inventory.txt` | observed |
| Library icon select animation | to frame 35 (about 0.57 s), Boosts to frame 45 (about 0.73 s) | `b/lottie-inventory.txt` | observed |
| Library icon canvas | 128 x 128 | `b/lottie-inventory.txt` | observed |
| Appearance toggle animations | sun 1.0 s, moon 1.5 s, automatic 1.5 s, 500 x 500 canvas | `b/lottie-inventory.txt` | observed |
| Theme texture tile sizes (1x) | denim 300, tweed 128, sand 96, grain 155 px | `b/image-asset-names.tsv` | observed |
| Noise dial knob previews | 56 x 56 pt (112 px at 2x) | `b/image-asset-names.tsv` | observed |
| Welcome videos | 8.5 s each, 1920 x 1200 | `b/video-inventory.txt` | observed |
| Capture sound | 0.63 s | `b/sound-afinfo.txt` | observed |
| Default auto-archive | 12 hours | `bin:0x103a0cc20` | inferred from banner copy |

## What could not be determined

- The visible text of strings of 15 bytes or less: section titles ("Favorites", "Pinned", "Today" as actual header text), settings tab names, short buttons, the short URL placeholder, auto-archive option labels. Only their comments survive in the string table. Recovering them needs disassembly of the code that builds them. (unknown)
- Feather glyph to action mapping: the icon font has no glyph names and the Swift constants are stripped. (unknown)
- All numeric layout values: sidebar default, minimum and maximum width, snap breakpoints, content corner radius, insets, shadow, and in-code animation timing. (unknown)
- Runtime keyboard bindings: the nib defaults are listed, but the app rebinds some and lets users edit them. (unknown beyond the nib)
- Default theme colors for a new space and the default overlay texture. (unknown)
- What `event.m4a` is played for. (unknown)
- `Arc.app/Contents/Frameworks/ArcCore.framework` (the Chromium engine with its own `.pak` locale files) was out of scope and not read. (unknown)
