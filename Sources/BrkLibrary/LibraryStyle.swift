import AppKit
import BrkBase
import BrkDomain

// Owner: F5. The Library views' numbers, colors, copy and icons that the shared tables do not carry. Each number is
// a `Metric` with its source, like `Metrics`; "cra Lnnn" is a line of the running-Arc measurements that
// layout-constants.md cites as cra; "P32-x" and "Q05-a" are this round's Arc captures
// (verify/visual-pairs/run-20261103, a 1280 x 776 pt window, positions in points from the column's or card's left).
// The panel's geometry (navigation column, cells, exit button) is in `Metrics.library` and `LibraryLayout`.

/// The one instance: `LibraryDraw.list.rowPitch.value`.
let LibraryDraw = LibraryDrawMetrics()

struct LibraryDrawMetrics: MetricGroup {
    let nav = LibraryNavMetrics()
    let column = LibraryColumnMetrics()
    let list = LibraryListMetrics()
    let media = LibraryMediaMetrics()
    let boosts = LibraryBoostMetrics()
    let spaces = LibrarySpacesMetrics()
    let history = HistoryPageMetrics()
}

/// A navigation cell (glyph over label) and the buttons at the column's foot.
struct LibraryNavMetrics: MetricGroup {
    let glyphSize = Metric(21.0, .anatomy("P32-b: the Downloads circle is 21 pt across"))
    let labelFont = Metric(11.0, .anatomy("P32-a/b: \"Downloads\" is 60 pt wide and 8.5 tall whether open or not: 11 pt bold for every page"))
    let selectionRadius = Metric(12.0, .guess("the selected cell's corner radius, from the capture's rounding"))
    let footerGlyph = Metric(15.0, .anatomy("P32-a: the exit arrow and the gift glyph are 15 pt"))
    let footerRadius = Metric(6.0, .guess("the exit button's fill under the pointer, from Q18-navy-library-downloads-arc.png's rounding"))
    let edgeWidth = Metric(1.0, .anatomy("P32-a: a 1 pt line at x 112"))
    let shadowWidth = Metric(10.0, .anatomy("P32-b: the column darkens over its first 10 pt beside the navigation"))
    let shadowWidthDark = Metric(37.0, .anatomy("Q18-navy-library-downloads: over a dark theme the darkening fades over 37 pt"))
    let sheen = Metric(0.05, .anatomy("Q18-navy-library-downloads: white grows to this strength across the navigation column, #66869E to #6E8CA3"))
}

/// The top of every page column: the search field and the Filter button.
struct LibraryColumnMetrics: MetricGroup {
    let searchTop = Metric(10.0, .anatomy("P32-b: the search field spans y 10...46"))
    let searchHeight = Metric(36.0, .anatomy("cra L1556: Arc's Library search field is 36 pt tall"))
    let searchRadius = Metric(10.0, .guess("search field corner radius, from the capture's rounding"))
    let searchFont = Metric(14.5, .anatomy("P32-a: \"Search Media…\" is 101 pt wide (15 pt measured 105)"))
    let searchInset = Metric(8.0, .anatomy("P32-a/b: the search field (or the Filter button) runs from x 120 to 409 in the 112...417 column"))
    let searchGlyph = Metric(19.0, .anatomy("P32-b: the magnifier's ink is 15 x 14.5, centred 22 into the field (a 16 pt symbol drew 12.5)"))
    let searchGlyphLeading = Metric(12.5, .anatomy("P32-b: the magnifier starts 12.5 from the field's left"))
    let searchTextLeading = Metric(42.0, .anatomy("P32-b: the placeholder starts 42 from the field's left"))
    let filterWidth = Metric(71.0, .anatomy("P32-b: the Filter button spans x 338...409"))
    let filterGap = Metric(7.5, .anatomy("P32-b: the field ends at x 330.5, the button starts at 338"))
}

