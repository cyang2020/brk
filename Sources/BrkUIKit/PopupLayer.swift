import AppKit

/// Where a popup that can reach over the page goes (hover cards, menus, tooltips, drag images), and the check that
/// none is drawn under a page.
///
/// Pages draw inside the window's own view tree: a content card hosts its page's view (CEF's borrowed Chromium views,
/// BrkCore's WebContents view), and Chromium's host windows are empty. So a popup covers the page exactly when its view
/// is layered above the page's view. The window's content view stacks, bottom to top: the theme background, the
/// sidebar while it is anchored, the content cards, then every overlay. A popup made as a subview of the sidebar, or
/// of any view under the cards, is hidden where it crosses a card.
@MainActor
public enum PopupLayer {
    /// Adds `popup` as the top subview of `anchor`'s window's content view, over the sidebar, the cards and their pages.
    /// `popup.frame` is in that content view's coordinates. False when `anchor` is not in a window.
    @discardableResult
    public static func present(_ popup: NSView, over anchor: NSView) -> Bool {
        guard let root = anchor.window?.contentView else { return false }
        root.addSubview(popup, positioned: .above, relativeTo: nil)
        return true
    }

    /// The window's content view, the coordinates `present` places a popup in.
    public static func root(of anchor: NSView) -> NSView? { anchor.window?.contentView }

    /// Views that show over a page's rectangle while layered under the page, so the page hides them where they cross
    /// it: one line per view (its class, identifier and rectangle in `root`). Empty when every popup is above the pages.
    ///
    /// Only what lies under a page's top-level view (the child of `root` that holds the page) is looked at. A view that
    /// spans the whole page there is a backdrop (the theme background, the inactive veil); any other view that crosses
    /// the page, clipped or not, is a popup at the wrong level.
    public static func coveredByPages(in root: NSView, pages: [NSView]) -> [String] {
        var found: [String] = []
        for page in pages where !page.isHiddenOrHasHiddenAncestor && page.isDescendant(of: root) {
            var top: NSView = page
            while let parent = top.superview, parent !== root { top = parent }
            guard top.superview === root, let index = root.subviews.firstIndex(of: top) else { continue }
            let pageRect = shown(page, in: root)
            guard pageRect.width >= 1, pageRect.height >= 1 else { continue }
            func visit(_ view: NSView) {
                guard !view.isHidden, view.alphaValue > 0.01 else { return }
                let rect = shown(view, in: root)
                let overlap = rect.intersection(pageRect)
                // A view spanning the whole page is a backdrop, under it by design; what it holds is still looked at.
                if !rect.contains(pageRect), !overlap.isNull, overlap.width >= 1, overlap.height >= 1 {
                    let id = view.identifier?.rawValue ?? ""
                    found.append("\(NSStringFromClass(type(of: view)))\(id.isEmpty ? "" : " \(id)") at \(NSStringFromRect(rect)) under the page at \(NSStringFromRect(pageRect))")
                    return
                }
                for subview in view.subviews { visit(subview) }
            }
            for below in root.subviews[..<index] { visit(below) }
        }
        return found
    }

    /// `view`'s frame in `root`, cut to the ancestors that clip it (a scroll view's clip, a layer that masks) and to
    /// the window (a card that slides past the window's edge, as when the Library opens). Not `visibleRect`: AppKit
    /// answers an empty rectangle for a window that is not on screen.
    private static func shown(_ view: NSView, in root: NSView) -> CGRect {
        var rect = view.convert(view.bounds, to: root).intersection(root.bounds)
        var ancestor = view.superview
        while let a = ancestor, a !== root {
            if a.clipsToBounds || a.layer?.masksToBounds == true || a is NSClipView { rect = rect.intersection(a.convert(a.bounds, to: root)) }
            ancestor = a.superview
        }
        return rect.isNull ? .zero : rect
    }
}
