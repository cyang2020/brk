import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit
import SwiftUI

// The settings window's building blocks, shared by every pane (and by the slots F2, F3 and F4 fill).
//
// Layout follows the sindresorhus/Settings package Arc builds its panes with (`Settings.Container`,
// `Settings.Section`): a right-aligned label column, the controls beside it, a divider between sections.
//
// Controls are AppKit controls inside SwiftUI (SwiftUI's own checkboxes and pop-ups are AppKit views underneath, but
// they do not carry the accessibility identifier, so neither the control socket nor a test could find them). Each
// control shows exactly the snapshot's value: a click asks for the change by dispatching a command and puts the
// control back at the snapshot's value; the next render shows the answer. Nothing is kept in the view.

private var S: SettingsMetrics { Metrics.settings }

// MARK: - Layout

/// A pane's body: fixed width, the package's padding.
struct SettingsContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content }
            .frame(width: S.contentWidth.value, alignment: .leading)
            .padding(.horizontal, S.horizontalPadding.value)
            .padding(.vertical, S.verticalPadding.value)
    }
}

/// What sits in a section's label column.
enum SectionLabel {
    case none
    case text(String)
    /// An SF Symbol (Arc's Advanced pane labels its groups with icons).
    case symbol(String)
}

/// One row of the label column and the controls beside it (Arc: `Settings.Section`).
struct SettingsSection<Content: View>: View {
    let label: SectionLabel
    @ViewBuilder var content: Content

    init(_ label: SectionLabel = .none, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: S.columnSpacing.value) {
            Group {
                switch label {
                case .none: Text(verbatim: " ")
                case .text(let text): Text(text)
                case .symbol(let name): Image(systemName: name).foregroundStyle(.secondary)
                }
            }
            .frame(width: S.labelWidth.value, alignment: .trailing)
            VStack(alignment: .leading, spacing: S.rowSpacing.value) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// The divider row between sections.
struct SettingsDivider: View {
    var body: some View { Divider().frame(height: S.sectionSpacing.value) }
}

/// Secondary text under a control or a section; wraps inside the column.
struct SettingsNote: View {
    let text: String
    /// Under a checkbox the text lines up with the checkbox's title.
    var underCheckbox = false

    var body: some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.leading, underCheckbox ? S.checkboxTextInset.value : 0)
    }
}

/// An NSView carrying a `ViewID` behind a SwiftUI region (a pane, a list), so the control socket and tests can find
/// it. It takes no clicks.
struct IdentifiedRegion: NSViewRepresentable {
    let id: ViewID
    var label: String?

    func makeNSView(context: NSViewRepresentableContext<Self>) -> PassThroughView {
        let view = PassThroughView()
        view.identify(id)
        return view
    }

    func updateNSView(_ view: PassThroughView, context: NSViewRepresentableContext<Self>) {
        view.identify(id)
        view.setAccessibilityLabel(label)
    }

    final class PassThroughView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

// MARK: - Controls

/// An AppKit control's own size, narrowed to the offer (it truncates rather than overflow). Without this SwiftUI
/// treats a control with low hugging priority as flexible and stretches it.
@MainActor
private func fitted(_ control: NSView, _ proposal: ProposedViewSize) -> CGSize {
    let natural = control.intrinsicContentSize
    return CGSize(width: min(proposal.width ?? natural.width, natural.width), height: natural.height)
}

/// A checkbox for one Bool setting. `field` names it (`settings-field-<field>`).
struct SettingsCheckbox: NSViewRepresentable {
    let title: String
    let field: String
    let isOn: Bool
    let toggle: @MainActor (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: NSViewRepresentableContext<Self>) -> NSButton {
        let button = NSButton(checkboxWithTitle: title, target: context.coordinator, action: #selector(Coordinator.clicked(_:)))
        button.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)
        return button
    }

    func updateNSView(_ button: NSButton, context: NSViewRepresentableContext<Self>) {
        context.coordinator.isOn = isOn
        context.coordinator.toggle = toggle
        button.isEnabled = context.environment.isEnabled
        button.identify(.settingsField(field))
        if button.title != title { button.title = title }
        button.state = isOn ? .on : .off
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView button: NSButton, context: NSViewRepresentableContext<Self>) -> CGSize? {
        fitted(button, proposal)
    }

    @MainActor final class Coordinator: NSObject {
        var isOn = false
        var toggle: (@MainActor (Bool) -> Void)?

        @objc func clicked(_ sender: NSButton) {
            let wanted = sender.state == .on
            sender.state = isOn ? .on : .off
            if wanted != isOn { toggle?(wanted) }
        }
    }
}

/// One entry of a settings pop-up.
enum PopUpEntry<Value: Hashable> {
    case option(String, Value, image: NSImage? = nil)
    case separator
    /// Runs instead of choosing a value ("Other…" opens the folder panel); the pop-up stays on the snapshot's value.
    case action(String, @MainActor () -> Void)

