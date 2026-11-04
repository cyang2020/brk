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
}

/// Arc's English copy used by the core views (visual-and-copy.md section 3). One place, so views and e2e agree.
public enum Copy {
    public static let urlPlaceholder = "Search or Enter URL…"
    public static let newTab = "New Tab"
    public static let clearToday = "Clear"
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
