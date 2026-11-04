import BrkBase
import CoreGraphics
import Foundation

// Easels (Arc: `SidebarEasel`, `WindowContent.Blueprint.easel`, `ARC_EaselUI`): a whiteboard that lives in a sidebar
// row like a tab and draws in its card instead of a page. Arc keeps an Easel's board on its servers and shares it
// by link; Brk keeps it in the saved state (`Doc.easels`, written to state.json with everything else) and copies
// inserted pictures into the data directory (BrkApp/EaselFiles.swift). Share writes a PNG of the board to a file.
//
// The row is a tab at `EaselPage.url(id)`: it moves, pins, archives and restores like any tab, has no browser
// (`projectPages` lists none) and its card hosts the board (`PaneContent.easel`). Deleting the Easel (the Library
// card's menu, after Arc's confirmation) removes the board, its pictures and every row that shows it.

/// The address of an Easel's row. A tab at such an address has no browser: its card draws the board natively.
public enum EaselPage {
    public static func url(_ id: EaselID) -> URL { URL(string: "brk://easel/" + id.rawValue)! }

    /// The Easel `url` shows, nil for any other address.
    public static func id(of url: URL?) -> EaselID? {
        guard let url, url.scheme == "brk", url.host == "easel" else { return nil }
        let raw = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return raw.isEmpty || raw.contains("/") ? nil : EaselID(raw)
    }

    public static func shows(_ url: URL?) -> Bool { id(of: url) != nil }

    /// Observed on Q09 a: the new Easel's row, its title box and its Library card all read "Untitled Easel".
    public static let defaultTitle = "Untitled Easel"

    /// The row's icon (Arc: `ARC_Favicons` Easel favicon, Q09 a): Arc's squiggle in dark grey on a white tile, as an
    /// SVG data URL so the sidebar's favicon loader draws it like any other. The path is `EaselPage.squiggle` (traced
    /// on P32 c) through its midpoints.
    public static let favicon = URL(string: "data:image/svg+xml;base64," + Data((
        #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="32" height="32">"#
            + ##"<rect x="0.5" y="0.5" width="15" height="15" rx="3.5" fill="#FFFFFF"/>"##
            + #"<path d="M10.37 13.60 Q3.27 6.74 3.58 5.79 Q3.90 4.85 4.61 4.92 Q5.32 5.00 7.68 7.61 Q10.05 10.21 10.84 10.37 "#
            + #"Q11.63 10.52 11.86 9.89 Q12.10 9.26 10.37 6.97 Q8.63 4.69 8.87 3.82 Q9.10 2.95 9.81 2.68 Q10.52 2.40 11.39 2.52 "#
            + ##"Q12.26 2.64 12.50 3.27 L12.73 3.90" fill="none" stroke="#3A3A3A" stroke-width="1.7" stroke-linecap="round" "##
            + #"stroke-linejoin="round"/></svg>"#
    ).utf8).base64EncodedString())!

    /// Arc's Easel squiggle (the sidebar row, the Library card, the freehand tool), traced on P32 c, in a unit box:
    /// drawn through the midpoints of these points so its turns are round.
    public static let squiggle: [CGPoint] = [
        CGPoint(x: 0.75, y: 1.0), CGPoint(x: 0.0, y: 0.387), CGPoint(x: 0.067, y: 0.218), CGPoint(x: 0.217, y: 0.232),
        CGPoint(x: 0.717, y: 0.697), CGPoint(x: 0.883, y: 0.725), CGPoint(x: 0.933, y: 0.613), CGPoint(x: 0.567, y: 0.204),
        CGPoint(x: 0.617, y: 0.049), CGPoint(x: 0.767, y: 0.0), CGPoint(x: 0.95, y: 0.021), CGPoint(x: 1.0, y: 0.134),
    ]
}

/// Words Arc shows around an Easel (observed on Q09 a and Q09 c).
public enum EaselCopy {
    /// The URL pill of a card showing an Easel.
    public static let share = "Share"
    public static let deleteTitle = "Are you sure you want to delete this Easel?"
    public static let deleteBody = "Doing so will delete the Easel permanently."
    public static let delete = "Delete"
}

