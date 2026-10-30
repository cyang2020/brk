import AppKit
import BrkBase
import BrkDomain

// Owner: F5. The Library views' numbers, colors, copy and icons that the shared tables do not carry. Each number is
// a `Metric` with its source, like `Metrics`; "cra Lnnn" is a line of the running-Arc measurements that
// layout-constants.md cites as cra. The archive page's group came from BrkOverlays/OverlayStyle.swift with the view.
// The panel's geometry (width, rows, exit button) is in `Metrics.library` and `LibraryLayout`.

/// The one instance: `LibraryDraw.list.rowPitch.value`.
let LibraryDraw = LibraryDrawMetrics()

struct LibraryDrawMetrics: MetricGroup {
    let panel = LibraryPanelMetrics()
    let list = LibraryListMetrics()
    let archive = ArchivePageMetrics()
}

/// The page rows in the panel and its exit button (cra L1548-1559 measured Arc's rail buttons; ours are sidebar rows).
struct LibraryPanelMetrics: MetricGroup {
    let titleFont = Metric(14.0, .anatomy("cra L115: sidebar rows have 14 pt titles; a page row is a sidebar row"))
    let iconSize = Metric(16.0, .guess("page glyph size in a 40 pt row, the sidebar's favicon size"))
    let iconLeading = Metric(10.0, .anatomy("cra L141: favicon centred 26 pt from the sidebar edge = selection inset 8 + 10"))
    let titleLeading = Metric(37.0, .anatomy("cra L141: row text starts at x 45 = selection inset 8 + 37"))
    let selectionHeight = Metric(Metrics.tablist.selectionHeight.value, .derived(
        rule: "the open page's fill is a sidebar row selection", from: ["Row selection background"]))
    let selectionRadius = Metric(Metrics.tablist.selectionRadius.value, .derived(
        rule: "the open page's fill is a sidebar row selection", from: ["Row selection background"]))
    let exitGlyph = Metric(15.0, .guess("the exit arrow's size in its 32 pt button, the dock's Library glyph size"))
}

/// The Downloads and History pages in the content area: Arc's list column measured in cra L1556.
struct LibraryListMetrics: MetricGroup {
    let padding = Metric(32.0, .guess("page margin inside the content card, the archive page's"))
    let columnMaxWidth = Metric(760.0, .guess("readable width of a list inside a wide content card, the archive page's"))
    let titleFontSize = Metric(26.0, .guess("page title size, the archive page's"))
    let headerHeight = Metric(40.0, .guess("title row height, the archive page's"))
    let searchHeight = Metric(36.0, .anatomy("cra L1556: Arc's Library search field is 36 pt tall"))
    let searchWidth = Metric(240.0, .guess("search field width; Arc's spans its 212 pt list column (cra L1556)"))
    let gap = Metric(12.0, .guess("space between the header, the search row and the list, the archive page's"))
    let dayHeaderHeight = Metric(36.0, .guess("height of a day header row above its rows"))
    let dayHeaderFont = Metric(13.0, .anatomy("cra L1556: day headers (\"Today\") are 13 pt semibold"))
    let rowPitch = Metric(56.0, .anatomy("cra L1556: Library rows are 56 pt apart"))
    let iconTile = Metric(24.0, .anatomy("cra L1556: a 24 pt icon tile at the row's start"))
    let iconRadius = Metric(6.0, .anatomy("cra L1471: Library thumbnails have 6 pt corners"))
    let iconToTitle = Metric(10.0, .anatomy("cra L1556: tile at x 130, title at x 164: 24 + 10"))
    let titleFont = Metric(14.0, .anatomy("cra L1556: row titles are 14 pt"))
    let detailFont = Metric(12.0, .anatomy("cra L1556: the URL under a title is 12 pt"))
    let rowRadius = Metric(8.0, .guess("hover background radius of a row, the archive entry's"))
    let progressHeight = Metric(4.0, .guess("download progress bar thickness"))
    let accessorySize = Metric(28.0, .arc("URL pill accessory buttons", .medium, note: "28 x 28: the row buttons reuse the pill's accessory size"))
    let emptyGlyph = Metric(40.0, .guess("glyph size above an empty page's title (cra L1557: Arc shows a download glyph)"))
    let emptyTitleFont = Metric(17.0, .guess("empty page title size"))
}

/// The archive page (moved from BrkOverlays with its view; the page was not measured in Arc).
struct ArchivePageMetrics: MetricGroup {
    let columnMaxWidth = Metric(760.0, .guess("readable width of the archive list inside a wide content card"))
    let padding = Metric(32.0, .guess("archive page margin inside the content card"))
    let titleFontSize = Metric(26.0, .guess("\"Archive\" title size"))
    let headerHeight = Metric(40.0, .guess("title row height"))
    let toolbarHeight = Metric(28.0, .guess("filter, threshold and Clear row height"))
    let filterWidth = Metric(240.0, .guess("filter field width"))
    let gap = Metric(12.0, .guess("space between toolbar controls and between sections"))
    let groupHeaderHeight = Metric(36.0, .guess("bucket header height"))
    let groupFontSize = Metric(13.0, .guess("bucket header text size"))
    let entryHeight = Metric(44.0, .guess("archive entry row height: title over URL"))
    let entryTitleFontSize = Metric(13.0, .guess("archive entry title size"))
    let entryDetailFontSize = Metric(11.0, .guess("archive entry URL and time size"))
    let faviconSize = Metric(16.0, .guess("favicon size in an archive entry"))
    let entryCornerRadius = Metric(8.0, .guess("archive entry hover background radius"))
}

