import AppKit
import BrkBase
import BrkContent
import BrkDomain
import BrkEngine
import BrkLayout
import BrkUIKit
import os

/// One browser window: an NSWindow with a full-size, transparent title bar (traffic lights over the sidebar), its
/// root view, and the glue that turns a `WindowSnapshot` into frames, views, page placement and focus.
@MainActor
public class WindowController: NSObject, NSWindowDelegate {
    public let id: WindowID
    /// Standard, incognito or Little Arc. A `.little` window is hosted by `LittleWindowController` (an NSPanel with
    /// Arc's hint strip and "Open in" control); the store picks the controller by kind.
    public let kind: WindowKind
    public let window: any HostWindow
    let root: WindowRootView
    private let engine: any WebEngine
    let send: @MainActor (Input) -> Void
    private(set) var lastSnapshot: WindowSnapshot?
    private(set) var lastFrames: WindowFrames?
    private var pendingFocus: FocusTarget?
    private var placed = false
    private var pageFullscreen = PageFullscreenTransition()
    var isFullscreenTransitioning: Bool { pageFullscreen.isTransitioning }

    /// `routeKey` answers a `.menu`-stage key input synchronously (`AppStore.dispatchKey`): the window asks it for a
    /// key equivalent its views did not take, so Arc's hidden menu rows ("key works while hidden") and remapped
    /// shortcuts work with a native view focused, where AppKit's menu would not fire for a hidden item.
    convenience init(id: WindowID, kind: WindowKind = .standard, engine: any WebEngine, send: @escaping @MainActor (Input) -> Void,
                     routeKey: @escaping @MainActor (KeyInput) -> Bool = { _ in false }) {
        let window = BrowserWindow(
            contentRect: CGRect(origin: .zero, size: kind == .little ? Metrics.littleArc.defaultSize.value : Metrics.window.defaultSize.value),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        self.init(id: id, kind: kind, engine: engine, send: send, routeKey: routeKey, window: window)
    }

    /// The host window is made by the caller (a `BrowserWindow`, or `LittleWindowController`'s panel); this installs
    /// the root view, the delegate and the two routing hooks every host window shares.
    init(id: WindowID, kind: WindowKind, engine: any WebEngine, send: @escaping @MainActor (Input) -> Void,
         routeKey: @escaping @MainActor (KeyInput) -> Bool, window: any HostWindow) {
        self.id = id
        self.kind = kind
        self.engine = engine
        self.send = send
        self.window = window
        root = WindowRootView(dispatch: { command in send(.user(id, command)) })
        super.init()
        window.isReleasedWhenClosed = false
        window.contentView = root
        window.delegate = self
        // The Ctrl+Tab switcher's page images: the window's own pixels, which include Chromium's.
        root.captureWindow = { [weak window] in (window as? NSWindow).flatMap(WindowCapture.image(of:)) }
        window.onActivity = { [weak self] in
            guard let self else { return }; self.send(.system(.window(self.id, .activity)))
        }
        if kind == .incognito { window.appearance = NSAppearance(named: .darkAqua) }
        window.onPagePointerDown = { [weak self] page in
            guard let self, page.window == self.id,
                  self.lastSnapshot?.content.presentedPanes.contains(where: { $0.content == .page(page) }) == true else { return }
            self.send(.user(self.id, .tab(.focus(page.item))))
        }
        window.onKeyEquivalent = { [weak self] event in
            if event.keyCode == Key.escape.code, TabIconPicker.isOpen { TabIconPicker.close(); return true }
            if event.keyCode == Key.escape.code, self?.cancelSplitDrag() == true { return true }
            guard let input = KeyInput(menuEvent: event) else { return false }
            return routeKey(input)
        }
        window.onEscapeBeforePage = { [weak self] event in
            // The icon popover takes Escape first, from the menu path, the window and the key monitor alike.
            if TabIconPicker.isOpen { TabIconPicker.close(); return true }
            // Site search keeps its first Escape (it leaves the mode, the bar stays) whichever monitor runs first.
            if let self, self.root.commandBar.takeEscape(event) { return true }
            guard let self, self.lastSnapshot?.overlay != nil || self.pageFullscreen.nativeExitShouldExitDocument,
                  let input = KeyInput(menuEvent: event) else { return false }
            return routeKey(input)
        }
        window.onScrollWheel = { [weak root] event in root?.handleScrollWheel(event) ?? false }
        window.onFlagsChanged = { [weak self] flags in
            guard let self else { return }
            let held = Modifiers(rawValue: flags.intersection(.deviceIndependentFlagsMask).rawValue
                & (Modifiers.shift.rawValue | Modifiers.control.rawValue | Modifiers.option.rawValue | Modifiers.command.rawValue))
            self.send(.system(.window(self.id, .modifiersChanged(held: held))))
        }
    }

    func setPageFullScreen(_ on: Bool) {
        tracePageFullscreen("page \(on)")
        pageFullscreen.pageChanged(on, nativeFullscreen: window.styleMask.contains(.fullScreen))
        applyPageFullscreen()
    }
    private func applyPageFullscreen() {
        // AppKit finishes the transition after its delegate returns; toggling inside did-enter is ignored.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.pageFullscreen.needsToggle(nativeFullscreen: self.window.styleMask.contains(.fullScreen)) else { return }
            self.tracePageFullscreen("toggle")
            self.window.toggleFullScreen(nil)
        }
    }
    private func tracePageFullscreen(_ event: String) {
        guard ProcessInfo.processInfo.environment["BRK_CONTROL_SOCKET"] != nil else { return }
        let line = "fullscreen \(ProcessInfo.processInfo.systemUptime) \(event) native=\(window.styleMask.contains(.fullScreen)) state=\(pageFullscreen)\n"
        let windows = NSApp.windows.map { w in
            "\(NSStringFromClass(type(of: w)))#\(w.windowNumber) full=\(w.styleMask.contains(.fullScreen)) key=\(w.isKeyWindow) parent=\(w.parent?.windowNumber ?? -1) collection=\(w.collectionBehavior.rawValue) frame=\(w.frame)"
        }.joined(separator: " | ")
        FileHandle.standardError.write(Data((line + "fullscreen windows active=\(NSApp.isActive) " + windows + "\n").utf8))
    }

