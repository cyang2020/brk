import CoreGraphics
import Foundation

// The constants file. Every layout, motion and theme number in the app is a `Metric` here, and a `Metric` cannot
// be built without a `MetricSource`. The inventory test (Tests/ArchitectureTests/MetricInventoryTests.swift) walks
// this table with reflection: every stored property of every group must be a `Metric` or another `MetricGroup`, so
// a bare `let x = 12.0` added anywhere in the table fails the test; every `.arc` source must be the start of a row
// in docs/arc-anatomy/layout-constants.md and state that row's confidence; every `.derived` rule must name rows;
// every `.guess` must give a reason.
//
// Views and layout read `.value`. No other file in Sources/ may contain a layout number (ArchitectureTests flags a
// literal `cornerRadius = <digit>` anywhere; reviewers catch the rest).

/// The "Confidence" column of layout-constants.md.
public enum Confidence: String, Hashable, Sendable, CaseIterable { case high, medium, low }

public enum MetricSource: Hashable, Sendable {
    /// A row of docs/arc-anatomy/layout-constants.md (decompiled from Arc 1.170.0, or a cra measurement cited
    /// there). `constant` is the start of the row's "Constant" cell; `confidence` must appear in its "Confidence"
    /// cell; `note` says which part of a row with several values this metric takes.
    case arc(_ constant: String, _ confidence: Confidence = .high, note: String? = nil)
    /// Computed from several rows; `rule` says how, `from` names the rows.
    case derived(rule: String, from: [String])
    /// Another anatomy fact: file and section.
    case anatomy(String)
    /// Ours, with the reason.
    case guess(String)
}

/// Erased view of a metric, for the inventory test and the control socket.
public protocol AnyMetric: Sendable {
    var source: MetricSource { get }
    var valueDescription: String { get }
}

/// A named group of metrics (or of groups). The inventory test recurses into these and rejects anything else.
public protocol MetricGroup: Sendable {}

public struct Metric<Value: Sendable>: Sendable, AnyMetric {
    public let value: Value
    public let source: MetricSource
    public init(_ value: Value, _ source: MetricSource) {
        self.value = value
        self.source = source
    }
    public var valueDescription: String { "\(value)" }
}

/// The one instance. `Metrics.sidebar.minWidth.value`.
public let Metrics = MetricsTable()

public struct MetricsTable: MetricGroup {
    public let sidebarTools = SidebarToolsMetrics()
    public let spaceTools = SpaceToolsMetrics()
    public let window = WindowMetrics()
    public let sidebar = SidebarMetrics()
    public let urlPill = URLPillMetrics()
    public let favorites = FavoritesMetrics()
    public let tablist = TablistMetrics()
    public let dock = DockMetrics()
    public let content = ContentMetrics()
    public let commandBar = CommandBarMetrics()
    public let ai = AIMetrics()
    public let motion = MotionMetrics()
    public let theme = ThemeMetrics()
    public let littleArc = LittleArcMetrics()
    public let peek = PeekMetrics()
    public let library = LibraryMetrics()
    public let settings = SettingsMetrics()
    public let persistence = PersistenceMetrics()
    public let keys = KeyMetrics()
    public let find = FindMetrics()
}

public struct WindowMetrics: MetricGroup {
    public let defaultSize = Metric(CGSize(width: 1280, height: 776), .arc("Main window default size"))
    public let trafficLightLeft = Metric(13.0, .arc("Title row left inset"))
    public let trafficLightSize = Metric(14.0, .arc("Window button (traffic light) size"))
    public let trafficLightSpacing = Metric(9.0, .arc("Window button spacing", note: "9 on current macOS; 6 behind an OS check"))
    /// Centre line of the traffic lights from the top.
    public let trafficLightCenterY = Metric(24.0, .derived(rule: "header top inset 4 + title row height 40 / 2",
                                                            from: ["Sidebar header top inset", "Title row (window buttons and navigation buttons) height"]))
    public let trafficLightHoverZone = Metric(CGRect(x: -50, y: 0, width: 140, height: 50), .arc("Traffic-light hover zone", .medium))
}