/// Colors for one scheme (visual-and-copy.md: "Base tokens", the ARC_CommandBar table, "Content area background and
/// corners", the ARC_HomeButton and BaseHomeComponents colors).
struct LibraryColors {
    /// PreviewBackgroundColor #FFFFFF / #212222: a page inside the content card.
    let page: NSColor
    /// ForegroundPrimary / Secondary / Tertiary.
    let foregroundPrimary: NSColor
    let foregroundSecondary: NSColor
    let foregroundTertiary: NSColor
    /// CommandBarRowHoverBackgroundColor black / white @ 0.05: a hovered row.
    let rowHighlight: NSColor
    /// LibraryItemOutline #000000 @ 0.03 / #FFFFFF @ 0.08: the edge of an icon tile.
    let itemOutline: NSColor
    /// DownloadProgressBarBackground #CED7E7 / #717782.
    let progressTrack: NSColor
    /// FocusRing #458AFF (P3), both schemes: the progress fill.
    let accent: NSColor

    static func of(_ scheme: Scheme) -> LibraryColors {
        let ink: NSColor = scheme == .light ? .black : .white
        return LibraryColors(
            page: scheme == .light ? .white : srgb(0x212222),
            foregroundPrimary: scheme == .light ? p3(0x0E0F10, alpha: 0.9) : ink.withAlphaComponent(0.8),
            foregroundSecondary: ink.withAlphaComponent(0.5),
            foregroundTertiary: ink.withAlphaComponent(0.3),
            rowHighlight: ink.withAlphaComponent(0.05),
            itemOutline: ink.withAlphaComponent(scheme == .light ? 0.03 : 0.08),
            progressTrack: scheme == .light ? srgb(0xCED7E7) : srgb(0x717782),
            accent: p3(0x458AFF)
        )
    }

    /// The panel's ink on the theme background: ForegroundPrimary, as the sidebar's row titles.
    static func panelInk(_ scheme: Scheme) -> NSColor {
        scheme == .light ? p3(0x0E0F10, alpha: 0.9) : NSColor(white: 1, alpha: 0.8)
    }

    private static func p3(_ hex: Int, alpha: Double = 1) -> NSColor {
        NSColor(displayP3Red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, alpha: alpha)
    }