/// Lists in the page column: day headers and 56 pt rows (Archived Tabs, Downloads); the empty state.
struct LibraryListMetrics: MetricGroup {
    let listTop = Metric(46.0, .anatomy("P32-e: the Today header starts under the search field"))
    let dayHeaderHeight = Metric(37.0, .anatomy("P32-e: \"Today\" is centred at y 72 and the first row starts at 83"))
    let dayHeaderFont = Metric(12.0, .anatomy("P32-a/e: \"Today\" is 34.5 pt wide, semibold (13 pt measured 37)"))
    let dayHeaderLeading = Metric(12.5, .anatomy("P32-a/e: \"Today\" starts at x 124.5, 12.5 into the column"))
    let dayHeaderBottom = Metric(3.0, .anatomy("P32-e: \"Today\" ends 3 above the first row"))
    let rowPitch = Metric(56.0, .anatomy("cra L1556: Library rows are 56 pt apart"))
    let rowLeading = Metric(10.0, .anatomy("P32-e: rows span the column inside its 10 pt padding"))
    let rowInset = Metric(8.0, .anatomy("cra L1556: the tile at x 130, 18 into the column = row 10 + 8"))
    let iconTile = Metric(24.0, .anatomy("cra L1556: a 24 pt icon tile at the row's start"))
    let iconRadius = Metric(6.0, .anatomy("cra L1471: Library thumbnails have 6 pt corners"))
    let iconToTitle = Metric(10.0, .anatomy("cra L1556: tile at x 130, title at x 164: 24 + 10"))
    let titleFont = Metric(14.0, .anatomy("cra L1556: row titles are 14 pt"))
    let detailFont = Metric(12.0, .anatomy("cra L1556: the URL under a title is 12 pt"))
    let rowRadius = Metric(8.0, .guess("hover background radius of a row"))
    let progressHeight = Metric(4.0, .guess("download progress bar thickness"))
    let accessorySize = Metric(24.0, .guess("a row's trailing buttons in a 304 pt column"))
    let emptyGlyph = Metric(57.0, .anatomy("P32-b: the empty Downloads circle is 47.5 pt across (a 48 pt symbol drew 40), centred at y 377"))
    let emptyGlyphGap = Metric(10.0, .anatomy("P32-b: \"Nothing here yet!\" starts 19.5 under the circle's ink"))
    let emptyTitleFont = Metric(17.0, .anatomy("P32-b: \"Nothing here yet!\" is 136 pt wide, 17 pt semibold"))
    let emptySubtitleFont = Metric(14.0, .anatomy("P32-b: the two grey lines are 14 pt, 17 apart"))
    let emptyTitleGap = Metric(8.0, .anatomy("P32-b: the grey lines start 8 under the title"))
    let emptyWidth = Metric(250.0, .anatomy("P32-b: the subtitle wraps after \"found some\", about 232 pt"))
}