public struct SidebarMetrics: MetricGroup {
    public let minWidth = Metric(164.0, .arc("Sidebar minimum width while dragging"))
    public let maxWidth = Metric(500.0, .arc("Sidebar maximum width"))
    public let hideBelow = Metric(82.0, .arc("Drag-to-hide threshold"))
    /// 8 + 8 + 4 x 47 + 3 x 8: the narrowest width that keeps four square favorites.
    public let resetWidth = Metric(228.0, .arc("Reset width on double-click of the sidebar edge"))
    public let snapTarget = Metric(228.0, .arc("Snap target while dragging"))
    public let snapDistance = Metric(14.0, .arc("Snap distance"))
    public let snapHold = Metric(0.5, .arc("Snap hold time", .medium))
    public let unsnapSpeed = Metric(50.0, .arc("Unsnap speed threshold", .medium))
    public let defaultWidth = Metric(228.0, .arc("Default sidebar width for a new window", .low))
    public let resizeHitWidth = Metric(8.0, .arc("Resize hit area", .medium, note: "width"))
    public let resizeHitTop = Metric(11.0, .arc("Resize hit area", .medium, note: "starts 11 below the top"))
    public let resizeHitBottomTrim = Metric(22.0, .arc("Resize hit area", .medium, note: "height = window height minus 22"))
    public let resizeIndicatorWidth = Metric(3.0, .arc("Resize indicator drawn while dragging", note: "width"))
    public let resizeIndicatorTrim = Metric(8.0, .arc("Resize indicator drawn while dragging", note: "hit-area height minus 8"))
    public let floatingInset = Metric(5.0, .arc("Floating sidebar inset from the window", .medium))
    public let floatingParkedGap = Metric(10.0, .arc("Floating sidebar parked position when hidden", .medium))
    public let floatingStayOpenSlack = Metric(80.0, .arc("Floating sidebar stays open while the pointer is within", .medium))
    public let outsideHoverZoneWidth = Metric(250.0, .arc("Hover zone outside the window's left edge", .medium))
    /// Multiples of the left content inset L: reveal strip from 2L outside to 1.5L inside; 0.6L when unhovered.
    public let revealOutsideFactor = Metric(2.0, .arc("Hidden-sidebar reveal strip at the left edge", .low, note: "2 x L outside"))
    public let revealInsideFactor = Metric(1.5, .arc("Hidden-sidebar reveal strip at the left edge", .low, note: "1.5 x L inside"))
    public let revealUnhoveredFactor = Metric(0.6, .arc("Hidden-sidebar reveal strip at the left edge", .low, note: "0.6 x L while not hovered"))
    public let headerTopInset = Metric(4.0, .arc("Sidebar header top inset"))
    public let titleRowHeight = Metric(40.0, .arc("Title row (window buttons and navigation buttons) height"))
    public let titleRowRightInset = Metric(6.0, .arc("Title row right inset"))
    public let headerBackgroundOverhang = Metric(30.0, .arc("Sidebar header background reaches below the header by", .medium))
    public let libraryMinWidth = Metric(417.0, .arc("Library (\"home\") panel width", note: "max(417, ...)"))
    public let libraryWindowMargin = Metric(56.0, .arc("Library (\"home\") panel width", note: "window width minus 56"))
}

public struct URLPillMetrics: MetricGroup {
    public let sideInset = Metric(8.0, .arc("URL pill horizontal inset"))
    public let height = Metric(36.0, .arc("URL pill height"))
    /// Continuous corners.
    public let cornerRadius = Metric(12.0, .arc("URL pill corner radius", .medium))
    public let leadingIcon = Metric(22.0, .arc("URL pill leading icon", .medium))
    public let accessorySize = Metric(28.0, .arc("URL pill accessory buttons", .medium, note: "28 x 28"))
    public let accessoryRadius = Metric(9.0, .arc("URL pill accessory buttons", .medium, note: "corner radius 9"))
    public let textMinHeight = Metric(20.0, .arc("URL pill text area minimum height", .low))
    /// Space between the title row and the pill.
    public let topGap = Metric(2.0, .guess("not in the constants table; cra L1217 measures the pill at y 46 below a title row that ends at 44"))
}

