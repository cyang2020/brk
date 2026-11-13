# Arc 1.170.0: layout and timing constants

Static read of the arm64 slice of `Arc.app/Contents/MacOS/Arc` (slice SHA-256 `77be289e16a139056dd9d0bf145ad4707d4e217289bb279a333949dcfd39c52d`). Arc was never launched.

## How to read this table

- `c/` means `/Users/administrator/.t3/projects/brk/.audit/arc-evidence/c/`.
- An address such as `0x100220684` is a function start in the arm64 slice. Ghidra names it `FUN_100220684`. Its decompiled text, with the REA Evidence ID, is in `c/ghidra-pseudo/<address>.json`. The disassembly with names filled in (Objective-C selectors, class fields, stubs) is in `c/disasm/<address>.s`.
- Where the table names a role, such as "pan handler", the role comes from the Objective-C method that calls the function (`c/objc-methods-arm64.tsv`) or from the class fields it reads (`c/objc-ivars-arm64.tsv`).
- Some values sit in static data tables, not in code. Those tables are dumped in `c/constblocks.tsv` with the function that returns each slot's address.
- `cra L123` is line 123 of `/Users/administrator/.cache/arc-ref/cra/docs/arc-reverse-engineering.md`. Those are measurements of the running Arc, mostly 1.170, some 1.168.
- Agreement: **agrees** means the code value and the cra measurement match. **close** means they match in effect but not in the exact number. **conflicts** means they differ. **code only** and **cra only** mean only one source has the value.
- Confidence: **high** means the number is in the code and the code shows what it controls. **medium** means the number is certain but its role is inferred from the surrounding calls. **low** means the role is uncertain, or there is a measurement but no code.
- Every number cited from code was read again straight from the instruction bytes by `c/scripts/verify_constants.py` (102 checks, 0 failed, output in `c/verify-constants.txt`). The script does not use Ghidra or objdump text, so a misreading in either tool would show up as a failure.

## Constants

