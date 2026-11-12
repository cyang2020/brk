import AppKit
import BrkBase
import BrkControl
import BrkEngine

/// Reads the live view tree for the control socket: views by accessibility identifier, attached page surfaces, the
/// first responder. Read-only; nothing here changes a view.
@MainActor
enum ViewTree {
    /// Every view in the window (title bar included) with a non-empty accessibility identifier, plus the three
    /// traffic lights under `windowButtons` keys: frame in `root`'s coordinates (top-left, flipped), hidden flag
    /// (itself or an ancestor), layer corner radius. When two views share an identifier the visible one wins, then the
    /// first in back-to-front order.
    static func identified(in window: NSWindow, relativeTo root: NSView) -> [String: ActualView] {
        var out: [String: ActualView] = [:]
        guard let top = window.contentView?.superview ?? window.contentView else { return out }
        walk(top) { view in
            let id = view.accessibilityIdentifier()
            guard !id.isEmpty else { return }
            let fact = ActualView(frame: view.convert(view.bounds, to: root), hidden: view.isHiddenOrHasHiddenAncestor,
                                  cornerRadius: Double(view.layer?.cornerRadius ?? 0))
            if let existing = out[id], !(existing.hidden && !fact.hidden) { return }
            out[id] = fact
        }
        for (type, key) in windowButtons {
            guard let button = window.standardWindowButton(type) else { continue }
            out[key] = ActualView(frame: button.convert(button.bounds, to: root), hidden: button.isHiddenOrHasHiddenAncestor,
                                  cornerRadius: Double(button.layer?.cornerRadius ?? 0))
        }
        return out
    }

    /// AppKit's traffic lights have no accessibility identifier; they are reported under these keys (N3 checks their
    /// position and size against Metrics.window).
    static let windowButtons: [(NSWindow.ButtonType, String)] = [
        (.closeButton, "window-close-button"), (.miniaturizeButton, "window-minimize-button"), (.zoomButton, "window-zoom-button"),
    ]

    /// The visible view with this identifier, if any (hidden ones only when nothing visible has it).
    static func find(_ identifier: String, in window: NSWindow) -> NSView? {
        guard let top = window.contentView?.superview ?? window.contentView else { return nil }
        var hidden: NSView?
        var found: NSView?
        walk(top) { view in
            guard found == nil, view.accessibilityIdentifier() == identifier else { return }
            if view.isHiddenOrHasHiddenAncestor { hidden = hidden ?? view } else { found = view }
        }
        return found ?? hidden
    }

    /// Pages whose surface is inside `root` right now, in back-to-front order.
    static func surfaces(in root: NSView) -> [PageID] {
        var out: [PageID] = []
        walk(root) { view in
            if let surface = view as? PageSurfaceView, !out.contains(surface.page) { out.append(surface.page) }
        }
        return out
    }

    /// Every page surface view under `root`.
    static func surfaceViews(in root: NSView) -> [NSView] {
        var out: [NSView] = []
        walk(root) { view in if view is PageSurfaceView { out.append(view) } }
        return out
    }

    /// The page whose surface contains `responder`, if it is a view inside one.
    static func page(containing responder: NSResponder?) -> PageID? {
        var view = responder as? NSView
        while let v = view {
            if let surface = v as? PageSurfaceView { return surface.page }
            view = v.superview
        }
        return nil
    }

    /// "ClassName", plus ":identifier" when the responder (or, for a field editor, the field it edits) has one:
    /// "NSTextView:command-bar-input" while the command bar's input is being edited.
    static func describe(_ responder: NSResponder?) -> String {
        guard let responder else { return "nil" }
        let name = NSStringFromClass(type(of: responder))
        var identified: NSView? = responder as? NSView
        if let text = responder as? NSTextView, text.isFieldEditor, let field = text.delegate as? NSView { identified = field }
        if let id = identified?.accessibilityIdentifier(), !id.isEmpty { return "\(name):\(id)" }
        if let page = page(containing: responder) { return "\(name):page-\(page)" }
        return name
    }

    static func walk(_ view: NSView, _ visit: (NSView) -> Void) {
        visit(view)
        for subview in view.subviews { walk(subview, visit) }
    }
}