public struct FavoritesMetrics: MetricGroup {
    public let inset = Metric(8.0, .arc("Favorites tray insets"))
    public let maxColumns = Metric(4, .arc("Favorites columns"))
    public let minTile = Metric(47.0, .arc("Favorites minimum tile size"))
    public let gap = Metric(8.0, .arc("Favorites gap"))
    /// Continuous corners.
    public let tileRadius = Metric(12.0, .arc("Favorites tile corner radius"))
    public let ringInset = Metric(1.0, .arc("Selected favorite ring", .medium, note: "inset 1"))
    public let ringRadius = Metric(11.0, .arc("Selected favorite ring", .medium, note: "corner radius 11"))
}

public struct TablistMetrics: MetricGroup {
    public let rowHeight = Metric(40.0, .arc("Sidebar row height", note: "40"))
    public let rowSpacing = Metric(1.0, .arc("Sidebar row height", .medium, note: "1 pt between rows"))
    public let dividerRowHeight = Metric(16.0, .arc("Pinned/Today divider row", .medium))
    public let dividerRowTallHeight = Metric(24.0, .arc("Pinned/Today divider row", .medium, note: "24 in one state"))
    public let topSpacerHeight = Metric(2.0, .arc("Spacer row at the top of the list", .medium))
    public let headerRowHeight = Metric(36.0, .arc("Another row type (probably folder or split header)", .low))
    /// The space title strip between the favorites tray and the tab list (outside the scrolling list: cra L1515
    /// sees the header stay put while the list scrolls; cra L141 puts its centre 18 below the tray).
    public let spaceHeaderHeight = Metric(36.0, .arc("Another row type (probably folder or split header)", .low,
                                                     note: "read as the space header strip; its role is not confirmed in code"))
    public let selectionHeight = Metric(36.0, .arc("Row selection background", .medium, note: "36 tall"))
    public let selectionInset = Metric(8.0, .arc("Row selection background", .medium, note: "inset 8"))
    public let selectionRadius = Metric(12.0, .arc("Row selection background", .medium, note: "corner radius 12"))
    public let hoverButtonRadius = Metric(12.0, .arc("Tab row hover-button background corner radius", .low))
    public let folderIndent = Metric(16.0, .guess("folder indent was not recovered (layout-constants.md, Not recovered); cra measures 18 at L142"))
    public let favicon = Metric(16.0, .guess("favicon size was not recovered; cra L142 measures rows only"))
}

public struct DockMetrics: MetricGroup {
    public let height = Metric(50.0, .arc("Dock (space switcher) height"))
    public let cellMaxWidth = Metric(34.0, .arc("Dock space cell width", note: "at most 34"))
    public let cellMinWidth = Metric(8.0, .arc("Dock space cell width", note: "shrinks to 8"))
    public let compactBelow = Metric(22.0, .arc("Dock space cell width", note: "compact below 22"))
    public let cellMaxHeight = Metric(32.0, .arc("Dock space cell height"))
    public let cellRadius = Metric(6.0, .arc("Dock cell corner radius"))
    public let pressScale = Metric(0.95, .arc("Dock cell press scale", .medium))
    public let buttonSize = Metric(32.0, .arc("\"+\" and Library buttons", .low, note: "32 x 32 (cra L1521-1522)"))
    public let buttonInset = Metric(8.0, .arc("\"+\" and Library buttons", .low, note: "8 from the edge"))
    public let libraryBottom = Metric(9.0, .arc("\"+\" and Library buttons", .low, note: "Library 9 from the bottom"))
}