| Constant | Value | Unit | Source | Agreement | Confidence |
|---|---|---|---|---|---|
| Sidebar minimum width while dragging | 164 | pt | Sidebar resize pan handler (`handleSidebarResizePanGestureRecognizer:` calls `0x100220684`), literal at `0x100220738` | code only (user widths 284, 328, 347 at cra L469, L44, L1210 fall inside the range) | high |
| Sidebar maximum width | 500 | pt | `0x100220684`, literal at `0x100220728` | code only | high |
| Drag-to-hide threshold: dragging the edge below this sets the width to 0 (sidebar hidden) | 82 | pt | `0x100220684`, `0x100220a04` | code only | high |
| Reset width on double-click of the sidebar edge | 228 (8 + 8 + 4 × 47 + 3 × 8, the narrowest width that keeps 4 square favorites) | pt | `handleSidebarResizeDoubleClickGestureRecognizer:` calls `0x100223b60`; inputs from the favorites table at `0x103784770` | agrees: cra L1590-1594 sees 4 columns at width 230 and 2 columns at 227 | high |
| Snap target while dragging | 228 (same formula) | pt | `0x100220684`, `0x100220a5c` to `0x100220a78` | agrees (same as above) | high |
| Snap distance | 14 | pt | `0x100220684`, `0x100220a80` | code only | high |
| Snap hold time: a snapped edge stays put until this much time has passed; a haptic plays on snap and on release | 0.5 | s | `0x100220684`, `0x100220ee0` (system uptime minus `timeOfSnap`) | code only | medium |
| Unsnap speed threshold | 50 | pt/s | `0x100220684`, `0x100220abc` (pan velocity) | code only | medium |
| Default sidebar width for a new window | probably 228 | pt | Window state setup functions `0x100271834`, `0x100274388` and `0x100396c50` call the same three favorites accessors, but the field they fill was not traced | code only | low |
| Resize hit area | 8 wide, centered on the sidebar edge (x = edge minus 4), starts 11 below the top, height = window height minus 22 | pt | Window layout `0x100218a50`, `0x100219004` to `0x100219050` | code only | medium |
| Resize indicator drawn while dragging | 3 wide, hit-area height minus 8, corner radius 4 (Core Graphics clamps it to 1.5) | pt | `SidebarResizeRegionView.layout` body `0x1000cb99c` | code only | high |
| Floating sidebar inset from the window | 5 from the left, top and bottom (height = window height minus 10) | pt | `0x100218a50`, `0x100218dac`, `0x100218dcc`, `0x100218de8` | code only | medium |
| Floating sidebar parked position when hidden | x = window left minus sidebar width minus 10 | pt | `0x100218a50`, `0x100218d28` | code only | medium |
| Sidebar show/hide animation duration | 0.08 | s | Animation closures `0x10021f338`, `0x10021f814`, `0x10021f910` (`setDuration:` then `setTimingFunction:`) | agrees: cra L457-458 and L860 fit 0.08 to 0.085 s, 66% of the travel in the first frame (L730) | high |
| Sidebar show/hide timing curve | cubic-bezier(0.25, 0.46, 0.45, 0.94) | none | Shared timing function built in `0x1009b9310`, fetched through `0x102a2e6bc` | close: cra L860 fitted 0.15, 0.7, 0.3, 1; both are fast-start, soft-landing curves | high |
| Content relayout animation (same curve) | 0.2 | s | `0x10021f028` | code only | medium |
| Floating sidebar stays open while the pointer is within | sidebar width + 80 (5 + 75) | pt | Window hover tracker `0x1000313ec` | code only | medium |
| Hover zone outside the window's left edge | 250 wide | pt | Window hover tracker setup `0x100031604`, rectangle (-250, 0, 250, height) at `0x103647590` | code only | medium |
| Traffic-light hover zone (window buttons light up when the pointer enters) | x from -50, 140 wide, 50 tall | pt | `0x100031604`, rectangle at `0x1036475b0` | close: cra L178-179 sees the buttons stay muted until the pointer reaches the title row | medium |
| Hidden-sidebar reveal strip at the left edge | from 2 × L outside the window to 1.5 × L inside, where L is the left content inset (10, so about 20 out and 15 in); 0.6 × L while the window is not hovered | pt | `0x10002fbd4` | code only | low |
| Library ("home") panel width | max(417, min(window width minus 56, stored width)) | pt | `0x100218a50`, `0x100218c14` and `0x100218c2c` | agrees: cra L1548 sees the Library widen the sidebar to 417 | high |
| Sidebar header top inset | 4 | pt | `SidebarHeaderView` setup `0x100155b34` (top constraint from the SidebarUI table at `0x103817980`) | agrees: cra L141 puts the title row center at 24 = 4 + 40 / 2 | high |
| Title row (window buttons and navigation buttons) height | 40 | pt | `0x100155b34`, `0x10015603c` | agrees (same as above) | high |
| Title row left inset | 13 (8 + 5) | pt | `0x100155b34`, `0x100155f94` to `0x100155fa0` | agrees: cra L1215 puts the first window button's 16 pt frame at x 12, so the 14 pt glyph starts at 13 | high |
| Title row right inset | 6 | pt | `0x100155b34`, `0x100155ff8` | agrees: cra L1215 says the reload button ends 6 pt from the sidebar edge | high |
| Window button (traffic light) size | 14 | pt | `ARCUI.WindowStandardButtons` size code `0x100b166c8` | agrees: cra L1215 frames are 16 wide on a 23 pt pitch | high |
| Window button spacing | 9; 6 on the other side of an OS-version check | pt | `0x100b166c8` and init `0x100b15450` | agrees: cra L1215 pitch 23 = 14 + 9 on macOS 26 | high for 9, medium for which OS gets 6 |
| Sidebar header background reaches below the header by | 30 | pt | `SidebarViewController.loadView` path `0x1002945e0`, `0x1002949f0` | code only | medium |
| URL pill horizontal inset | 8 each side | pt | `0x100155b34`, `0x1001560d4` and `0x100156134` | agrees: cra L1217 | high |
| URL pill height | 36 | pt | `CommandBarPlaceholderView` setup `0x1003a90b4`, `0x1003a99c0` | agrees: cra L1217-1218 | high |
| URL pill corner radius | 12, continuous corners | pt | `CommandBarPlaceholderView.updateLayer` `0x1003a9cd4` reads the CommandBar table at `0x1037c9008` | close: cra L1218 fits about 10 with a circular corner, and a continuous 12 looks like that | medium |
| URL pill leading icon | 22 × 22 | pt | `0x1003a90b4`, `0x1003aed10` | code only | medium |
| URL pill accessory buttons | 28 × 28, corner radius 9 | pt | `CommandBarPlaceholderButtonsView` `0x1002e811c` | close: cra L1222-1223 sees them about 29 pt apart | medium |
| URL pill text area minimum height | 20 | pt | `0x1003a90b4`, `0x1003a9978` | code only | low |
| Favorites tray insets | 8 on every side | pt | Favorites table `0x103784770` (getter `0x101ceb648`) | agrees: cra L180-181, L473 | high |
| Favorites columns | 4; drops to 2, then 1, when a tile would be narrower than 47 | count | Favorites table `0x103784790` | agrees: cra L1590-1594 | high |
| Favorites minimum tile size | 47 × 47 | pt | Favorites table `0x103784798` (getter `0x101ceb674`) | agrees: cra L473 (47 tall) | high |
| Favorites gap | 8 | pt | Favorites table `0x1037847a8` | agrees: cra L473, L180 | high |
| Favorites tile corner radius | 12, continuous corners | pt | `AppTrayItemBackgroundView.updateLayer` `0x101cf2978` | close: cra L473 fits a 13 pt circular corner | high |
| Selected favorite ring | inset 1, corner radius 11 | pt | `AppTrayItemHighlightRingView` `0x101cf3454` | close: cra L475 sees a 2 pt rim inside the edge | medium |
| Sidebar row height | 40; with 1 pt between rows the pitch is 41 | pt | `TablistOutlineDelegate outlineView:heightOfRowByItem:` calls `0x100355860` | agrees: cra L142, L748 (41 pt pitch) | high for 40, medium for the 1 pt spacing |
| Pinned/Today divider row | 16 (24 in one state) | pt | `0x100355860` | agrees: cra L748 measures a 17 pt row (16 + 1) | medium |
| Spacer row at the top of the list | 2 | pt | `0x100355860` | agrees: cra L748 measures 3 (2 + 1) | medium |
| Another row type (probably folder or split header) | 36 | pt | `0x100355860` through the SidebarUI table at `0x103817aa8` | code only | low |
| Row selection background | 36 tall (the view is 36 + 16 with an 8 pt inset), corner radius 12 continuous, shadow shape radius 12 | pt | `SidebarUI.CellSelectionStateView`: `0x102a2cb14`, `0x102a2c934`, `0x102a2c5f4`; 36 from the SidebarUI table at `0x103817b70` | close: cra L637 sees a white rounded selected row | medium |
| Tab row hover-button background corner radius | 12 | pt | `TabCellRegionalBackgroundButton`, set at `0x1003691e4` from the SidebarUI table at `0x103817b90` | code only | low |
| Dock (space switcher) height | 50 | pt | `0x1002945e0` height constraint from the SidebarUI table at `0x1038179b8` | agrees: cra L1521 (263 × 50 strip) | high |
| Dock space cell width | at most 34; shrinks to fit, minimum 8; below 22 a compact style is used | pt | `SidebarDockCollectionViewLayout.prepareLayout` body `0x1027d7bcc` | agrees: cra L1519-1520 (34 pt pitch) | high |
| Dock space cell height | at most 32 | pt | `0x1027d7bcc` | agrees: cra L1520 (34 × 32 hit cells) | high |
| Dock cell corner radius | 6 | pt | `SidebarDockItemView` `0x1027de5a0` | agrees: cra L1523 (about 6) | high |
| Dock cell press scale | 0.95 | factor | `SidebarDockItemView mouseDown:`, `0x1027deaf4` | code only | medium |
| "+" and Library buttons | 32 × 32; Library at x 8, 9 above the bottom; "+" 8 from the sidebar edge | pt | not traced in code | cra only: cra L1521-1522 | low |
| Content card inset | 10 on top, left, right and bottom (bottom becomes 78 in one state whose trigger was not identified) | pt | Window layout view-state builder `0x1002165e4`, written to `ViewState.contentInsets` | agrees: cra L467, L851-853 (10, kept after hiding the sidebar) | high for 10, low for 78 |
| Content card corner radius | 6; 0 in one state (probably full screen) | pt | `WindowContentViewController.State` builder `0x1000f25b4`, `0x1000f32cc` | agrees: cra L468 (6) | high |
| Content card shadow | switched on (`shouldDisplayShadow` = true); radius and opacity are not set here | none | `0x1000f25b4` | code only | medium |
| Content highlight border width | 2; 3 in one state | pt | `0x1000f25b4`, `0x1000f336c` | code only | medium |
| Split view gap between panes | 10 | pt | not traced in code | cra only: cra L621 | low |
| Main window default size | 1280 × 776 | pt | `MainWindowController` init `0x10031a090`, also `0x100313f9c` | code only | high for the value, medium for the role |
| Command bar width | min(766, area width minus 160); if the area is narrower than 766, area width minus 20 | pt | `0x1003020ac`, called from window-controller code that centers it | agrees: cra L121 (about 766) | high for 766, medium for the margins |
| Command bar box height and position | 338 tall, at least 24 from top and bottom, centered both ways by the caller | pt | `0x1003020ac`; caller `0x1002fbb3c` adds the center constraints | close: cra L121 (vertically centered) | medium |
| Command bar attached to the toolbar | width 100 to 720, at least 80 from the right edge, at least 24 from the bottom | pt | `0x1002ee5dc`; 720 from the CommandBar table at `0x1037c8f40` | close: cra L124 (list hangs under the toolbar) | low |
| Command bar suggestion row height | 50 | pt | `SuggestionsView tableView:heightOfRow:` `0x102237fd4` | agrees: cra L122 | high |
| Visible suggestions and list height | 1 to 5 rows; height = rows × 50 + 10, plus 0, 4 or 10 on top; capped at 260, 264 or 270 | pt | `SuggestionsView intrinsicContentSize` `0x102235b70` | code only | medium |
| Command bar input row height | at least 50; 64 in the other mode | pt | `CommandBarView` `0x102206388`, `0x1022072ac` | conflicts: cra L122 measures 60 | medium |
| Command bar inner spacing | stack spacing 10, inset 12 | pt | `0x102207120` | code only | medium |
| Command bar opening bounce | scale 0.95 to 1 (animation key `arc_commandBarBounce`) | factor | `CommandBarContainer` `0x102203aa4` | close: cra L450-451, L458 see it appear in one frame (a scale bounce, no fade) | medium |
| Little Arc command bar width | 500 | pt | not traced in code | cra only: cra L507-508 | low |
| Theme texture opacity, as a multiple of the theme intensity | grain 0.8, sand 0.15, denim 0.6, tweed 0.4; tiled; multiply blend (normal at 0) | factor | `WindowThemeUI` `0x10153258c` | code only | medium |
| Theme layer alpha | the gradient's alpha over the underlay and the window's material: 0.2 + 0.55 × `intensityFactor` | factor | `0x101530d98` (arm64) | white theme at 0.78 over a black and a white window: 228 and 252, the same as a test window with these layers (docs/checks/2026-11-13-window-translucency.md) | high |
| Theme layer underlay | under the gradient: white at min(layer alpha, 0.5); black at 35% of that in a dark window (a theme following macOS in dark mode, or websites set to Dark) | factor | `0x101530d98` (arm64) | dark macOS: 193 and 235; P19-b | high |
| Theme overlay alpha while the window is inactive | the texture's alpha × 0.25 while the window is neither key nor main | factor | `0x101530cdc` (arm64) | code only | high |
| Metal gradient texture size | factor × 100 | px | `0x10152fbb4` | code only | low |
| Little Arc default window size | 1185 × 832 when no size is saved; other branches use 800 × 600, 490 × 600 and 490 × 329; new windows cascade by 30 | pt | `LittleBrowserWindow` `0x1002c303c` | code only (cra L492 measured 1688 × 1010, a saved size) | medium |
| Tooltip quick re-show | if the last tooltip closed less than 0.6 s ago, the next one appears after 0.01 s | s | Tooltip controller `0x100de3c44` | agrees: cra L790 (moving straight to another control swaps at once) | high |
| Tooltip first-show delay | 1.6 (measured); the default was not found in code | s | cra L789-790 | cra only | medium |
| Toast duration | 5 by default; 3 for one toast type; 3600 and 864000 (stays) for two others; some types carry their own | s | Toast controller `0x1018e346c` | code only | high for 5 s, medium for the others |
| Auto-archive choices | 1 h, 6 h, 12 h, 24 h, 7 d, 30 d (plus a 20 s debug value) | s | Threshold-to-seconds function `0x10014928c` | agrees: cra L54 lists 12 h, 24 h, 7 d, 30 d | high |
| Auto-archive default | 12 h | h | banner copy only (`visual-and-copy.md`, layout table) | code only, not confirmed in code | low |
| Space switch animation | about 0.17 s of visible motion | s | not traced in code | cra only: cra L447-448 | low |