    /// Restores the saved frame once (`initialFrame`), before the window is shown. The resulting `windowDidResize`
    /// reports the fitted frame to the store, which queues it behind the current dispatch.
    func place(_ snapshot: WindowSnapshot) {
        guard !placed else { return }
        placed = true
        let screens = NSScreen.screens.map(\.visibleFrame)
        let main = NSScreen.main?.visibleFrame ?? CGRect(origin: .zero, size: Metrics.window.defaultSize.value)
        window.setFrame(initialFrame(for: snapshot, screens: screens, main: main), display: false)
    }

    /// Where the window first appears: the saved frame when it is on a screen, else centered (`WindowPlacement.fit`).
    /// A subclass with another default size answers differently.
    func initialFrame(for snapshot: WindowSnapshot, screens: [CGRect], main: CGRect) -> CGRect {
        WindowPlacement.fit(snapshot.bounds, screens: screens, main: main)
    }

    /// Applies a snapshot: frames = `WindowLayout.compute(snapshot, contentSize)`; `root.render(...)` with
    /// `engine.surface(for:)`; traffic lights to `frames.sidebar?.trafficLightsOrigin`, or the Library panel's (hidden
    /// while the sidebar is hidden; Arc shows them on hover); keyboard focus only when `snapshot.focus` differs from the last one.
    /// Render itself never calls `send`; AppKit's resize and move delegate calls do, and the store queues those.
    func render(_ snapshot: WindowSnapshot) {
        place(snapshot)
        window.level = window.styleMask.contains(.fullScreen) ? .normal : (snapshot.stayOnTop ? .floating : .normal)
        let frames = WindowLayout.compute(snapshot, contentSize: root.bounds.size)
        root.render(snapshot, frames: frames, surface: { [engine, id] page in page.window == id ? engine.surface(for: page) : nil })
        // The Library's panel keeps them where the sidebar had them (P32: Arc shows them over its navigation column).
        window.placeTrafficLights(origin: frames.sidebarFloats ? nil : frames.sidebar?.trafficLightsOrigin ?? frames.library.map { LibraryLayout.trafficLightsOrigin(in: $0.strip) })
        window.backgroundColor = NSColor(srgbRed: snapshot.theme.windowColor.red, green: snapshot.theme.windowColor.green,
                                         blue: snapshot.theme.windowColor.blue, alpha: 1)
        let repeatedFind = snapshot.focus == .findInput && snapshot.find?.focusRequest != lastSnapshot?.find?.focusRequest
        let repeatedReveal = snapshot.focus == .sidebar && snapshot.tabTools.revealGeneration != lastSnapshot?.tabTools.revealGeneration
        if snapshot.focus != lastSnapshot?.focus || repeatedFind || repeatedReveal || pendingFocus != nil {
            pendingFocus = nil
            applyFocus(snapshot.focus)
        }
        lastSnapshot = snapshot
        lastFrames = frames
    }