public struct ContentMetrics: MetricGroup {
    public let inset = Metric(10.0, .arc("Content card inset", note: "10"))
    /// Continuous corners.
    public let cornerRadius = Metric(6.0, .arc("Content card corner radius"))
    public let fullScreenCornerRadius = Metric(0.0, .arc("Content card corner radius", note: "0 in one state"))
    public let showsShadow = Metric(true, .arc("Content card shadow", .medium))
    public let shadowRadius = Metric(10.0, .guess("shadow radius and opacity were not recovered; the spike's value"))
    public let shadowOpacity = Metric(0.2, .guess("visual-and-copy.md Shadow token #000000 @ 0.2 (light); the draw value was not recovered"))
    public let highlightBorder = Metric(2.0, .arc("Content highlight border width", .medium))
    public let splitGap = Metric(10.0, .arc("Split view gap between panes", .low))
    /// Each split pane's header (back, forward, reload, host, close) and the hairline under it.
    public let paneHeaderHeight = Metric(32.0, .guess("measured on the 2026-11-03 Arc capture P23a: the header runs from the card top to the hairline 32 pt below"))
    public let paneHeaderSeparator = Metric(1.0, .guess("measured on the 2026-11-03 Arc capture P23a: a 1 pt hairline under the pane header"))
    public let paneHeaderButton = Metric(28.0, .guess("measured on the 2026-11-03 Arc capture P23a: header buttons on a 36 pt pitch, glyphs 14 pt"))
    public let paneHeaderButtonPitch = Metric(36.0, .guess("measured on the 2026-11-03 Arc capture P23a: back, forward and reload centres 36 pt apart"))
    public let paneHeaderEdge = Metric(21.0, .guess("measured on the 2026-11-03 Arc capture P23a: the first and last button centres 21 pt in from the card edges"))
    public let paneHeaderFont = Metric(13.0, .guess("measured on the 2026-11-03 Arc capture P23a: the host reads at the sidebar's 13 pt"))
    public let maxPanes = Metric(4, .anatomy("visual-and-copy.md, Split view: first to fourth Split View page"))
    public let minPaneFraction = Metric(0.15, .guess("narrowest a pane may be dragged, as a fraction of the content width; Arc's minimum was not traced"))
}

public struct CommandBarMetrics: MetricGroup {
    public let width = Metric(766.0, .arc("Command bar width", note: "766"))
    public let sideMargin = Metric(160.0, .arc("Command bar width", .medium, note: "area width minus 160"))
    public let narrowMargin = Metric(20.0, .arc("Command bar width", .medium, note: "area width minus 20 when narrower than 766"))
    public let boxHeight = Metric(338.0, .arc("Command bar box height and position", .medium, note: "338 tall"))
    public let minVerticalMargin = Metric(24.0, .arc("Command bar box height and position", .medium, note: "at least 24 from top and bottom"))
    public let attachedMinWidth = Metric(100.0, .arc("Command bar attached to the toolbar", .low, note: "width 100 to 720"))
    public let attachedMaxWidth = Metric(720.0, .arc("Command bar attached to the toolbar", .low, note: "width 100 to 720"))
    public let attachedRightMargin = Metric(80.0, .arc("Command bar attached to the toolbar", .low, note: "at least 80 from the right edge"))
    public let suggestionRowHeight = Metric(50.0, .arc("Command bar suggestion row height"))
    public let maxVisibleRows = Metric(5, .arc("Visible suggestions and list height", .medium, note: "1 to 5 rows"))
    public let listPadding = Metric(10.0, .arc("Visible suggestions and list height", .medium, note: "rows x 50 + 10"))
    public let inputRowHeight = Metric(50.0, .arc("Command bar input row height", .medium, note: "at least 50; cra measures 60"))
    public let stackSpacing = Metric(10.0, .arc("Command bar inner spacing", .medium, note: "stack spacing 10"))
    public let contentInset = Metric(12.0, .arc("Command bar inner spacing", .medium, note: "inset 12"))
    public let openBounceFrom = Metric(0.95, .arc("Command bar opening bounce", .medium))
    public let littleArcWidth = Metric(500.0, .arc("Little Arc command bar width", .low))
    /// Typing pause before the default engine's suggest endpoint is asked (`Effect.fetchSuggestions`).
    public let suggestionDebounce = Metric(0.15, .guess("debounce before a search-suggestion fetch; Arc's value was not traced"))
    public let maxSearchSuggestions = Metric(5, .guess("search-engine suggestions shown; Arc shows a handful under the typed row"))
}

