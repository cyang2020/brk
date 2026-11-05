import AppKit
import BrkBase
import BrkDomain

// Owner: R3-3 (Easels). The board's and the Library cards' numbers and colors. Positions are points measured on this
// round's Arc captures (verify/visual-pairs/run-20261103, a 1280 x 776 pt window): Q09 a is a new Easel in a card
// spanning x 228...1270, y 10...766; P32 c is the Library's Easels page.

let EaselDraw = EaselMetrics()

struct EaselMetrics: MetricGroup {
    let board = EaselBoardMetrics()
    let toolbar = EaselToolbarMetrics()
    let card = EaselCardMetrics()
}

struct EaselBoardMetrics: MetricGroup {
    let titleBox = Metric([628.0, 78.5], .anatomy("Q09 a: the title box spans x 435...1063, y 44.5...123 (its stroke's outer edge)"))
    let titleTop = Metric(34.5, .anatomy("Q09 a: the title box's top is 34.5 below the card's (y 44.5 in a card from y 10)"))
    let titleSideMargin = Metric(64.0, .guess("the title box narrows to keep this much of the card beside it in a narrow window"))
    let titleInset = Metric(3.0, .anatomy("Q09 a: the selected text's highlight starts 3 below the box's outer top"))
    let selectionStroke = Metric(3.0, .anatomy("Q09 a: the title box's blue stroke is 3 pt (x 435...438)"))
    let selectionRadius = Metric(8.0, .guess("the title box's corner radius, from the capture's rounding"))
    let handleRadius = Metric(3.5, .anatomy("Q09 a: the corner handles are 7 pt circles centred on the box's corners"))
    let handleStroke = Metric(1.5, .anatomy("Q09 a: the handles' blue ring"))
    let elementOutset = Metric(6.0, .guess("a selected shape's frame sits this far outside it, so the stroke stays visible"))
    let fontTool = Metric([36.0, 79.5], .anatomy("Q09 a: the + / Aa / − card spans x 386.5...422.5, y 43.5...123"))
    let fontToolGap = Metric(12.5, .anatomy("Q09 a: the card ends 12.5 left of the title box"))
    let fontToolRadius = Metric(8.0, .guess("the + / Aa / − card's corner radius, from the capture's rounding"))
    let fontToolGlyph = Metric(15.0, .anatomy("Q09 a: \"Aa\" is 15 pt (serif), + and − 13 pt"))
    let strokeWidth = Metric(3.0, .guess("Arc's default pen width for shapes, arrows and ink (ARC_EaselUI is not readable)"))
    let arrowHead = Metric(14.0, .guess("the arrow head's sides"))
    let imageRadius = Metric(8.0, .guess("a picture's corner radius on the board"))
    let hitSlop = Metric(8.0, .guess("how far from a line or a stroke a click still picks it"))
    let minimumResize = Metric(8.0, .guess("the smallest box a corner-handle drag leaves"))
}

/// The bottom toolbar (select, image, text, ellipse, rectangle, arrow, freehand | duplicate) and the person button.
struct EaselToolbarMetrics: MetricGroup {
    let margin = Metric(12.0, .anatomy("Q09 a: the toolbar starts 12 right of and ends 12 above the card's edges; the person button sits 12 from the bottom right"))
    let height = Metric(44.0, .anatomy("Q09 a: the toolbar spans y 710...754"))
    let padding = Metric(4.0, .anatomy("Q09 a: the first button starts at x 244, 4 into the toolbar at 240"))
    let button = Metric(36.0, .anatomy("Q09 a: the selected tool's grey square is 36 pt (x 244...280, y 714...750)"))
    let step = Metric(38.0, .anatomy("Q09 a: seven tools from x 244 to the separator at 510: 38 pt apart"))
    let separatorGap = Metric([1.0, 3.0], .anatomy("Q09 a: a 1 pt separator at x 510, the duplicate button 3 pt after it"))
    let radius = Metric(10.0, .guess("the toolbar's corner radius, from the capture's rounding"))
    let buttonRadius = Metric(8.0, .guess("the selected tool's square corner radius"))
    let glyph = Metric(17.0, .anatomy("Q09 a: the tool glyphs are about 17 pt"))
    let person = Metric(44.0, .anatomy("Q09 a: the person button spans x 1214...1258, y 710...754"))
    let shadowBlur = Metric(9.0, .guess("the panels' shadow blur, fitted to Q09 a's soft edge"))
}