/// The Media page: the card list and the "Your Media in the Library" card.
struct LibraryMediaMetrics: MetricGroup {
    let headerCenter = Metric(63.0, .anatomy("P32-a: \"Today\" is centred at y 63"))
    let cardTop = Metric(83.0, .anatomy("P32-a: the first card starts at y 83"))
    let cardHeight = Metric(48.0, .anatomy("P32-a: a card spans y 83...131"))
    let cardPitch = Metric(60.0, .anatomy("P32-a: cards are 60 pt apart"))
    let cardLeading = Metric(12.0, .anatomy("P32-a: cards span x 124...404.5"))
    let cardRadius = Metric(12.0, .guess("a media card's corner radius, from the capture's rounding"))
    let introLeading = Metric(28.0, .anatomy("P32-a: the introduction card spans x 140...388.5"))
    let introTop = Metric(288.25, .anatomy("P32-a: the introduction card starts at y 288.25"))
    let introRadius = Metric(16.0, .guess("the introduction card's corner radius"))
    let introPadding = Metric(13.5, .anatomy("P32-a: its text and Show Media start at x 153.5, 13.5 inside the card"))
    let introGlyph = Metric(34.0, .anatomy("P32-a: the media glyph's ink spans x 495 to 660 of the 4x crop, about 41 points including its slant"))
    let introGlyphCenter = Metric(49.0, .anatomy("P32-a: the media glyph is centred 49 below the card's top"))
    let introTitleCenter = Metric(84.5, .anatomy("P32-a: the title is centred 84.5 below the card's top"))
    let introTitleFont = Metric(13.0, .anatomy("P32-a: \"Your Media in the Library\" is 160 pt wide, bold (13.5 pt measured 165.5)"))
    let introBodyFont = Metric(12.0, .anatomy("P32-a: a 37-character description line is 219 pt wide, lines 17 apart (13 pt wrapped it at 34)"))
    let introBodyLine = Metric(17.0, .anatomy("P32-a: the description's lines are 17 apart"))
    let introBodyTop = Metric(99.25, .anatomy("P32-a: the description's first line is centred 108 below the card's top"))
    let introFootnoteLine = Metric(14.0, .anatomy("P32-a: the footnote's lines are 14 apart, the first centred 18.5 under Show Media"))
    let introButtonHeight = Metric(40.0, .anatomy("P32-a: Show Media spans y 450...490"))
    let introButtonRadius = Metric(8.0, .guess("Show Media's corner radius"))
    let introFootnoteFont = Metric(11.0, .anatomy("P32-a: the footnote fits two lines, a 36-character line 202 pt wide, 14 apart (10.5 pt measured 194)"))
}

/// The Boosts page: one row per Boost under the search field.
struct LibraryBoostMetrics: MetricGroup {
    let rowTop = Metric(48.0, .anatomy("P32-f: the first row is centred at y 84"))
    let tile = Metric(44.0, .anatomy("P32-f: the icon tile is 44 pt square"))
    let tileRadius = Metric(10.0, .guess("the Boost tile's corner radius"))
    let tileLeading = Metric(14.0, .anatomy("P32-f: the tile starts at x 126"))
    let titleLeading = Metric(66.0, .anatomy("P32-f: the name starts at x 178"))
    let titleFont = Metric(15.0, .anatomy("P32-f: \"My Boost\" is 15 pt"))
    let detailFont = Metric(13.0, .anatomy("P32-f: the domain is 13 pt"))
    let sectionGap = Metric(20.0, .guess("space above the local gallery's header"))
}

/// The Spaces page: one tall card per space.
struct LibrarySpacesMetrics: MetricGroup {
    let cardTop = Metric(48.0, .anatomy("P32-d: cards span y 48...728 in a 776 pt panel"))
    let cardRadius = Metric(14.0, .guess("a Space card's corner radius, from the capture's rounding"))
    let headerCenter = Metric(25.0, .anatomy("P32-d: the Space name is centred 25 below the card's top"))
    let padding = Metric(16.0, .anatomy("P32-d: the name starts 16 into the card"))
    let titleFont = Metric(13.0, .anatomy("P30-a: \"Space 1\" is 47 pt wide and \"对照\" 24.5, medium (Brk's 15 pt regular measured 51.5 and 28)"))
    let rowTop = Metric(64.0, .anatomy("P32-d: the first row is centred at y 112, 64 below the card's top"))
    let rowPitch = Metric(41.0, .anatomy("P32-d: rows are 41 pt apart"))
    let rowFont = Metric(14.0, .anatomy("P30-a: \"Interface comparison\" is 135 pt wide, the sidebar's 14 pt (15 pt measured 143.5)"))
    let favicon = Metric(14.0, .anatomy("P32-d: the favicon squares are 14 pt"))
    let faviconRadius = Metric(3.0, .guess("the small favicon squares' corners"))
    let rowTextLeading = Metric(25.0, .anatomy("P32-d: a row's text starts 25 after its icon's start (x 19 and 44 in the card)"))
    let indent = Metric(16.0, .anatomy("P32-d: a folder's children start 16 further in"))
    let dividerHeight = Metric(17.0, .anatomy("P32-d: Interface comparison at y 276.5, the line at 304.5, Inbox at 334.5: 41 + 17"))
    let footerCenter = Metric(22.0, .anatomy("P32-d: the move handle and … are centred 22 above the card's bottom"))
    let footerButton = Metric(24.0, .guess("the footer buttons' size"))
    let footerInset = Metric(22.0, .anatomy("P30-a: the move handle and … are centred 22 in from the card's left and right edges, #888989"))
    let plusSize = Metric(31.0, .anatomy("P32-d: the + button is 31 pt across"))
    let plusGap = Metric(48.0, .anatomy("P32-d: the + button is centred 48 after the last card"))
    let shadowRadius = Metric(24.0, .anatomy("P30-a: no outline; the panel darkens from #EDEDED at a card's edge back to #FCFCFC about 25 pt out"))
    let shadowDrop = Metric(1.0, .anatomy("P30-a: the shadow is a little darker under a card (#EBEBEA) than over it (#EDEDEC)"))
    let shadowOpacity = Metric(0.15, .anatomy("P30-a: #FCFCFC to #EDEDED right at a card's edge"))
    let themeWash = Metric(0.15, .guess("P30-a: the 对照 card (a pale beige theme) is the panel's #FCFCFC and Space 1's runs #E4E4FB to #FDEFEE: its theme at about 15% over the panel"))
    let faviconPlaceholderAlpha = Metric(0.17, .anatomy("P32-d: a favicon-less row's square is #D1D1D1 on the #FCFCFC card"))
    let darkCardShade = Metric(0.08, .anatomy("Q18-navy-library-spaces: the 对照 card reads #6A7B91 where the theme's window color is #74839B"))
}