public struct MotionMetrics: MetricGroup {
    public let sidebarToggle = Metric(0.08, .arc("Sidebar show/hide animation duration"))
    /// cubic-bezier control points (x1, y1, x2, y2).
    public let sidebarCurve = Metric([0.25, 0.46, 0.45, 0.94], .arc("Sidebar show/hide timing curve"))
    public let contentRelayout = Metric(0.2, .arc("Content relayout animation (same curve)", .medium))
    public let spaceSwitch = Metric(0.17, .arc("Space switch animation", .low))
    /// Arc's shader has a `transitioning` state but no duration literal was found; we reuse the space switch.
    public let themeCrossfade = Metric(0.17, .guess("crossfade duration was not recovered; equals the space switch"))
    public let tooltipQuickReshowWindow = Metric(0.6, .arc("Tooltip quick re-show", note: "closed less than 0.6 s ago"))
    public let tooltipQuickReshowDelay = Metric(0.01, .arc("Tooltip quick re-show", note: "appears after 0.01 s"))
    public let tooltipFirstDelay = Metric(1.6, .arc("Tooltip first-show delay", .medium))
    public let toastDuration = Metric(5.0, .arc("Toast duration", note: "5 by default"))
}

public struct ThemeMetrics: MetricGroup {
    /// Texture opacity = intensity x multiplier; tiled; multiply blend (normal when intensity is 0).
    public let grainOpacity = Metric(0.8, .arc("Theme texture opacity, as a multiple of the theme intensity", .medium, note: "grain"))
    public let sandOpacity = Metric(0.15, .arc("Theme texture opacity, as a multiple of the theme intensity", .medium, note: "sand"))
    public let denimOpacity = Metric(0.6, .arc("Theme texture opacity, as a multiple of the theme intensity", .medium, note: "denim"))
    public let tweedOpacity = Metric(0.4, .arc("Theme texture opacity, as a multiple of the theme intensity", .medium, note: "tweed"))
    /// Wash: white in light, black at 35% in dark; opacity = min(base + slope x factor, cap).
    public let darkWashAlpha = Metric(0.35, .arc("Theme background wash", .low, note: "dark: black at 35%"))
    public let washBase = Metric(0.2, .arc("Theme background wash", .low, note: "0.2 +"))
    public let washSlope = Metric(0.55, .arc("Theme background wash", .low, note: "0.55 x factor"))
    public let washCap = Metric(0.5, .arc("Theme background wash", .low, note: "capped at 0.5"))
    public let gradientTexturePerFactor = Metric(100.0, .arc("Metal gradient texture size", .low))
    /// Tile sizes of Arc's own textures (px @1x). Ours are generated procedurally at these sizes.
    public let grainTile = Metric(155, .anatomy("visual-and-copy.md, Gradient and grain assets"))
    public let sandTile = Metric(96, .anatomy("visual-and-copy.md, Gradient and grain assets"))
    public let denimTile = Metric(300, .anatomy("visual-and-copy.md, Gradient and grain assets"))
    public let tweedTile = Metric(128, .anatomy("visual-and-copy.md, Gradient and grain assets"))
    /// Wheel rules for the companion colors derived from the primary (Arc: `wheel` analogous | complimentary).
    public let analogousHueOffset = Metric(30.0, .guess("analogous companions at +-30 degrees; Arc's exact offset was not recovered"))
    public let complementaryHueOffset = Metric(180.0, .anatomy("model-and-shortcuts.md 1.13: wheel `complimentary` is the opposite hue"))
    /// Lightness moved by each wheel companion: the first lighter, the second darker.
    public let companionLightnessStep = Metric(0.06, .guess("electron-v1 theme.ts themeFromPrimary: companions 6% lighter and 6% darker; Arc's lightnessRange was not recovered"))
}