/// The Library's Easels page (P32 c, positions from the page column's left at x 112).
struct EaselCardMetrics: MetricGroup {
    let top = Metric(60.0, .anatomy("P32 c: the first row of cards starts at y 60"))
    let leading = Metric(12.0, .anatomy("P32 c: the first card starts at x 124, 12 into the column"))
    let size = Metric(132.0, .anatomy("P32 c: a card is 132 x 132 (x 124...256, y 60...192)"))
    let gap = Metric(16.0, .anatomy("P32 c: the second card starts at x 272, 16 after the first"))
    let inset = Metric(8.0, .anatomy("P32 c: the board inside a card is 116 x 116, 8 from the card's edge"))
    let radius = Metric(14.0, .guess("a card's corner radius, from the capture's rounding"))
    let boardRadius = Metric(9.0, .guess("the board's corner radius inside a card"))
    let boardRim = Metric(3.0, .anatomy("P32 c: a 1 pt grey edge, then 3 pt of white before the board's grey fill"))
    let titleLeading = Metric(10.5, .anatomy("P32 c: the scribble and the title start 10.5 into the board"))
    let titleBottom = Metric(9.7, .anatomy("P32 c: \"Untitled\" starts at y 145.5, the board ends at 184"))
    let titleFont = Metric(13.5, .anatomy("P32 c: \"Untitled\" is 53.5 pt wide in bold"))
    let titleWidth = Metric(78.0, .anatomy("P32 c: \"Untitled Easel\" wraps after \"Untitled\""))
    let scribble = Metric([12.5, 14.5, 12.0, 57.0], .anatomy("P32 c: the red squiggle is 12.5 x 14.5 at x 144, y 125: 12 and 57 into the board"))
}

/// Colors observed on Q09 a and P32 c, and Arc's Easel colors (visual-and-copy.md, ARC_EaselUI).
struct EaselColors {
    /// EaselSelectionColor #6CBAD9: the selected title box and shapes.
    let selection = LibraryColors.srgb(0x6CBAD9)
    /// The board (Q09 a: #FEFEFE).
    let board = LibraryColors.srgb(0xFEFEFE)
    /// The toolbar, the font-size card and the person button (Q09 a: #FDFDFD with a soft shadow).
    let panel = LibraryColors.srgb(0xFDFDFD)
    /// The toolbar's, the font card's and the person button's soft shadow (Q09 a: about 5 % darker 6 pt around them).
    let shadow = NSColor.black.withAlphaComponent(0.16)

    func applyShadow(to layer: CALayer?) {
        layer?.shadowColor = shadow.cgColor
        layer?.shadowOpacity = 1
        layer?.shadowRadius = EaselDraw.toolbar.shadowBlur.value
        layer?.shadowOffset = CGSize(width: 0, height: -1)
    }
    /// A tool's glyph (Q09 a: #575757) and the selected tool's square (#ABABAB) under a white glyph.
    let glyph = LibraryColors.srgb(0x575757)
    let selectedTool = LibraryColors.srgb(0xABABAB)
    let separator = LibraryColors.srgb(0xE7E7E7)
    /// The + and − beside "Aa" (Q09 a: #BBBBBB).
    let fontStep = LibraryColors.srgb(0xBBBBBB)
    /// EaselTitleText #101118 @ 0.8 is the resting title; Q09 a's selected title is black.
    let title = LibraryColors.srgb(0x000000)
    /// Library cards (P32 c): the card #F2F2F1, the board's edge #E0E0E0 and fill #F5F5F5, the scribble #F25E6B,
    /// the title #2A2A2A.
    let card = LibraryColors.srgb(0xF2F2F1)
    let cardHover = LibraryColors.srgb(0xEAEAE9)
    let cardEdge = LibraryColors.srgb(0xE0E0E0)
    let cardBoard = LibraryColors.srgb(0xF5F5F5)
    let scribble = LibraryColors.srgb(0xF25E6B)
    let cardTitle = LibraryColors.srgb(0x2A2A2A)
    /// The same card on a dark theme (Q18-navy-library-easels-arc.png): a band of white 0.05, a board of grey 0.3 inside a
    /// white 0.08 line, the title in the Library's strong ink.
    let darkCard = NSColor(white: 1, alpha: 0.05)
    let darkCardHover = NSColor(white: 1, alpha: 0.09)
    let darkCardEdge = NSColor(white: 1, alpha: 0.08)
    let darkCardBoard = NSColor(white: 0x8C / 255.0, alpha: 0.3)
    let darkCardTitle = NSColor(white: 1, alpha: 0.87)
}

let EaselPalette = EaselColors()

/// The board's tools, in toolbar order (Q09 a). `select` and `image` are not shapes: image opens a file panel.
public enum EaselTool: String, CaseIterable, Sendable {
    case select, image, text, ellipse, rectangle, arrow, pen

    var shape: EaselShape? {
        switch self {
        case .select, .image: nil
        case .text: .text
        case .ellipse: .ellipse
        case .rectangle: .rectangle
        case .arrow: .arrow
        case .pen: .ink
        }
    }

    /// SF Symbols standing in for Arc's EaselIcon* images (Arc's files are not copied); text draws an outlined A.
    var symbol: String? {
        switch self {
        case .select: "cursorarrow"
        case .image: "photo"
        case .text: nil
        case .ellipse: "circle"
        case .rectangle: "square"
        case .arrow: "arrow.up.right"
        case .pen: "scribble"
        }
    }

    var label: String {
        switch self {
        case .select: "Select"
        case .image: "Image"
        case .text: "Text"
        case .ellipse: "Ellipse"
        case .rectangle: "Rectangle"
        case .arrow: "Arrow"
        case .pen: "Freehand"
        }
    }
}
