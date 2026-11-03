import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// "Warn before quitting" (General). Arc asks with a dialog whose suppression button is "Quit, and don’t ask again"
/// (observed), so every way of quitting is covered. Wiring (BrkApp): Cmd+Q and Brk > Quit reach `AppEffect.quit`,
/// which asks before anything is torn down (`AppStore.confirmQuit`); a quit that reaches
/// `Lifecycle.applicationShouldTerminate` without it (the Dock menu, a quit Apple event) asks there. SIGTERM, the
/// control socket's quit and a logout, restart or shut down never ask.
@MainActor
public enum QuitWarning {
    /// The user's answer: quit or not, and whether to stop asking.
    public struct Answer: Equatable, Sendable {
        public let quit: Bool
        public let dontAskAgain: Bool
        public init(quit: Bool, dontAskAgain: Bool) {
            self.quit = quit
            self.dontAskAgain = dontAskAgain
        }
    }

    /// Whether to go on quitting. Asks only while the setting is on; "Quit, and don’t ask again" turns it off.
    public static func shouldQuit(_ general: GeneralSettings, dispatch: Dispatch, ask: @MainActor (NSAlert) -> Answer = QuitWarning.run) -> Bool {
        guard general.warnBeforeQuitting else { return true }
        let answer = ask(alert())
        if answer.quit, answer.dontAskAgain { dispatch(.settings(.general(.warnBeforeQuitting(false)))) }
        return answer.quit
    }

    /// The same question without a nested run loop: on `window` as a sheet (the app keeps running while it is open,
    /// and the ordered quit that may follow does not start inside a modal session), else as a modal alert. `answer`
    /// gets whether to go on quitting; it is called at once when the setting is off.
    public static func confirm(_ general: GeneralSettings, on window: NSWindow?, dispatch: @escaping Dispatch,
                               ask: @MainActor (NSAlert, NSWindow?, @escaping @MainActor (Answer) -> Void) -> Void = QuitWarning.present,
                               answer: @escaping @MainActor (Bool) -> Void) {
        guard general.warnBeforeQuitting else { answer(true); return }
        ask(alert(), window) { reply in
            if reply.quit, reply.dontAskAgain { dispatch(.settings(.general(.warnBeforeQuitting(false)))) }
            answer(reply.quit)
        }
    }

    /// Shows `alert` as a sheet on `window` when it can take one, else modally.
    public static func present(_ alert: NSAlert, on window: NSWindow?, _ done: @escaping @MainActor (Answer) -> Void) {
        guard let window, window.isVisible, window.attachedSheet == nil else { done(run(alert)); return }
        alert.beginSheetModal(for: window) { response in
            MainActor.assumeIsolated {
                done(Answer(quit: response == .alertFirstButtonReturn, dontAskAgain: alert.suppressionButton?.state == .on))
            }
        }
    }

    /// Arc's dialog: its title and message are short strings that did not survive in the binary; the suppression
    /// button's text did.
    static func alert() -> NSAlert {
        let alert = NSAlert()
        alert.messageText = SettingsCopy.quitTitle
        alert.informativeText = SettingsCopy.quitMessage
        alert.addButton(withTitle: SettingsCopy.quitButton)
        alert.addButton(withTitle: SettingsCopy.cancelButton)
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = SettingsCopy.quitDontAskAgain
        // The control socket clicks these by identifier (the e2e scenario answers the real dialog).
        alert.buttons.first?.identify(.settingsField("quitWarning-quit"))
        alert.buttons.last?.identify(.settingsField("quitWarning-cancel"))
        alert.suppressionButton?.identify(.settingsField("quitWarning-dontAsk"))
        return alert
    }

    public static func run(_ alert: NSAlert) -> Answer {
        let response = alert.runModal()
        return Answer(quit: response == .alertFirstButtonReturn, dontAskAgain: alert.suppressionButton?.state == .on)
    }
}