public struct LittleArcMetrics: MetricGroup {
    public let defaultSize = Metric(CGSize(width: 1185, height: 832), .arc("Little Arc default window size", .medium))
    public let cascade = Metric(30.0, .arc("Little Arc default window size", .medium, note: "new windows cascade by 30"))
    /// The other sizes Arc's `LittleBrowserWindow` uses in other branches; which branch is which was not traced.
    public let compactSize = Metric(CGSize(width: 800, height: 600), .arc("Little Arc default window size", .medium, note: "800 x 600 in another branch"))
    public let commandBarWidth = Metric(500.0, .arc("Little Arc command bar width", .low))
    /// Without a page a Little Arc is its command bar alone (the 2026-11-03 capture P21a: 980 x 658 px at 2x).
    public let commandBarSize = Metric(CGSize(width: 490, height: 329), .arc("Little Arc default window size", .medium, note: "490 x 329 in another branch"))
    // The header over the page (measured on the 2026-11-03 Arc capture P21b, a 1185 x 832 window).
    public let headerHeight = Metric(47.0, .guess("measured on the 2026-11-03 Arc capture P21b: the page starts 47 pt below the window top"))
    public let lightsLeading = Metric(10.0, .guess("measured on the 2026-11-03 Arc capture P21b: the close light's left edge 10 pt from the window's"))
    public let controlTop = Metric(8.0, .guess("measured on the 2026-11-03 Arc capture P21b: the pill and the Open in button start 8 pt below the top"))
    public let pillLeading = Metric(83.0, .guess("measured on the 2026-11-03 Arc capture P21b: the host pill starts 83 pt from the left, after the lights"))
    public let pillHeight = Metric(31.0, .guess("measured on the 2026-11-03 Arc capture P21b: the host pill is 31 pt tall"))
    public let pillGap = Metric(9.0, .guess("measured on the 2026-11-03 Arc capture P21b: 9 pt between the pill and the Open in button"))
    public let openInHeight = Metric(30.0, .guess("measured on the 2026-11-03 Arc capture P21b: the Open in button is 30 pt tall"))
    public let openInTrailing = Metric(7.0, .guess("measured on the 2026-11-03 Arc capture P21b: the Open in button ends 7 pt from the right"))
    public let pickerWidth = Metric(247.0, .guess("measured on the 2026-11-03 Arc capture P21c: the space picker is 247 pt wide"))
    public let pickerTop = Metric(4.0, .guess("measured on the 2026-11-03 Arc capture P21c: the picker starts 4 pt below the top"))
    public let pickerTrailing = Metric(4.0, .guess("measured on the 2026-11-03 Arc capture P21c: the picker ends 4 pt from the right"))
    public let pickerSearchHeight = Metric(46.0, .guess("measured on the 2026-11-03 Arc capture P21c: the Search Spaces field row is 46 pt"))
    public let pickerRowHeight = Metric(46.0, .guess("measured on the 2026-11-03 Arc capture P21c: space rows on a 46 pt pitch"))
    public let pickerIcon = Metric(26.0, .guess("measured on the 2026-11-03 Arc capture P21c: 26 pt icon boxes, 13 pt in from the picker's edge"))
    public let closeButton = Metric(24.0, .guess("measured on the 2026-11-03 Arc capture P21a: the bar's close button is 24 pt square, 22 pt from the right, centred on the input row"))
    public let openInRadius = Metric(7.0, .guess("measured on the 2026-11-03 Arc capture P21b: the Open in button's corners about 7 pt"))
    public let badgeRadius = Metric(4.0, .guess("measured on the 2026-11-03 Arc capture P21b: the ⌘O badge's corners about 4 pt"))
    public let controlRadius = Metric(6.0, .guess("measured on the 2026-11-03 Arc captures P21a/c: the close button, collapse button and icon boxes round about 6 pt"))
    public let pickerRadius = Metric(10.0, .guess("measured on the 2026-11-03 Arc capture P21c: the space picker's corners about 10 pt"))
}

/// Peek (Arc: `modalV2`): a card over the content area with a column of round buttons beside it. Arc's modal frame
/// math was not traced; the values are measured on the 2026-11-03 paired capture (P22a, 1280 x 776 window).
public struct PeekMetrics: MetricGroup {
    /// The card's left edge from the content area's (333 - 228 on the capture).
    public let leadingInset = Metric(105.0, .guess("measured on the 2026-11-03 Arc capture P22a: card left edge 105 pt right of the content area's"))
    /// The card's right edge from the content area's (1270 - 1175 on the capture), room for the button column.
    public let trailingInset = Metric(95.0, .guess("measured on the 2026-11-03 Arc capture P22a: card right edge 95 pt left of the content area's"))
    public let verticalInset = Metric(2.0, .guess("measured on the 2026-11-03 Arc capture P22a: card 12 pt below the window top and 12 pt above its bottom"))
    public let cornerRadius = Metric(6.0, .derived(rule: "the capture's card corner matches the content card's", from: ["Content card corner radius"]))
    public let shadowRadius = Metric(18.0, .guess("Peek card shadow radius; the capture shows a soft shadow, the value was not traced"))
    /// The three round buttons (close, open as tab, open in split) beside the card's top right corner.
    public let controlSize = Metric(34.0, .guess("measured on the 2026-11-03 Arc capture P22a: white circles 34 pt across"))
    public let controlGap = Metric(13.0, .guess("measured on the 2026-11-03 Arc capture P22a: 13 pt between the card and the circles"))
    public let controlTop = Metric(7.0, .guess("measured on the 2026-11-03 Arc capture P22a: the first circle's top 7 pt below the card's"))
    public let controlPitch = Metric(44.0, .guess("measured on the 2026-11-03 Arc capture P22a: circle centres 44 pt apart"))
    public let controlGlyph = Metric(15.0, .guess("measured on the 2026-11-03 Arc capture P22a: the glyphs are about 15 pt"))
    /// The page under an open Peek is washed with the window color (white reads #F7F4F1 under the #F2EAE4 theme).
    public let backdropAlpha = Metric(0.55, .guess("measured on the 2026-11-03 Arc capture P22a: white under the Peek reads 55 percent toward the theme color"))
}

