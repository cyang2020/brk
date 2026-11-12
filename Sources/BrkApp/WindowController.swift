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
        window.onPointerNavigation = { [weak self] direction, point, page in
            guard let self, let snapshot = self.lastSnapshot else { return }
            let region: PointerNavigation.Region
            if let page, snapshot.content.presentedPanes.contains(where: { $0.content == .page(page) }) { region = .page(page) }
            else if self.root.isSidebar(atWindowPoint: point) { region = .sidebar }
            else { region = .other }
            guard let command = PointerNavigation.command(direction, over: region, overlayOpen: snapshot.overlay != nil,
                                                          stepsSpaces: self.kind == .standard) else { return }
            self.send(.user(self.id, command))
        }
        // Typing asks the page nothing unless a highlight is showing (it may just have been replaced).
        window.onPageSelectionMayChange = { [weak self, engine] page, typing in
            if typing, self?.lastSnapshot?.urlPill.shareQuote != true { return }
            engine.checkSelection(page)
        }
        window.onKeyEquivalent = { [weak self] event in
            if event.keyCode == Key.escape.code, TabIconPicker.isOpen { TabIconPicker.close(); return true }
            if event.keyCode == Key.escape.code, self?.cancelSplitDrag() == true { return true }
            guard let input = KeyInput(menuEvent: event) else { return false }
            return routeKey(input)
        }
        // ⌘Z and ⇧⌘Z while Edit Theme is open step through the panel's edits, before the page or the Edit menu's
        // Undo sees them (the panel is never key, so the browser window has the keys).
        window.onKeyBeforePage = { [weak self] event in
            // A save card over the window (SavePromptCards) saves on Return, before the key table sees it.
            if event.keyCode == 36 || event.keyCode == 76, event.modifierFlags.intersection([.command, .shift, .option, .control]).isEmpty,
               self?.root.savePromptKey(save: true) == true { return true }
            guard let self, event.keyCode == Key.z.code else { return false }
            let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
            guard flags == .command || flags == [.command, .shift] else { return false }
            // ⌘Z while an undo toast shows ("Cleared Tabs! Use ⌘Z to undo") undoes that, before the page or the Edit
            // menu's Undo, wherever the keyboard focus is.
            if flags == .command, self.lastSnapshot?.tabTools.toast?.keycap == "⌘Z" {
                self.send(.user(self.id, .tabTools(.undoToast)))
                return true
            }
            return self.root.spaceDialog.stepThemeEdit(redo: flags.contains(.shift))
        }
        window.onEscapeBeforePage = { [weak self] event in
            // The icon popover takes Escape first, from the menu path, the window and the key monitor alike.
            if TabIconPicker.isOpen { TabIconPicker.close(); return true }
            // A save card over the window (SavePromptCards) declines on Escape, before the key table sees it.
            if self?.root.savePromptKey(save: false) == true { return true }
            // Site search keeps its first Escape (it leaves the mode, the bar stays) whichever monitor runs first.
            if let self, self.root.commandBar.takeEscape(event) { return true }
            guard let self, self.lastSnapshot?.overlay != nil || self.pageFullscreen.nativeExitShouldExitDocument,
                  let input = KeyInput(menuEvent: event) else { return false }
            return routeKey(input)
        }
        window.onScrollWheel = { [weak root] event in root?.handleScrollWheel(event) ?? false }
        if let browser = window as? BrowserWindow {
            browser.canStartCaptureDrag = { [weak self, weak browser] event in
                guard let self, let browser, let snapshot = self.lastSnapshot, snapshot.capture == nil, snapshot.overlay == nil,
                      let hit = browser.contentView?.superview?.hitTest(event.locationInWindow) ?? browser.contentView?.hitTest(event.locationInWindow),
                      let surface = BrowserWindow.surface(containing: hit),
                      snapshot.content.presentedPanes.contains(where: { $0.focused && $0.content == .page(surface.page) }) else { return false }
                return true
            }
            browser.startCaptureDrag = { [weak self] in
                guard let self else { return false }
                self.root.expectCaptureShortcut(true)
                self.send(.user(self.id, .capture(.begin(.area))))
                let started = self.lastSnapshot?.capture != nil
                if !started { self.root.expectCaptureShortcut(false) }
                return started
            }
        }
        window.onFlagsChanged = { [weak self] flags in
            guard let self else { return }
            let held = Modifiers(rawValue: flags.intersection(.deviceIndependentFlagsMask).rawValue
                & (Modifiers.shift.rawValue | Modifiers.control.rawValue | Modifiers.option.rawValue | Modifiers.command.rawValue))
            self.send(.system(.window(self.id, .modifiersChanged(held: held))))
        }
    }

    /// Enter/Exit Full Screen while AppKit animates a transition: AppKit drops a toggle sent mid-animation, so a
    /// second press would be lost and the window would end where the user did not ask. The presses are counted and
    /// an odd count is applied once the transition finishes.
    private var queuedToggles = 0
    func toggleFullScreen() {
        guard !pageFullscreen.isTransitioning else { queuedToggles += 1; tracePageFullscreen("queued toggle \(queuedToggles)"); return }
        // AppKit does not take a floating (Stay on Top) window to full screen: it goes down to the normal level first
        // and floats again when it leaves full screen (`windowDidExitFullScreen`).
        if !window.styleMask.contains(.fullScreen), window.level != .normal { window.level = .normal }
        window.toggleFullScreen(nil)
    }
    private func applyQueuedToggles() {
        guard queuedToggles > 0 else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.pageFullscreen.isTransitioning, self.queuedToggles > 0 else { return }
            let odd = self.queuedToggles % 2 == 1
            self.queuedToggles = 0
            self.tracePageFullscreen("apply queued toggle \(odd)")
            if odd { self.window.toggleFullScreen(nil) }
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
    /// `engine.surface(for:)`; traffic lights to `frames.sidebar?.trafficLightsOrigin` (anchored or floating), or the Library panel's (hidden
    /// while the sidebar is hidden; Arc shows them on hover); keyboard focus only when `snapshot.focus` differs from the last one.
    /// Render itself never calls `send`; AppKit's resize and move delegate calls do, and the store queues those.
    func render(_ snapshot: WindowSnapshot) {
        var snapshot = snapshot
        snapshot.fullScreen = fullScreen
        place(snapshot)
        window.level = window.styleMask.contains(.fullScreen) ? .normal : (snapshot.stayOnTop ? .floating : .normal)
        let frames = WindowLayout.compute(snapshot, contentSize: root.bounds.size)
        root.render(snapshot, frames: frames, surface: { [engine, id] page in page.window == id ? engine.surface(for: page) : nil })
        // The floating sidebar keeps them too (Arc), and the Library's panel keeps them where the sidebar had them
        // (P32: Arc shows them over its navigation column).
        window.placeTrafficLights(origin: frames.sidebar?.trafficLightsOrigin ?? frames.library.map { LibraryLayout.trafficLightsOrigin(in: $0.strip) })
        RestingTrafficLights.find(in: window.standardWindowButton(.closeButton)?.superview)?.scheme = snapshot.theme.scheme
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

    /// The snapshot's focus again, after a card over the window (SavePromptCards) held the keyboard.
    func reapplyFocus() { if let last = lastSnapshot { applyFocus(last.focus) } }

    /// Keyboard focus follows the snapshot: a page gets it through the engine, a native view through the root's
    /// narrow focus API; nothing else in BrkApp touches a view's responder status.
    func applyFocus(_ target: FocusTarget) {
        switch target {
        case .page(let page):
            engine.focus(page, in: window)
        case .none:
            engine.focus(nil, in: window)
        case .capture, .findInput, .commandBarInput, .renameField, .spaceDialog, .profileDialog, .sidebar, .easel:
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
    /// An AI page in this window first commits what is being typed (`PageSandboxView.commitEdits`), then the window closes.
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        if pageEditsCommitted || !PageSandboxView.anyCanSave(in: window) { return true }
        guard !committingPageEdits else { return false }
        committingPageEdits = true
        Task { @MainActor [weak self] in
            guard let self else { return }
            await PageSandboxView.commitAll(in: self.window)
            self.committingPageEdits = false
            self.pageEditsCommitted = true
            self.window.performClose(nil)
            if self.window.isVisible { self.pageEditsCommitted = false }
        }
        return false
    }
    private var committingPageEdits = false
    private var pageEditsCommitted = false

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

    /// The window is in macOS full screen, or going there: from the start of the move in to the start of the move out.
    /// The title row follows it (`WindowSnapshot.fullScreen`).
    private var fullScreen = false {
        didSet { if fullScreen != oldValue, let last = lastSnapshot { render(last) } }
    }

    public func windowWillEnterFullScreen(_ notification: Notification) {
        tracePageFullscreen("will enter"); pageFullscreen.nativeWillChange(to: true)
        fullScreen = true
    }
    public func windowWillExitFullScreen(_ notification: Notification) {
        tracePageFullscreen("will exit"); pageFullscreen.nativeWillChange(to: false)
        fullScreen = false
    }
    public func windowDidEnterFullScreen(_ notification: Notification) {
        tracePageFullscreen("did enter")
        // The titlebar is in AppKit's full screen window now: its buttons as they are (`showSystemTrafficLights`).
        if let last = lastSnapshot { render(last) }
        pageFullscreen.nativeDidChange(); window.level = .normal; applyPageFullscreen(); applyQueuedToggles()
    }
    public func windowDidFailToEnterFullScreen(_ window: NSWindow) { fullscreenTransitionFailed() }
    public func windowDidFailToExitFullScreen(_ window: NSWindow) { fullscreenTransitionFailed() }
    private func fullscreenTransitionFailed() {
        tracePageFullscreen("failed")
        fullScreen = window.styleMask.contains(.fullScreen)
        defer { applyQueuedToggles() }
        if pageFullscreen.nativeFailed(nativeFullscreen: window.styleMask.contains(.fullScreen)) {
            for pane in lastSnapshot?.content.presentedPanes ?? [] {
                if case .page(let page) = pane.content { engine.perform(.exitFullscreen, on: page) }
            }
        }
    }
    public func windowDidExitFullScreen(_ notification: Notification) {
        tracePageFullscreen("did exit")
        // AppKit has put the titlebar back in the window: the lights go to Arc's spots again.
        if let last = lastSnapshot { render(last) }
        if pageFullscreen.nativeExited() {
            for pane in lastSnapshot?.content.presentedPanes ?? [] {
                if case .page(let page) = pane.content { engine.perform(.exitFullscreen, on: page) }
            }
        }
        applyPageFullscreen()
        applyQueuedToggles()
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
    /// A key-down the window takes before the focused page or the menu, when it answers true (the theme panel's ⌘Z).
    var onKeyBeforePage: ((NSEvent) -> Bool)? { get set }
    var onPagePointerDown: ((PageID) -> Void)? { get set }
    /// A mouse-up or key-up with a page focused: its highlight may have changed (the URL pill's Share Quote). `typing`:
    /// a key-up without Shift or Command, which changes a highlight only by replacing or leaving one.
    var onPageSelectionMayChange: ((PageID, _ typing: Bool) -> Void)? { get set }
    /// Back or forward from the mouse: a side button outside a page, or a navigation swipe anywhere (`PointerNavigation`).
    /// `page` is the shown page under the pointer, if any.
    var onPointerNavigation: ((PointerNavigation.Direction, _ point: NSPoint, _ page: PageID?) -> Void)? { get set }
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
        if event.type == .keyDown, onKeyBeforePage?(event) == true { return true }
        if [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown, .scrollWheel].contains(event.type) { onActivity?() }
        if event.type == .scrollWheel, onScrollWheel?(event) == true { return true }
        if let taken = pointerNavigation(event) { return taken }
        switch event.type {
        case .leftMouseUp, .keyUp:
            if let surface = Self.surface(containing: firstResponder), surface.window === self {
                onPageSelectionMayChange?(surface.page, event.type == .keyUp && event.modifierFlags.intersection([.shift, .command]).isEmpty)
            }
        case .flagsChanged: onFlagsChanged?(event.modifierFlags)
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            // Control stays the keyboard's report alone: a click while Control is held mid Ctrl+Tab walk would otherwise
            // read as a repeated report, which the reducer takes for a missed release and commits the walk.
            if !event.modifierFlags.contains(.control) { onFlagsChanged?(event.modifierFlags) }
            if event.type == .leftMouseDown, let surface = pageSurface(at: event.locationInWindow) {
                onPagePointerDown?(surface.page)
            }
        default: break
        }
        if event.type == .keyDown, !event.modifierFlags.intersection([.command, .control]).isEmpty {
            keyLog.notice("window.sendEvent keyDown code=\(event.keyCode, privacy: .public) eventWindow=\(event.windowNumber, privacy: .public) firstResponder=\(Self.describe(self.firstResponder), privacy: .public)")
        }
        return event.type == .keyDown && (Self.surface(containing: firstResponder)?.routesKeysThroughWindow ?? true) && routeKeyEquivalent(event)
    }

    /// Side buttons 4 and 5 and the navigation swipe (mouse drivers' Back and Forward, the three-finger trackpad swipe).
    /// Over a shown page the side buttons stay Chromium's: Blink takes them and navigates that page itself. Elsewhere,
    /// and the swipe everywhere (Chrome handles it in its own browser window, which an embedded page lacks), the
    /// controller runs `PointerNavigation`'s command. A side button's press and release are both taken, so no view under
    /// the pointer sees half a click; the command runs on the release, as Blink does on a page. Nil: not one of these.
    private func pointerNavigation(_ event: NSEvent) -> Bool? {
        let direction: PointerNavigation.Direction
        switch event.type {
        case .swipe:
            guard let swiped = PointerNavigation.direction(swipeDeltaX: event.deltaX) else { return nil }
            direction = swiped
        case .otherMouseDown, .otherMouseUp:
            guard let pressed = PointerNavigation.direction(button: event.buttonNumber), pageSurface(at: event.locationInWindow) == nil else { return nil }
            guard event.type == .otherMouseUp else { return true }
            direction = pressed
        default:
            return nil
        }
        keyLog.notice("window.pointerNavigation \(direction == .back ? "back" : "forward", privacy: .public) type=\(event.type.rawValue, privacy: .public)")
        onPointerNavigation?(direction, event.locationInWindow, pageSurface(at: event.locationInWindow)?.page)
        return true
    }

    /// The shown page surface under a point of this window, if any.
    func pageSurface(at point: NSPoint) -> PageSurfaceView? {
        guard let hit = contentView?.superview?.hitTest(point) ?? contentView?.hitTest(point),
              let surface = Self.surface(containing: hit), surface.window === self, !surface.isHiddenOrHasHiddenAncestor else { return nil }
        return surface
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
    /// the window's top-left content space; nil hides them (sidebar hidden). At rest Arc draws them as grey circles,
    /// key window or not, and the colored buttons only while the pointer is over them (`RestingTrafficLights`).
    ///
    /// The buttons are not moved against AppKit: it lays its titlebar out again whenever it likes (the moment the
    /// pointer goes over the buttons, for one) and puts them back at its own spots, a fixed inset from the titlebar's
    /// left edge and centred in its height. So the titlebar itself is moved and sized until those spots are Arc's: the
    /// user's report (26b91660a8:verify/visual-pairs/run-20261103/Q16) was the colored buttons coming up 4 pt left of and 8 pt
    /// above the grey circles, with the circles' own spots taking no click. AppKit sets the titlebar's frame back each
    /// time the pointer goes onto or off the buttons; `RestingTrafficLights` puts it right in the same display pass.
    func placeArcTrafficLights(origin: CGPoint?) {
        let buttons = [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { standardWindowButton($0) }
        if styleMask.contains(.fullScreen) { return showSystemTrafficLights(buttons) }
        if let resting = RestingTrafficLights.find(in: buttons.first?.superview), resting.fullScreen {
            // Back from full screen: the buttons go back to their resting look (the pointer is on the page, not on them).
            resting.fullScreen = false
            buttons.forEach { $0.alphaValue = RestingTrafficLights.restingAlpha }
        }
        guard let origin, let titlebar = buttons.first?.superview, let container = titlebar.superview, let frame = container.superview else {
            buttons.forEach { $0.isHidden = true }
            let resting = RestingTrafficLights.find(in: buttons.first?.superview)
            resting?.isHidden = true
            resting?.origin = nil
            return
        }
        let resting = RestingTrafficLights.find(in: titlebar) ?? {
            // Made before Brk has moved anything: the buttons are where AppKit puts them.
            let made = RestingTrafficLights(buttons: buttons, container: container)
            titlebar.addSubview(made, positioned: .below, relativeTo: buttons.first)
            made.movedByAppKit = { [weak self, weak made] in
                guard let self, let made, let origin = made.origin else { return }
                self.placeArcTrafficLights(origin: origin)
            }
            return made
        }()
        resting.origin = origin
        resting.placing = true
        defer { resting.placing = false }
        let size = buttons[0].frame.size
        // AppKit centres the buttons in the titlebar's height and starts them `systemLeading` in from its left edge.
        let height = 2 * origin.y + size.height
        let shift = origin.x - resting.systemLeading
        let target = CGRect(x: shift, y: frame.bounds.height - height, width: frame.bounds.width - shift, height: height)
        if container.frame != target { container.frame = target }
        if titlebar.frame != container.bounds { titlebar.frame = container.bounds }
        // The same spots AppKit's own layout gives in this titlebar; only the pitch is Brk's to keep.
        let pitch = Metrics.window.trafficLightSize.value + Metrics.window.trafficLightSpacing.value
        for (i, button) in buttons.enumerated() {
            button.isHidden = false
            let spot = CGPoint(x: resting.systemLeading + Double(i) * pitch, y: (height - size.height) / 2)
            if button.frame.origin != spot { button.setFrameOrigin(spot) }
        }
        resting.isHidden = false
        resting.frame = buttons.map(\.frame).reduce(buttons[0].frame) { $0.union($1) }
        resting.needsDisplay = true
    }

    /// Full screen: AppKit moves the titlebar into its own window that comes down with the menu bar and lays it out
    /// itself. Arc shows the standard coloured buttons there, not its grey circles (the user's report, 2026-11-12):
    /// Brk leaves them where AppKit puts them, fully opaque, and stops answering AppKit's moves until the window
    /// leaves full screen.
    private func showSystemTrafficLights(_ buttons: [NSButton]) {
        if let resting = RestingTrafficLights.find(in: buttons.first?.superview) {
            resting.fullScreen = true
            resting.origin = nil
            resting.isHidden = true
        }
        for button in buttons {
            button.isHidden = false
            button.alphaValue = 1
        }
    }
}

/// Arc's traffic lights at rest (2a96a9d7f0:verify/visual-pairs/run-20261103: every capture with the pointer elsewhere, P01-a in
/// the key window and P01-d with another app frontmost): three flat circles of black at 8.5% over the sidebar
/// (#DCD5D3 on #F0EAE6), the colored buttons with their glyphs only while the pointer is over them (P01-c). Sits
/// under the standard buttons, which stay clickable and turn transparent at rest.
@MainActor
final class RestingTrafficLights: NSView {
    private let buttons: [NSButton]
    private var tracking: NSTrackingArea?

    /// Where Brk last put the lights (the window's top-left content space), nil while they are hidden.
    var origin: CGPoint?
    /// True while Brk itself moves the titlebar, so its own moves are not taken for AppKit's.
    var placing = false
    /// The window is in full screen: AppKit's buttons show as they are and this view stays hidden.
    var fullScreen = false
    /// AppKit put the titlebar back (a window resize, full screen and back): place the lights again.
    var movedByAppKit: (() -> Void)?
    /// How far in from the titlebar's left edge AppKit starts the buttons (9 on macOS 26), read before Brk moved them.
    let systemLeading: Double

    init(buttons: [NSButton], container: NSView) {
        self.buttons = buttons
        systemLeading = buttons.first.map { Double($0.frame.minX) } ?? 9
        super.init(frame: .zero)
        identifier = Self.id
        buttons.forEach { $0.alphaValue = Self.restingAlpha }
        container.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(titlebarFrameChanged(_:)), name: NSView.frameDidChangeNotification, object: container)
    }

    /// AppKit put the titlebar back at its own place: it does every time the pointer goes onto or off the buttons
    /// (logged 2026-11-05: (0, 744, 1280, 32), eight times for four passes of the pointer) and on a resize. The
    /// lights are placed again by whichever of three comes first: this view's own layout or its drawing later in the
    /// same display pass, before anything reaches the screen, or the next run-loop turn. With only the last, as
    /// before, the colored buttons could show at AppKit's spots (4 pt left, 8 pt up) for one screen refresh under the
    /// pointer (the user's second report, Q20).
    @objc private func titlebarFrameChanged(_ note: Notification) {
        guard !placing, origin != nil, !isHidden else { return }
        moved = true
        needsLayout = true
        needsDisplay = true
        DispatchQueue.main.async { [weak self] in self?.placeAgain() }
    }

    private var moved = false

    private func placeAgain() {
        guard moved else { return }
        moved = false
        guard !placing, origin != nil, !isHidden else { return }
        movedByAppKit?()
    }

    override func layout() {
        super.layout()
        placeAgain()
    }

    override func viewWillDraw() {
        super.viewWillDraw()
        placeAgain()
    }

    /// The standard buttons at rest: effectively invisible under the grey circles. Not 0: AppKit treats a fully
    /// transparent miniaturize button as absent and `miniaturize(_:)` then does nothing (Cmd+M, Window > Minimize and
    /// the Dock all stopped minimizing the window when this was 0; BB3 and R49-WindowMenu caught it).
    static let restingAlpha: CGFloat = 0.01

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    static let id = NSUserInterfaceItemIdentifier("resting-traffic-lights")
    static func find(in container: NSView?) -> RestingTrafficLights? {
        container?.subviews.first { $0.identifier == id } as? RestingTrafficLights
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// The window's scheme: a dark theme's lights at rest are lighter than it, each with a rim in its own color
    /// (Q18-navy-row-hover-arc.png), a light theme's are plain grey.
    var scheme = Scheme.light { didSet { if scheme != oldValue { needsDisplay = true } } }

    /// Q18-navy-row-hover-arc.png, at 2x: the rims read #9A647C, #94926E and #399179, the insides white 0.3 over the theme.
    private static let darkRims = [(0x9A, 0x64, 0x7C), (0x94, 0x92, 0x6E), (0x39, 0x91, 0x79)].map {
        NSColor(srgbRed: Double($0.0) / 255, green: Double($0.1) / 255, blue: Double($0.2) / 255, alpha: 1)
    }

    override func draw(_ dirtyRect: NSRect) {
        let light = Metrics.window.trafficLightSize.value - 1, full = Metrics.window.trafficLightSize.value
        for (index, button) in buttons.enumerated() {
            let frame = convert(button.frame, from: superview)
            func circle(_ side: Double) -> NSBezierPath {
                NSBezierPath(ovalIn: CGRect(x: frame.midX - side / 2, y: frame.midY - side / 2, width: side, height: side))
            }
            guard scheme == .dark else {
                NSColor(white: 0, alpha: 0.085).setFill()
                circle(light).fill()
                continue
            }
            NSColor(white: 1, alpha: 0.3).setFill()
            circle(full).fill()
            Self.darkRims[min(index, Self.darkRims.count - 1)].setStroke()
            let rim = circle(full - 1)
            rim.lineWidth = 1
            rim.stroke()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area)
        tracking = area
    }

    override func mouseEntered(with event: NSEvent) { buttons.forEach { $0.alphaValue = 1 } }
    override func mouseExited(with event: NSEvent) {
        guard !fullScreen else { return }
        buttons.forEach { $0.alphaValue = Self.restingAlpha }
    }
}

/// The browser window. Never lets CEF's host windows take key status from it (they are its child windows).
@MainActor
public final class BrowserWindow: NSWindow, HostWindow {
    public var onActivity: (() -> Void)?
    public var onFlagsChanged: ((NSEvent.ModifierFlags) -> Void)?
    public var onScrollWheel: ((NSEvent) -> Bool)?
    public var onKeyEquivalent: ((NSEvent) -> Bool)?
    public var onKeyBeforePage: ((NSEvent) -> Bool)?
    public var onEscapeBeforePage: ((NSEvent) -> Bool)?
    public var onPagePointerDown: ((PageID) -> Void)?
    public var onPageSelectionMayChange: ((PageID, _ typing: Bool) -> Void)?
    public var onPointerNavigation: ((PointerNavigation.Direction, _ point: NSPoint, _ page: PageID?) -> Void)?
    /// Arc's ⇧⌘-drag capture: whether this ⇧⌘ mouse-down is over the focused page, and, once it moves, starting
    /// the capture (true when the overlay is up to take the held mouse-down).
    var canStartCaptureDrag: ((NSEvent) -> Bool)?
    var startCaptureDrag: (() -> Bool)?
    private var heldCaptureDown: NSEvent?

    public override func sendEvent(_ event: NSEvent) {
        if let held = heldCaptureDown {
            switch event.type {
            case .leftMouseDragged:
                guard hypot(event.locationInWindow.x - held.locationInWindow.x, event.locationInWindow.y - held.locationInWindow.y) >= 3 else { return }
                heldCaptureDown = nil
                if startCaptureDrag?() == true { super.sendEvent(held); super.sendEvent(event); return }
                deliver(held)
            case .leftMouseUp:
                // A ⇧⌘-click, not a drag: the page gets it as usual (open the link in a new tab).
                heldCaptureDown = nil; deliver(held)
            default: break
            }
        } else if event.type == .leftMouseDown,
                  event.modifierFlags.intersection([.shift, .command, .option, .control]) == [.shift, .command],
                  canStartCaptureDrag?(event) == true {
            heldCaptureDown = event
            return
        }
        deliver(event)
    }
    private func deliver(_ event: NSEvent) {
        if hostEvent(event) { return }
        super.sendEvent(event)
    }

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // AppKit offers Command chords here before the window's sendEvent: the theme panel's ⌘Z goes first.
        if event.type == .keyDown, onKeyBeforePage?(event) == true { return true }
        return hostKeyEquivalent(event, handledByViews: super.performKeyEquivalent(with: event))
    }

    private var lightsOrigin: CGPoint?

    /// Unhiding the buttons (the sidebar coming back, or floating in) makes AppKit lay the titlebar out once more
    /// after this pass, back at its own spots; the lights are placed again after that.
    public func placeTrafficLights(origin: CGPoint?) {
        let wasHidden = lightsOrigin == nil
        lightsOrigin = origin
        placeArcTrafficLights(origin: origin)
        guard wasHidden, origin != nil else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.placeArcTrafficLights(origin: self.lightsOrigin)
        }
    }
}