    /// Keyboard focus follows the snapshot: a page gets it through the engine, a native view through the root's
    /// narrow focus API; nothing else in BrkApp touches a view's responder status.
    func applyFocus(_ target: FocusTarget) {
        switch target {
        case .page(let page):
            engine.focus(page, in: window)
        case .none:
            engine.focus(nil, in: window)
        case .capture, .findInput, .commandBarInput, .renameField, .spaceDialog, .profileDialog, .sidebar:
            engine.focus(nil, in: window)
            if !root.focus(target) {
                // The view is not on screen yet (same render that opened it): re-applied by the next render.
                pendingFocus = target
            }
        }
    }

    func cancelSplitDrag() -> Bool { root.cancelDrag() }

    // MARK: NSWindowDelegate -> WindowEvent

    public func windowDidResize(_ notification: Notification) { reportGeometry() }
    public func windowDidMove(_ notification: Notification) { reportGeometry() }
    public func windowWillClose(_ notification: Notification) {
        root.cancelDrag()
        send(.system(.window(id, .closed)))
    }
    public func windowDidResignKey(_ notification: Notification) {
        root.cancelDrag()
        send(.system(.window(id, .resignedKey)))
    }

    /// Becoming key again (app switch, a closed overlay panel) re-applies the snapshot's focus, so a page gets its
    /// Chromium view back as first responder and a native field keeps its own.
    public func windowDidBecomeKey(_ notification: Notification) {
        send(.system(.window(id, .becameKey)))
        if let last = lastSnapshot { applyFocus(last.focus) }
    }

    public func windowWillEnterFullScreen(_ notification: Notification) {
        tracePageFullscreen("will enter"); pageFullscreen.nativeWillChange(to: true)
    }
    public func windowWillExitFullScreen(_ notification: Notification) {
        tracePageFullscreen("will exit"); pageFullscreen.nativeWillChange(to: false)
    }
    public func windowDidEnterFullScreen(_ notification: Notification) {
        tracePageFullscreen("did enter")
        pageFullscreen.nativeDidChange(); window.level = .normal; applyPageFullscreen()
    }
    public func windowDidFailToEnterFullScreen(_ window: NSWindow) { fullscreenTransitionFailed() }
    public func windowDidFailToExitFullScreen(_ window: NSWindow) { fullscreenTransitionFailed() }
    private func fullscreenTransitionFailed() {
        tracePageFullscreen("failed")
        if pageFullscreen.nativeFailed(nativeFullscreen: window.styleMask.contains(.fullScreen)) {
            for pane in lastSnapshot?.content.presentedPanes ?? [] {
                if case .page(let page) = pane.content { engine.perform(.exitFullscreen, on: page) }
            }
        }
    }
    public func windowDidExitFullScreen(_ notification: Notification) {
        tracePageFullscreen("did exit")
        if pageFullscreen.nativeExited() {
            for pane in lastSnapshot?.content.presentedPanes ?? [] {
                if case .page(let page) = pane.content { engine.perform(.exitFullscreen, on: page) }
            }
        }
        applyPageFullscreen()
        window.level = lastSnapshot?.stayOnTop == true ? .floating : .normal
    }

