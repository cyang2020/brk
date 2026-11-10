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
    public let pageSwipe = PageSwipeMetrics()
    public let miniPlayer = MiniPlayerMetrics()
    public let content = ContentMetrics()
    public let commandBar = CommandBarMetrics()
    public let ai = AIMetrics()
    public let motion = MotionMetrics()
    public let theme = ThemeMetrics()
    public let littleArc = LittleArcMetrics()
    public let peek = PeekMetrics()
    public let library = LibraryMetrics()
    public let libraryFlyout = LibraryFlyoutMetrics()
    public let settings = SettingsMetrics()
    public let persistence = PersistenceMetrics()
    public let keys = KeyMetrics()
    public let find = FindMetrics()
    public let boostPanel = BoostPanelMetrics()
    public let capture = CaptureMetrics()
    public let siteControls = SiteControlsMetrics()
    public let downloadFlight = DownloadFlightMetrics()
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
    /// With the toolbar shown (Shift+Cmd+D) the favorites tray starts here; its tiles are 8 lower, at 45.
    public let toolbarTrayTop = Metric(36.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P01-b: Arc's favorite tiles start 45 below the window top with the toolbar shown"))
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
    /// The empty tray: Arc's dashed "Drag to add Favorites" box 7.5 in from the sides, 7 below the pill, 94.5 tall,
    /// with the space header 12.5 under it.
    public let emptyTrayHeight = Metric(114.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P07-b: Arc's space header starts 114 below the pill when Favorites is empty"))
    public let emptyBoxInset = Metric(CGSize(width: 7.5, height: 7.0), .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P07-b: the dashed box spans x 7.5 to 220.5 and starts 7 below the pill"))
    public let emptyBoxHeight = Metric(94.5, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P07-b: the dashed box is 94.5 tall"))
}

public struct TablistMetrics: MetricGroup {
    public let rowHeight = Metric(40.0, .arc("Sidebar row height", note: "40"))
    public let rowSpacing = Metric(1.0, .arc("Sidebar row height", .medium, note: "1 pt between rows"))
    public let dividerRowHeight = Metric(16.0, .arc("Pinned/Today divider row", .medium))
    public let tidyDividerExtra = Metric(8.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P46-a Arc capture: with Max on the hairline is at y 801 px and New Tab at 856 px, 8 and 16 px lower than with Max off"))
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
    /// The part of a tab row, as fractions of its height from the top, where a dragged tab joins it in a split; the
    /// quarters above and below still reorder.
    /// The speaker of a tab that is making sound: a button between the icon and the title, from the selection's left edge.
    public let speakerLeading = Metric(34.0, .anatomy("650eca2184:verify/visual-pairs/run-20261103/r5-5/REPORT.md, Q18-media-f-arc.png: the speaker's hover square spans x 42 to 66, the row's selection starts at 8"))
    public let speakerSide = Metric(24.0, .anatomy("650eca2184:verify/visual-pairs/run-20261103/r5-5/REPORT.md, Q18-media-f-arc.png: the speaker's hover square is 24 x 24"))
    /// How much further right the title starts while the speaker shows.
    public let speakerTitleAdvance = Metric(26.0, .anatomy("650eca2184:verify/visual-pairs/run-20261103/r5-5/REPORT.md, Q18-media-a-arc.png: the title's ink starts at x 70 instead of 44"))
    /// The round button at the list's top or bottom edge while the current row is scrolled out of view.
    public let currentArrowSide = Metric(28.0, .anatomy("650eca2184:verify/visual-pairs/run-20261103/r5-5/REPORT.md, Q18-media-e-arc.png: the circle spans x 100 to 128, y 578 to 606"))
    public let currentArrowInset = Metric(5.0, .anatomy("650eca2184:verify/visual-pairs/run-20261103/r5-5/REPORT.md, Q18-media-e-arc.png: the circle ends 5 above the list's lower edge at y 611; Q18-media-r-arrow-up-arc.png: it starts 6 below the upper edge"))
    public let splitJoinZone = Metric(0.25...0.75, .anatomy("eaad5e542c:verify/visual-pairs/run-20261103/Q15/NOTES.md: 9.5 pt from a row's top or bottom edge reorders, 11.5 pt joins"))
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

/// Arc's mini player at the bottom of the sidebar (`MediaControlsFeature.MediaControlsView`, read from the binary and
/// measured; 650eca2184:verify/visual-pairs/run-20261103/r5-5/REPORT.md has the addresses).
public struct MiniPlayerMetrics: MetricGroup {
    /// One line of a card: the title, the controls or the volume slider.
    public let rowHeight = Metric(33.0, .anatomy("650eca2184:verify/visual-pairs/run-20261103/r5-5/REPORT.md, bin:0x102494318: a card at rest is 33 tall"))
    /// A card under the pointer: the title and the controls.
    public let expandedHeight = Metric(66.0, .anatomy("650eca2184:verify/visual-pairs/run-20261103/r5-5/REPORT.md, bin:0x1024942a4"))
    /// With its volume slider open.
    public let volumeHeight = Metric(99.0, .anatomy("650eca2184:verify/visual-pairs/run-20261103/r5-5/REPORT.md, bin:0x1024942a4"))
    public let sideInset = Metric(8.0, .anatomy("650eca2184:verify/visual-pairs/run-20261103/r5-5/REPORT.md, Q18-media-c-arc.png: the card spans x 8 to 220 of a 228 sidebar"))
    public let bottomGap = Metric(8.0, .anatomy("650eca2184:verify/visual-pairs/run-20261103/r5-5/REPORT.md, Q18-media-c-arc.png: the card ends 8 above Arc's update banner, which ends 8 above the dock; Brk has no banner"))
    /// From the list's lower edge down to the stack.
    public let listGap = Metric(9.0, .anatomy("650eca2184:verify/visual-pairs/run-20261103/r5-5/REPORT.md, Q18-media-c-arc.png: the hairline at y 644, the card from y 653"))
    /// Cards at rest, per card behind the front one: up, narrower in all, and fainter down to a floor.
    public let restStep = Metric(7.0, .anatomy("650eca2184:verify/visual-pairs/run-20261103/r5-5/REPORT.md, bin:0x1024942a4: yOffset -7 per card"))
    public let restWidthStep = Metric(10.0, .anatomy("650eca2184:verify/visual-pairs/run-20261103/r5-5/REPORT.md, bin:0x1024942a4: widthOffset 10 per card"))
    public let restWidthMax = Metric(90.0, .anatomy("650eca2184:verify/visual-pairs/run-20261103/r5-5/REPORT.md, bin:0x1024942a4: widthOffset at most 90"))
    public let restAlphaStep = Metric(0.2, .anatomy("650eca2184:verify/visual-pairs/run-20261103/r5-5/REPORT.md, bin:0x1024942a4: opacity 1 - 0.2 per card"))
    public let restAlphaMin = Metric(0.4, .anatomy("650eca2184:verify/visual-pairs/run-20261103/r5-5/REPORT.md, bin:0x1024942a4: opacity at least 0.4"))
    /// Cards under the pointer, apart.
    public let expandedGap = Metric(5.0, .anatomy("650eca2184:verify/visual-pairs/run-20261103/r5-5/REPORT.md, bin:0x1024942a4: height + 5 per card"))
    public let radius = Metric(8.0, .anatomy("650eca2184:verify/visual-pairs/run-20261103/r5-5/REPORT.md, bin:0x10249a5f4: RoundedRectangle 8, continuous"))
    /// The controls row: five buttons, the first and the last this far in, the gaps equal.
    public let controlsInset = Metric(10.0, .anatomy("650eca2184:verify/visual-pairs/run-20261103/r5-5/REPORT.md, Q18-media-e-arc.png: the buttons centre at 30, 72, 114, 156 and 198 on a card from x 8"))
    public let buttonSide = Metric(24.0, .anatomy("650eca2184:verify/visual-pairs/run-20261103/r5-5/REPORT.md, Q18-media-e-arc.png: the pause button's hover square spans x 102 to 126"))
    /// The title's frame in the title row, from the card's left edge, and where it stops before the × button.
    public let titleLeading = Metric(12.0, .anatomy("650eca2184:verify/visual-pairs/run-20261103/r5-5/REPORT.md, Q18-media-e-arc.png: the title's ink starts at x 23, 15 in from the card; the label keeps 2 of its own and the M 1 more"))
    public let titleTrailing = Metric(4.0, .guess("the title's end before the × button; no capture has a title long enough to reach it"))
    /// The volume slider's track in its row, from the card's edges (Q18-media-j-arc).
    public let sliderInset = Metric(8.0, .anatomy("650eca2184:verify/visual-pairs/run-20261103/r5-5/REPORT.md, Q18-media-j-volume-arc.png: the track spans x 16 to 212 on a card from x 8 to 220"))
    public let sliderTrack = Metric(6.0, .anatomy("650eca2184:verify/visual-pairs/run-20261103/r5-5/REPORT.md, Q18-media-j-volume-arc.png: the track is 6 tall"))
    public let sliderKnob = Metric(CGSize(width: 20, height: 16), .anatomy("650eca2184:verify/visual-pairs/run-20261103/r5-5/REPORT.md, Q18-media-j-volume-arc.png: the white knob spans 19.5 x 15.5"))
    /// The pointer leaving the stack closes it at once (Q18, k10), but with a slider open only after this long.
    public let sliderHoverOffDelay = Metric(2.0, .anatomy("650eca2184:verify/visual-pairs/run-20261103/r5-5/REPORT.md, bin:0x102493f9c: debounce(for: 2), and Q18-media-z4, -z5"))
    public let hoverAnimation = Metric(0.25, .anatomy("650eca2184:verify/visual-pairs/run-20261103/r5-5/REPORT.md, bin:0x102493070: a spring of response 0.25, damping 0.9"))
}

public struct ContentMetrics: MetricGroup {
    public let inset = Metric(10.0, .arc("Content card inset", note: "10"))
    /// Between an anchored sidebar and the card: none, the card's left edge is the sidebar's right edge (164, 228 and
    /// 500 wide alike); top, right and bottom keep `inset`.
    public let sidebarGap = Metric(0.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P01-a and P03-b/c: Arc's card starts at the sidebar width"))
    /// Continuous corners.
    public let cornerRadius = Metric(6.0, .arc("Content card corner radius"))
    public let statusBubbleMaxHeight = Metric(40.0, .guess("Chromium's status bubble widget is a short child of the page's host window; its other widgets are taller or are not at its bottom edge"))
    public let fullScreenCornerRadius = Metric(0.0, .arc("Content card corner radius", note: "0 in one state"))
    public let showsShadow = Metric(true, .arc("Content card shadow", .medium))
    /// Measured round Arc's card (2a96a9d7f0:verify/visual-pairs/run-20261103 P01-a, P23-a): 12% black just under it fading out
    /// within 9 pt, 7% just above it within 5. A split's focused pane casts a wider one (BrkContent's SplitDropDraw).
    public let shadowRadius = Metric(2.9, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, Arc captures P01-a: the edges fade like a 2.9 pt Gaussian"))
    public let shadowOpacity = Metric(0.22, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, Arc captures P01-a: 12% under the card plus 7% over it"))
    public let shadowOffset = Metric(1.4, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, Arc captures P01-a: the shadow sits 1.4 pt below the card"))
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
    /// "Allow window dragging from the top of webpages": the band over the page's top edge, and how far the pointer
    /// moves before a press there is a window drag rather than a click on the page.
    public let pageDragHeight = Metric(10.0, .guess("Arc's band height was not recovered; about a title bar's grab strip"))
    public let pageDragThreshold = Metric(3.0, .guess("AppKit's usual drag slop"))
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
    /// The centered bar (Cmd+T) has the taller input row and a hairline under it; the bar over the URL pill has neither.
    public let centeredInputRowHeight = Metric(64.0, .arc("Command bar input row height", .medium, note: "64 in the other mode"))
    /// Over the URL pill the card starts at the pill's left edge, 1.5 above its top, and is 350 wide until its input
    /// row needs more (P02-b: x 8 to 358 over a pill at 8...220, y 46; P02-c grows to 359 for "Search Google Docs").
    public let attachedCardWidth = Metric(350.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P02-b Arc capture: edit card 350 pt wide"))
    public let attachedTopOffset = Metric(-2.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, Arc captures P02-b/c: the card's top edge 44 (88 px), the pill's top 46"))
    /// Rows start right under the input row over the pill and 5 under the hairline when centered; 9 under the last row.
    public let centeredListTop = Metric(4.5, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, Arc captures Q01-a/b: the hairline 64 under the card's top, the first highlight 70.5 (a row's highlight is 2 in)"))
    public let listBottom = Metric(10.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, Arc captures P02-b, Q01-a/b: the card's bottom edge 10 under the last row's frame (Q01: 547.5 for a top at 219)"))
    public let stackSpacing = Metric(10.0, .arc("Command bar inner spacing", .medium, note: "stack spacing 10"))
    public let contentInset = Metric(12.0, .arc("Command bar inner spacing", .medium, note: "inset 12"))
    public let openBounceFrom = Metric(0.95, .arc("Command bar opening bounce", .medium))
    public let littleArcWidth = Metric(500.0, .arc("Little Arc command bar width", .low))
    /// Typing pause before the default engine's suggest endpoint is asked (`Effect.fetchSuggestions`).
    public let suggestionDebounce = Metric(0.15, .guess("debounce before a search-suggestion fetch; Arc's value was not traced"))
    public let translationDebounce = Metric(1.0, .guess("pause in typing before the translate prefix asks a local agent, which takes seconds; Brk's own"))
    public let maxSearchSuggestions = Metric(5, .guess("search-engine suggestions shown; Arc shows a handful under the typed row"))
}

/// Arc's `ARCUI.PageSwipeController` and its owner `WindowLayoutController` (Arc 1.170, addresses in
/// 38d57390e3:verify/visual-pairs/run-20261103/r5-7/REPORT.md): the sidebar's pages, how they follow two fingers, where they settle.
public struct PageSwipeMetrics: MetricGroup {
    fileprivate static let read = "r5-7/REPORT.md, PageSwipeController"
    /// The position moves by this much of `scrollingDeltaX`, the other way (bin:0x100a1ac40, multiplier -0.5).
    public let fingerScale = Metric(0.5, .anatomy(PageSwipeMetrics.read))
    /// Past the reachable pages the position is pressed: (1 - 1 / (over x 0.15 / 255 + 1)) x 255 (bin:0x100a1911c).
    public let rubberBandConstant = Metric(0.15, .anatomy(PageSwipeMetrics.read))
    public let rubberBandDimension = Metric(255.0, .anatomy(PageSwipeMetrics.read))
    /// At least this fast (points a second, over the last `velocityWindow`) the fingers decide the page; slower, the
    /// nearest page does (bin:0x100a1ca4c).
    public let commitVelocity = Metric(5.0, .anatomy(PageSwipeMetrics.read))
    public let velocityWindow = Metric(0.1, .anatomy(PageSwipeMetrics.read))
    /// The spring every page move settles with, critically damped. The binary configures response 0.25 (0.4 without a
    /// settling handler, bin:0x100a19fc0); Arc's recordings (Q19/) fit 0.200 within a third of a pixel on five settles.
    public let settleResponse = Metric(0.2, .anatomy("r5-7/REPORT.md, the spring fit"))
    /// Settled when closer than this.
    public let settleEpsilon = Metric(0.2, .guess("half a device pixel on a 2x display at most; Arc's animator rests on its own threshold, not read"))
    /// A wheel without phases: this much within `wheelGap` steps one page, at most once per `wheelInterval` (bin:0x100a1b46c).
    public let wheelTrigger = Metric(1.0, .anatomy(PageSwipeMetrics.read))
    public let wheelGap = Metric(0.05, .anatomy(PageSwipeMetrics.read))
    public let wheelInterval = Metric(0.25, .anatomy(PageSwipeMetrics.read))
    /// The gesture is the sidebar's from its first event. In Arc AppKit decides on that event alone; Brk lets this much
    /// travel pass first (Q19: a real gesture's first event can have none, and the first moving one may point wrongly).
    public let decideDistance = Metric(6.0, .guess("Brk's own: Arc has no such number, AppKit forwards on the first event"))
    /// The Library page's width bounds and how the sidebar leaves as it comes in, per unit of progress: Arc scales the
    /// column by 1 - 0.1 x progress, moves it 25 right and fades it out by progress 0.47 (measured from Q19/ at 4 positions).
    public let librarySidebarScale = Metric(0.1, .anatomy("r5-7/REPORT.md, the Library page (measured)"))
    public let librarySidebarSlide = Metric(25.0, .anatomy("r5-7/REPORT.md, the Library page (measured)"))
    public let librarySidebarFade = Metric(2.15, .anatomy("r5-7/REPORT.md, the Library page (measured)"))
    /// Past the last Space: Arc's `EdgeFeedbackView` fades in over 15 points of pressed travel, its ring fills over
    /// 22.5, and lifting after it has been full for 0.1 s opens Create a Space (bin:0x100214f70, bin:0x10021ca38).
    public let edgeFade = Metric(15.0, .anatomy(PageSwipeMetrics.read))
    public let edgeArm = Metric(22.5, .anatomy(PageSwipeMetrics.read))
    public let edgeHold = Metric(0.1, .anatomy(PageSwipeMetrics.read))
    /// `CircularProgressView.Configuration`: plus at 16 pt medium, line 2.5 (bin:0x100312fbc). Size and place measured (Q19/).
    public let edgeLine = Metric(2.5, .anatomy(PageSwipeMetrics.read))
    public let edgeGlyph = Metric(16.0, .anatomy(PageSwipeMetrics.read))
    public let edgeRing = Metric(30.0, .anatomy("r5-7/REPORT.md, the edge feedback (measured)"))
    public let edgeRingInset = Metric(27.5, .anatomy("r5-7/REPORT.md, the edge feedback (measured)"))
    /// The gradient at the trailing edge: from no ink to this share of the foreground, this wide (measured, Q19/).
    public let edgeGradientWidth = Metric(80.0, .anatomy("r5-7/REPORT.md, the edge feedback (measured)"))
    public let edgeGradientAlpha = Metric(0.1, .anatomy("r5-7/REPORT.md, the edge feedback (measured)"))
}

public struct MotionMetrics: MetricGroup {
    public let sidebarToggle = Metric(0.08, .arc("Sidebar show/hide animation duration"))
    /// cubic-bezier control points (x1, y1, x2, y2).
    public let sidebarCurve = Metric([0.25, 0.46, 0.45, 0.94], .arc("Sidebar show/hide timing curve"))
    public let contentRelayout = Metric(0.2, .arc("Content relayout animation (same curve)", .medium))
    /// Arc's shader has a `transitioning` state but no duration literal was found. A Space switch does not use it:
    /// the colors follow the page position (`PageSwipeMetrics`).
    public let themeCrossfade = Metric(0.17, .guess("crossfade duration was not recovered; the 0.17 s the old Space switch used"))
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
    /// A dark color under Arc's dark button: from the navy preset at five slider positions (r5-6/REPORT.md).
    public let darkColorDarkWash = Metric(207.0 / 255, .anatomy("f588406ceb:verify/visual-pairs/run-20261103/r5-6/REPORT.md: navy under the dark button runs from #2D4468 towards #CFCFCF"))
    public let darkColorDarkWashBase = Metric(0.19, .anatomy("f588406ceb:verify/visual-pairs/run-20261103/r5-6/REPORT.md: 22% at the slider's right end"))
    public let darkColorDarkWashSlope = Metric(0.62, .anatomy("f588406ceb:verify/visual-pairs/run-20261103/r5-6/REPORT.md: 78% at the slider's left end"))
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
    public let tipFrame = Metric(CGRect(x: 283.5, y: 55, width: 283.5, height: 75), .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P21-b Arc capture: the tip spans 283.5 points ending 8 from the window's right, y 55 to 130 (x is measured from the right)"))
    public let tipInset = Metric(10.5, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P21-b Arc capture: the tip's text starts 10.5 in"))
    public let tipTitleTop = Metric(11.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P21-b Arc capture: the title is centred at y 74, the tip starts at 55"))
    public let tipBodyLine = Metric(17.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P21-b Arc capture: the two body lines are centred 17 points apart"))
    public let tipRadius = Metric(5.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P21-b Arc capture: the tip's corners are about 5 points"))
    public let openInLeading = Metric(4.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P21-b Arc capture: the words' ink starts 6.5 points into the button (the label's cell adds 2)"))
    public let openInKeyGap = Metric(6.5, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P21-b Arc capture: the words end 6 points before the ⌘O badge"))
    public let openInRuleGap = Metric(6.25, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P21-b Arc capture: the badge ends 6.25 points before the rule"))
    public let openInChevronZone = Metric(30.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P21-b Arc capture: the rule to the button's end is 29.75 points"))
    public let openInRuleInset = Metric(6.25, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P21-b Arc capture: the rule is 17.5 tall in the 30 pt button"))
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

/// The Library (media, downloads, easels and notes, spaces, boosts, archive). Like Arc's, its panel replaces the
/// sidebar (width: Metrics.sidebar.libraryMinWidth and .libraryWindowMargin; the Spaces page widens it to fit its
/// cards) and the content area beside it keeps showing the page. The panel is a navigation column of icon cells and
/// the open page's column. "P32-a" is a measurement of that round's Arc capture (P32/P32-a-arc.png beside the
/// report, a 1280 x 776 pt window).
public struct LibraryMetrics: MetricGroup {
    public let navWidth = Metric(112.0, .anatomy("visual-pairs/run-20261103/REPORT.md, P32-a: the navigation column spans x 0...112, a 1 pt edge after it"))
    public let navCellLeading = Metric(9.5, .anatomy("visual-pairs/run-20261103/REPORT.md, P32-a: the selected cell's fill starts at x 9.5"))
    public let navCellWidth = Metric(94.5, .anatomy("visual-pairs/run-20261103/REPORT.md, P32-a: the selected cell's fill ends at x 104"))
    public let navCellHeight = Metric(78.0, .anatomy("visual-pairs/run-20261103/REPORT.md, P32-a/b/e/f: each cell's fill is 78 pt tall"))
    public let navTop = Metric(94.0, .anatomy("visual-pairs/run-20261103/REPORT.md, P32-a: the Media cell's fill starts at y 94"))
    public let navBottomReserve = Metric(104.0, .anatomy("visual-pairs/run-20261103/REPORT.md, P32-e: the Archived Tabs cell ends 104 above the bottom (y 672 of 776)"))
    public let navGlyphCenter = Metric(30.0, .anatomy("visual-pairs/run-20261103/REPORT.md, P32-b: the Downloads glyph is centred 30 below its cell's top"))
    public let navLabelCenter = Metric(55.0, .anatomy("visual-pairs/run-20261103/REPORT.md, P32-b: the Downloads label is centred 55 below its cell's top"))
    public let giftTrailing = Metric(7.0, .anatomy("visual-pairs/run-20261103/REPORT.md, P32-a: the gift button's glyph is centred at x 89, a 32 pt button 7 from the column's edge"))
    public let columnPadding = Metric(10.0, .anatomy("visual-pairs/run-20261103/REPORT.md, P32-b: the search field runs from x 122 to 407 in the 112...417 column"))
    public let spacesCardWidth = Metric(240.0, .anatomy("visual-pairs/run-20261103/REPORT.md, P32-d: a Space card is 240 pt wide"))
    public let spacesCardGap = Metric(24.0, .anatomy("visual-pairs/run-20261103/REPORT.md, P32-d: cards at x 140 and 404"))
    public let spacesLeading = Metric(28.0, .anatomy("visual-pairs/run-20261103/REPORT.md, P32-d: the first card starts 28 after the navigation column"))
    public let spacesTrailing = Metric(100.0, .anatomy("visual-pairs/run-20261103/REPORT.md, P30-a: the panel ends 100 after the last card, where the page card starts (x 744 with two spaces); the + button is centred 48 after the card"))
}

/// The settings window (Arc: `PreferencesFeature`, a `Settings` package window with a pane toolbar). Arc builds its
/// panes with the sindresorhus/Settings package (the binary has `Settings.SettingsWindowController`,
/// `ToolbarItemStyleViewController`, `Settings.Container(contentWidth:minimumLabelWidth:)` and `Settings.Section`):
/// a right-aligned label column, the controls beside it, a divider between sections, and a window that fits each
/// pane's height. Arc's own numbers were not recovered, so every value here is ours.
public struct SettingsMetrics: MetricGroup {
    /// The window's frame, title bar and pane toolbar included; every pane is shown at this size (Arc 1.170's
    /// settings window does not resize per pane).
    public let windowSize = Metric(CGSize(width: 684, height: 650), .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P38: every Arc settings capture is 1368 x 1300 px"))
    /// The width of a pane's cards.
    public let contentWidth = Metric(556.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P38-a-arc.png: cards span x 128 to 1240 px"))
    public let horizontalPadding = Metric(64.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P38-a-arc.png: 128 px from the window's left edge to a card"))
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

/// The Library button's flyout and badge (Arc: `HomeBadging`, `HomeButton`, `HomeButtonHoverRegionTracker`), read from
/// Arc 1.170's binary and measured on real Arc; docs/arc-anatomy/library-flyout.md has every probe and address.
public struct LibraryFlyoutMetrics: MetricGroup {
    /// The flyout lists the newest items only: its frame is `rows x rowPitch + button` tall.
    public let rows = Metric(4, .anatomy("docs/arc-anatomy/library-flyout.md, bin:0x1026a9ff0 and 0x1026ab75c: the expanded frame is 256 = 4 x 56 + 32; seven recent items in Arc listed the newest four"))
    /// A new or finished item becomes the button's badge only when it is younger than this.
    public let badgeFreshness = Metric(300.0, .anatomy("docs/arc-anatomy/library-flyout.md, bin:0x10269fb4c: HomeBadgingItemsState compares the item's age with 300 s before it shows it"))
    /// The pointer must rest on the button this long before the flyout opens.
    public let openDwell = Metric(0.3, .anatomy("docs/arc-anatomy/library-flyout.md, bin:0x1026b5fe8: the button and flyout regions each wait 0.15 s; on Arc a 0.28 s rest never opened it, 0.32 s did, and it showed 0.29 to 0.30 s after the pointer arrived"))
    /// Resting on the strip right of the button (the Space dots) this long closes an open flyout.
    public let dockCollapse = Metric(0.5, .anatomy("docs/arc-anatomy/library-flyout.md, bin:0x1026b5fa4: HomeDockRegion waits 0.5 s; on Arc the flyout closed 0.6 s after the pointer moved onto the dots"))
    /// The hover area over the open flyout: the sidebar's width, this tall from the button's bottom.
    public let regionHeight = Metric(256.0, .anatomy("docs/arc-anatomy/library-flyout.md, bin:0x1026ab75c, 0x1026b64b4: the flyout region is the whole expanded frame; on Arc the flyout stayed open at y 600 and closed at y 560 with the button's bottom at 836"))
    /// The button's own hover square.
    public let buttonRegion = Metric(32.0, .anatomy("docs/arc-anatomy/library-flyout.md, bin:0x1026b54c0: HomeButtonRegion is 32 x 32 at the frame's corner"))
    public let rowPitch = Metric(56.0, .anatomy("docs/arc-anatomy/library-flyout.md, bin:0x1026aa004: the flyout is n x 56 + 32 tall; rows on Arc sit 56 apart"))
    public let rowHeight = Metric(48.0, .anatomy("docs/arc-anatomy/library-flyout.md: a hovered row's fill spans y 755 to 803 on Arc"))
    /// Between the newest row's fill and the button's top.
    public let rowBottomGap = Metric(1.0, .anatomy("docs/arc-anatomy/library-flyout.md: the newest row's fill ends at y 803, the button starts at 804"))
    public let rowLeading = Metric(4.0, .anatomy("docs/arc-anatomy/library-flyout.md: the fill starts 4 pt into the 228 pt sidebar (x 324)"))
    /// A row is the sidebar's width less this.
    public let rowWidthInset = Metric(16.0, .anatomy("docs/arc-anatomy/library-flyout.md, bin:0x1026afaa0: a cell is min(width, 1000) - 16 wide; Arc's fill spans x 324 to 536"))
    public let rowRadius = Metric(12.0, .anatomy("docs/arc-anatomy/library-flyout.md: the fill's corner follows a 12 pt circle (x 331, 329.5, 328, 327, 326.5 at 1 to 5 pt below its top)"))
    public let iconSize = Metric(40.0, .anatomy("docs/arc-anatomy/library-flyout.md: a document icon's page spans 29 x 37.5 pt, the page of a 40 pt Finder icon; centred 24 pt into the row"))
    public let iconLeading = Metric(4.0, .anatomy("docs/arc-anatomy/library-flyout.md: the icon's 40 pt box starts at x 328, 4 pt into the row"))
    public let textLeading = Metric(57.0, .anatomy("docs/arc-anatomy/library-flyout.md: the title and the subtitle start at x 381, 57 pt into the row"))
    public let titleFont = Metric(14.0, .anatomy("docs/arc-anatomy/library-flyout.md: report.pdf, photo.png and sunset.png read 64.0, 64.5 and 70.5 pt wide, SF 14 regular"))
    public let subtitleFont = Metric(12.0, .anatomy("docs/arc-anatomy/library-flyout.md: 20 seconds ago, 14 seconds ago and 9 seconds ago read 88.5, 87.5 and 82 pt wide, SF 12 regular"))
    /// From the row's top to the title's and the subtitle's baselines.
    public let titleBaseline = Metric(21.8, .anatomy("docs/arc-anatomy/library-flyout.md: in the row at y 587 the title's ascenders start at 598.5 (SF 14's are 10.3 tall)"))
    public let subtitleBaseline = Metric(36.5, .anatomy("docs/arc-anatomy/library-flyout.md: the subtitle's digits start at 615 (SF 12's are 8.5 tall)"))
    /// The title and subtitle colours: label and secondary label black (white on a dark theme).
    public let titleInk = Metric(0.85, .anatomy("docs/arc-anatomy/library-flyout.md: the title's darkest pixels read #262728 on #F1F8FA"))
    public let subtitleInk = Metric(0.5, .anatomy("docs/arc-anatomy/library-flyout.md: the subtitle's darkest pixels read #787B7D on #F1F8FA"))
    public let subtitleInkDark = Metric(0.55, .guess("secondaryLabelColor's white in a dark appearance; no dark Space exists in the user's Arc"))
    /// A running download's ring in its row, and the × that cancels it.
    public let rowRing = Metric(24.0, .anatomy("docs/arc-anatomy/library-flyout.md: the ring of big-download.bin spans x 336 to 360 on Arc"))
    public let cancelGlyph = Metric(11.0, .anatomy("docs/arc-anatomy/library-flyout.md: the × beside a running download is 11 pt across, centred 18 pt before the row's right end"))
    public let cancelTrailing = Metric(18.0, .anatomy("docs/arc-anatomy/library-flyout.md: the × beside a running download is centred at x 518 in the row ending at 536"))
    /// The backdrop behind the rows: the sidebar's colour, opaque at the top row, fading out above it. Pairs of
    /// (distance above the top row, opacity), measured from how much of the rows above still shows.
    public let backdropFade = Metric([140.0, 0.0, 116.0, 0.2, 86.0, 0.36, 50.0, 0.69, 32.0, 0.83, 26.0, 0.89, 0.0, 1.0],
                                     .anatomy("docs/arc-anatomy/library-flyout.md: with four rows (top row at y 580) the selected tab above shows 100, 80, 64, 31, 17 and 11 percent of its rest contrast at y 440, 464, 494, 530, 548 and 554"))
    public let fadeIn = Metric(0.1, .anatomy("docs/arc-anatomy/library-flyout.md: the rows go from nothing to 60, 94 and 100 percent in three 1/60 s frames"))
    public let fadeOut = Metric(0.06, .anatomy("docs/arc-anatomy/library-flyout.md: the rows go to 30, 5 and 0 percent in three 1/60 s frames"))
    /// A running download's badge: a disc over the button's top-right corner.
    public let progressBadge = Metric(20.0, .anatomy("docs/arc-anatomy/library-flyout.md: the disc spans x 344 to 364 and y 799 to 819 over the button centred at 344, 820"))
    public let badgeCenter = Metric([10.0, -11.0], .anatomy("docs/arc-anatomy/library-flyout.md: the disc's centre sits 10 pt right of and 11 pt above the button's centre; a file badge's (a 32 pt icon) 10 right and 10 above"))
    public let fileBadge = Metric(32.0, .anatomy("docs/arc-anatomy/library-flyout.md: notes.txt's page spans 22 x 30 pt over the button, the page of a 32 pt icon"))
    public let progressRingWidth = Metric(2.0, .anatomy("docs/arc-anatomy/library-flyout.md: the badge's ring is 2 pt wide in its 20 pt disc"))
    /// The download blue (`DownloadProgressBarBackground` is the track), sampled on Arc.
    public let progressBlue = Metric("#1828F8", .anatomy("docs/arc-anatomy/library-flyout.md: the ring and arrow read #1828F8, the disc #E8E8F8, the track #B8C0F8"))
    public let progressDisc = Metric("#E8E8F8", .anatomy("docs/arc-anatomy/library-flyout.md: the badge disc's fill"))
    public let progressTrack = Metric("#B8C0F8", .anatomy("docs/arc-anatomy/library-flyout.md: the ring's unfilled part"))
    /// A new badge springs in (`interpolatingSpring(mass: 1, stiffness: 500, damping: 25, initialVelocity: 10)`) from
    /// this scale and height above, while the one it replaces fades in `badgeOut`.
    public let badgeSpring = Metric([1.0, 500.0, 25.0, 10.0], .anatomy("docs/arc-anatomy/library-flyout.md, bin:0x1026b0b30: Animation.interpolatingSpring(mass:stiffness:damping:initialVelocity:)"))
    public let badgeEnterScale = Metric(1.5, .anatomy("docs/arc-anatomy/library-flyout.md, bin:0x1026b1510: the badge's insertion scales from 1.5"))
    public let badgeEnterLift = Metric(16.0, .guess("height the new badge drops from; Arc's transition offsets -80 (bin:0x1026b1528) but the video shows the icon entering just above the button"))
    public let badgeOut = Metric(0.14, .anatomy("docs/arc-anatomy/library-flyout.md, bin:0x1026ada9c: Animation.linear(duration: 0.14)"))
    /// The preview a row's click opens (Arc: `ItemPreviewPresenter`, measured on p15 and p16 of docs/arc-anatomy/library-flyout.md).
    public let previewDim = Metric(0.7, .anatomy("docs/arc-anatomy/library-flyout.md: behind the card the page's white reads #4C4C4C"))
    /// The card behind Quick Look's view: a radial grey, `previewShade[0]` in the middle falling off with the square of
    /// the distance to `previewShade[1]` at half the card's width; its vertical radius is `previewShadeAspect` times the
    /// horizontal one (it barely darkens towards the top and bottom) and its middle sits `previewShadeShift` of the card's
    /// width left of the card's.
    public let previewShade = Metric(["#D6D6D6", "#4D4D4D"], .anatomy("docs/arc-anatomy/library-flyout.md, The preview: 20 readings on two rows of a 974 pt card (two Arc pictures agree) fit 214 - 0.00058 ((dx + 9)^2 + (dy / 2.76)^2) within 4 levels; Quick Look draws no background of its own"))
    public let previewShadeAspect = Metric(2.76, .anatomy("docs/arc-anatomy/library-flyout.md, The preview: the same fit"))
    public let previewShadeShift = Metric(-0.0092, .anatomy("docs/arc-anatomy/library-flyout.md, The preview: the same fit puts the middle 9 pt left of the card's; the left half reads up to 11 levels lighter than the right at the same distance"))
    /// The toolbar band is the same grey under a white wash this strong.
    public let previewToolbarWash = Metric(0.29, .anatomy("docs/arc-anatomy/library-flyout.md, The preview: at five places across the card the toolbar reads 0.23 to 0.30 of the way from the grey below it to white"))
    /// The card's inset from the window: these fractions of its width and height.
    public let previewInsets = Metric([0.12, 0.133], .anatomy("docs/arc-anatomy/library-flyout.md: in the 1280 x 776 window the card spans x 153 to 1127 and y 103 to 674, for an image and for a PDF alike"))
    public let previewRadius = Metric(12.0, .guess("the card's corner; Arc's reads about 12 at 2x"))
    public let previewToolbar = Metric(46.0, .anatomy("docs/arc-anatomy/library-flyout.md: the toolbar spans y 173 to 219 on the screen"))
    public let previewPadding = Metric(16.0, .anatomy("docs/arc-anatomy/library-flyout.md: the 320 x 200 image is fitted 15 below the toolbar and 17 above the card's bottom"))
    public let previewGlyph = Metric(14.0, .guess("× ‹ › … symbol size in the toolbar"))
    public let previewButton = Metric(28.0, .guess("hit size of the toolbar's glyph buttons"))
    /// Centres of ×, ‹ and ›, then where the name starts, from the card's left edge.
    public let previewButtons = Metric([25.0, 61.0, 93.0, 113.0], .anatomy("docs/arc-anatomy/library-flyout.md: × at x 178, ‹ at 214, › at 246 and the name from 266 in the window, the card at 153"))
    public let previewNameGap = Metric(8.0, .anatomy("docs/arc-anatomy/library-flyout.md: '2 minutes ago' starts 8 pt after 'photo.png'"))
    public let previewOpenTrailing = Metric(9.0, .anatomy("docs/arc-anatomy/library-flyout.md: 'Open in Preview ↗' spans x 972 to 1118, 9 before the card's right edge"))
    public let previewOpenHeight = Metric(30.0, .anatomy("docs/arc-anatomy/library-flyout.md: the Open button spans y 111 to 141"))
    public let previewOpenPadding = Metric(13.0, .anatomy("docs/arc-anatomy/library-flyout.md: the button is 146 wide around a 120 pt label"))
    public let previewOpenRadius = Metric(8.0, .guess("the Open button's corner"))
    public let previewMoreGap = Metric(22.0, .anatomy("docs/arc-anatomy/library-flyout.md: the … is centred 22 pt left of the Open button"))
}

/// A download's flight from the page into the Library button (Arc: `DownloadsUI.DownloadToLibrary`; every number's
/// source is in docs/arc-anatomy/library-flyout.md, "The download flight"). Points are in the window, y up from its
/// bottom-left corner, as Arc's view model computes them.
public struct DownloadFlightMetrics: MetricGroup {
    /// Downward pull on the thrown icon, points per second squared.
    public let gravity = Metric(2648.7, .anatomy("docs/arc-anatomy/library-flyout.md, bin:0x101ce29f8: DownloadViewModel.init stores g = 2648.7"))
    /// The upward launch speed is `launch[0] + launch[1] x start height / window height` (1600 at the bottom, 500 at the top).
    public let launch = Metric([1600.0, -1100.0], .anatomy("docs/arc-anatomy/library-flyout.md, bin:0x101ce23a8: vy0 = (source.y / windowHeight) * -1100 + 1600"))
    /// The flight starts this far from the pointer (right, and down).
    public let startOffset = Metric([15.0, -15.0], .anatomy("docs/arc-anatomy/library-flyout.md, bin:0x101ce4e7c and 0x101ce5120: source = (pointer.x + 15, pointer.y - 15) for the first and every later flight; the icon's first frames on Arc sit 12 left of and 7 above that point after 1/60 s"))
    /// Where the icon goes while the sidebar shows: above and right of the Library button, which it falls into.
    public let sidebarTarget = Metric([32.0, 40.0], .anatomy("docs/arc-anatomy/library-flyout.md, bin:0x101ce2a84: without the bin the destination is (32, 40)"))
    /// Where it goes while the sidebar is hidden: the bin's corner. It lands `binLanding` short of it and springs in.
    public let binTarget = Metric([70.0, 70.0], .anatomy("docs/arc-anatomy/library-flyout.md, bin:0x101ce4e9c: animateDownload(source:destination: (70, 70))"))
    public let binLanding = Metric(8.0, .anatomy("docs/arc-anatomy/library-flyout.md, bin:0x101ce2a78 and 0x101ce2f70: lands at destination.x - 8, then the bounce targets destination.x + 8"))
    /// Frames per second of the planned path.
    public let frameRate = Metric(60.0, .anatomy("docs/arc-anatomy/library-flyout.md, bin:0x101ce2b60: one keyframe per 1/60 s; the bounce is sampled at 60 per second"))
    /// Without the bin the path runs this many frames past the button, shrinking to nothing.
    public let overrunFrames = Metric(8.0, .anatomy("docs/arc-anatomy/library-flyout.md, bin:0x101ce2bac: the loop runs to duration + 0.1333 s when the bin is off"))
    /// Scale (width, height) at the start; both reach `apexScale` at the top of the arc.
    public let startScale = Metric([0.8, 1.2], .anatomy("docs/arc-anatomy/library-flyout.md, bin:0x103783310: before the apex scale = (0.8 p + 0.8, 0.4 p + 1.2) for p = t / apexTime; Arc's first frames read 24 x 31 points"))
    public let apexScale = Metric(1.6, .anatomy("docs/arc-anatomy/library-flyout.md, bin:0x101ce2c2c: 1.6 at the apex; the icon spans 48 x 48 points there on Arc"))
    /// From the apex to the landing the scale falls by this much (sidebar: to 0.3; bin: to 0.7).
    public let landingShrink = Metric([1.3, 0.9], .anatomy("docs/arc-anatomy/library-flyout.md, bin:0x101ce2d1c and 0x101ce2d48: scale = 1.6 - k (1 - f), k = 1.3 without the bin, 0.9 with it"))
    /// The bounce into the bin: spring (response, damping ratio), sampled from the landing with the landing speed.
    public let bounceSpring = Metric([0.48, 0.72], .anatomy("docs/arc-anatomy/library-flyout.md, bin:0x101ce2ea4: iconBounceAnimator.configure(response: 0.48, dampingRatio: 0.72); Arc's icon drops 58 points below the bin's corner before it settles, the spring predicts 57.4"))
    /// The icon: SF Symbol arrow.down.circle on a disc, this wide.
    public let iconSize = Metric(30.0, .anatomy("docs/arc-anatomy/library-flyout.md, bin:0x101cdeb24: Image(systemName: \"arrow.down.circle\").resizable().frame(30, 30)"))
    /// SwiftUI's resizable symbol fills its frame; NSImage's symbol keeps a margin, so it is drawn this much larger.
    public let iconGlyphScale = Metric(1.153, .anatomy("docs/arc-anatomy/library-flyout.md, Arc's ring spans 29.4 of the 30 points and is 2.5 thick (47 and 4 at the apex scale 1.6); arrow.down.circle at 24 pt regular drawn into 30 points spans 25.5 and is 2.0 thick, and 1.153 times larger spans 29.25 and 2.5"))
    /// It turns from `rotation[0]` to `rotation[1]` degrees on a spring (response, damping ratio).
    public let rotation = Metric([-35.0, 5.0], .anatomy("docs/arc-anatomy/library-flyout.md, bin:0x101cde254, 0x101ce0880: @State rotation = -35, set to 5 in onAppear"))
    public let rotationSpring = Metric([1.2, 1.0], .anatomy("docs/arc-anatomy/library-flyout.md, bin:0x101cdeec8: withAnimation(.spring(response: 1.2, dampingFraction: 1))"))
    public let fadeSpring = Metric([0.3, 1.0], .anatomy("docs/arc-anatomy/library-flyout.md, bin:0x101cdef10: alpha 0 to 1 withAnimation(.spring(response: 0.3, dampingFraction: 1))"))
    /// Shadow: system blue at this opacity, blur radius, offset down.
    public let iconShadow = Metric([0.25, 8.0, 4.0], .anatomy("docs/arc-anatomy/library-flyout.md, bin:0x101cde278: shadow(color: .blue.opacity(0.25), radius: 8, y: 4)"))
    /// The symbol's ink (Arc's maxContrastColor) and the disc behind it (backgroundExtra), light then dark.
    public let iconInk = Metric(["#4C4C4C", "#E6E6E6"], .anatomy("docs/arc-anatomy/library-flyout.md, the arrow and ring read #4C4C4C on Arc's light Space; dark is ours (no dark Space in the user's Arc)"))
    public let iconDisc = Metric(["#FFFFFF", "#2C2C2E"], .anatomy("docs/arc-anatomy/library-flyout.md, the disc reads #FEFEFE on Arc's light Space; dark is ours"))
    /// Each flight keeps the overlay this long after it lands; when the last one is done the bin leaves.
    public let hold = Metric(1.0, .anatomy("docs/arc-anatomy/library-flyout.md, bin:0x101ce1d9c: asyncAfter(now + projectileMotionDuration + 1.0) leaves the group"))
    /// The icons go this long after the bin starts to leave (Arc closes its overlay window on the bin's completion).
    public let clearDelay = Metric(0.23, .anatomy("docs/arc-anatomy/library-flyout.md, r2: the bin starts out at 3.20 s, the last frame with the icon is 3.43 s"))
    /// The bin while the sidebar is hidden: a rounded square this wide, its centre this far from the window's left and bottom edges.
    public let binSize = Metric(46.0, .anatomy("docs/arc-anatomy/library-flyout.md, bin:0x101cdf438 and 0x101cdf48c: padding 8 in a 62 x 62 frame; Arc's bin spans x 31 to 76"))
    public let binRadius = Metric(12.0, .anatomy("docs/arc-anatomy/library-flyout.md, bin:0x101cdef98: RoundedRectangle(cornerRadius: 12, style: .continuous)"))
    public let binCenter = Metric([53.0, 53.0], .anatomy("docs/arc-anatomy/library-flyout.md, bin:0x101cddd2c (y = height - 53) and 0x101ce1c68 (x 53 shown); Arc's bin centre reads (53.5, 723.5) in a 776 tall window"))
    public let binHiddenX = Metric(-80.0, .anatomy("docs/arc-anatomy/library-flyout.md, bin:0x101ce1c28: binPositionX animates to -80 to leave"))
    /// The bin's slide: Arc's Motion spring default (stiffness, damping, mass 1).
    public let binSpring = Metric([300.0, 10.0], .anatomy("docs/arc-anatomy/library-flyout.md, bin:0x100b87810: SpringAnimation's default stiffness 300 and damping 10; Arc's bin leaves 5 then 11 points in its first two frames, the spring predicts 5.2 and 14"))
    /// Arc's overlay window draws its first frame this long after it was made, and its springs (the bin's slide, the
    /// icon's turn and fade) run from the making while the thrown path starts at the first frame: on the first flight
    /// of a run the bin appears nearly in place and the icon opaque and almost upright. Later flights start together.
    public let firstFlightLead = Metric(0.4, .anatomy("docs/arc-anatomy/library-flyout.md, r2: the bin first shows at x 37 and settles at 55 (spring time 0.40 s), r3 at 54 (0.9 s); r1: the icon is opaque in its first frame and upright at the apex (turn spring at about 0.75 s); r4's second flight starts faint and turned"))
    public let binFill = Metric(["#EBEBEB", "#3A3A3C"], .anatomy("docs/arc-anatomy/library-flyout.md, the bin reads #EBEBEB (Arc's palette background); dark is ours"))
    public let binGlyph = Metric(["#5C5C5C", "#C7C7C7"], .anatomy("docs/arc-anatomy/library-flyout.md, the Library glyph in the bin reads #5C5C5C; dark is ours"))
    /// The bin's shadow: (opacity, radius), black on light, white on dark.
    public let binShadow = Metric([0.3, 0.15, 12.0], .anatomy("docs/arc-anatomy/library-flyout.md, bin:0x101cdf190 to 0x101cdf1c4: shadow(color: black 0.3 or white 0.15 in dark, radius: 12)"))
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
    private static let capture = "7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P18-a/b/d Arc captures measured at 2x"
    /// The Cmd+F bar floats at the card's top-right corner and keeps this width however wide the card is.
    public let width = Metric(300.0, .anatomy(capture))
    public let inset = Metric(10.0, .anatomy(capture + ": bar to the card's top and right edges"))
    public let row = Metric(32.0, .anatomy(capture))
    public let cornerRadius = Metric(5.0, .anatomy(capture))
    public let shadowRadius = Metric(12.0, .anatomy(capture + ": shadow fades over 7 pt below, 4 pt above"))
    public let shadowOffset = Metric(2.0, .anatomy(capture))
    public let shadowOpacity = Metric(0.5, .anatomy(capture + ": the shadow darkens white to #D3D4D8 at the lower edge"))
    public let iconLeading = Metric(10.0, .anatomy(capture + ": magnifier"))
    public let iconSize = Metric(12.0, .anatomy(capture + ": magnifier"))
    public let textLeading = Metric(33.0, .anatomy(capture + ": query text starts"))
    public let queryFont = Metric(13.0, .anatomy(capture + ": query ascender 9.75 pt"))
    public let statusFont = Metric(10.0, .anatomy(capture + ": count and NOT FOUND cap height 7 pt"))
    /// Distances from the bar's right edge.
    public let statusTrailing = Metric(94.5, .anatomy(capture + ": count 1/6 ends 94.5 pt before the right edge"))
    public let notFoundTrailing = Metric(35.5, .anatomy(capture + ": NOT FOUND ends 35.5 pt before the right edge"))
    public let previousCenter = Metric(74.0, .anatomy(capture + ": up arrow centre"))
    public let nextCenter = Metric(48.0, .anatomy(capture + ": down arrow centre"))
    public let separatorTrailing = Metric(30.0, .anatomy(capture + ": vertical separator"))
    public let separatorHeight = Metric(18.0, .anatomy(capture + ": vertical separator"))
    public let closeCenter = Metric(16.0, .anatomy(capture + ": close cross centre"))
    public let button = Metric(24.0, .guess("Hit target around the 11 pt arrow and close glyphs"))
    /// SF Symbol point sizes that draw Arc's glyphs: arrows 11 pt wide, the magnifier 12 x 12, the cross 9 pt.
    public let glyph = Metric(13.0, .anatomy(capture + ": arrows are 11 pt wide"))
    public let iconGlyph = Metric(13.0, .anatomy(capture + ": magnifier 12 x 12 pt"))
    public let closeGlyph = Metric(12.0, .anatomy(capture + ": close cross"))
    public let textInset = Metric(3.0, .guess("NSTextField's cell padding before the first glyph"))
    public let statusWidth = Metric(44.0, .guess("Room for a count up to 999/999 before the arrows"))
    public let notFoundWidth = Metric(70.0, .guess("NOT FOUND is 61 pt wide in 10 pt semibold"))
    public let message = Metric(22.0, .guess("Brk-only status line (errors, replacement results) under the rows"))
    public let messageFont = Metric(11.0, .guess("Brk-only status line"))
    /// Brk's replacement row (Arc has no visible Find and Replace) reuses the find row's insets.
    public let replaceWidth = Metric(56.0, .guess("Replace label in 12 pt medium"))
    public let replaceAllWidth = Metric(30.0, .guess("All label in 12 pt medium"))
    public let actionFont = Metric(12.0, .guess("Replacement row labels"))
    public let gap = Metric(4.0, .guess("Find control spacing"))
    /// Below this bar width (narrow split panes) the bar stacks its controls in rows.
    public let compactWidth = Metric(200.0, .guess("Query, count, arrows and close need about 200 pt in one row"))
    public let compactInset = Metric(4.0, .guess("Narrow panes keep most of their width for the stacked controls"))
    public let compactPadding = Metric(6.0, .guess("Stacked find controls inset"))
    public let actionWidth = Metric(80.0, .guess("Minimum width for readable stacked replacement labels"))
}

/// Arc's site control center (ARC_SiteControlCenter): an NSPopover under the URL pill's site icon. The popover
/// window is 262 x 227 pt; its body is 237 x 202 pt.
public struct SiteControlsMetrics: MetricGroup {
    private static let capture = "7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P36-a Arc capture measured at 2x"
    public let width = Metric(237.0, .anatomy(capture + ": popover body"))
    public let inset = Metric(10.5, .anatomy(capture + ": buttons to the body's left and right edges"))
    public let top = Metric(9.5, .anatomy(capture + ": the body's edge at y 182 px, the buttons start at 201 px"))
    public let button = Metric(CGSize(width: 48, height: 32.5), .anatomy(capture + ": the four action buttons and the Extensions + button"))
    public let buttonGap = Metric(8.0, .anatomy(capture))
    public let buttonRadius = Metric(8.0, .anatomy(capture))
    public let buttonGlyph = Metric(15.0, .anatomy(capture + ": share, Boost, camera and full-page glyphs"))
    public let buttonsPerRow = Metric(4, .anatomy(capture))
    public let extensionIcon = Metric(16.0, .guess("an extension button shows the extension's toolbar icon at Chromium's 16 pt action size; P36-a has no extension installed to measure"))
    public let buttonShadowBlur = Metric(3.0, .anatomy(capture + ": the shadow spreads about 2 pt round each button"))
    public let buttonShadowOffset = Metric(1.0, .anatomy(capture + ": the shadow is heavier under the button"))
    /// Arc's Boost glyph is a brush with a sparkle at its top-left; Brk draws SF paintbrush.pointed plus sparkle.
    public let badgeScale = Metric(0.55, .guess("SF sparkle sized to Arc's boost.sparkle accent"))
    public let badgeOffset = Metric(CGPoint(x: 2, y: 1), .guess("Moves the brush off the sparkle's corner"))
    /// Baselines from the body's top: section titles, then the Developer Mode title and its state.
    public let extensionsBaseline = Metric(66.5, .anatomy(capture + ": Extensions title"))
    public let extensionsRow = Metric(80.0, .anatomy(capture + ": Extensions + button top"))
    public let sectionGap = Metric(28.0, .anatomy(capture + ": + button bottom to the Settings baseline"))
    public let sectionFont = Metric(14.0, .anatomy(capture + ": section title cap height 10 pt, semibold"))
    public let rowGap = Metric(13.0, .anatomy(capture + ": the Developer Mode circle is centred at y 520.5 px"))
    public let rowIcon = Metric(32.0, .anatomy(capture + ": Developer Mode circle"))
    public let rowSpacing = Metric(11.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P36-b Arc capture: the two circles start 86 px apart"))
    public let rowTitleWidth = Metric(168.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P36-b Arc capture: 'Automatic Picture-In-P…' ends at x 600 px, its title starts at 267 px"))
    public let rowGlyph = Metric(14.0, .anatomy(capture + ": hammer glyph"))
    public let rowText = Metric(51.0, .anatomy(capture + ": Developer Mode title starts"))
    public let rowTitleBaseline = Metric(12.75, .anatomy(capture + ": Developer Mode's glyphs span y 495 to 520 px, the circle's centre 520.5 px"))
    public let rowSubtitleBaseline = Metric(29.0, .anatomy(capture + ": Off spans y 529 to 547 px"))
    public let rowFont = Metric(13.0, .anatomy(capture + ": Off, a 13 pt line"))
    public let rowTitleFont = Metric(14.0, .anatomy(capture + ": Developer Mode spans x 268 to 483 px, a 14 pt semibold line (13 pt is 205 px)"))
    public let bottom = Metric(14.0, .anatomy(capture + ": circle bottom to the body's bottom edge (no web page: no security row)"))
    /// The security row under a hairline for an http(s) page: a grey rounded button with a lock and Secure or Insecure,
    /// and a round … button at the right.
    public let securityDividerGap = Metric(15.5, .anatomy(capture + ": the circle's centre at y 520.5 px, the hairline at 584 px"))
    public let securityGap = Metric(10.0, .anatomy(capture + ": hairline to the security row"))
    public let securityHeight = Metric(32.0, .anatomy(capture + ": Insecure button and … circle"))
    public let securityBottom = Metric(10.0, .anatomy(capture + ": security row to the body's bottom edge"))
    public let securityPadding = Metric(9.5, .anatomy(capture + ": lock inset in the Insecure button"))
    public let securityTrailing = Metric(9.0, .anatomy(capture + ": Insecure text to the button's right edge"))
    public let securityGlyph = Metric(13.0, .anatomy(capture + ": the lock is 10 x 13.5 pt"))
    public let securityGlyphGap = Metric(3.0, .anatomy(capture + ": the lock's ink starts at x 205 px, Insecure at 242 px (the symbol image is wider than its ink)"))
    public let securityFont = Metric(14.0, .anatomy(capture + ": Insecure cap height 10 pt"))
    /// Brk's second page holds the full site form (Arc puts these in menus, settings and permission prompts).
    public let detailsSize = Metric(CGSize(width: 360, height: 520), .guess("Room for the site form without crowding the page"))
    public let detailsHeader = Metric(36.0, .guess("Back button row of the site settings page"))
    public let anchorTrailing = Metric(19.0, .anatomy(capture + ": site icon centre to the pill's right edge"))
    public let anchorRise = Metric(4.5, .anatomy(capture + ": body top 90 pt from the window top, 8 pt under the pill"))
    /// Where the popover points when the sidebar, and with it the site button, is hidden.
    public let fallbackAnchor = Metric(CGPoint(x: 24, y: 12), .guess("Content area's top-left corner, clear of the traffic lights"))
}

/// Brk's AI panel (docs/design/ai-panel.md, ai-right-panel.md). Arc has none: these are Brk's choices, taken from the
/// sidebar's own sizes where the panel copies one of its parts.
public struct AIMetrics: MetricGroup {
    // The column (AIPanelLayout).
    public let width = Metric(360.0, .guess("the panel column at its widest: a 344 pt reading width, where a three-column price table and a short chart fit"))
    public let minimumWidth = Metric(280.0, .guess("the panel column at its narrowest, still a 264 pt reading width"))
    public let minimumCardWidth = Metric(400.0, .guess("the web card keeps at least this much beside the panel; the panel gives way first"))
    public let maximumShare = Metric(0.5, .guess("the panel dragged wider stops at half the window (docs/design/ai-right-panel.md)"))
    public let maximumStoredWidth = Metric(4000.0, .guess("the widest width a window keeps for its panel; the layout still stops at half the window"))
    public let resizeHitWidth = Metric(8.0, .guess("as wide as the sidebar's resize handle (SidebarMetrics.resizeHitWidth), centred on the card's other edge"))
    // The drop area at the window's right edge while the panel is closed (docs/design/ai-right-panel.md).
    public let edgeDropBand = Metric(40.0, .guess("the spec's band: the drop area shows once the pointer is this close to the window's right edge"))
    public let edgeDropDash = Metric([6.0, 4.0], .guess("the drop area's dashed outline: dash and gap"))
    public let edgeDropFont = Metric(14.0, .guess("the drop area's words, a little over the panel's body text"))
    // Lit sidebar rows while the pointer is over a list row or a chip.
    public let litBorderWidth = Metric(1.5, .guess("the outline in the Space's color round a lit row or tile"))
    public let litTint = Metric(0.12, .guess("the Space's color laid over a lit row's fill, light enough to read the title"))
    // The title row's chat button.
    public let toggleBadgeHeight = Metric(13.0, .guess("the count on the chat button, a little under the list icon's 14"))
    public let toggleBadgeFont = Metric(9.0, .guess("the count's digits, as on the panel's list icon"))
    public let columnInset = Metric(8.0, .derived(rule: "the sidebar keeps its rows this far from its edges (TablistMetrics.selectionInset); the panel mirrors it, so the gap to the card is the same on both sides", from: ["Row selection background"]))
    public let headerTop = Metric(4.0, .derived(rule: "the sidebar's title row starts 4 below the window's top (SidebarMetrics.headerTopInset)", from: ["Sidebar header top inset"]))
    public let headerHeight = Metric(40.0, .guess("the sidebar's title row height, so the header's centre is the traffic lights' (Metrics.window.trafficLightCenterY)"))
    public let bottomInset = Metric(10.0, .guess("the composer ends where the web card does (Metrics.content.inset)"))
    // Fonts.
    public let titleFont = Metric(13.0, .guess("the header's conversation name, as a sidebar row title"))
    public let bodyFont = Metric(13.0, .guess("messages and answers, as sidebar row titles"))
    public let stepFont = Metric(12.0, .guess("the step line, approvals' sentence, the + menu and chips"))
    public let noticeFont = Metric(11.0, .guess("the centred notice pill"))
    public let libraryTitleFont = Metric(15.0, .guess("the Library's \"AI 对话\" page: the selected conversation's name over its transcript"))
    // Parts.
    public let iconSize = Metric(24.0, .guess("the header's icon buttons, hit area"))
    public let iconGlyph = Metric(13.0, .guess("the header's icon glyphs"))
    public let iconRadius = Metric(6.0, .guess("the header icons' hover fill"))
    public let itemGap = Metric(10.0, .guess("space between messages in the transcript"))
    public let bubblePadding = Metric(CGSize(width: 10, height: 6), .guess("a user message's text inside its fill"))
    public let bubbleMaxShare = Metric(0.88, .guess("a user message is at most this share of the reading width"))
    public let stepHeight = Metric(26.0, .guess("the step line, like the URL pill's item fill but lower"))
    public let stepRowHeight = Metric(20.0, .guess("one step in the expanded list"))
    public let itemRadius = Metric(8.0, .guess("the step line's and approval card's corners, as the URL pill's fill"))
    public let noticeHeight = Metric(20.0, .guess("the centred notice pill"))
    public let pageHeaderHeight = Metric(30.0, .guess("a page card's title row"))
    public let pageInset = Metric(CGSize(width: 10, height: 6), .guess("a page inside its card: the title row's own margin at the sides"))
    public let composerPadding = Metric(8.0, .guess("the composer's inside margin"))
    public let composerMaxLines = Metric(6, .guess("the composer grows to this many lines, then scrolls"))
    public let sendSize = Metric(24.0, .guess("the round send and stop button"))
    public let plusSize = Metric(24.0, .guess("the composer's + button"))
    public let chipHeight = Metric(20.0, .guess("a tab chip in the composer"))
    public let chipMaxWidth = Metric(170.0, .guess("a tab chip's widest, its title truncated"))
    public let chipRadius = Metric(6.0, .guess("a tab chip's corners"))
    public let smallRadius = Metric(4.0, .guess("the hover fill of a chip's × and of Show Command"))
    public let menuRowHeight = Metric(26.0, .guess("one row of the + menu and the @ list"))
    public let menuPadding = Metric(4.0, .guess("the + menu's and @ list's inside margin"))
    public let dropBorderWidth = Metric(2.0, .guess("the composer's outline while tabs are dragged over the panel"))
    public let buttonHeight = Metric(26.0, .guess("Allow and Deny, and the answer's action rows"))
    public let gap = Metric(8.0, .guess("space between controls"))
    // The conversation list (docs/design/ai-threads.md).
    public let threadRowHeight = Metric(40.0, .guess("a list row's two lines: the name at 13 pt over the state at 11 pt, the height of a two-line Library row less its icon"))
    public let stripHeight = Metric(26.0, .guess("a strip for another Space's conversation at the list's top, the step line's height"))
    public let searchHeight = Metric(28.0, .guess("the list's search box, the URL pill's height less its border"))
    public let dotsHeight = Metric(50.0, .derived(rule: "the page dots' row at the panel's foot is the dock's height, so its dots sit on the line of the sidebar's Space dots", from: ["Dock (space switcher) height"]))
    // A kept page shown as a tab: its caption row, then the page.
    public let keptPageInset = Metric(28.0, .guess("a kept page's margin inside its card, at the sides and the foot"))
    public let keptPageGap = Metric(12.0, .guess("between a kept page's caption row and the page"))
    // The Library's "AI 对话" page: the selected conversation over the content card.
    public let libraryColumnWidth = Metric(720.0, .guess("the Library preview's reading column, like a chat app's"))
    public let libraryColumnInset = Metric(28.0, .guess("the Library preview's margin around its column"))
    // The card that asks before a page's link opens.
    public let cornerRadius = Metric(12.0, .guess("the link prompt's corners"))
    public let borderWidth = Metric(1.0, .guess("the link prompt's hairline"))
    public let padding = Metric(18.0, .guess("the link prompt's inner margin"))
    public let inset = Metric(12.0, .guess("the link prompt's distance from the content area's edges"))
    public let linkPromptWidth = Metric(460.0, .guess("the card that asks before a page's link opens"))
    public let linkPromptHeight = Metric(124.0, .guess("the card that asks before a page's link opens"))
}

/// Arc's Boost panel, measured on this run's 2x shots (P37-a/b/c/d-arc-editor.png).
public struct BoostPanelMetrics: MetricGroup {
    public let size = Metric(CGSize(width: 183, height: 588), .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P37 Boost editor shots: the panel window, 366 x 1176 px"))
    public let codeWidth = Metric(480.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P37 Boost editor shots: the Code page widens the panel to 960 px"))
    public let cornerRadius = Metric(10.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P37 Boost editor shots: transparent panel corners"))
    public let headerHeight = Metric(40.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P37 Boost editor shots: header with its hairline at y 79 px"))
    public let tileHeight = Metric(38.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P37 Boost editor shots: tiles 76 px tall"))
    public let tileRadius = Metric(10.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P37 Boost editor shots: tile corners"))
    public let settingsRadius = Metric(10.0, .guess("My Boost settings card: matches the tiles; Arc's menu was not captured"))
    public let zapHintHeight = Metric(55.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P37 Boost editor shots: P37-c2 Zap strip, hairline at 1416 px to the card bottom at 1526 px"))
    public let zapOutline = Metric(3.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P37 Boost editor shots: P37-c2 the page card's #575757 outline while Zap is on, 6 px"))
}

/// Arc's capture mode, measured on this run's 2x shots (P33-a/b/c/d-arc.png).
public struct CaptureMetrics: MetricGroup {
    /// The nominal alphas, calibrated on the window: at 0.224 Brk's mask read white as #CDCDCD (Arc #C6C6C6), at 0.55
    /// its fade read #2A2A2A text as #A6A6A6 (Arc's #1A1A1A reads #949494), so both are set by that ratio.
    public let pageDim = Metric(0.256, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P33-a: white page under the mask reads #C6C6C6"))
    public let sidebarFade = Metric(0.507, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P33-a: sidebar text #1A1A1A reads #949494 on an unchanged background"))
    public let hintCard = Metric(CGSize(width: 355, height: 66), .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P33 capture shots: P33-a bottom card, 710 x 132 px"))
    public let hintCardRadius = Metric(14.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P33 capture shots: P33-a bottom card corners"))
    public let hintCardBottom = Metric(35.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P33 capture shots: P33-a bottom card ends 70 px above the page bottom"))
    public let lessonHeight = Metric(46.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P33 capture shots: P33-a top-right strip, 92 px"))
    public let lessonRadius = Metric(12.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P33 capture shots: P33-a top-right strip corners"))
    public let menuCard = Metric(CGSize(width: 273, height: 354), .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P33 capture shots: P33-c menu card, 546 x 708 px"))
    public let menuRadius = Metric(9.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P33 capture shots: P33-c menu card corners"))
    public let menuGap = Metric(3.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P33 capture shots: P33-c menu card starts 6 px right of the selection"))
    public let menuRowPitch = Metric(40.0, .anatomy("7399886bfd:verify/visual-pairs/run-20261103/REPORT.md, P33 capture shots: P33-c rows 80 px apart"))
}