    var title: String? {
        switch self {
        case .option(let title, _, _), .action(let title, _): title
        case .separator: nil
        }
    }
}

/// A pop-up button for one choice. `selected` is the snapshot's value; choosing another calls `choose` once.
struct SettingsPopUp<Value: Hashable>: NSViewRepresentable {
    let field: String
    let entries: [PopUpEntry<Value>]
    let selected: Value?
    let choose: @MainActor (Value) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: NSViewRepresentableContext<Self>) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.picked(_:))
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: NSViewRepresentableContext<Self>) {
        context.coordinator.entries = entries
        context.coordinator.selected = selected
        context.coordinator.choose = choose
        button.identify(.settingsField(field))
        let titles = entries.map { $0.title ?? "" }
        if button.itemArray.map(\.title) != titles || button.itemArray.count != entries.count {
            button.removeAllItems()
            for entry in entries {
                switch entry {
                case .separator: button.menu?.addItem(.separator())
                case .option(let title, _, let image):
                    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                    item.image = image
                    button.menu?.addItem(item)
                case .action(let title, _):
                    button.menu?.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: ""))
                }
            }
        }
        context.coordinator.showSelected(in: button)
    }

    /// As wide as offered (the panes give pop-ups one width so they line up), as tall as the control.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView button: NSPopUpButton, context: NSViewRepresentableContext<Self>) -> CGSize? {
        CGSize(width: proposal.width ?? button.intrinsicContentSize.width, height: button.intrinsicContentSize.height)
    }

    @MainActor final class Coordinator: NSObject {
        var entries: [PopUpEntry<Value>] = []
        var selected: Value?
        var choose: (@MainActor (Value) -> Void)?

        func showSelected(in button: NSPopUpButton) {
            let index = entries.firstIndex { if case .option(_, let value, _) = $0 { value == selected } else { false } }
            if let index { button.selectItem(at: index) } else { button.select(nil) }
        }

        @objc func picked(_ sender: NSPopUpButton) {
            let index = sender.indexOfSelectedItem
            showSelected(in: sender)
            guard entries.indices.contains(index) else { return }
            switch entries[index] {
            case .option(_, let value, _): if value != selected { choose?(value) }
            case .action(_, let run): run()
            case .separator: break
            }
        }
    }
}

/// A push button, or a borderless icon button when `symbol` is set.
struct SettingsButton: NSViewRepresentable {
    let title: String
    let field: String
    var symbol: String?
    let action: @MainActor () -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: NSViewRepresentableContext<Self>) -> NSButton {
        let button = NSButton(title: title, target: context.coordinator, action: #selector(Coordinator.clicked(_:)))
        if let symbol, let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title) {
            button.image = image
            button.imagePosition = .imageOnly
            button.isBordered = false
            button.contentTintColor = .secondaryLabelColor
        }
        return button
    }

    func updateNSView(_ button: NSButton, context: NSViewRepresentableContext<Self>) {
        context.coordinator.action = action
        button.isEnabled = context.environment.isEnabled
        button.identify(.settingsField(field))
        if button.title != title { button.title = title }
        button.toolTip = symbol == nil ? nil : title
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView button: NSButton, context: NSViewRepresentableContext<Self>) -> CGSize? {
        fitted(button, proposal)
    }

    @MainActor final class Coordinator: NSObject {
        var action: (@MainActor () -> Void)?
        @objc func clicked(_ sender: NSButton) { action?() }
    }
}

/// A one-line text field that commits on Return or when editing ends (not per keystroke). `text` is the snapshot's
/// value; while the user edits, the field keeps the typed text (typed text is view state, like the command bar's).
struct SettingsTextField: NSViewRepresentable {
    let field: String
    let text: String
    let placeholder: String
    var edit: (@MainActor (String) -> Void)? = nil
    var submit: (@MainActor (String) -> Void)? = nil
    let commit: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: NSViewRepresentableContext<Self>) -> NSTextField {
        let textField = NSTextField(string: text)
        textField.placeholderString = placeholder
        textField.delegate = context.coordinator
        textField.target = context.coordinator
        textField.action = #selector(Coordinator.committed(_:))
        textField.lineBreakMode = .byTruncatingTail
        textField.cell?.isScrollable = true
        textField.cell?.wraps = false
        return textField
    }

    func updateNSView(_ textField: NSTextField, context: NSViewRepresentableContext<Self>) {
        context.coordinator.commit = commit
        context.coordinator.edit = edit
        context.coordinator.submit = submit
        context.coordinator.last = text
        textField.identify(.settingsField(field))
        textField.placeholderString = placeholder
        if textField.currentEditor() == nil, textField.stringValue != text { textField.stringValue = text }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView textField: NSTextField, context: NSViewRepresentableContext<Self>) -> CGSize? {
        CGSize(width: proposal.width ?? textField.intrinsicContentSize.width, height: textField.intrinsicContentSize.height)
    }

    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var commit: (@MainActor (String) -> Void)?
        var edit: (@MainActor (String) -> Void)?
        var submit: (@MainActor (String) -> Void)?
        var last = ""

        @objc func committed(_ sender: NSTextField) {
            send(sender.stringValue)
            submit?(sender.stringValue)
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            edit?(field.stringValue)
        }

        func controlTextDidEndEditing(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            send(field.stringValue)
        }

        private func send(_ value: String) {
            guard value != last else { return }
            last = value
            commit?(value)
        }
    }
}

/// A line of text the control socket and tests can read back (`settings-field-<field>`, the label's string value).
struct SettingsLabel: NSViewRepresentable {
    let text: String
    let field: String
    var secondary = false

    func makeNSView(context: NSViewRepresentableContext<Self>) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }

    func updateNSView(_ label: NSTextField, context: NSViewRepresentableContext<Self>) {
        label.identify(.settingsField(field))
        if label.stringValue != text { label.stringValue = text }
        label.textColor = secondary ? .secondaryLabelColor : .labelColor
        label.font = secondary ? .systemFont(ofSize: NSFont.smallSystemFontSize) : .systemFont(ofSize: NSFont.systemFontSize)
    }

    /// Wraps at the offered width, as SwiftUI's own Text does.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView label: NSTextField, context: NSViewRepresentableContext<Self>) -> CGSize? {
        let natural = label.cell?.cellSize ?? label.intrinsicContentSize
        let width = min(proposal.width ?? natural.width, natural.width)
        let height = label.cell?.cellSize(forBounds: CGRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)).height ?? natural.height
        return CGSize(width: width, height: height)
    }
}