/// What a board element is. Arc's tools (Q09 a, left to right): select, image, text, ellipse, rectangle, arrow,
/// freehand; select and image are not shapes.
public enum EaselShape: String, Hashable, Sendable, Codable, CaseIterable {
    case text, ellipse, rectangle, arrow, ink, image
}

/// Arc's Easel inks (`Vibrant.Easel*`, visual-and-copy.md). Elements are drawn in black unless recoloured.
public enum EaselInk: String, Hashable, Sendable, Codable, CaseIterable {
    case black, darkBlue, darkGreen, grey, lightBlue, lightGreen, pink, purple, red, yellow

    /// Vibrant.Easel* light values (visual-and-copy.md).
    public var rgba: RGBA {
        switch self {
        case .black: RGBA(hex: "#000000")
        case .darkBlue: RGBA(hex: "#3139FB")
        case .darkGreen: RGBA(hex: "#107A00")
        case .grey: RGBA(hex: "#BBBBBB")
        case .lightBlue: RGBA(hex: "#00C7F3")
        case .lightGreen: RGBA(hex: "#34E895")
        case .pink: RGBA(hex: "#FF994E")
        case .purple: RGBA(hex: "#C0009F")
        case .red: RGBA(hex: "#F53714")
        case .yellow: RGBA(hex: "#FFD335")
        }
    }
}

/// One thing on a board. Coordinates are board points with x measured from the board's horizontal centre and y down
/// from its top, so the board keeps its drawing centred under the title when the window is resized (Arc centres the
/// title box in the card, Q09 a).
public struct EaselElement: Hashable, Sendable, Codable, Identifiable {
    public var id: String
    public var shape: EaselShape
    /// Text, shapes and images: their box. Arrows and ink: the bounding box of `points`.
    public var frame: CGRect
    /// Arrow: start then end. Ink: the stroke, in order. Empty for the other shapes.
    public var points: [CGPoint]
    /// Text boxes only.
    public var text: String
    public var fontSize: Double
    public var ink: EaselInk
    /// Images only: the copy in the data directory (BrkApp/EaselFiles.swift).
    public var image: URL?

    public init(id: String, shape: EaselShape, frame: CGRect, points: [CGPoint] = [], text: String = "", fontSize: Double = EaselElement.textSize,
                ink: EaselInk = .black, image: URL? = nil) {
        self.id = id
        self.shape = shape
        self.frame = frame
        self.points = points
        self.text = text
        self.fontSize = fontSize
        self.ink = ink
        self.image = image
    }

    /// A text box's default size (Arc's FontSizeBody; guessed, Arc's style sheet is not readable).
    public static let textSize = 18.0

    /// The element moved by `offset` (its box and its points).
    public func moved(by offset: CGSize) -> EaselElement {
        var copy = self
        copy.frame = frame.offsetBy(dx: offset.width, dy: offset.height)
        copy.points = points.map { CGPoint(x: $0.x + offset.width, y: $0.y + offset.height) }
        return copy
    }

    /// The element stretched from `from` to `to` (a corner handle's drag on the selection): its box and its points keep
    /// their place relative to the selection's box. A text keeps its font size.
    public func resized(from: CGRect, to: CGRect) -> EaselElement {
        guard from.width > 0, from.height > 0 else { return self }
        let sx = to.width / from.width, sy = to.height / from.height
        func map(_ p: CGPoint) -> CGPoint { CGPoint(x: to.minX + (p.x - from.minX) * sx, y: to.minY + (p.y - from.minY) * sy) }
        var copy = self
        copy.points = points.map(map)
        let origin = map(frame.origin)
        copy.frame = points.isEmpty ? CGRect(x: origin.x, y: origin.y, width: frame.width * sx, height: frame.height * sy) : EaselElement.bounds(of: copy.points)
        return copy
    }

    /// The smallest box around `points` (an arrow's or a stroke's frame).
    public static func bounds(of points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .zero }
        var box = CGRect(origin: first, size: .zero)
        for point in points.dropFirst() { box = box.union(CGRect(origin: point, size: .zero)) }
        return box
    }
}

