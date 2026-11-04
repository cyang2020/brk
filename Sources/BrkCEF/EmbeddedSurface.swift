import AppKit
import BrkBase
import BrkEngine
import CefKit
import os

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
    private weak var host: NSWindow?
    /// Chromium views currently inside this surface, compositor first (bottom), each with the superview it came
    /// from, to give it back at close and shutdown.
    private var borrowed: [(view: NSView, home: NSView?)] = []
    private var attempts = 0
    private var retired = false
    private var observedWindow: NSWindow?
    private var nativeFullscreenOwnsFrame = false
    var editableSelection = false
    /// The focused element of the page is a text field or an editing host / an editing host (rich text).
    var editableFocused = false
    var richEditableFocused = false
    /// Edit-menu services carried out on this page (EmbeddedSurface+TextServices.swift), newest last.
    var textServiceLog: [String] = []
    var editingMenuTransport: CefDevTools?
    override var editingMenuResponder: NSResponder? { editingBrowser == nil ? nil : self }
    override func prepareEditingMenu() async { await refreshEditingSupport() }
    private let log = Logger(subsystem: "brk", category: "embed")
    /// Called once Chromium's input view (`RenderWidgetHostViewCocoa`) exists inside the surface, so the page can
    /// take keyboard focus. The renderer creates it a little after the two views are embedded; a focus applied
    /// before that lands on the surface itself and key equivalents fall through to the menu.
    var onReadyForFocus: (() -> Void)?

    /// The host window builds its tree after `on_window_created`; the spike saw the views within a few polls.
    private static let pollInterval: TimeInterval = 0.05
    private static let maxAttempts = 200   // 10 s

    var editingBrowser: CefBrowser? {
        guard !retired, window?.isVisible == true, containsFirstResponder, !isHiddenOrHasHiddenAncestor else { return nil }
        return chrome?.browser
    }
    var isEmbedded: Bool { !borrowed.isEmpty }
    var isReadyForFocus: Bool { isEmbedded && Self.find("RenderWidgetHostViewCocoa", in: self) != nil }

    /// Starts embedding `chrome`'s views, polling on the main run loop until they appear.
    func adopt(_ chrome: CefChromeBrowser) {
        self.chrome = chrome
        attempts = 0
        retired = false
        tryEmbed()
    }

    private func tryEmbed() {
        guard !retired, !isEmbedded, let chrome, chrome.isWindowAlive || chrome.isAwaitingPopupView else { return }
        if let hostWindow = chrome.nsWindow, let content = hostWindow.contentView,
           let compositor = Self.find("ViewsCompositorSuperview", in: content),
           let webContents = Self.find("WebContentsViewCocoa", in: content) {
            host = hostWindow
            HostWindows.adopt(hostWindow, parent: nativeFullscreenOwnsFrame ? nil : window)
            borrowed = [(compositor, compositor.superview), (webContents, webContents.superview)]
            for (view, _) in borrowed {
                addSubview(view)
                view.frame = bounds
                view.autoresizingMask = [.width, .height]
            }
            syncHostFrame()
            log.notice("page \(self.page.description, privacy: .public): embedded after \(self.attempts, privacy: .public) polls into window \(self.window?.windowNumber ?? -1, privacy: .public); host window \(hostWindow.windowNumber, privacy: .public)")
            waitForInputView(attempt: 0)
            return
        }
        attempts += 1
        guard attempts < Self.maxAttempts else {
            let tree = chrome.nsWindow?.contentView.map { Self.describe($0) } ?? ["(no host window)"]
            log.fault("page \(self.page.description, privacy: .public): Chromium's views never appeared; host view tree: \(tree.joined(separator: " | "))")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pollInterval) { [weak self] in self?.tryEmbed() }
    }

    private func waitForInputView(attempt: Int) {
        guard !retired else { return }
        if isReadyForFocus {
            if let input = Self.find("RenderWidgetHostViewCocoa", in: self) { PanelActionRouting.install(on: input); WebTextServices.prepare() }
            log.notice("page \(self.page.description, privacy: .public): input view ready after \(attempt, privacy: .public) polls")
            onReadyForFocus?()
            return
        }
        guard attempt < Self.maxAttempts else {
            log.error("page \(self.page.description, privacy: .public): no RenderWidgetHostViewCocoa appeared; keyboard focus cannot reach the page")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.pollInterval) { [weak self] in self?.waitForInputView(attempt: attempt + 1) }
    }

    /// Hide an unpresented browser while its operations keep its borrowed views and host alive.
    func park() {
        invalidateEditingMenu()
        onReadyForFocus = nil
        removeFromSuperview()
        chrome?.browser.setFocus(false)
        chrome?.browser.wasHidden(true)
        if let host { host.parent?.removeChildWindow(host); host.orderOut(nil) }
        stopObservingMoves()
    }

    /// Gives the borrowed views back to where they came from and detaches the host window from ours. Idempotent;
    /// also stops a pending embed. Must run before the browser closes (shutdown phase 1, and every page close).
    func returnViews() {
        invalidateEditingMenu()
        retired = true
        for (view, home) in borrowed {
            if let home {
                home.addSubview(view)
                view.frame = home.bounds
                view.autoresizingMask = [.width, .height]
            } else {
                view.removeFromSuperview()
            }
        }
        borrowed = []
        if let host { HostWindows.release(host) }
        host = nil
        stopObservingMoves()
    }

    override var acceptsFirstResponder: Bool { true }

    /// The view that takes keyboard focus: Chromium's input view inside the moved views, else the surface itself.
    var keyboardTarget: NSView { Self.find("RenderWidgetHostViewCocoa", in: self) ?? self }

    override func layout() {
        super.layout()
        for (view, _) in borrowed where view.frame != bounds { view.frame = bounds }
        syncHostFrame()
    }

    /// Leaving a window hides the page (Chromium is told); entering one re-parents the host window under it. The
    /// host window follows our window's moves as well as our layout.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopObservingMoves()
        if let window {
            // Borrowed Chromium input views need mouse movement from their new host window.
            window.acceptsMouseMovedEvents = true
            if let host { HostWindows.adopt(host, parent: nativeFullscreenOwnsFrame ? nil : window) }
            syncHostFrame()
            chrome?.browser.wasHidden(false)
            NotificationCenter.default.addObserver(self, selector: #selector(windowDidMove(_:)), name: NSWindow.didMoveNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(windowBecameVisible(_:)), name: NSWindow.didChangeOcclusionStateNotification, object: window)
            NotificationCenter.default.addObserver(self, selector: #selector(windowBecameVisible(_:)), name: NSApplication.didUnhideNotification, object: nil)
            observedWindow = window
        } else {
            chrome?.browser.wasHidden(true)
            if let host { host.parent?.removeChildWindow(host) }
        }
    }

    /// A native fullscreen host cannot simultaneously be a child of another fullscreen window or accept
    /// embedding frame writes. CEF owns that interval; normal parenting/geometry resume after its exit completes.
    func nativeFullscreenChanged(_ fullscreen: Bool, completed: Bool) {
        guard !retired else { return }
        nativeFullscreenOwnsFrame = fullscreen || !completed
        if let host { HostWindows.adopt(host, parent: nativeFullscreenOwnsFrame ? nil : window) }
        if !nativeFullscreenOwnsFrame { syncHostFrame() }
    }

    @objc private func windowDidMove(_ note: Notification) { syncHostFrame() }

    /// Chromium decides whether the page is shown from its own (empty, transparent) host window. After Hide and
    /// Show the window server reports that window as occluded, Chromium hides its input view, and AppKit then skips
    /// it for key equivalents and clicks: Cmd shortcuts went to the menu and clicks to this surface. When our
    /// window is visible again, the page is shown again.
    /// Chromium hides the view a moment after the notification sometimes, so the check runs again for 1.5 s.
    @objc private func windowBecameVisible(_ note: Notification) {
        for delay in [0, 0.15, 0.4, 0.8, 1.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.showInputViewIfHidden() }
        }
    }
    private func showInputViewIfHidden() {
        guard !retired, isEmbedded, !nativeFullscreenOwnsFrame, !NSApp.isHidden, let window, let host, window.isVisible, window.occlusionState.contains(.visible),
              !isHiddenOrHasHiddenAncestor, Self.find("RenderWidgetHostViewCocoa", in: self)?.isHiddenOrHasHiddenAncestor == true else { return }
        log.notice("page \(self.page.description, privacy: .public): input view hidden after the window came back; showing the host again")
        window.removeChildWindow(host)
        host.orderOut(nil)
        window.addChildWindow(host, ordered: .above)
        syncHostFrame()
        chrome?.browser.wasHidden(false)
    }

    private func stopObservingMoves() {
        if let observedWindow {
            NotificationCenter.default.removeObserver(self, name: NSWindow.didMoveNotification, object: observedWindow)
            NotificationCenter.default.removeObserver(self, name: NSWindow.didChangeOcclusionStateNotification, object: observedWindow)
            NotificationCenter.default.removeObserver(self, name: NSApplication.didUnhideNotification, object: nil)
        }
        observedWindow = nil
    }

    /// Keeps the host window's frame equal to our screen frame, so popups, IME candidate windows and tooltips that
    /// Chromium positions in host-window coordinates land on the card (one layout behind is harmless: it is empty).
    private func syncHostFrame() {
        guard !nativeFullscreenOwnsFrame, let host, let window else { return }
        let target = window.convertToScreen(convert(bounds, to: nil))
        if host.frame != target { host.setFrame(target, display: false) }
    }

    var frameInWindow: CGRect? {
        guard let window, let content = window.contentView else { return nil }
        let r = convert(bounds, to: content)
        return content.isFlipped ? r : CGRect(x: r.minX, y: content.bounds.height - r.maxY, width: r.width, height: r.height)
    }

    var embeddedViewClasses: [String] { borrowed.map { NSStringFromClass(type(of: $0.view)) } }

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

    private static func describe(_ view: NSView, depth: Int = 0) -> [String] {
        var out = ["\(String(repeating: "  ", count: depth))\(NSStringFromClass(type(of: view))) \(NSStringFromRect(view.frame))"]
        if depth < 3 { for sub in view.subviews { out += describe(sub, depth: depth + 1) } }
        return out
    }
}
