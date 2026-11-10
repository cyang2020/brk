import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

// Owner: W4 (dialogs). Rename Space and the Delete Space confirmation in Arc's centred dialog (`ArcDialog.swift`),
// matched to P26 a (Rename “X”, the name filled in and selected, Rename) and P27 a (the app icon, Delete your “X”
// Space?, one line of text, the red Delete). Deleting an Easel asks in the same dialog (Q09 c).

struct SpaceAlertMetrics: MetricGroup {
    let renameField = Metric([24.0, 36.0], .guess("Rename field's gap under the title and height (the field 375 wide, its top 100 pt down), measured on P26 a"))
    let renameButtonGap = Metric(21.5, .guess("Rename buttons' gap under the field, measured on P26 a"))
    let deleteBodyGap = Metric(17.0, .anatomy("scripts/station/arc-reference/P27/P27-a-arc.png: the title's ink ends at y 776 px, the text's starts at 817 px"))
    let deleteButtonGap = Metric(37.5, .anatomy("scripts/station/arc-reference/P27/P27-a-arc.png: the text's ink ends at y 838 px, the buttons start at 919 px; the card stays 273 points tall"))
}

let SpaceAlert = SpaceAlertMetrics()

enum SpaceAlertCopy {
    /// Observed on P26 a and P27 a.
    static func renameTitle(_ name: String) -> String { "Rename “\(name)”" }
    static let rename = "Rename"
    static func deleteTitle(_ name: String) -> String { "Delete your “\(name)” Space?" }
    static let deleteBody = "This will archive all the tabs and folders inside it."
    static let delete = "Delete"
}

/// What the dialog shows and the commands its buttons send.
enum SpaceAlertKind: Equatable {
    case rename(id: SpaceID, title: String)
    case delete(SpaceDeletionRequest)
    case deleteEasel(EaselDeletionRequest)
    /// Brk's own: a conversation deleted for good, from the AI panel's list or the Library's "AI 对话" page.
    case deleteConversation(ConversationDeletionRequest)

    var cancelCommand: Command {
        switch self {
        case .rename: .sidebar(.openDialog(nil))
        case .delete(let request): .space(.confirmDelete(request.id, token: request.token, confirmed: false))
        case .deleteEasel(let request): .easel(.confirmDelete(request.id, token: request.token, confirmed: false))
        case .deleteConversation(let request): .library(.confirmDeleteConversation(request.id, token: request.token, confirmed: false))
        }
    }

    /// Rename with a blank name is not offered (the button is disabled); the name is trimmed.
    func confirmCommand(name: String) -> Command? {
        switch self {
        case .rename(let id, _):
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : .space(.update(id, title: trimmed, icon: nil, theme: nil))
        case .delete(let request): return .space(.confirmDelete(request.id, token: request.token, confirmed: true))
        case .deleteEasel(let request): return .easel(.confirmDelete(request.id, token: request.token, confirmed: true))
        case .deleteConversation(let request): return .library(.confirmDeleteConversation(request.id, token: request.token, confirmed: true))
        }
    }
}

@MainActor
final class SpaceAlertView: NSView, NSTextFieldDelegate {
    let alert: SpaceAlertKind
    private let dispatch: Dispatch
    let dialog: ArcDialogView
    let field = AlertField()

    init(_ alert: SpaceAlertKind, scheme: Scheme, dispatch: @escaping Dispatch) {
        self.alert = alert
        self.dispatch = dispatch
        switch alert {
        case .rename(_, let name):
            field.stringValue = name
            dialog = ArcDialogView(scheme: scheme, icon: nil, title: ArcDialogView.title(SpaceAlertCopy.renameTitle(name), scheme: scheme),
                                   rows: [ArcDialogRow(view: field, gap: SpaceAlert.renameField.value[0], height: SpaceAlert.renameField.value[1])],
                                   buttonGap: SpaceAlert.renameButtonGap.value, buttonRight: ArcDialog.buttonRight.value[0], confirm: SpaceAlertCopy.rename)
            dialog.firstField = field
        case .delete(let request):
            dialog = ArcDialogView(scheme: scheme, icon: .app, title: ArcDialogView.title(SpaceAlertCopy.deleteTitle(request.title), scheme: scheme),
                                   rows: [ArcDialogRow(view: ArcDialogView.body(SpaceAlertCopy.deleteBody, scheme: scheme), gap: SpaceAlert.deleteBodyGap.value)],
                                   buttonGap: SpaceAlert.deleteButtonGap.value, buttonRight: ArcDialog.buttonRight.value[0],
                                   confirm: SpaceAlertCopy.delete, destructive: true)
        case .deleteEasel:
            dialog = ArcDialogView(scheme: scheme, icon: .app, title: ArcDialogView.title(EaselCopy.deleteTitle, scheme: scheme),
                                   rows: [ArcDialogRow(view: ArcDialogView.body(EaselCopy.deleteBody, scheme: scheme), gap: SpaceAlert.deleteBodyGap.value)],
                                   buttonGap: SpaceAlert.deleteButtonGap.value, buttonRight: ArcDialog.buttonRight.value[0],
                                   confirm: EaselCopy.delete, destructive: true)
        case .deleteConversation(let request):
            let language = request.language
            dialog = ArcDialogView(scheme: scheme, icon: .app, title: ArcDialogView.title(AIThreadWords.deleteQuestion(AgentLine.oneLine(request.title, limit: 60), language), scheme: scheme),
                                   rows: [ArcDialogRow(view: ArcDialogView.body(AIThreadWords.deleteDetail(pages: request.pages, language), scheme: scheme), gap: SpaceAlert.deleteBodyGap.value)],
                                   buttonGap: SpaceAlert.deleteButtonGap.value, buttonRight: ArcDialog.buttonRight.value[0],
                                   confirm: AIThreadWords.delete(language), destructive: true, cancel: AIThreadWords.cancel(language))
        }
        super.init(frame: .zero)
        field.delegate = self
        field.target = self
        field.action = #selector(confirmClicked)
        field.identify(.spaceToolsControl("space-rename-field"))
        dialog.card.identify(.spaceDialog)
        dialog.onCancel = { [weak self] in self.map { $0.dispatch($0.alert.cancelCommand) } }
        dialog.onConfirm = { [weak self] in self?.confirmClicked() }
        addSubview(dialog)
        updateConfirm()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    var card: NSView { dialog.card }
    var cancel: AlertButton { dialog.cancel }
    var confirm: AlertButton { dialog.confirm }

    func focus() -> Bool { dialog.focus() }

    override func layout() {
        super.layout()
        dialog.frame = bounds
    }

    func controlTextDidChange(_ obj: Notification) { updateConfirm() }

    private func updateConfirm() {
        dialog.confirm.isEnabled = alert.confirmCommand(name: field.stringValue) != nil
    }

    @objc private func confirmClicked() {
        if let command = alert.confirmCommand(name: field.stringValue) { dispatch(command) }
    }
}
