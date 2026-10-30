import AppKit
import BrkBase
import BrkEngine
import CefKit

/// The page surface for the Chrome runtime. Chromium binds a Chrome-runtime browser's compositor to its own window,
/// so we cannot parent the browser into our view; instead, once the browser's host window has its view tree, the
/// two views that draw and take input are moved into this view (the hosting spike's "embed" mode, verified for
/// clipping, clicks, scroll, keys, focus, live resize and chrome:// pages).
///
/// The technique is reimplemented here from what the spike measured about Chromium's view tree; no code is copied
/// from cra (the user ruled it out), although the spike's prototype credits cra for the idea.
@MainActor
final class EmbeddedSurface: PageSurfaceView {
    private weak var chrome: CefChromeBrowser?
    /// Chromium views currently inside this surface, compositor first (bottom), input view above it.
    private var borrowed: [NSView] = []
    /// Where each borrowed view came from, to give it back at close and shutdown.
    private weak var homeView: NSView?

    /// Starts embedding `chrome`'s views. They appear asynchronously (the host window builds its tree after
    /// `on_window_created`), so this polls on the main run loop.
    func adopt(_ chrome: CefChromeBrowser) {
        // TODO(W2):
        // 1. Wait (poll every 50 ms, give up after 10 s and log the host's view tree) until chrome.nsWindow?.contentView
        //    contains a view whose class name is "WebContentsViewCocoa" and one named "ViewsCompositorSuperview".
        // 2. HostWindows.adopt(hostWindow, parent: window): strip .titled/.resizable, clear background, no shadow,
        //    ignoresMouseEvents = true, never key/main (HostWindows key guard), add as child window of our window so it
        //    follows us between spaces and to full screen.
        // 3. homeView = the compositor's current superview; addSubview(compositor); addSubview(webContentsView);
        //    both frame = bounds, autoresizingMask = [.width, .height]; borrowed = [compositor, webContentsView].
        // 4. Keep the host window's frame equal to our screen frame on every layout (`layout()` below), so popups,
        //    IME candidate windows and tooltips that Chromium positions in host-window coordinates land on the card.
        fatalError("not implemented")
    }

    /// Gives the borrowed views back to their host window and detaches the host window from ours. Idempotent. Must
    /// run before the browser closes (shutdown phase 1, and every page close).
    func returnViews() {
        // TODO(W2): for each borrowed view (reverse order): homeView?.addSubview(view); borrowed = [];
        // window?.removeChildWindow(host); HostWindows.release(host).
        fatalError("not implemented")
    }

    override func layout() {
        super.layout()
        // TODO(W2): borrowed views frame = bounds; host window frame = our frame in screen coordinates (one layout
        // behind is harmless: the window is empty, spike "viewport-lag").
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // TODO(W2): window == nil -> chrome?.browser.wasHidden(true) and remove the host window from the old parent;
        // else re-parent the host window as a child of the new window, wasHidden(false).
    }

    var frameInWindow: CGRect? {
        guard let window, let content = window.contentView else { return nil }
        let r = convert(bounds, to: content)
        return content.isFlipped ? r : CGRect(x: r.minX, y: content.bounds.height - r.maxY, width: r.width, height: r.height)
    }

    var embeddedViewClasses: [String] { borrowed.map { NSStringFromClass(type(of: $0)) } }

    var containsFirstResponder: Bool {
        guard let responder = window?.firstResponder as? NSView else { return false }
        return responder.isDescendant(of: self)
    }

    /// Depth-first search by Objective-C class name (Chromium's view classes are private).
    static func find(_ className: String, in root: NSView) -> NSView? {
        if NSStringFromClass(type(of: root)) == className { return root }
        for sub in root.subviews { if let found = find(className, in: sub) { return found } }
        return nil
    }
}