## Not recovered, and why

- **Space header height and font, row title and favicon sizes, row horizontal padding, folder indent, split row layout.** These views use slots in the shared SidebarUI value table (`c/constblocks.tsv`, block "SidebarUI module", 65 values from `0x103817980`). Most reads are folded into the code, so a slot can only be named where a call shows what it sets. Only 7 slots were named here (4, 8, 12, 36 twice, 50, plus the dock). cra has measurements for most of these (L115-116, L141-142, L180).
- **URL pill and command bar font sizes, command bar corner radius and shadow.** The fonts and the popover background radius are passed in through view state (`CommandBarViewObservableInputs.contentCornerRadius`), not set as literals in the view code. The two CommandBar value tables are dumped, but most of their slots are unnamed.
- **Content card shadow radius and opacity, scrim and border alpha.** The state only switches the shadow on. The drawing code reads the actual values from another state object that was not traced.
- **Split view divider width and drag handle.** `ARCUI.SplitViewController` receives them as init arguments. The caller is `WindowContentsContainerViewController`, a generic Swift class with no Objective-C metadata, and no direct call into the init was found in a static read.
- **Theme gradient color stops, noise defaults, crossfade duration.** The stop count is data (`BlendedGradientConfiguration.baseColors` and `overlayColors`), not a constant. No duration literal was found near the background renderer.
- **Floating sidebar corner radius.** The floating-sidebar code passes 6 and 5 to a layout helper, but that helper builds edge insets, not a radius. The radius was not found.
- **Hover delays, tooltip base delay, auto-archive sweep interval, auto-archive default in code.** These are passed in from settings or feature flags at run time, or sit in code paths not reached from the anchors used here.
- **Dock "+" and Library button frames.** Not traced. cra has measurements (L1521-1522).

Tool notes: REA 6.7.0 drove Ghidra 12.1.4. Ghidra's decompiler program for macOS arm64 was missing, so it was built from Ghidra's own bundled source into `Ghidra/Features/Decompiler/os/mac_arm_64/`. Import and auto-analysis took 18.4 minutes, with the slow analyzers switched off (decompiler-based analyzers, stack, function ID). Ghidra's decompiled text sometimes drops floating-point literals, so every number above was also read from the instructions (see `c/disasm/`) and from the raw bytes (`c/verify-constants.txt`). The scripts that rebuild the name maps and the fact index are in `c/scripts/`.