/// The History page in the content area (Q05-a, positions from the card's top left).
struct HistoryPageMetrics: MetricGroup {
    let headerCenter = Metric(28.0, .anatomy("Q05-a: \"History\" and the search field are centred 28 below the card's top"))
    let logoLeading = Metric(23.0, .anatomy("Q05-a: the logo spans x 23...43"))
    let logoSize = Metric(22.0, .anatomy("Q05-a: the logo is 22 pt"))
    let titleLeading = Metric(65.5, .anatomy("Q05-a: \"History\"'s text starts at x 67.5 (its label 2 pt inside the frame)"))
    let titleFont = Metric(23.5, .anatomy("Q05-a: \"History\" is 72 pt wide"))
    let searchLeading = Metric(265.0, .anatomy("Q05-a: the search field spans x 265...962"))
    let searchMaxWidth = Metric(697.0, .anatomy("Q05-a: the search field is 697 pt wide"))
    let searchHeight = Metric(42.0, .anatomy("Q05-a: the search field is 42 pt tall"))
    let searchFont = Metric(12.5, .anatomy("Q05-a: the magnifier and \"Search history\" span 93 pt (13 pt measured 96.5)"))
    let searchGlyphLeading = Metric(14.5, .anatomy("Q05-a: the magnifier starts 14.5 into the field"))
    let searchTextLeading = Metric(37.0, .anatomy("Q05-a: the placeholder starts 37 into the field"))
    let navTop = Metric(64.0, .anatomy("Q05-a: \"Arc history\"'s fill spans y 64...104"))
    let navWidth = Metric(252.0, .anatomy("Q05-a: the selected item's fill ends at x 253"))
    let navHeight = Metric(40.0, .anatomy("Q05-a: navigation items are 40 pt apart"))
    let navIconLeading = Metric(24.5, .anatomy("Q05-a: the item icons are centred at x 34.5 (a 22 pt frame from 23.5)"))
    let navTextLeading = Metric(62.0, .anatomy("Q05-a: the item labels' ink starts 1 point right of a label at 61 (x 291 pt from the window)"))
    let navTextRaise = Metric(1.0, .anatomy("Q05-a: the item labels sit a point above the rows' middle"))
    let navFont = Metric(14.0, .anatomy("Q05-a: \"Delete browsing data\" is 138 pt wide, medium (14.5 pt measured 143.5)"))
    let listLeading = Metric(279.0, .anatomy("Q05-a: the visits card spans x 279...1018"))
    let listTop = Metric(79.0, .anatomy("Q05-a: the visits card starts at y 79"))
    let listMaxWidth = Metric(739.0, .anatomy("Q05-a: the visits card is 739 pt wide"))
    let listRadius = Metric(8.0, .guess("the visits card's corner radius, Chromium's cr-card"))
    let dayHeaderHeight = Metric(69.0, .anatomy("Q05-a: the first row is centred 87 below the visits card's top"))
    let dayTitleCenter = Metric(36.5, .anatomy("Q05-a: the day title's ink spans y 119...134, 30...45 below the visits card's top"))
    let dayFont = Metric(16.0, .anatomy("Q05-a: \"Today - Tuesday, November 3, 2026\" is 16 pt medium"))
    let padding = Metric(25.0, .anatomy("Q05-a: the day title and the checkboxes start 25 into the card"))
    let rowHeight = Metric(36.0, .anatomy("Q05-a: visits are 36 pt apart"))
    let checkbox = Metric(18.0, .anatomy("Q05-a: the checkbox's outline is 16 pt (drawn 1 pt inside its frame)"))
    let timeLeading = Metric(57.0, .anatomy("Q05-a: the time starts 57 into the card"))
    let faviconLeading = Metric(162.0, .anatomy("Q05-a: the favicon starts 162 into the card"))
    let titleLeadingInRow = Metric(190.0, .anatomy("Q05-a: the title starts 190 into the card"))
    let rowTitleFont = Metric(12.0, .anatomy("Q05-a: \"Visual fixture\" is 75 pt wide, medium (12.5 pt measured 78)"))
    let rowDetailFont = Metric(12.0, .anatomy("Q05-a: \"127.0.0.1:8764\" is 79.5 pt wide (12.5 pt measured 82)"))
    let timeFont = Metric(11.5, .anatomy("Q05-a: \"1:06 PM\" is 44 pt wide"))
    let gapHeight = Metric(15.0, .anatomy("Q05-a: a session break adds 15 pt (12:53 to 12:18 PM is 51 pt), its line the whole height under the time column"))
    let gapMinutes = Metric(15.0, .guess("visits further apart than this show a break, Chromium's history page threshold"))
    let menuTrailing = Metric(32.0, .anatomy("Q05-a: the ⋮ button is centred 32 from the card's right"))
}

