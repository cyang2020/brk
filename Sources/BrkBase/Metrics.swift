import CoreGraphics
import Foundation

// The constants file. Every layout, motion and theme number in the app is a `Metric` here, and a `Metric` cannot
// be built without a `Source`, so an unsourced number does not compile. `.arc(name)` quotes the "Constant" column
// of docs/arc-anatomy/layout-constants.md (decompiled from Arc 1.170.0); `.cra(line)` is a measurement of the
// running Arc cited there; `.anatomy(section)` is another anatomy fact; `.guess(reason)` is ours.
//
// Views and layout read `.value`. No other file in Sources/ may contain a layout number (ArchitectureTests flags a
// literal `cornerRadius = <digit>` anywhere; reviewers catch the rest).

public enum MetricSource: Hashable, Sendable {
    case arc(String)
    case cra(String)
    case anatomy(String)
    case guess(String)
}

public struct Metric<Value: Sendable>: Sendable {
    public let value: Value
    public let source: MetricSource
    public init(_ value: Value, _ source: MetricSource) {
        self.value = value
        self.source = source
    }
}

public enum Metrics {
    public enum Window {
        public static let defaultSize = Metric(CGSize(width: 1280, height: 776), .arc("Main window default size"))
        public static let trafficLightLeft = Metric(13.0, .arc("Title row left inset"))
        public static let trafficLightSize = Metric(14.0, .arc("Window button (traffic light) size"))
        public static let trafficLightSpacing = Metric(9.0, .arc("Window button spacing"))
        /// Centre line of the traffic lights from the top: header top inset 4 + title row 40 / 2.
        public static let trafficLightCenterY = Metric(24.0, .arc("Sidebar header top inset + Title row height / 2"))
        public static let trafficLightHoverZone = Metric(CGRect(x: -50, y: 0, width: 140, height: 50), .arc("Traffic-light hover zone"))
    }

    public enum Sidebar {
        public static let minWidth = Metric(164.0, .arc("Sidebar minimum width while dragging"))
        public static let maxWidth = Metric(500.0, .arc("Sidebar maximum width"))
        public static let hideBelow = Metric(82.0, .arc("Drag-to-hide threshold"))
        /// 8 + 8 + 4 x 47 + 3 x 8: the narrowest width that keeps four square favorites.
        public static let resetWidth = Metric(228.0, .arc("Reset width on double-click of the sidebar edge"))
        public static let snapTarget = Metric(228.0, .arc("Snap target while dragging"))
        public static let snapDistance = Metric(14.0, .arc("Snap distance"))
        public static let snapHold = Metric(0.5, .arc("Snap hold time"))
        public static let unsnapSpeed = Metric(50.0, .arc("Unsnap speed threshold"))
        public static let defaultWidth = Metric(228.0, .arc("Default sidebar width for a new window (low confidence)"))
        public static let resizeHitWidth = Metric(8.0, .arc("Resize hit area"))
        public static let resizeHitTop = Metric(11.0, .arc("Resize hit area"))
        public static let resizeHitBottomTrim = Metric(22.0, .arc("Resize hit area"))
        public static let resizeIndicatorWidth = Metric(3.0, .arc("Resize indicator drawn while dragging"))
        public static let resizeIndicatorTrim = Metric(8.0, .arc("Resize indicator drawn while dragging"))
        public static let floatingInset = Metric(5.0, .arc("Floating sidebar inset from the window"))
        public static let floatingParkedGap = Metric(10.0, .arc("Floating sidebar parked position when hidden"))
        public static let floatingStayOpenSlack = Metric(80.0, .arc("Floating sidebar stays open while the pointer is within"))
        public static let outsideHoverZoneWidth = Metric(250.0, .arc("Hover zone outside the window's left edge"))
        /// Multiples of the left content inset L: reveal strip from 2L outside to 1.5L inside; 0.6L when unhovered.
        public static let revealOutsideFactor = Metric(2.0, .arc("Hidden-sidebar reveal strip at the left edge (low)"))
        public static let revealInsideFactor = Metric(1.5, .arc("Hidden-sidebar reveal strip at the left edge (low)"))
        public static let revealUnhoveredFactor = Metric(0.6, .arc("Hidden-sidebar reveal strip at the left edge (low)"))
        public static let headerTopInset = Metric(4.0, .arc("Sidebar header top inset"))
        public static let titleRowHeight = Metric(40.0, .arc("Title row (window buttons and navigation buttons) height"))
        public static let titleRowRightInset = Metric(6.0, .arc("Title row right inset"))
        public static let headerBackgroundOverhang = Metric(30.0, .arc("Sidebar header background reaches below the header by"))
        public static let libraryMinWidth = Metric(417.0, .arc("Library (\"home\") panel width"))
        public static let libraryWindowMargin = Metric(56.0, .arc("Library (\"home\") panel width"))
    }

