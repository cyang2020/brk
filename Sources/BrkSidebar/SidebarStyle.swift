import AppKit
import BrkBase
import BrkDomain
import BrkUIKit

// Owner: W3. The sidebar's drawing numbers, ink colors and copy that the frozen contracts (`Metrics`,
// `SidebarTokens`, `Copy`) do not carry yet. Each one states its source in the same vocabulary as `Metrics`, so the
// integrator can move the whole group into `BrkBase/Metrics.swift` (and the inks into `SidebarTokens`, the strings
// into `Copy`) in one edit. "cra Lnnn" is a line of the measurement notes that layout-constants.md cites as cra.

/// The one instance: `Draw.rowTitleFont.value`.
let Draw = SidebarDrawMetrics()

struct SidebarDrawMetrics: MetricGroup {
    // Type: one family, the system font (visual-and-copy.md, Fonts: the default UI font is `system`).
    let rowTitleFont = Metric(14.0, .anatomy("cra L115: sidebar rows have 14 pt titles"))
    let groupTitleFont = Metric(12.0, .guess("tab group header title; Arc's TabGroupHeaderCellView was not captured, drawn as a section label"))
    let spaceHeaderFont = Metric(13.0, .anatomy("verify/visual-pairs/run-20261103 P01-a, P20-a: 对照 is 24.5 x 12 and This Window 80 wide, 13 pt semibold (cra L180 had 14 medium)"))
    let urlFont = Metric(13.0, .anatomy("cra L1219: URL pill host text is SF 13 regular"))
    let smallFont = Metric(12.0, .guess("Clear button and favorites empty title; Arc's tooltips are 12 pt medium (cra L790)"))
    let captionFont = Metric(11.0, .guess("favorites empty subtitle; Arc's secondary row line is 11 pt (cra L115)"))