/// Colors for one scheme (visual-and-copy.md: "Base tokens", the ARC_CommandBar table, "Content area background and
/// corners", the ARC_HomeButton and BaseHomeComponents colors). The Library panel draws no background of its own: the
/// window's theme shows through it, as behind the sidebar it replaces (Q18-navy-library-*: the column reads the same
/// as the sidebar at every height). So these are inks and translucent fills: white on a dark theme (the Q18-navy-library
/// pictures), the values measured on the near-white P32 pictures on a light one.
struct LibraryColors {
    /// What the panel looks like under a light theme (P32: #FCFCFC): a card's shadow fill and the media preview's page.
    let panel: NSColor
    /// The selected navigation cell (P32: #EAEAE9 on the panel; Q18-navy: white 0.09).
    let control: NSColor
    /// The search field, the Filter button (the same as `control` on P32; Q18-navy: white 0.08 and 0.05).
    let search: NSColor
    let filter: NSColor
    /// The line between the navigation and the page column (P32: #EAE9E8; Q18-navy: white 0.04), and card outlines.
    let edge: NSColor
    /// The darkening at the page column's left edge, and how far it fades (P32-b: black 0.04 over 10 pt; Q18-navy:
    /// black 0.05 over 37 pt).
    let shade: NSColor
    let shadeWidth: Double
    /// Grey controls on the panel (the Space cards' move handle and …: P30-a #888989).
    let navInk: NSColor
    /// The open page's navigation glyph (P32: #5A5A5A).
    let navInkSelected: NSColor
    /// The other pages' navigation glyphs and labels (P32-b: #6A6A6A and #737373), and the exit and gift buttons at
    /// the column's foot (#7A7878).
    let navGlyph: NSColor
    let navLabel: NSColor
    let navFooter: NSColor
    /// PreviewBackgroundColor #FFFFFF / #212222: a page inside the content card (the History page).
    let page: NSColor
    /// ForegroundPrimary / Secondary / Tertiary.
    let foregroundPrimary: NSColor
    let foregroundSecondary: NSColor
    let foregroundTertiary: NSColor
    /// The open page's label and an empty state's title (Q18-navy: white 0.87; P32: `foregroundPrimary`).
    let foregroundStrong: NSColor
    /// The search field's placeholder and magnifier, the Filter button's word and glyph.
    let searchPlaceholder: NSColor
    let searchGlyph: NSColor
    let filterInk: NSColor
    /// CommandBarRowHoverBackgroundColor black / white @ 0.05: a hovered row.
    let rowHighlight: NSColor
    /// LibraryItemOutline #000000 @ 0.03 / #FFFFFF @ 0.08: the edge of an icon tile.
    let itemOutline: NSColor
    /// A tile without a favicon and a Media placeholder card (P32-e: #F1F1F1).
    let placeholder: NSColor
    /// DownloadProgressBarBackground #CED7E7 / #717782.
    let progressTrack: NSColor
    /// FocusRing #458AFF (P3), both schemes: the progress fill.
    let accent: NSColor