    public enum URLPill {
        public static let sideInset = Metric(8.0, .arc("URL pill horizontal inset"))
        public static let height = Metric(36.0, .arc("URL pill height"))
        public static let cornerRadius = Metric(12.0, .arc("URL pill corner radius (continuous)"))
        public static let leadingIcon = Metric(22.0, .arc("URL pill leading icon"))
        public static let accessorySize = Metric(28.0, .arc("URL pill accessory buttons"))
        public static let accessoryRadius = Metric(9.0, .arc("URL pill accessory buttons"))
        public static let textMinHeight = Metric(20.0, .arc("URL pill text area minimum height (low)"))
    }

    public enum Favorites {
        public static let inset = Metric(8.0, .arc("Favorites tray insets"))
        public static let maxColumns = Metric(4, .arc("Favorites columns"))
        public static let minTile = Metric(47.0, .arc("Favorites minimum tile size"))
        public static let gap = Metric(8.0, .arc("Favorites gap"))
        public static let tileRadius = Metric(12.0, .arc("Favorites tile corner radius (continuous)"))
        public static let ringInset = Metric(1.0, .arc("Selected favorite ring"))
        public static let ringRadius = Metric(11.0, .arc("Selected favorite ring"))
    }

    public enum Tablist {
        public static let rowHeight = Metric(40.0, .arc("Sidebar row height"))
        public static let rowSpacing = Metric(1.0, .arc("Sidebar row height (1 pt between rows, medium)"))
        public static let dividerRowHeight = Metric(16.0, .arc("Pinned/Today divider row"))
        public static let dividerRowTallHeight = Metric(24.0, .arc("Pinned/Today divider row (one state)"))
        public static let topSpacerHeight = Metric(2.0, .arc("Spacer row at the top of the list"))
        public static let headerRowHeight = Metric(36.0, .arc("Another row type (probably folder or split header) (low)"))
        public static let selectionHeight = Metric(36.0, .arc("Row selection background"))
        public static let selectionInset = Metric(8.0, .arc("Row selection background"))
        public static let selectionRadius = Metric(12.0, .arc("Row selection background"))
        public static let hoverButtonRadius = Metric(12.0, .arc("Tab row hover-button background corner radius (low)"))
        public static let folderIndent = Metric(16.0, .guess("folder indent was not recovered (layout-constants.md, Not recovered)"))
        public static let favicon = Metric(16.0, .guess("favicon size was not recovered; cra L142 measures rows only"))
    }

    public enum Dock {
        public static let height = Metric(50.0, .arc("Dock (space switcher) height"))
        public static let cellMaxWidth = Metric(34.0, .arc("Dock space cell width"))
        public static let cellMinWidth = Metric(8.0, .arc("Dock space cell width"))
        public static let compactBelow = Metric(22.0, .arc("Dock space cell width"))
        public static let cellMaxHeight = Metric(32.0, .arc("Dock space cell height"))
        public static let cellRadius = Metric(6.0, .arc("Dock cell corner radius"))
        public static let pressScale = Metric(0.95, .arc("Dock cell press scale"))
        public static let buttonSize = Metric(32.0, .cra("L1521-1522 (\"+\" and Library buttons)"))
        public static let buttonInset = Metric(8.0, .cra("L1521-1522"))
        public static let libraryBottom = Metric(9.0, .cra("L1521-1522"))
    }

    public enum Content {
        public static let inset = Metric(10.0, .arc("Content card inset"))
        public static let cornerRadius = Metric(6.0, .arc("Content card corner radius"))
        public static let fullScreenCornerRadius = Metric(0.0, .arc("Content card corner radius (0 in one state)"))
        public static let showsShadow = Metric(true, .arc("Content card shadow"))
        public static let shadowRadius = Metric(10.0, .guess("shadow radius and opacity were not recovered; spike value"))
        public static let shadowOpacity = Metric(0.2, .guess("visual-and-copy.md Shadow token #000000 @ 0.2 (light)"))
        public static let highlightBorder = Metric(2.0, .arc("Content highlight border width"))
        public static let splitGap = Metric(10.0, .cra("L621 (split view gap between panes)"))
        public static let maxPanes = Metric(4, .anatomy("visual-and-copy.md, Split view: first to fourth Split View page"))
        public static let minPaneFraction = Metric(0.15, .guess("narrowest a pane may be dragged, fraction of content width"))
    }