/// What a board card shows (`WindowSnapshot.easels`, one per card showing an Easel).
public struct EaselSnapshot: Hashable, Sendable, Codable {
    public var id: EaselID
    /// The card showing it (`PaneContent.easel`).
    public var page: PageID
    public var title: String
    /// The title box's font size, changed by the + / − buttons beside it (Arc's FontSizeH1, H2, Body).
    public var titleSize: Double
    public var elements: [EaselElement]
    /// Just created: the title box is selected with its text highlighted, ready to type over (Q09 a).
    public var editingTitle: Bool
    /// A picture could not be added or the board could not be shared.
    public var message: String?
}

/// One card of the Library's Easels page (P32 c): its title and a small drawing of its board.
public struct EaselCard: Hashable, Sendable, Codable, Identifiable {
    public var id: EaselID
    public var title: String
    public var titleSize: Double
    public var elements: [EaselElement]
    public var modifiedAt: Instant
}

/// Arc's delete confirmation (Q09 c), waiting for Cancel or Delete.
public struct EaselDeletionRequest: Hashable, Sendable, Codable {
    public let id: EaselID
    public let title: String
    public let token: String
}

public enum EaselCommand: Hashable, Sendable, Codable {
    /// File > New Easel (Ctrl+Shift+E): an Untitled Easel, its row at the end of the space's Pinned, shown with its
    /// title selected.
    case create
    /// A Library card: shows the Easel's row in this space, or adds one at the end of Pinned when it has none here.
    case open(EaselID)
    /// The title box was edited. A blank title keeps the old one.
    case rename(EaselID, title: String)
    /// The title box's + (1) and − (-1): the next of Arc's three title sizes.
    case stepTitleSize(EaselID, by: Int)
    case add(EaselID, EaselElement)
    /// Moved, resized or retyped elements, replaced by id. An emptied text box is removed.
    case update(EaselID, [EaselElement])
    case remove(EaselID, [String])
    /// The toolbar's duplicate button: copies of the elements, offset down and right, selected afterwards by the view.
    case duplicate(EaselID, [String])
    /// The image tool: a file panel for a picture, placed centred on `at` (board points).
    case chooseImage(EaselID, at: CGPoint)
    /// A picture file (chosen in the panel or dropped on the board) is copied into the data directory and placed.
    case importImage(EaselID, from: URL, at: CGPoint)
    /// The URL pill's Share: the board as a PNG, through a save panel (this project shares by file, not by link).
    case share(EaselID)
    case requestDelete(EaselID)
    case confirmDelete(EaselID, token: String, confirmed: Bool)
}

public enum EaselEffect: Hashable, Sendable {
    case chooseImage(WindowID, EaselID, at: CGPoint)
    /// Copy `source` into the Easel's folder; answered by `EaselEvent.imageImported` or `.failed`.
    case importImage(WindowID, EaselID, from: URL, at: CGPoint, element: String)
    /// Ask where to save the board's PNG and write it; answered by `EaselEvent.shared` or `.failed`.
    case share(WindowID, EaselCard)
    /// The Easel was deleted: remove its folder of pictures.
    case deleteFiles(EaselID)
}

public enum EaselEvent: Sendable, Equatable {
    /// The copy of a picture is in place; `size` is its size in points (the element keeps it, scaled down to fit).
    case imageImported(WindowID, EaselID, element: String, file: URL, size: CGSize, at: CGPoint)
    case shared(WindowID, EaselID, URL)
    case failed(WindowID, EaselID, String)
}

/// Saved. Arc: `SidebarEasel` (`easelID`, `title`) plus the board Arc keeps on its servers.
struct Easel: Sendable, Equatable {
    let id: EaselID
    var title: String
    var titleSize: Double
    let createdAt: Instant
    var modifiedAt: Instant
    /// The profile whose Library lists it (the space's profile when it was created).
    var profile: ProfileID
    var elements: [EaselElement]
}

/// Arc's three title sizes (FontSizeH1, H2, Body in `ARC_EaselUI`), largest first. H1 is measured on Q09 a (the
/// 162 pt wide "Untitled Easel" in bold); H2 and Body are guesses.
enum EaselTitleSizes {
    static let all: [Double] = [25, 20, 16]
    static let `default` = all[0]

    static func step(_ size: Double, by delta: Int) -> Double {
        let index = all.firstIndex(of: size) ?? 0
        return all[min(all.count - 1, max(0, index - delta))]
    }
}