    /// Deferred native layout can clear Chromium's responder after the last page callback. Repair only the
    /// window fallback, using this window's current intent. A native editor, hidden window, or moved page wins.
    public func windowDidUpdate(_ notification: Notification) {
        guard window.isVisible, window.firstResponder == nil || window.firstResponder === window,
              case .page(let page) = lastSnapshot?.focus,
              let surface = engine.surface(for: page), surface.window === window,
              !surface.isHiddenOrHasHiddenAncestor else { return }
        engine.focus(page, in: window)
    }

    private func reportGeometry() {
        let content = root.bounds.size
        send(.system(.window(id, .geometry(bounds: window.frame, contentSize: content))))
    }
}

/// What a browser host window adds to NSWindow: the two routing hooks the controller installs. `BrowserWindow`
/// (standard and incognito windows) and `BrowserPanel` (Little Arc) conform; the shared event handling is in the
/// extension, so both classes' `sendEvent` and `performKeyEquivalent` overrides are one line each.
@MainActor
public protocol HostWindow: NSWindow {
    var onActivity: (() -> Void)? { get set }
    /// Called for every `flagsChanged` (and every mouse-down, which carries the modifiers held at that moment), so
    /// Control going up or down and a Shift held for a click reach the reducer whoever has focus.
    var onFlagsChanged: ((NSEvent.ModifierFlags) -> Void)? { get set }
    var onScrollWheel: ((NSEvent) -> Bool)? { get set }
    /// A key equivalent the window's views did not take (a native view has focus, or none): the shortcut table
    /// decides before AppKit's menu, so hidden rows and user remaps work. Returns whether it was consumed.
    var onKeyEquivalent: ((NSEvent) -> Bool)? { get set }
    var onEscapeBeforePage: ((NSEvent) -> Bool)? { get set }
    var onPagePointerDown: ((PageID) -> Void)? { get set }
    /// Arc's title row lights, or hidden (nil) while the sidebar is hidden.
    func placeTrafficLights(origin: CGPoint?)
}

private let keyLog = Logger(subsystem: "brk", category: "keys")

extension HostWindow {
    /// The first step of `sendEvent`. Reports modifiers: every `flagsChanged`, and every mouse-down (the event
    /// carries the modifiers held at that moment, so a Shift+click is known to the reducer even when the
    /// `flagsChanged` went to another window or was never sent, as the control socket's injected clicks are).
    /// Then, with a native view (or nothing) focused, the table decides a key-down first, the way Arc's key-binding
    /// layer does before AppKit's menu: AppKit never fires a hidden menu item's key equivalent and only offers
    /// Command chords to `performKeyEquivalent`, so Ctrl+Tab and Arc's hidden rows would otherwise die here. An
    /// unbound key (typing in a field) is not consumed and takes the normal path. With a page view focused Chromium
    /// gets the event and CEF's key handler routes it (before and after the page). Returns true when consumed.
    func hostEvent(_ event: NSEvent) -> Bool {
        // Chrome handles fullscreen Escape before CEF's pre-key callback. Give an open native overlay the
        // table's menu path first, so Exit dismisses it before Chrome leaves the document's fullscreen.
        if event.type == .keyDown, event.keyCode == Key.escape.code, onEscapeBeforePage?(event) == true { return true }
        if [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel].contains(event.type) { onActivity?() }
        if event.type == .scrollWheel, onScrollWheel?(event) == true { return true }
        switch event.type {
        case .flagsChanged: onFlagsChanged?(event.modifierFlags)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            // Control stays the keyboard's report alone: a click while Control is held mid Ctrl+Tab walk would otherwise
            // read as a repeated report, which the reducer takes for a missed release and commits the walk.
            if !event.modifierFlags.contains(.control) { onFlagsChanged?(event.modifierFlags) }
            if event.type == .leftMouseDown,
               let hit = contentView?.superview?.hitTest(event.locationInWindow) ?? contentView?.hitTest(event.locationInWindow),
               let surface = Self.surface(containing: hit), surface.window === self, !surface.isHiddenOrHasHiddenAncestor {
                onPagePointerDown?(surface.page)
            }
        default: break
        }
        if event.type == .keyDown, !event.modifierFlags.intersection([.command, .control]).isEmpty {
            keyLog.notice("window.sendEvent keyDown code=\(event.keyCode, privacy: .public) eventWindow=\(event.windowNumber, privacy: .public) firstResponder=\(Self.describe(self.firstResponder), privacy: .public)")
        }
        return event.type == .keyDown && (Self.surface(containing: firstResponder)?.routesKeysThroughWindow ?? true) && routeKeyEquivalent(event)
    }

