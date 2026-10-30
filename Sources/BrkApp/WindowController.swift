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
public final class WindowController: NSObject, NSWindowDelegate {
    public let id: WindowID
    /// Standard, incognito or Little Arc. TODO(F3): a `LittleWindowController` over an NSPanel for `.little`; today
    /// the little window is a standard window at Little Arc's default size with no sidebar.
    public let kind: WindowKind
    public let window: BrowserWindow
    let root: WindowRootView
    private let engine: any WebEngine
    private let send: @MainActor (Input) -> Void
    private(set) var lastSnapshot: WindowSnapshot?
    private(set) var lastFrames: WindowFrames?
    private var pendingFocus: FocusTarget?
    private var placed = false

    /// `routeKey` answers a `.menu`-stage key input synchronously (`AppStore.dispatchKey`): the window asks it for a
    /// key equivalent its views did not take, so Arc's hidden menu rows ("key works while hidden") and remapped
    /// shortcuts work with a native view focused, where AppKit's menu would not fire for a hidden item.
    init(id: WindowID, kind: WindowKind = .standard, engine: any WebEngine, send: @escaping @MainActor (Input) -> Void,
         routeKey: @escaping @MainActor (KeyInput) -> Bool = { _ in false }) {
        self.id = id
        self.kind = kind
        self.engine = engine
        self.send = send
        window = BrowserWindow(
            contentRect: CGRect(origin: .zero, size: kind == .little ? Metrics.littleArc.defaultSize.value : Metrics.window.defaultSize.value),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        root = WindowRootView(dispatch: { command in send(.user(id, command)) })
        super.init()
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.contentView = root
        window.delegate = self
        window.onKeyEquivalent = { event in
            guard let input = KeyInput(menuEvent: event) else { return false }
            return routeKey(input)
        }
        window.onFlagsChanged = { [weak self] flags in
            guard let self else { return }
            let held = Modifiers(rawValue: flags.intersection(.deviceIndependentFlagsMask).rawValue
                & (Modifiers.shift.rawValue | Modifiers.control.rawValue | Modifiers.option.rawValue | Modifiers.command.rawValue))
            self.send(.system(.window(self.id, .modifiersChanged(held: held))))
        }
    }

    /// Restores the saved frame once (`WindowPlacement.fit`), before the window is shown. The resulting
    /// `windowDidResize` reports the fitted frame to the store, which queues it behind the current dispatch.
    func place(_ snapshot: WindowSnapshot) {
        guard !placed else { return }
        placed = true
        let screens = NSScreen.screens.map(\.visibleFrame)
        let main = NSScreen.main?.visibleFrame ?? CGRect(origin: .zero, size: Metrics.window.defaultSize.value)
        window.setFrame(WindowPlacement.fit(snapshot.bounds, screens: screens, main: main), display: false)
    }

    /// Applies a snapshot: frames = `WindowLayout.compute(snapshot, contentSize)`; `root.render(...)` with
    /// `engine.surface(for:)`; traffic lights to `frames.sidebar?.trafficLightsOrigin` (hidden while the sidebar is
    /// hidden; Arc shows them on hover); keyboard focus only when `snapshot.focus` differs from the last one.
    /// Render itself never calls `send`; AppKit's resize and move delegate calls do, and the store queues those.
    func render(_ snapshot: WindowSnapshot) {
        place(snapshot)
        let frames = WindowLayout.compute(snapshot, contentSize: root.bounds.size)
        root.render(snapshot, frames: frames, surface: { [engine] page in engine.surface(for: page) })
        window.placeTrafficLights(origin: frames.sidebarFloats ? nil : frames.sidebar?.trafficLightsOrigin)
        window.backgroundColor = NSColor(srgbRed: snapshot.theme.windowColor.red, green: snapshot.theme.windowColor.green,
                                         blue: snapshot.theme.windowColor.blue, alpha: 1)
        if snapshot.focus != lastSnapshot?.focus || pendingFocus != nil {
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
            engine.focus(page)
        case .none:
            engine.focus(nil)
        case .commandBarInput, .renameField, .spaceDialog, .profileDialog, .sidebar:
            engine.focus(nil)
            if !root.focus(target) {
                // The view is not on screen yet (same render that opened it): re-applied by the next render.
                pendingFocus = target
            }
        }
    }

    // MARK: NSWindowDelegate -> WindowEvent

    public func windowDidResize(_ notification: Notification) { reportGeometry() }
    public func windowDidMove(_ notification: Notification) { reportGeometry() }
    public func windowWillClose(_ notification: Notification) { send(.system(.window(id, .closed))) }

    /// Becoming key again (app switch, a closed overlay panel) re-applies the snapshot's focus, so a page gets its
    /// Chromium view back as first responder and a native field keeps its own.
    public func windowDidBecomeKey(_ notification: Notification) {
        if let last = lastSnapshot { applyFocus(last.focus) }
    }

    private func reportGeometry() {
        let content = window.contentView?.bounds.size ?? .zero
        send(.system(.window(id, .geometry(bounds: window.frame, contentSize: content))))
    }
}

/// The browser window. Never lets CEF's host windows take key status from it (they are its child windows).
@MainActor
public final class BrowserWindow: NSWindow {
    /// Called for every `flagsChanged`, so Control going up or down reaches the reducer whoever has focus.
    var onFlagsChanged: ((NSEvent.ModifierFlags) -> Void)?
    /// A key equivalent the window's views did not take (a native view has focus, or none): the shortcut table
    /// decides before AppKit's menu, so hidden rows and user remaps work. Returns whether it was consumed.
    var onKeyEquivalent: ((NSEvent) -> Bool)?
    private let keyLog = Logger(subsystem: "brk", category: "keys")