    public enum CommandBar {
        public static let width = Metric(766.0, .arc("Command bar width"))
        public static let sideMargin = Metric(160.0, .arc("Command bar width (area width minus 160)"))
        public static let narrowMargin = Metric(20.0, .arc("Command bar width (narrow areas)"))
        public static let boxHeight = Metric(338.0, .arc("Command bar box height and position"))
        public static let minVerticalMargin = Metric(24.0, .arc("Command bar box height and position"))
        public static let attachedMinWidth = Metric(100.0, .arc("Command bar attached to the toolbar (low)"))
        public static let attachedMaxWidth = Metric(720.0, .arc("Command bar attached to the toolbar (low)"))
        public static let attachedRightMargin = Metric(80.0, .arc("Command bar attached to the toolbar (low)"))
        public static let suggestionRowHeight = Metric(50.0, .arc("Command bar suggestion row height"))
        public static let maxVisibleRows = Metric(5, .arc("Visible suggestions and list height"))
        public static let listPadding = Metric(10.0, .arc("Visible suggestions and list height"))
        public static let inputRowHeight = Metric(50.0, .arc("Command bar input row height (conflicts with cra 60)"))
        public static let stackSpacing = Metric(10.0, .arc("Command bar inner spacing"))
        public static let contentInset = Metric(12.0, .arc("Command bar inner spacing"))
        public static let openBounceFrom = Metric(0.95, .arc("Command bar opening bounce"))
        public static let littleArcWidth = Metric(500.0, .cra("L507-508 (Little Arc command bar width)"))
    }

    public enum Motion {
        public static let sidebarToggle = Metric(0.08, .arc("Sidebar show/hide animation duration"))
        /// cubic-bezier control points (x1, y1, x2, y2).
        public static let sidebarCurve = Metric([0.25, 0.46, 0.45, 0.94], .arc("Sidebar show/hide timing curve"))
        public static let contentRelayout = Metric(0.2, .arc("Content relayout animation (same curve)"))
        public static let spaceSwitch = Metric(0.17, .cra("L447-448 (space switch, visible motion)"))
        /// Arc's shader has a `transitioning` state but no duration literal was found; we reuse the space switch.
        public static let themeCrossfade = Metric(0.17, .guess("crossfade duration not recovered; equals the space switch"))
        public static let tooltipQuickReshowWindow = Metric(0.6, .arc("Tooltip quick re-show"))
        public static let tooltipQuickReshowDelay = Metric(0.01, .arc("Tooltip quick re-show"))
        public static let tooltipFirstDelay = Metric(1.6, .cra("L789-790 (tooltip first-show delay)"))
        public static let toastDuration = Metric(5.0, .arc("Toast duration"))
        /// Arc's "press twice for Arc's shortcut" window is a runtime value; ours.
        public static let pressTwiceWindow = Metric(1.0, .guess("promptAfterConsumedByWebView second-press window"))
    }

    public enum Theme {
        /// Texture opacity = intensity x multiplier; tiled; multiply blend (normal when intensity is 0).
        public static let grainOpacity = Metric(0.8, .arc("Theme texture opacity, as a multiple of the theme intensity"))
        public static let sandOpacity = Metric(0.15, .arc("Theme texture opacity, as a multiple of the theme intensity"))
        public static let denimOpacity = Metric(0.6, .arc("Theme texture opacity, as a multiple of the theme intensity"))
        public static let tweedOpacity = Metric(0.4, .arc("Theme texture opacity, as a multiple of the theme intensity"))
        /// Wash: white in light, black at 35% in dark; opacity = min(base + slope x factor, cap).
        public static let darkWashAlpha = Metric(0.35, .arc("Theme background wash (low)"))
        public static let washBase = Metric(0.2, .arc("Theme background wash (low)"))
        public static let washSlope = Metric(0.55, .arc("Theme background wash (low)"))
        public static let washCap = Metric(0.5, .arc("Theme background wash (low)"))
        public static let gradientTexturePerFactor = Metric(100.0, .arc("Metal gradient texture size (low)"))
        /// Tile sizes of Arc's own textures (px @1x). Ours are generated procedurally at these sizes.
        public static let grainTile = Metric(155, .anatomy("visual-and-copy.md, Gradient and grain assets"))
        public static let sandTile = Metric(96, .anatomy("visual-and-copy.md, Gradient and grain assets"))
        public static let denimTile = Metric(300, .anatomy("visual-and-copy.md, Gradient and grain assets"))
        public static let tweedTile = Metric(128, .anatomy("visual-and-copy.md, Gradient and grain assets"))
    }

    public enum LittleArc {
        public static let defaultSize = Metric(CGSize(width: 1185, height: 832), .arc("Little Arc default window size"))
        public static let cascade = Metric(30.0, .arc("Little Arc default window size (new windows cascade)"))
    }

    public enum Persistence {
        public static let saveDebounce = Metric(0.4, .guess("trailing debounce for state.json writes"))
        public static let sweepInterval = Metric(60.0, .guess("real-time interval of the auto-archive sweep"))
        public static let shutdownTimeout = Metric(5.0, .guess("longest wait for OnBeforeClose of every browser at quit"))
        public static let historyCap = Metric(500, .guess("history entries kept"))
        public static let archiveCap = Metric(2000, .guess("archive entries kept"))
    }
}
