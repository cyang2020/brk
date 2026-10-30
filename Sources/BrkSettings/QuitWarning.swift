import AppKit
import BrkBase
import BrkDomain
import BrkUIKit

/// "Warn before quitting" (General). Arc asks in `applicationShouldTerminate(_:)` with a dialog whose suppression
/// button is "Quit, and don’t ask again" (observed), so every way of quitting is covered (Cmd+Q, the Dock menu,
/// the app menu). The reducer keeps quitting an ordered effect; this is the question the terminate handler asks
/// before it starts. Wiring: `Lifecycle.applicationShouldTerminate` calls `shouldQuit` first (not for SIGTERM or the
/// control socket's quit), see the F1 report.
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
        return alert
    }

    public static func run(_ alert: NSAlert) -> Answer {
        let response = alert.runModal()
        return Answer(quit: response == .alertFirstButtonReturn, dontAskAgain: alert.suppressionButton?.state == .on)
    }
}