    /// `performKeyEquivalent`'s tail: the views' answer, logged, then the table's turn. With a page focused
    /// Chromium's view already took the event, so the table only runs with a native view (or nothing) focused.
    func hostKeyEquivalent(_ event: NSEvent, handledByViews handled: Bool) -> Bool {
        keyLog.notice("window.performKeyEquivalent code=\(event.keyCode, privacy: .public) handledByViews=\(handled, privacy: .public) firstResponder=\(Self.describe(self.firstResponder), privacy: .public)")
        return handled || routeKeyEquivalent(event)
    }

    /// The table's turn after the views. Also called by the control socket's injector, which delivers to the
    /// content view and the menu by hand when the window is not key.
    public func routeKeyEquivalent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, let route = onKeyEquivalent else { return false }
        let routed = route(event)
        if routed { keyLog.notice("window.routeKeyEquivalent code=\(event.keyCode, privacy: .public) consumed by the table") }
        return routed
    }

    /// The page surface the responder sits in (the engine's views), if any.
    static func surface(containing responder: NSResponder?) -> PageSurfaceView? {
        var view = responder as? NSView
        while let v = view {
            if let surface = v as? PageSurfaceView { return surface }
            view = v.superview
        }
        return nil
    }

    static func describe(_ responder: NSResponder?) -> String {
        guard let responder else { return "nil" }
        return NSStringFromClass(type(of: responder))
    }

    /// Arc's title row: lights at x 13 with 14 pt buttons on a 23 pt pitch, centred 24 pt from the top. `origin` is in
    /// the window's top-left content space; nil hides them (sidebar hidden).
    func placeArcTrafficLights(origin: CGPoint?) {
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { standardWindowButton($0) }
        guard let origin, let container = buttons.first?.superview else {
            buttons.forEach { $0.isHidden = true }
            return
        }
        let pitch = Metrics.window.trafficLightSize.value + Metrics.window.trafficLightSpacing.value
        for (i, button) in buttons.enumerated() {
            button.isHidden = false
            let size = button.frame.size
            let x = origin.x + Double(i) * pitch
            // The titlebar container is not flipped: convert the top-left origin to AppKit's bottom-left.
            let y = container.bounds.height - origin.y - size.height
            button.setFrameOrigin(CGPoint(x: x, y: y))
        }
    }
}

/// The browser window. Never lets CEF's host windows take key status from it (they are its child windows).
@MainActor
public final class BrowserWindow: NSWindow, HostWindow {
    public var onActivity: (() -> Void)?
    public var onFlagsChanged: ((NSEvent.ModifierFlags) -> Void)?
    public var onScrollWheel: ((NSEvent) -> Bool)?
    public var onKeyEquivalent: ((NSEvent) -> Bool)?
    public var onEscapeBeforePage: ((NSEvent) -> Bool)?
    public var onPagePointerDown: ((PageID) -> Void)?

    public override func sendEvent(_ event: NSEvent) {
        if hostEvent(event) { return }
        super.sendEvent(event)
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        hostKeyEquivalent(event, handledByViews: super.performKeyEquivalent(with: event))
    }

    public func placeTrafficLights(origin: CGPoint?) { placeArcTrafficLights(origin: origin) }
}