    static func of(_ scheme: Scheme) -> LibraryColors {
        scheme == .light ? light : dark
    }

    private static let light: LibraryColors = {
        let ink = NSColor.black
        let control = ink.withAlphaComponent(0.072)
        let primary = p3(0x0E0F10, alpha: 0.9), secondary = ink.withAlphaComponent(0.5), tertiary = ink.withAlphaComponent(0.3)
        return LibraryColors(
            panel: srgb(0xFCFCFC), control: control, search: control, filter: control,
            edge: ink.withAlphaComponent(0.075), shade: ink.withAlphaComponent(0.04), shadeWidth: LibraryDraw.nav.shadowWidth.value,
            navInk: srgb(0x8F8F8F), navInkSelected: srgb(0x5B5B5B), navGlyph: srgb(0x6A6A6A), navLabel: srgb(0x737373), navFooter: srgb(0x7A7878),
            page: .white,
            foregroundPrimary: primary, foregroundSecondary: secondary, foregroundTertiary: tertiary, foregroundStrong: primary,
            searchPlaceholder: tertiary.blended(withFraction: 0.35, of: secondary) ?? secondary, searchGlyph: secondary, filterInk: srgb(0x5B5B5B),
            rowHighlight: ink.withAlphaComponent(0.05), itemOutline: ink.withAlphaComponent(0.03), placeholder: ink.withAlphaComponent(0.045),
            progressTrack: srgb(0xCED7E7), accent: p3(0x458AFF)
        )
    }()

    /// White inks and fills, read off the Q18-navy-library pictures against the same pixel without the item.
    private static let dark: LibraryColors = {
        func white(_ alpha: Double) -> NSColor { NSColor(white: 1, alpha: alpha) }
        return LibraryColors(
            panel: srgb(0x262626), control: white(0.09), search: white(0.08), filter: white(0.05),
            edge: white(0.04), shade: NSColor(white: 0, alpha: 0.05), shadeWidth: LibraryDraw.nav.shadowWidthDark.value,
            navInk: white(0.5), navInkSelected: white(0.87), navGlyph: white(0.63), navLabel: white(0.63), navFooter: white(0.63),
            page: srgb(0x212222),
            foregroundPrimary: white(0.8), foregroundSecondary: white(0.6), foregroundTertiary: white(0.3), foregroundStrong: white(0.87),
            searchPlaceholder: white(0.58), searchGlyph: white(0.45), filterInk: white(0.63),
            rowHighlight: white(0.05), itemOutline: white(0.08), placeholder: white(0.05),
            progressTrack: srgb(0x717782), accent: p3(0x458AFF)
        )
    }()

