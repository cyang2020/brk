import AppKit
import BrkBase
import BrkDomain
import BrkEngine
import BrkLayout
import BrkUI

/// One browser window: an NSWindow with a full-size, transparent title bar (traffic lights over the sidebar), its
/// root view, and the glue that turns a `WindowSnapshot` into frames, views, page placement and focus.
@MainActor
public final class WindowController: NSObject, NSWindowDelegate {
    public let id: WindowID
    public let window: BrowserWindow
    let root: WindowRootView
    private let engine: any WebEngine
    private let send: @MainActor (Input) -> Void
    private(set) var lastSnapshot: WindowSnapshot?
    private(set) var lastFrames: WindowFrames?

    init(id: WindowID, engine: any WebEngine, send: @escaping @MainActor (Input) -> Void) {
        self.id = id
        self.engine = engine
        self.send = send
        window = BrowserWindow(
            contentRect: CGRect(origin: .zero, size: Metrics.Window.defaultSize.value),
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
    }

    /// Applies a snapshot. Steps: restore the saved frame once (`WindowPlacement.fit`); frames =
    /// `WindowLayout.compute(snapshot, contentSize)`; `root.render(...)` with `engine.surface(for:)`; traffic lights to
    /// `frames.sidebar?.trafficLightsOrigin` (hidden while the sidebar is hidden, Arc shows them on hover);
    /// keyboard focus only when `snapshot.focus` differs from the last one:
    /// `.page(id)` -> `engine.focus(id)`; `.commandBarInput` -> `engine.focus(nil)`, first responder = bar input;
    /// `.renameField`, `.spaceDialog`, `.sidebar` likewise; `.none` -> `engine.focus(nil)`.
    func render(_ snapshot: WindowSnapshot) {
        // TODO(W2): the steps above. Never call send() from here (render must not produce input).
        fatalError("not implemented")
    }

    // MARK: NSWindowDelegate -> WindowEvent

    public func windowDidResize(_ notification: Notification) { reportGeometry() }
    public func windowDidMove(_ notification: Notification) { reportGeometry() }
    public func windowWillClose(_ notification: Notification) { send(.system(.window(id, .closed))) }

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

    public override func sendEvent(_ event: NSEvent) {
        if event.type == .flagsChanged { onFlagsChanged?(event.modifierFlags) }
        super.sendEvent(event)
    }

    /// Arc's title row: lights at x 13 with 14 pt buttons on a 23 pt pitch, centred 24 pt from the top.
    func placeTrafficLights(origin: CGPoint?) {
        // TODO(W2): for close/miniaturize/zoom: setFrameOrigin in the titlebar view's coordinates from `origin`
        // (window top-left space), spacing Metrics.Window.trafficLightSize + trafficLightSpacing; nil hides them.
        fatalError("not implemented")
    }
}