    public override func sendEvent(_ event: NSEvent) {
        if event.type == .flagsChanged { onFlagsChanged?(event.modifierFlags) }
        if event.type == .keyDown, !event.modifierFlags.intersection([.command, .control]).isEmpty {
            keyLog.notice("window.sendEvent keyDown code=\(event.keyCode, privacy: .public) eventWindow=\(event.windowNumber, privacy: .public) firstResponder=\(Self.describe(self.firstResponder), privacy: .public)")
        }
        // With a native view (or nothing) focused the table decides first, the way Arc's key-binding layer does
        // before AppKit's menu: AppKit never fires a hidden menu item's key equivalent and only offers Command
        // chords to `performKeyEquivalent`, so Ctrl+Tab and Arc's hidden rows would otherwise die here. An unbound
        // key (typing in a field) is not consumed and takes the normal path. With a page view focused Chromium gets
        // the event and CEF's key handler routes it (before and after the page).
        if event.type == .keyDown, Self.surface(containing: firstResponder)?.routesKeysThroughWindow ?? true, routeKeyEquivalent(event) { return }
        super.sendEvent(event)
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

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let handled = super.performKeyEquivalent(with: event)
        keyLog.notice("window.performKeyEquivalent code=\(event.keyCode, privacy: .public) handledByViews=\(handled, privacy: .public) firstResponder=\(Self.describe(self.firstResponder), privacy: .public)")
        if handled { return true }
        return routeKeyEquivalent(event)
    }

    /// The table's turn after the views: with a page focused Chromium's view already took the event, so this only
    /// runs with a native view (or nothing) focused. Also called by the control socket's injector, which delivers
    /// to the content view and the menu by hand when the window is not key.
    func routeKeyEquivalent(_ event: NSEvent) -> Bool {
        guard event.type == .keyDown, let route = onKeyEquivalent else { return false }
        let routed = route(event)
        if routed { keyLog.notice("window.routeKeyEquivalent code=\(event.keyCode, privacy: .public) consumed by the table") }
        return routed
    }

    static func describe(_ responder: NSResponder?) -> String {
        guard let responder else { return "nil" }
        return NSStringFromClass(type(of: responder))
    }

    /// Arc's title row: lights at x 13 with 14 pt buttons on a 23 pt pitch, centred 24 pt from the top. `origin` is in
    /// the window's top-left content space; nil hides them (sidebar hidden).
    func placeTrafficLights(origin: CGPoint?) {
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
