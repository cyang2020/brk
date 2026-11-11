import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

// Arc 1.170's save cards (~/brk-arc-reference/save-password/: save-password-arc.png, save-address-arc.png and
// save-card-arc.png, fixture forms submitted on 2026-11-12): the window dimmed, a symbol on a grey tile, the title,
// the text, the blue Save (↵) at the bottom right beside the decline button with its ESC cap, and for a password
// Never on this site at the bottom left. Their rows sit exactly as the Delete Space dialog's (P27 a): the title's ink
// 119 pt down, 23.5 pt from its baseline to the text's top, 40.5 pt from the text's baseline to the buttons. Copy from
// Arc's binary (ADKClient.showSavePasswordPrompt, showSaveAddressEntryPrompt, showSaveCreditCardPrompt).

public enum SavePromptCopy {
    public static func title(_ kind: SavePrompt.Kind, site: String?) -> String {
        switch kind {
        case .password: site.map { "Save password for \($0)?" } ?? "Save this password?"
        case .address: "Save Address?"
        case .card: "Save this card?"
        }
    }
    public static func body(_ kind: SavePrompt.Kind) -> String {
        switch kind {
        case .password: "That way, it’ll be auto-filled next time"
        case .address: "Saved addresses will appear in auto-fill next time you order something."
        case .card: "That way, it can be auto-filled next time"
        }
    }
    public static func decline(_ kind: SavePrompt.Kind) -> String {
        switch kind {
        case .password: "No"
        case .address: "No Thanks"
        case .card: "Not Now"
        }
    }
    public static let never = "Never on this site"
    public static let save = "Save"
}

@MainActor
public final class SavePromptCard: NSView {
    public let prompt: SavePrompt
    let dialog: ArcDialogView
    /// The button pressed: Save (or Return), the decline button (or Esc, or a click beside the card), Never on this site.
    public var onAnswer: (SavePromptAnswer) -> Void = { _ in }

    public init(_ prompt: SavePrompt, scheme: Scheme) {
        self.prompt = prompt
        let kind = prompt.kind
        let icon: ArcDialogIcon = switch kind { case .password: .key; case .address: .house; case .card: .creditCard }
        dialog = ArcDialogView(scheme: scheme, icon: icon, title: ArcDialogView.title(SavePromptCopy.title(kind, site: prompt.site), scheme: scheme),
                               rows: [ArcDialogRow(view: ArcDialogView.body(SavePromptCopy.body(kind), scheme: scheme), gap: SpaceAlert.deleteBodyGap.value)],
                               buttonGap: SpaceAlert.deleteButtonGap.value, buttonRight: ArcDialog.buttonRight.value[0],
                               confirm: SavePromptCopy.save, cancel: SavePromptCopy.decline(kind), extra: kind == .password ? SavePromptCopy.never : nil)
        super.init(frame: .zero)
        dialog.card.identify(.spaceToolsControl("save-prompt"))
        dialog.extra?.identify(.spaceToolsControl("alert-extra"))
        dialog.escapeCancels = true
        dialog.onCancel = { [weak self] in self?.onAnswer(.notNow) }
        dialog.onConfirm = { [weak self] in self?.onAnswer(.save) }
        dialog.onExtra = { [weak self] in self?.onAnswer(.never) }
        addSubview(dialog)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    public override var isFlipped: Bool { true }

    /// The card takes the keyboard: Return saves, Esc declines.
    public func focus() -> Bool { dialog.focus() }

    /// Escape and Return: the decline and Save buttons (the window hands both keys to an open card before its key
    /// table, WindowController, which would otherwise take them).
    public func decline() { onAnswer(.notNow) }
    public func accept() { onAnswer(.save) }

    public override func layout() {
        super.layout()
        dialog.frame = bounds
    }
}