    static func p3(_ hex: Int, alpha: Double = 1) -> NSColor {
        NSColor(displayP3Red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, alpha: alpha)
    }

    static func srgb(_ hex: Int, alpha: Double = 1) -> NSColor {
        NSColor(srgbRed: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, alpha: alpha)
    }
}

extension NSAppearance {
    /// Aqua or Dark Aqua for a theme scheme, so AppKit controls on a page match its colors.
    static func library(_ scheme: Scheme) -> NSAppearance? {
        NSAppearance(named: scheme == .light ? .aqua : .darkAqua)
    }
}

/// The Library's English copy. "Observed" strings are Arc's (the HomeButton strings in the binary, the menu nib, cra's
/// AX reads of the running app, or this round's captures); GUESS marks the ones Arc keeps in code that did not survive.
public enum LibraryCopy {
    /// The navigation cells. Observed in P32: "Media", "Downloads", "Easels", "Spaces", "Boosts", "Archived Tabs".
    public static func title(_ page: LibraryPage) -> String {
        switch page {
        case .media: "Media"
        case .downloads: "Downloads"
        case .easelsAndNotes: "Easels"
        case .spaces: "Spaces"
        case .boosts: "Boosts"
        case .archive: "Archived Tabs"
        }
    }

    /// Observed comment "Button; Exit the Library".
    public static let exit = "Exit the Library"
    /// GUESS: Arc's gift button invites friends to Arc; Brk has no invitations.
    static let gift = "Invitations are not part of Brk"
    /// Observed in P32: "Search Media…", "Search Downloads…", "Search Easels…", "Search Boosts…", "Search Archive…",
    /// and "Filter".
    static func search(_ page: LibraryPage) -> String {
        switch page {
        case .media: "Search Media…"
        case .downloads: "Search Downloads…"
        case .easelsAndNotes: "Search Easels…"
        case .spaces: "Search Spaces…"
        case .boosts: "Search Boosts…"
        case .archive: "Search Archive…"
        }
    }
    static let filter = "Filter"
    /// Observed: "Nothing here yet!" (the Archive and Downloads empty titles), "Come back after you've found some cool
    /// stuff to save." (Downloads), "No results found for " (search).
    static let nothingHereYet = "Nothing here yet!"
    static let downloadsEmpty = "Come back after you’ve found some cool stuff to save."
    static func noResults(_ query: String) -> String { "No results found for “\(query)”" }
    /// GUESS.
    static let easelsEmpty = "Make one with File > New Easel (⌃⇧E)."
    /// Observed: "File deleted or moved" (Downloads).
    static let fileMissing = "File deleted or moved"
    static let clearDownloads = "Clear Downloads"
    /// GUESS: the Downloads filter's choices.
    static let allDownloads = "All Downloads"
    static let inProgress = "In Progress"
    static let completed = "Completed"
    static let failedOrCancelled = "Failed or Cancelled"
    static let cancel = "Cancel"
    static let open = "Open"
    static let openInNewTab = "Open in New Tab"
    static let showInFinder = "Show in Finder"
    static let copyLink = "Copy Link"
    static let cancelDownload = "Cancel Download"
    static let removeFromList = "Remove from List"
    static let removeFromHistory = "Remove from history"
    static let failed = "Failed"
    static let cancelled = "Cancelled"
    static func downloading(_ received: String, of total: String?) -> String {
        total.map { "\(received) of \($0)" } ?? received
    }

    /// Observed section titles "Today", "Yesterday"; other days GUESS ("Monday, October 26").
    static let today = "Today"
    static let yesterday = "Yesterday"

    // The Media page. Observed in P32-a.
    static let mediaIntroTitle = "Your Media in the Library"
    static let mediaIntroBody = "Quickly grab screenshots, images, and videos from your computer by showing them in the Brk Library!"
    static let showMedia = "Show Media"
    static let mediaPrivacy = "Media never leaves your computer and is not viewable by anyone but you."
    /// GUESS: Brk's Media page lists its own captures.
    static let mediaEmpty = "Capture an area, a full page or a portrait to add it here. Private captures stay in memory."