/// The Library (downloads, history, archive, media, easels and notes, boosts, spaces). Like Arc's, its panel replaces
/// the sidebar (width: Metrics.sidebar.libraryMinWidth and .libraryWindowMargin) and the open page fills the content
/// area. The panel lists the pages under the title row, one sidebar-sized row each (Metrics.tablist.selectionInset
/// and .rowSpacing); its exit button is where the dock's Library button is (Metrics.dock).
public struct LibraryMetrics: MetricGroup {
    public let listTop = Metric(44.0, .derived(rule: "header top inset 4 + title row height 40: the page list starts under the traffic lights",
                                               from: ["Sidebar header top inset", "Title row (window buttons and navigation buttons) height"]))
    public let rowHeight = Metric(40.0, .arc("Sidebar row height", note: "a page row in the Library panel is a sidebar row"))
}

/// The settings window (Arc: `PreferencesFeature`, a `Settings` package window with a pane toolbar). Arc builds its
/// panes with the sindresorhus/Settings package (the binary has `Settings.SettingsWindowController`,
/// `ToolbarItemStyleViewController`, `Settings.Container(contentWidth:minimumLabelWidth:)` and `Settings.Section`):
/// a right-aligned label column, the controls beside it, a divider between sections, and a window that fits each
/// pane's height. Arc's own numbers were not recovered, so every value here is ours.
public struct SettingsMetrics: MetricGroup {
    /// The content size the window opens at, before the first pane is measured and the window fits it.
    public let windowSize = Metric(CGSize(width: 660, height: 460), .guess("settings window content size before the pane fits it; contentWidth plus both horizontal paddings wide"))
    /// Every pane is this wide (Settings.Container's `contentWidth`).
    public let contentWidth = Metric(600.0, .guess("pane content width; Arc's Settings.Container(contentWidth:) value was not recovered; fits a label column and the longest Links checkbox"))
    public let horizontalPadding = Metric(30.0, .guess("Settings.Container's horizontal padding in the sindresorhus/Settings package source"))
    public let verticalPadding = Metric(20.0, .guess("Settings.Container's vertical padding in the sindresorhus/Settings package source"))
    /// The right-aligned label column (Settings.Container's `minimumLabelWidth`).
    public let labelWidth = Metric(170.0, .guess("label column width; fits 'Archive Little Arcs after:' and 'Air Traffic Control:' at the system font"))
    public let columnSpacing = Metric(8.0, .guess("space between the label column and the controls (SwiftUI's default HStack spacing)"))
    public let rowSpacing = Metric(8.0, .guess("vertical space between the controls of one section"))
    /// The divider row between sections (the package's Divider frame height).
    public let sectionSpacing = Metric(20.0, .guess("height of the divider row between sections in the sindresorhus/Settings package source"))
    /// A checkbox's description lines up with its title, past the box.
    public let checkboxTextInset = Metric(20.0, .guess("AppKit checkbox box width plus its title gap at the regular control size"))
    public let popUpWidth = Metric(180.0, .guess("width of the pop-up buttons, so the pickers of a pane line up"))
    /// Folder icons in the Download Location menu.
    public let menuIconSize = Metric(16.0, .guess("AppKit's small icon size for menu item images"))
    /// The "is not your default web browser" box at the top of General (Arc: MakeDefaultViewBackgroundColor).
    public let noticePadding = Metric(12.0, .guess("inner padding of the default-browser notice box"))
    public let noticeCornerRadius = Metric(8.0, .guess("corner radius of the default-browser notice box"))
    /// The profile picker above the profile's settings (Arc: ProfilePicker and ProfilePickerText colors).
    public let profilePillSpacing = Metric(6.0, .guess("space between the profile picker's pills"))
    public let profilePillPadding = Metric(CGSize(width: 10, height: 4), .guess("inner padding of a profile picker pill"))
    public let profilePillCornerRadius = Metric(6.0, .guess("corner radius of a profile picker pill"))
    /// Air Traffic Control (Arc: LinkRoutingDialog): the pattern field and how tall the route list grows.
    public let routePatternWidth = Metric(220.0, .guess("width of a route's host pattern field"))
    public let routeListMaxHeight = Metric(180.0, .guess("the route list scrolls past this height so the Links pane stays on screen"))
    /// The Shortcuts pane's list scrolls inside a fixed height (the table has more than a hundred actions).
    public let shortcutsListHeight = Metric(360.0, .guess("height of the Shortcuts pane's scrolling list"))
}