    private static func srgb(_ hex: Int, alpha: Double = 1) -> NSColor {
        NSColor(srgbRed: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension NSAppearance {
    /// Aqua or Dark Aqua for a theme scheme, so AppKit controls on a page match its colors.
    static func library(_ scheme: Scheme) -> NSAppearance? {
        NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
    }
}

/// The Library's English copy. "Observed" strings are Arc's (the HomeButton strings in the binary, the menu nib, or
/// cra's AX reads of the running app); GUESS marks the ones Arc keeps in code that did not survive.
public enum LibraryCopy {
    /// The panel's page rows. Observed: "Downloads", "Media", "Archived Tabs" (cra L1550, AX descriptions of Arc's
    /// rail), "Easels & Notes", "Boosts" (menu rows "View Easels & Notes", "View Boosts"), "Spaces" ("Search Spaces");
    /// "History" (menu row "View History").
    public static func title(_ page: LibraryPage) -> String {
        switch page {
        case .downloads: "Downloads"
        case .history: "History"
        case .archive: "Archived Tabs"
        case .media: "Media"
        case .easelsAndNotes: "Easels & Notes"
        case .boosts: "Boosts"
        case .spaces: "Spaces"
        }
    }

    /// Observed comment "Button; Exit the Library".
    public static let exit = "Exit the Library"
    /// Observed: "Search Downloads…" (cra L1556); History's by analogy (GUESS).
    static let searchDownloads = "Search Downloads…"
    static let searchHistory = "Search History…"
    /// Observed: "Nothing here yet!" (the Archive and Downloads empty titles), "Come back after you've found some cool
    /// stuff to save." (Downloads), "No results found for " (search).
    static let nothingHereYet = "Nothing here yet!"
    static let downloadsEmpty = "Come back after you've found some cool stuff to save."
    static func noResults(_ query: String) -> String { "No results found for “\(query)”" }
    /// GUESS.
    static let historyEmpty = "Pages you visit in this profile show up here."
    /// Observed: "File deleted or moved" (Downloads). History copy describes the implemented history-only action.
    static let fileMissing = "File deleted or moved"
    static let clearHistory = "Clear History…"
    static let clearHistoryConfirm = "Clear this profile's browsing history?"
    static let clear = "Clear"
    static let clearDownloads = "Clear Downloads"
    static let cancel = "Cancel"
    static let open = "Open"
    static let openInNewTab = "Open in New Tab"
    static let showInFinder = "Show in Finder"
    static let copyLink = "Copy Link"
    static let cancelDownload = "Cancel Download"
    static let removeFromList = "Remove from List"
    static let removeFromHistory = "Remove from History"
    static let failed = "Failed"
    static let cancelled = "Cancelled"
    static func downloading(_ received: String, of total: String?) -> String {
        total.map { "\(received) of \($0)" } ?? received
    }

    /// Observed section titles "Today", "Yesterday"; other days GUESS ("Monday, October 26").
    static let today = "Today"
    static let yesterday = "Yesterday"

    /// The pages of a later wave: an honest empty state. Observed: "Nothing Boosted Yet!"; "Opens the Space Manager,
    /// where you can rearrange your Spaces, folders, tabs, and more."; the rest GUESS.
    static func laterTitle(_ page: LibraryPage) -> String {
        page == .boosts ? "Nothing Boosted Yet!" : nothingHereYet
    }

    static func laterSubtitle(_ page: LibraryPage) -> String {
        switch page {
        case .media: "Screenshots, captures, images and videos will show here in a later version of Brk."
        case .easelsAndNotes: "Easels and Notes will show here in a later version of Brk."
        case .boosts: "Boosts will show here in a later version of Brk."
        case .spaces: "The Space Manager, where you can rearrange your Spaces, folders, tabs, and more, comes in a later version of Brk."
        case .downloads, .history, .archive: ""
        }
    }

    // The archive page (moved from BrkOverlays/OverlayStyle.swift with the view).
    /// Observed: "Opens the Archive, where all your closed tabs live." The page title is a GUESS (short label).
    static let archiveTitle = "Archive"
    /// Observed.
    static let archiveFilter = "Filter Archived Tabs"
    static let clearArchive = "Clear Archive"
    static let archiveThreshold = "Archive tabs after"
    /// GUESS (short labels).
    static let restore = "Restore"
    static let close = "Close"
    static let noMatch = "No archived tabs match your filter."

    /// "Earlier This Week" observed; the others GUESS (Arc's buckets are enum names only).
    static func bucket(_ bucket: ArchiveBucket) -> String {
        switch bucket {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .pastWeek: "Earlier This Week"
        case .pastMonth: "Past Month"
        case .beyond: "Beyond"
        }
    }

    /// Inferred from the comments "Auto archive threshold; 12 hours" and so on; the visible labels live in code.
    static func threshold(_ threshold: AutoArchiveThreshold) -> String {
        switch threshold {
        case .oneHour: "1 hour"
        case .sixHours: "6 hours"
        case .twelveHours: "12 hours"
        case .twentyFourHours: "24 hours"
        case .sevenDays: "7 days"
        case .thirtyDays: "30 days"
        case .never: "Never"
        }
    }

    /// Observed: "Auto-Closed", "Manually Closed" (the archive's "How was the tab closed?" filter); the others GUESS.
    static func reason(_ reason: ArchiveReason) -> String {
        switch reason {
        case .manual: "Manually Closed"
        case .auto: "Auto-Closed"
        case .clearToday: "Cleared from Today"
        case .containerDeleted: "Folder or Space deleted"
        }
    }
}

/// SF Symbols standing in for Arc's Library icons (ARC_HomeButton's Lottie animations `downloads`, `archive`,
/// `screenshots`, `easels`, `boosts`, `spaces`; Arc's files are not copied). History has no Arc icon.
enum LibraryIcon {
    static func symbol(_ page: LibraryPage) -> String {
        switch page {
        case .downloads: "arrow.down.circle"
        case .history: "clock"
        case .archive: "archivebox"
        case .media: "photo.on.rectangle"
        case .easelsAndNotes: "scribble"
        case .boosts: "paintbrush"
        case .spaces: "square.grid.2x2"
        }
    }

    static func image(_ page: LibraryPage, size: Double) -> NSImage? {
        NSImage(systemSymbolName: symbol(page), accessibilityDescription: LibraryCopy.title(page))?
            .withSymbolConfiguration(.init(pointSize: size, weight: .regular))
    }
}

/// A plain container with top-left origin, like every BrkUI container.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Favicons for archive entries, fetched once per URL (the same cache as BrkOverlays' command bar keeps; BrkLibrary
/// may not import BrkOverlays).
@MainActor
final class FaviconCache {
    static let shared = FaviconCache()
    private var images: [URL: NSImage] = [:]
    private var waiting: [URL: [(NSImage) -> Void]] = [:]

    /// The cached image, or nil now and `then` once it arrives (never, if the fetch fails).
    func image(for url: URL, then: @escaping (NSImage) -> Void) -> NSImage? {
        if let image = images[url] { return image }
        if waiting[url] != nil {
            waiting[url]?.append(then)
            return nil
        }
        waiting[url] = [then]
        Task {
            let data = try? await URLSession.shared.data(from: url).0
            let callbacks = waiting.removeValue(forKey: url) ?? []
            guard let data, let image = NSImage(data: data) else { return }
            images[url] = image
            for callback in callbacks { callback(image) }
        }
        return nil
    }
}
