import AppKit
import BrkBase
import BrkDomain
import BrkSettings
import BrkLayout

@MainActor
final class SitePanels: NSObject, NSWindowDelegate {
    private var panels: [WindowID: NSPanel] = [:]
    private var values: [WindowID: SiteControlSnapshot] = [:]
    var send: ((WindowID, Command) -> Void)?
    func render(_ snapshots: [WindowID: SiteControlSnapshot], owner: (WindowID) -> NSWindow?) {
        for id in panels.keys where snapshots[id] == nil { panels.removeValue(forKey: id)?.close(); values[id] = nil }
        for (id, value) in snapshots {
            guard let parent = owner(id) else { continue }
            let panel: NSPanel
            if let existing = panels[id] { panel = existing }
            else {
                panel = SiteControlPanel(contentRect: CGRect(x: 0, y: 0, width: 440, height: 680), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
                panel.title = "Website controls"
                panel.hidesOnDeactivate = false
                panel.isReleasedWhenClosed = false
                panel.delegate = self
                panel.contentView = SiteControlsHost(frame: panel.contentLayoutRect)
                panel.setFrameOrigin(CGPoint(x: parent.frame.minX + 30, y: parent.frame.maxY - panel.frame.height - 40))
                panels[id] = panel
                panel.makeKeyAndOrderFront(nil)
            }
            guard values[id] != value else { continue }
            values[id] = value
            (panel.contentView as? SiteControlsHost)?.render(value) { [weak self] in self?.send?(id, $0) }
        }
    }
    func window(for id: WindowID) -> NSWindow? { panels[id] }
    func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel, let id = panels.first(where: { $0.value === panel })?.key else { return }
        panels[id] = nil; values[id] = nil
        send?(id, .site(.closeControls))
    }
}

@MainActor
final class SiteDialogs {
    private struct Prompt {
        let alert: NSAlert
        let target: SiteTarget
        let allowLoading: Bool
        let cancel: () -> Void
    }
    private var prompts: [String: Prompt] = [:]
    func validate(_ snapshot: AppSnapshot) {
        for (id, prompt) in prompts {
            let document = snapshot.observations[prompt.target.page]?.document
            let current = document == .ready(prompt.target.document) || (prompt.allowLoading && document == .loading(prompt.target.document))
            guard !current || !snapshot.pages.contains(where: { $0.id == prompt.target.page && $0.context == prompt.target.context }) else { continue }
            dismiss(id)
        }
    }
    func confirm(_ request: ClearSiteData, in window: NSWindow?, reply: @escaping (Bool) -> Void) {
        guard let window, window.attachedSheet == nil else { reply(false); return }
        let alert = NSAlert()
        alert.messageText = "Clear browsing data?"
        alert.informativeText = request.explanation + "\n\nProfile records, settings, tabs and downloaded files are kept. Active downloads, document output and extension operations must finish first."
        alert.addButton(withTitle: "Clear data"); alert.addButton(withTitle: "Cancel")
        let key = ViewID.settingsField("confirmSiteClear").identifier
        alert.buttons[0].identifier = NSUserInterfaceItemIdentifier(key)
        alert.buttons[0].setAccessibilityIdentifier(key)
        prompts[request.id] = Prompt(alert: alert, target: request.target, allowLoading: false, cancel: { reply(false) })
        alert.beginSheetModal(for: window) { [weak self] response in
            guard self?.prompts.removeValue(forKey: request.id) != nil else { return }
            reply(response == .alertFirstButtonReturn)
        }
    }
    func permission(_ prompt: SitePermissionPrompt, in window: NSWindow?, answer: @escaping (SitePermission, Bool) -> Void) {
        guard let window, window.attachedSheet == nil else { answer(.ask, false); return }
        let alert = NSAlert()
        alert.messageText = "\(prompt.requestingOrigin.value) requests access"
        alert.informativeText = prompt.capabilities.map(\.rawValue).sorted().joined(separator: ", ").capitalized + "\n\nPage: \(prompt.target.origin.value)\nmacOS authorization is also required for protected devices."
        alert.addButton(withTitle: "Allow"); alert.addButton(withTitle: "Deny"); alert.addButton(withTitle: "Dismiss")
        for (index, name) in ["sitePermissionAllow", "sitePermissionDeny", "sitePermissionDismiss"].enumerated() {
            let key = ViewID.settingsField(name).identifier
            alert.buttons[index].identifier = NSUserInterfaceItemIdentifier(key)
            alert.buttons[index].setAccessibilityIdentifier(key)
        }
        alert.showsSuppressionButton = true
        alert.suppressionButton?.title = "Remember for this origin in this profile"
        prompts[prompt.id] = Prompt(alert: alert, target: prompt.target, allowLoading: true, cancel: { answer(.ask, false) })
        alert.beginSheetModal(for: window) { [weak self] response in
            guard self?.prompts.removeValue(forKey: prompt.id) != nil else { return }
            answer(response == .alertFirstButtonReturn ? .allow : response == .alertSecondButtonReturn ? .deny : .ask, alert.suppressionButton?.state == .on)
        }
    }
    func dismiss(_ id: String) {
        guard let prompt = prompts.removeValue(forKey: id) else { return }
        if let window = prompt.alert.window.sheetParent { window.endSheet(prompt.alert.window, returnCode: .cancel) }
        prompt.alert.window.orderOut(nil)
        prompt.cancel()
    }
}

@MainActor
private final class SiteControlPanel: NSPanel {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .control, .option])
        if event.keyCode == 53 || (modifiers == .command && event.charactersIgnoringModifiers?.lowercased() == "w") {
            performClose(nil); return true
        }
        return super.performKeyEquivalent(with: event)
    }
}