    // The Boosts page. Observed: "Nothing Boosted Yet!", "New Boost"; the rest GUESS.
    static let nothingBoosted = "Nothing Boosted Yet!"
    static let newBoost = "New Boost"
    static let installFromFile = "Install from File…"
    static let localGallery = "Local Boost Gallery"

    // The Spaces page: the pencil's tooltip (it opens the theme panel) and the controls; the card's … menu is the
    // reducer's (`.sidebar(.popupMenu(.spaceCard))`, Arc's rows in P30-c).
    static let editSpace = "Edit Space…"
    static let newSpace = "New Space…"
    static let moveSpace = "Drag to reorder"
    static let more = "More"

    // The archive page (moved from BrkOverlays/OverlayStyle.swift with the view).
    /// Observed: "Clear Archive", "Archive tabs after".
    static let clearArchive = "Clear Archive"
    static let archiveThreshold = "Archive tabs after"
    /// Observed: the archive's "How was the tab closed?" filter.
    static let closedHow = "How was the tab closed?"
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

    // The History page (Q05-a; Arc's is Chromium's history page, so its copy is Chromium's, with Brk's name).
    static let historyTitle = "History"
    static let brkHistory = "Brk history"
    static let otherDevices = "Tabs from other devices"
    static let deleteBrowsingData = "Delete browsing data"
    static let searchHistory = "Search history"
    static let historyEmpty = "Your browsing history appears here"
    static let otherDevicesEmpty = "Tabs from other devices appear here. Brk does not sync tabs between devices."
    static let noHistoryResults = "No search results found"
    /// The last card of a search, the visits the local search model found that the words did not (Brk's own).
    static let foundByMeaning = "Found by meaning"
    static let moreFromSite = "More from this site"
    static let clearHistoryConfirm = "Clear this profile's browsing history?"
    static let clear = "Clear"
    static let delete = "Delete"
    static func selected(_ count: Int) -> String { "\(count) selected" }
    /// "Today - Tuesday, November 3, 2026", "Yesterday - …", then the date.
    static let todayPrefix = "Today - "
    static let yesterdayPrefix = "Yesterday - "
}

/// SF Symbols standing in for Arc's Library icons (ARC_HomeButton's Lottie animations `screenshots`, `downloads`,
/// `easels`, `spaces`, `boosts`, `archive`; Arc's files are not copied).
enum LibraryIcon {
    /// The same glyph filled in, for the open page's cell: Arc's two-color icons show the theme's color inside the
    /// outline (P32-b white, Q18-navy-library-downloads navy). `macwindow` has no filled version.
    static func filledSymbol(_ page: LibraryPage) -> String {
        page == .easelsAndNotes ? "rectangle.fill" : symbol(page) + ".fill"
    }

    static func symbol(_ page: LibraryPage) -> String {
        switch page {
        case .media: "photo.on.rectangle.angled"
        case .downloads: "arrow.down.circle"
        // P32: Arc's Easels glyph is a window frame with a scribble (no badge), Spaces two portrait cards.
        case .easelsAndNotes: "macwindow"
        case .spaces: "rectangle.portrait.on.rectangle.portrait.angled"
        case .boosts: "paintbrush.pointed"
        case .archive: "archivebox"
        }
    }

    static func image(_ page: LibraryPage, size: Double, weight: NSFont.Weight = .regular) -> NSImage? {
        symbol(symbol(page), size: size, weight: weight, label: LibraryCopy.title(page))
    }

    static func symbol(_ name: String, size: Double, weight: NSFont.Weight = .regular, label: String? = nil) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: label)?
            .withSymbolConfiguration(.init(pointSize: size, weight: weight))
    }
}

/// A plain container with top-left origin, like every BrkUI container.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Favicons for Library rows, fetched once per URL (the same cache as BrkOverlays' command bar keeps; BrkLibrary may
/// not import BrkOverlays).
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
