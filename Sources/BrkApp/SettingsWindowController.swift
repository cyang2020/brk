import AppKit
import BrkBase
import BrkDomain
import BrkSettings

/// Owner: F1. The one settings window (Arc: the Settings package's `SettingsWindowController`). Reconciled from
/// `AppSnapshot.settings` by the store: shown and brought front when a pane opens, hidden when `pane` becomes nil.
/// Closing it with the title bar button dispatches `.settings(.closeWindow)`, so the state follows the window
/// (Cmd+W and Esc dispatch the same from the host). The host installs the pane toolbar, titles the window with the
/// pane and fits its height; the frame's position is remembered across launches, like Arc's
/// `company.browser.Settings.FrameAutosaveName`.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    let window: NSWindow
    private let host: SettingsHost
    private let send: @MainActor (Command) -> Void
    private var shown = false
    private var pane: SettingsPane?
    private weak var previousKeyWindow: NSWindow?

    static var frameAutosaveName: String { "\(Bundle.main.bundleIdentifier ?? Product.name).Settings.FrameAutosaveName" }

    init(send: @escaping @MainActor (Command) -> Void) {
        self.send = send
        host = SettingsHost(dispatch: send)
        window = NSWindow(contentRect: CGRect(origin: .zero, size: Metrics.settings.windowSize.value),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.delegate = self
        if !window.setFrameUsingName(Self.frameAutosaveName) { window.center() }
        window.setFrameAutosaveName(Self.frameAutosaveName)
    }

    /// Renders the values, then shows the window when a pane opens and hides it when the pane goes.
    func render(_ settings: SettingsSnapshot) {
        let changingPane = settings.pane != pane
        pane = settings.pane
        host.render(settings)
        if settings.pane != nil {
            guard !shown || changingPane else { return }
            if let key = NSApp.keyWindow, key !== window { previousKeyWindow = key }
            shown = true
            window.makeKeyAndOrderFront(nil)
        } else if shown {
            shown = false
            let returnFocus = window.isKeyWindow
            window.orderOut(nil)
            if returnFocus, let previousKeyWindow, previousKeyWindow.isVisible { previousKeyWindow.makeKeyAndOrderFront(nil) }
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard shown else { return }
        shown = false
        send(.settings(.closeWindow))
    }
}
