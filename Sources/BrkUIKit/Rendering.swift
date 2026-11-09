import AppKit
import BrkBase
import BrkDomain
import BrkLayout

/// How views send intent: one closure, given by the window controller, that dispatches `.user(window, command)` to
/// the app's store. Views never mutate app state and never hold a reference to the store.
public typealias Dispatch = @MainActor (Command) -> Void

// The rendering contract every BrkUI view follows (there is no protocol for it; render signatures differ by what
// each view needs):
// - `render(...)` receives its slice of the snapshot and its frames, and makes the view match. Idempotent: the same
//   input twice changes nothing; a view compares the new slice with the last one (Equatable) and returns early.
// - Frames come from `WindowFrames`; a view never computes a position itself (BrkLayout owns geometry).
// - Transient interaction state (hover, pressed, drag preview, typed query, scroll offset) stays in the view; it is
//   not app state. Anything that must survive a re-render or be visible to another view is a command instead.
// - Each addressable view sets its accessibility identifier from `ViewID` (`identify(_:)`), never a string literal.

extension NSView {
    @MainActor public func identify(_ id: ViewID) {
        setAccessibilityIdentifier(id.identifier)
    }
}

extension NSTextField {
    /// The frame width a one-line label needs. Its cell draws the text 2 points in from each side, and on current macOS
    /// `intrinsicContentSize` leaves one of those out: a frame of that width cuts the last letter or, with a truncating
    /// line break, ends a text that fits with an ellipsis.
    public var cellWidth: Double { ceil(cell?.cellSize.width ?? fittingSize.width) }
}

/// NSColors for the current theme, built once per theme change from `ResolvedTheme.tokens`.
public struct Palette: Equatable {
    public let scheme: Scheme
    public let tokens: SidebarTokens
    /// The space's primary color (the gradient's first stop). Arc tints the folder glyph and the empty favicon with
    /// its hue.
    public let accent: RGBA

    public init(_ theme: ResolvedTheme) {
        scheme = theme.scheme
        tokens = theme.tokens
        accent = theme.gradient.first ?? RGBA(0.5, 0.5, 0.5)
    }

    public func color(_ rgba: RGBA) -> NSColor {
        NSColor(srgbRed: rgba.red, green: rgba.green, blue: rgba.blue, alpha: rgba.alpha)
    }

    /// Arc's `focus` palette color, seen as its split focus ring (P23-a, P23-c): light, the theme's hue and saturation at
    /// relative luminance 0.097; dark, a lighter shade of the hue (the same numbers as `ThemeAccent.splitFocusRing`).
    /// Brk's own Space-colored marks use it too: a kept page's new-data dot and the AI panel's send button and links.
    public var focusColor: NSColor {
        if scheme == .light { return color(themeShade(accent, luminance: 0.097)) }
        var hue: CGFloat = 0, saturation: CGFloat = 0, value: CGFloat = 0, alpha: CGFloat = 0
        NSColor(srgbRed: accent.red, green: accent.green, blue: accent.blue, alpha: 1).getHue(&hue, saturation: &saturation, brightness: &value, alpha: &alpha)
        return NSColor(hue: hue, saturation: min(0.53, saturation * 9), brightness: 0.8, alpha: 1)
    }
}

/// Arc's English copy used by the core views (visual-and-copy.md section 3). One place, so views and e2e agree.
public enum Copy {
    public static let urlPlaceholder = "Search or Enter URL…"
    public static let newTab = "New Tab"
    public static let clearToday = "Clear"
    /// bin:0x10394f670: the tooltip when the ↓ shows; bin:0x10394f6c0: the tooltip without it.
    public static let clearTodayAll = "Clear Today tabs"
    public static let clearTodayOthers = "Clear unselected Today tabs"
    public static let favoritesEmptyTitle = "Drag to add Favorites"
    public static let favoritesEmptySubtitle = "Favorites keep your most used sites and apps close"
    public static let archiveTabTooltip = "Archive this tab"
    public static let archiveEmpty = "Hover your mouse over a tab and press the × to archive it."
    public static let clearArchiveConfirm = "Are you sure you'd like to Clear Archive?"
    public static let deleteFolderWarning = "Deleting this folder will archive the tabs inside it."
    /// Arc's auto-archive banner (`bin:0x103a0cc20`: "Arc archives tabs that you haven’t used in the past 12 hours. You
    /// can adjust this in %@Settings%@."), the product's own name for Arc's; `archiveEducationLink` is the linked word.
    public static func archiveEducation(_ threshold: String) -> String {
        "\(Product.name) archives tabs that you haven’t used in the past \(threshold). You can adjust this in \(archiveEducationLink)."
    }
    public static let archiveEducationLink = "Settings"
}