public struct PersistenceMetrics: MetricGroup {
    public let saveDebounce = Metric(0.4, .guess("trailing debounce for state.json writes"))
    public let sweepInterval = Metric(60.0, .guess("real-time interval of the auto-archive sweep; Arc's comes from settings at run time"))
    public let shutdownTimeout = Metric(5.0, .guess("longest wait for OnBeforeClose of every browser at quit before the controlled failure"))
    public let historyCap = Metric(500, .guess("history entries kept"))
    public let archiveCap = Metric(2000, .guess("archive entries kept"))
}

public struct KeyMetrics: MetricGroup {
    /// Arc's "press twice for Arc's shortcut" window is a runtime value; ours.
    public let pressTwiceWindow = Metric(1.0, .guess("promptAfterConsumedByWebView second-press window"))
    /// How long a `beforePage` press identity is kept for its `afterPage` partner (PressCorrelator).
    public let correlationWindow = Metric(2.0, .guess("longest the renderer may take to answer OnPreKeyEvent before OnKeyEvent is treated as a new press"))
}

public struct FindMetrics: MetricGroup {
    public let width = Metric(540.0, .guess("Native find controls sized for one page card; Arc pixel parity remains unmeasured"))
    public let padding = Metric(8.0, .guess("Native find bar inset"))
    public let row = Metric(28.0, .guess("Native small text controls plus vertical breathing room"))
    public let gap = Metric(4.0, .guess("Find control spacing"))
    public let button = Metric(28.0, .guess("Find navigation and close button width"))
    public let actionWidth = Metric(92.0, .guess("Minimum width for readable replacement action labels"))
}

/// Local CLI answer document; these are Brk choices, not claimed Arc pixel measurements.
public struct AIMetrics: MetricGroup {
    public let width = Metric(420.0, .guess("readable answer column beside the source page"))
    public let minimumWidth = Metric(260.0, .guess("minimum answer column width"))
    public let minimumHeight = Metric(180.0, .guess("minimum answer panel height"))
    public let inset = Metric(12.0, .guess("answer panel inset from content card"))
    public let padding = Metric(18.0, .guess("answer document inner margin"))
    public let gap = Metric(8.0, .guess("answer controls vertical spacing"))
    public let buttonHeight = Metric(26.0, .guess("native answer control height"))
    public let closeWidth = Metric(70.0, .guess("answer cancel and close button width"))
    public let questionHeight = Metric(44.0, .guess("two-line question heading"))
    public let headingFont = Metric(14.0, .guess("answer document header font"))
    public let questionFont = Metric(15.0, .guess("answer question font"))
    public let bodyFont = Metric(13.0, .guess("selectable answer body font"))
    public let cornerRadius = Metric(12.0, .guess("answer document rounded corners"))
    public let borderWidth = Metric(1.0, .guess("answer panel hairline"))
}
