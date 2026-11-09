import AppKit
import BrkBase
import BrkDomain
import UserNotifications

/// Brk's own macOS notifications for its AI conversations (docs/design/ai-threads.md): an agent waits for approval, or a
/// reply that ran over a minute finished. The reducer asks for each one (`Effect.aiNotify`); they are posted only while
/// Brk is not the frontmost app, since in front the list's strip, the dot's ring and the count already say it. Clicking
/// one brings Brk to the front and opens that conversation (`AIIntent.showConversation`).
///
/// A test instance (under the control socket) never asks macOS for permission and posts nothing: it keeps what it would
/// have posted, for the control socket to read and to click (`ControlOp.aiNotifications`, `openAINotification`).
@MainActor
final class AINotifications: NSObject, UNUserNotificationCenterDelegate {
    private let recording: Bool
    private(set) var recorded: [AINotification] = []
    /// A notification was clicked: show this conversation.
    var onOpen: ((AIRequestID) -> Void)?
    private var asked = false

    init(recording: Bool) {
        self.recording = recording
        super.init()
    }

    func post(_ notice: AINotification) {
        guard !NSApp.isActive else { return }
        if recording { recorded.append(notice); return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let content = UNMutableNotificationContent()
        content.title = notice.title
        content.body = notice.body
        content.userInfo = ["conversation": notice.conversation.rawValue]
        content.threadIdentifier = "brk-ai-" + notice.conversation.rawValue
        let request = UNNotificationRequest(identifier: "brk-ai-\(notice.conversation.rawValue)-\(notice.kind.rawValue)", content: content, trigger: nil)
        let first = !asked
        asked = true
        Task { @MainActor in
            if first { _ = try? await center.requestAuthorization(options: [.alert, .sound]) }
            try? await center.add(request)
        }
    }

    /// What a click on a notification does; the control socket's stand-in for one.
    func open(_ id: AIRequestID) {
        NSApp.activate(ignoringOtherApps: true)
        onOpen?(id)
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        guard let raw = response.notification.request.content.userInfo["conversation"] as? String else { return }
        await MainActor.run { self.open(AIRequestID(raw)) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        // Posted while Brk was in the back; it came to the front since: the list says it now.
        []
    }
}
