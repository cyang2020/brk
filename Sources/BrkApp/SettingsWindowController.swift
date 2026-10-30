import AppKit
import BrkBase
import BrkDomain
import BrkSettings

/// Owner: F1. The one settings window (Arc: `SettingsWindowController`). Reconciled from `AppSnapshot.settings`
/// by the store: shown and brought front while `pane` is set, hidden when it is nil; closing it with the title bar
/// button dispatches `.settings(.closeWindow)` so the state follows the window, not the other way round.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    let window: NSWindow
    private let host: SettingsHost
    private let send: @MainActor (Command) -> Void
    private var shown = false

    init(send: @escaping @MainActor (Command) -> Void) {
        self.send = send
        host = SettingsHost(dispatch: send)
        window = NSWindow(contentRect: CGRect(origin: .zero, size: Metrics.settings.windowSize.value),
                          styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.delegate = self
        window.center()
    }

    /// Shows or hides the window for the pane, and renders the values.
    func render(_ settings: SettingsSnapshot) {
        host.render(settings)
        if settings.pane != nil {
            if !shown {
                shown = true
                window.makeKeyAndOrderFront(nil)
            }
        } else if shown {
            shown = false
            window.orderOut(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        if shown {
            shown = false
            send(.settings(.closeWindow))
        }
    }
}