    // Row interior, measured from the sidebar edge: favicon centred at 26, title at 45 (cra L141, L180).
    let faviconLeading = Metric(10.0, .anatomy("cra L141: favicon 16 pt centred 26 pt from the sidebar edge = selection inset 8 + 10"))
    /// The label's frame; its cell draws the text 2 further in (Arc's text starts at x 44).
    let titleLeading = Metric(34.0, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P01-a: Arc's row text starts 3 left of the cra L141 x 45"))
    let spaceChevron = Metric(13.0, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P05-c: Arc's collapse chevron is 7 pt wide, centred in the icon slot"))
    let spaceHeaderLeading = Metric(6.0, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P01-a: Arc's space name starts at x 16, 5 left of the row icon slot"))
    let dividerInset = Metric(18.0, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P01-a: the Pinned/Today hairline runs from x 18 to 18 before the sidebar edge"))
    let clearTrailing = Metric(19.0, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P01-c: Clear ends 19 before the sidebar edge"))
    let clearGap = Metric(10.0, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P01-c: the hairline stops 10 before Clear"))
    let titleTrailing = Metric(8.0, .guess("title end padding inside the selection, mirrors the 8 pt selection inset"))
    let closeTrailing = Metric(6.0, .guess("the hover button's right padding inside the selection: (36 - 24) / 2"))
    let emptyFavicon = Metric(14.0, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P01-a: Arc's empty favicon is a 14 pt square centred 26 from the sidebar edge"))
    let emptyFaviconRadius = Metric(2.5, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P01-a: the empty favicon's corners round over about 2.5 pt"))
    let folderGlyphWidth = Metric(22.0, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P01-a: Arc's open folder spans x 16 to 38 in the 16 pt icon row"))
    let folderClosedSide = Metric(18.0, .anatomy("verify/visual-pairs/run-20261103/results.tsv P13-a: Arc's closed folder is about 18 x 18, centred on the row"))
    let folderClosedRadius = Metric(3.0, .guess("corner radius of the closed folder's body in P13-a"))
    let folderGlyphShift = Metric(1.0, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P01-a: the folder is centred at x 27, 1 right of the favicon slot's centre"))
    let folderGlyphLine = Metric(1.4, .guess("the folder outline is about 1.4 pt wide in the P01-a capture (3 px at 2x)"))
    // Split rows: each pane a TabCellBackgroundChild box inside the row (measured on the 2026-11-03 Arc capture P23a/b).
    let splitSegmentInset = Metric(4.0, .guess("measured on the 2026-11-03 Arc capture P23a: pane boxes 4 pt inside the row's selection"))
    let splitSegmentGap = Metric(4.0, .guess("measured on the 2026-11-03 Arc capture P23a: 4 pt between pane boxes"))
    let splitSegmentRadius = Metric(8.0, .guess("measured on the 2026-11-03 Arc capture P23a: pane box corners about 8 pt"))
    let splitSegmentIconLeading = Metric(7.0, .guess("measured on the 2026-11-03 Arc capture P23a: the pane's icon 7 pt inside its box"))
    let splitSegmentTitleLeading = Metric(36.0, .guess("measured on the 2026-11-03 Arc capture P23a: the pane's title 36 pt inside its box"))
    let peekMarkerIcon = Metric(14.0, .guess("measured on the 2026-11-03 Arc capture P22a: a 14 pt icon in the 24 pt Peek marker"))
    let splitSegmentTitleMinWidth = Metric(80.0, .guess("the 2026-11-03 Arc capture P23b: four pane boxes of about 50 pt show icons only, two of 100 pt show titles"))

    // Title row (cra L1215, Arc 1.170 AX tree).
    let navButton = Metric(32.0, .anatomy("cra L1215: Go back, Go forward and Reload are 32 x 32"))
    let navGap = Metric(2.0, .anatomy("cra L1215: the navigation buttons are 2 pt apart"))
    let toggleGap = Metric(4.0, .anatomy("cra L1215: sidebar toggle at x 77 = the third light's end (73) + 4"))
    let navButtonCompact = Metric(28.0, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P03-b: at 164 Arc's back, forward and … are centred 28 apart, ending 6 from the edge"))
    let navGlyph = Metric(14.0, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P01-c: Arc's back arrow is 14.5 pt wide and its reload 15 pt"))
    let navButtonRadius = Metric(9.0, .guess("hover fill of the title-row buttons; reuses the URL pill accessory radius 9"))

    // Toolbar (P01-b): grey glyphs and host on the white card top.
    let toolbarGlyph = Metric(13.0, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P01-b: the toolbar arrows are 13 pt wide, a size under the title row's"))
    let toolbarHostSlack = Metric(2.0, .guess("the host label is a little wider than its cell so a short host never truncates"))
    let toolbarLinkGap = Metric(5.0, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P01-b: the host starts 5 after the link glyph"))
    let toolbarGlyphAlpha = Metric(0.5, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P01-b: toolbar glyphs #7E7E7E on white"))
    let toolbarDisabledAlpha = Metric(0.21, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P01-b: a disabled arrow is #C9C9C9 on white"))
    let toolbarTextAlpha = Metric(0.56, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P01-b: the host is #717171 on white"))
    let toolbarHairlineAlpha = Metric(0.045, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P01-b: the hairline under the toolbar is #F4F4F4 on white"))

    // URL pill.
    /// The label's frame; its cell draws the text 2 further in, at x 21 in the sidebar.
    let shareTextLeading = Metric(32.0, .anatomy("Q09 a: an Easel's \"Share\" starts at x 42 in the pill at x 8 (the label's own 2 pt inset first)"))
    let shareLockGlyph = Metric([10.0, 13.0, 13.0], .anatomy("Q09 a: the pill's lock is 10 x 13 at x 21 (13 into the pill)"))
    let shareEdge = Metric(1.0, .anatomy("Q09 a: an Easel's pill has a 1 pt #CFCFCF edge"))
    let pillTextLeading = Metric(11.0, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P01-a: pill at x 8, host text at x 21"))
    let pillSearchTextLeading = Metric(2.0, .guess("measured on the 2026-11-03 Arc capture P20a: a blank window's placeholder starts 34 pt into the pill, right after the magnifier"))
    let pillAccessoryInset = Metric(4.0, .guess("accessory button inset: (pill 36 - button 28) / 2"))
    let pillAccessoryGap = Metric(1.0, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P01-c: copy link and site controls centred 29 apart (cra L1222-1223)"))
    let pillAccessoryGlyph = Metric(15.0, .guess("copy-link and site-control glyph size inside the 28 pt accessory"))

    // Favorites.
    let tileFavicon = Metric(16.0, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P01-a: Arc's favicons are 16 pt in the 47 pt tiles"))
    let tileRingWidth = Metric(2.0, .anatomy("cra L475: the active favorite has a 2 pt rim inside the edge"))
    let tileRenameInset = Metric(4.0, .guess("side padding of the rename field across a favorites tile; Arc's favorite rename was not recovered"))
    let emptyDash = Metric([5.0, 5.0], .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P07-b: the empty favorites box is dashed 5 on, 5 off"))
    let emptyBoxFillAlpha = Metric(0.35, .guess("the empty favorites box is a shade lighter than the sidebar (#F3EEEB over #F0EBE6 in P07-b)"))
    let emptyBadge = Metric(16.0, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P07-b: a 16 pt star badge 12.5 below the box top"))
    let emptyBadgeTop = Metric(12.5, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P07-b: the badge spans y 101.5 to 117.5 in a box starting at 89"))
    let emptyTitleFont = Metric(13.0, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P07-b: Drag to add Favorites is bold, about 132 pt wide"))
    let emptyTitleGap = Metric(6.0, .guess("space between the star badge and the bold title in the empty favorites box"))
    let emptySubtitleGap = Metric(3.0, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P07-b: the subtitle's first line is centred 18 under the title's"))
    let emptyTextInset = Metric(26.0, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P07-b: the subtitle wraps after \"most\", its first line about 136 wide; 26 keeps that break at every scale down to 164 (P05-f), where a label's fixed padding makes the text relatively wider"))
    let emptySubtitleFont = Metric(11.5, .anatomy("verify/visual-pairs/run-20261103/P07/P07-b-arc.png: \"Favorites keep your most\" is 136.5 pt and \"used sites and apps close\" 140.5 pt wide, SF 11.5 (12 measures 141.6 and 146.2)"))
    let emptyCloseSize = Metric(18.0, .guess("hit size of the × on the empty favorites box"))
    let emptyCloseInset = Metric(15.0, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P07-b: the × is centred 15 in from the box's top-right corner"))

    // Dock.
    let dockGlyph = Metric(15.0, .guess("space emoji or symbol size in a 34 x 32 dock cell (cra L115: tiny emoji)"))
    let dockDot = Metric(8.0, .guess("dot for a space without an icon, measured on P25-a-arc.png (16 px at 2x)"))
    let dockActiveInk = Metric(0.47, .guess("black (white in dark) over the sidebar for the current space's icon or dot, sampled on P25 a (#817E7C on #EFEAE6)"))
    let dockInactiveInk = Metric(0.22, .guess("the same for the other spaces, sampled on P25 a (#BAB6B2)"))
    let dockButtonGlyph = Metric(15.0, .guess("Library and + glyph size in their 32 pt buttons"))
    let inactiveSpaceAlpha = Metric(0.45, .anatomy("cra L115: inactive space icons in the dock are dimmed; amount guessed"))

    // States and motion.
    let unloadedAlpha = Metric(0.5, .guess("Snapshot.swift: unloaded Pinned and Favorites tabs draw dimmer; amount guessed"))
    let dragThreshold = Metric(3.0, .guess("pointer travel before a press becomes a drag (AppKit's own threshold)"))
    let dragPreviewAlpha = Metric(0.9, .guess("opacity of the dragged row image"))
    let dragSourceAlpha = Metric(0.3, .guess("opacity of the row left behind while it is dragged"))
    let dragPreviewShadow = Metric(8.0, .guess("blur of the shadow under the dragged row or tile"))
    // The card a tab drag shows over the content (P23-d-arc.png: card x 989.5...1158.5, y 273.5...523.5 in the window).
    let dragCardWidth = Metric(169.0, .anatomy("verify/visual-pairs/run-20261103/P23/P23-d-arc.png: the drag card is 338 px wide at 2x"))
    let dragCardHeight = Metric(250.0, .anatomy("verify/visual-pairs/run-20261103/P23/P23-d-arc.png: the drag card is 500 px tall at 2x"))
    let dragCardRadius = Metric(18.0, .anatomy("verify/visual-pairs/run-20261103/P23/P23-d-arc.png: the card's edge is 13 pt in 1 pt below its top and meets the side 17 pt down"))
    let dragCardIcon = Metric(16.0, .anatomy("verify/visual-pairs/run-20261103/P23/P23-d-arc.png: the empty favicon is a 14 pt square, the row's 16 pt slot"))
    let dragCardIconCenter = Metric(105.0, .anatomy("verify/visual-pairs/run-20261103/P23/P23-d-arc.png: the icon is centred 105 below the card top, on its vertical axis"))
    let dragCardTitleFont = Metric(13.0, .anatomy("verify/visual-pairs/run-20261103/P23/P23-d-arc.png: \"Interface comparison\" is 137 pt wide in bold, SF 13 bold"))
    let dragCardTitleTop = Metric(137.0, .anatomy("verify/visual-pairs/run-20261103/P23/P23-d-arc.png: the title's capitals span 140.5...150 below the card top"))
    let dragCardInset = Metric(8.0, .guess("the title's side margin inside the card: Arc keeps the 137 pt \"Interface comparison\" on one line in the 169 pt card"))
    let dragCardShadow = Metric(10.0, .guess("blur of the drag card's shadow: it fades over about 16 pt at the sides, 20 below (P23-d-arc.png)"))
    let dragCardShadowOpacity = Metric(0.16, .guess("the drag card's shadow darkens #FCFCFC to #E4E5E5 at its side (P23-d-arc.png)"))
    let dropLineWidth = Metric(2.0, .guess("drop indicator thickness (DragHintHighlighted)"))
    // The split preview over a tab row's middle (P23-e-arc.png: capsule x 15...233.5, slot from 15, chip 22...114,
    // "Seconda…" from 150, × centred at 216 in the window).
    let splitJoinChipWidth = Metric(0.42, .anatomy("verify/visual-pairs/run-20261103/P23/P23-e-arc.png: the dragged tab's chip is 92 pt of the 218.5 pt capsule"))
    let splitJoinChipOffset = Metric(7.0, .anatomy("verify/visual-pairs/run-20261103/P23/P23-e-arc.png: the darker slot shows 7 pt left of the chip (x 15...22)"))
    let splitJoinTargetLeading = Metric(26.0, .anatomy("verify/visual-pairs/run-20261103/P23/P23-e-arc.png: the target's title starts 26 pt right of the capsule's middle"))
    let splitJoinTargetTrailing = Metric(7.0, .anatomy("verify/visual-pairs/run-20261103/P23/P23-e-arc.png: the target's title ends about 7 pt before the ×'s centre"))
    /// Saturation (a share of the theme's, capped at 0.5 like `HueInk`) and lightness of the slot and the chip.
    let splitJoinSlotInk = Metric([0.37, 0.586], .anatomy("verify/visual-pairs/run-20261103/P23/P23-e-arc.png: the slot is #82A9A8 (HSL 178, 0.185, 0.586) on the pale teal theme"))
    let splitJoinChipInk = Metric([0.254, 0.892], .anatomy("verify/visual-pairs/run-20261103/P23/P23-e-arc.png: the chip is #E0E7E7 (HSL 180, 0.127, 0.892)"))
    let splitJoinTargetInk = Metric(0.15, .anatomy("verify/visual-pairs/run-20261103/P23/P23-e-arc.png: the target's title is #D8D8D8 on the #F5F5F5 capsule"))
    let selectedShadowRadius = Metric(1.0, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P01-a: Arc's current tab card has a 1.5 pt shadow line under its lower edge, darkest at the edge"))
    let selectedShadowOffset = Metric(1.0, .anatomy("verify/visual-pairs/run-20261103/REPORT.md, P01-a: the shadow line sits under the card, not around it"))
    let floatingShadowRadius = Metric(16.0, .guess("floating sidebar shadow blur; not recovered (layout-constants.md, Not recovered)"))
    let floatingDismissPoll = Metric(1.0 / 30, .guess("seconds between pointer checks while the floating sidebar waits to close"))
    let autoScrollStep = Metric(8.0, .guess("points per drag sample when dragging near the list's top or bottom edge"))
    let hairline = Metric(1.0, .anatomy("cra L748: 1 pt hairlines (list edges); also the separator, the floating border and the empty favorites box"))
    let floatingGradientAlpha = Metric(0.92, .guess("opacity of the theme gradient over the blurred page in the floating sidebar"))
}

/// Colors the sidebar needs that `SidebarTokens` does not carry (visual-and-copy.md, section 1). Black or white by
/// scheme, like every sidebar token.
struct Ink {
    let scheme: Scheme
    /// The space's primary color: light titles take its hue (`sidebarInk`).
    var accent = RGBA(0.5, 0.5, 0.5)

    private func bw(_ lightAlpha: Double, _ darkAlpha: Double) -> NSColor {
        scheme == .light ? NSColor(white: 0, alpha: lightAlpha) : NSColor(white: 1, alpha: darkAlpha)
    }

    /// Row titles. Light: the theme's own near-black (`sidebarInk`; Arc writes a #F2EAE4 space's rows in #221910, not
    /// the ForegroundPrimary token #0E0F10 @ 0.9). Dark: #FFFFFF @ 0.8 (Base tokens).
    var text: NSColor {
        guard scheme == .light else { return NSColor(white: 1, alpha: 0.8) }
        let ink = sidebarInk(accent)
        return NSColor(srgbRed: ink.red, green: ink.green, blue: ink.blue, alpha: 1)
    }
    /// CommandBarPlaceholderText @ 0.6: the URL in the pill, and enabled title-row glyphs (cra L1220: ~59%).
    var secondary: NSColor { bw(0.6, 0.6) }
    /// CommandBarPlaceholderPlaceholderText @ 0.3: "Search or Enter URL…".
    var placeholder: NSColor { bw(0.3, 0.3) }
    /// TabCellSlash: black or white @ 0.3, the stroke between split panes in one row.
    var slash: NSColor { bw(0.3, 0.3) }
    /// LoadingPageBorder: #0C50FF light, #2AB6F6 dark.
    var loading: NSColor {
        scheme == .light ? NSColor(srgbRed: 12 / 255, green: 80 / 255, blue: 1, alpha: 1)
            : NSColor(srgbRed: 42 / 255, green: 182 / 255, blue: 246 / 255, alpha: 1)
    }
    /// PopoverShadow: #151C32 @ 0.3 light, @ 0.8 dark. The floating sidebar's shadow.
    var shadow: NSColor { NSColor(srgbRed: 21 / 255, green: 28 / 255, blue: 50 / 255, alpha: scheme == .light ? 0.3 : 0.8) }
    /// Active and hovered favorite tile: cra L473 measures white ~38% over a light sidebar; dark uses TabCellBackgroundCurrent.
    func tileCurrent(_ palette: Palette) -> NSColor {
        scheme == .light ? NSColor(white: 1, alpha: 0.38) : palette.color(palette.tokens.tabCurrent)
    }
}

extension Palette {
    var ink: Ink { Ink(scheme: scheme, accent: accent) }
}

/// Arc's copy that `Copy` does not hold yet (visual-and-copy.md section 3, unless noted).
enum SidebarCopy {
    static let closeKeepPinned = "Close and Keep Pinned"
    /// The group header's × (Arc: "Tooltip for the button to close a group of tabs in the sidebar"; the text itself
    /// is not in the static strings).
    static let closeTabGroup = "Close Tab Group"
    static let refreshLiveFolder = "Refresh Live Folder"

    /// The note in an open Live Folder without rows.
    static func liveFolderNote(_ state: LiveFolderState) -> String {
        switch state {
        case .loading: "Loading pull requests…"
        case .empty, .ready: "No open pull requests"
        case .failed: "Couldn’t refresh. Try Again"
        case .notLoaded: "Not refreshed yet. Refresh"
        case .stale: "Refresh to update"
        }
    }

    /// The Live Folder row's tooltip: its source and how fresh it is.
    static func liveFolderTip(_ live: LiveFolderSnapshot) -> String {
        let state: String = switch live.state {
        case .loading: "Refreshing…"
        case .ready(let n): n == 1 ? "1 open pull request" : "\(n) open pull requests"
        case .empty: "No open pull requests"
        case .stale: "Refresh to update"
        case .notLoaded: "Not refreshed since launch"
        case .failed(let message): message
        }
        return "GitHub · \(live.source)\n\(state)"
    }
    static let collapsePinned = "Collapse Pinned Tabs"
    static let expandPinned = "Expand Pinned Tabs"
    /// cra L1215: the title-row buttons' accessibility names.
    static let goBack = "Go back"
    static let goForward = "Go forward"
    static let reload = "Reload"
    static let stop = "Stop"
    static let showHideSidebar = "Show/Hide Sidebar"
    /// The dock's left button opens the Library (Arc's `HomeButton`, "View Library").
    static let library = "Library"
    static let copyLink = "Copy Link"
    static let newSpaceMenu = "New…"
    /// Arc's title for a new tab before its first document commits.
    static let untitled = "Untitled"
    static let spaceOptions = "Space Options"
    static let dismiss = "Dismiss"
}
