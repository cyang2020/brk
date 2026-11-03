import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

// Owner: F2 (with W4's dialog container). The profile dialogs' contents in Arc's centred dialog.

struct ProfileDialogMetrics: MetricGroup {
    let bodyGap = Metric(12.0, .guess("body text's gap under the title, measured on P42 a and Q04 a"))
    let promptGap = Metric([17.6, 18.0], .guess("\"What do you want to call this Profile?\" gap under the body, and its height, measured on P42 a"))
    let nameField = Metric([7.4, 49.0], .guess("name field's gap under the prompt and height, measured on P42 a"))
    let hintGap = Metric([3.0, 16.0], .guess("\"Profiles are not synced…\" gap under the field and height, measured on P42 a"))
    let createButtonGap = Metric(27.0, .guess("New Profile buttons' gap under the hint, measured on P42 a"))
    let pickerGap = Metric([6.0, 28.0], .guess("Change Profile's pill row gap under the body and height, measured on Q04 a"))
    let changeButtonGap = Metric(28.0, .guess("Change Profile buttons' gap under the pill row, measured on Q04 a"))
    let iconGrid = Metric([9.0, 34.0], .guess("New Profile's icon step: columns and cell pitch (ours; Arc's second step was not captured)"))
}

let ProfileDialogLayout = ProfileDialogMetrics()

/// What Arc 1.170 shows where `ProfileCopy` (shared with the Profiles pane) reads otherwise. P42 a and Q04 a.
enum ProfileDialogCopy {
    static let createExplanation = "Profiles make your Spaces truly separate — with their own history, saved passwords, extensions, and other browsing data. No more flipping between work and personal accounts!"
    static let namePlaceholder = "Personal"
    static let notSynced = "Profiles are not synced between computers."
    static let notSyncedBold = "not synced"
    static let next = "Next"
    static func changeTitle(_ space: String) -> String { space.isEmpty ? "Change this Space’s Profile" : "Change \(space)’s Profile" }
    static func spaceProfile(_ space: String) -> String { space.isEmpty ? "Profile" : "\(space)’s Profile" }
    /// GUESS: Arc's second step (the icon) was not captured.
    static func iconTitle(_ name: String) -> String { "Choose an icon for “\(name)”" }
}

@MainActor
final class ProfileDialogView: NSView, NSTextFieldDelegate {
    private var draft: ProfileDraft
    private let dispatch: Dispatch
    private let scheme: Scheme
    private(set) var dialog: ArcDialogView!
    private let nameField = AlertField(placeholder: ProfileDialogCopy.namePlaceholder, fontSize: 16)
    private let typedField = AlertField()
    private let hint = NSTextField(labelWithString: "")
    /// New Profile: 0 the name, 1 the icon.
    private var step = 0
    private let spaceName: String
    private var picker: PickerRow?

    init(_ draft: ProfileDraft, spaceName: String, scheme: Scheme, dispatch: @escaping Dispatch) {
        self.draft = draft
        self.dispatch = dispatch
        self.scheme = scheme
        self.spaceName = spaceName
        super.init(frame: .zero)
        let m = ProfileDialogLayout
        let body = { (text: String) in ArcDialogRow(view: ArcDialogView.body(text, scheme: scheme), gap: m.bodyGap.value) }
        switch draft.dialog {
        case .create:
            dialog = ArcDialogView(scheme: scheme, icon: .profile(badge: "+", color: ProfileFace.green),
                                   title: ArcDialogView.title(ProfileCopy.createTitle, scheme: scheme), rows: nameRows(),
                                   buttonGap: m.createButtonGap.value, buttonRight: ArcDialog.buttonRight.value[1], confirm: ProfileDialogCopy.next)
            dialog.firstField = nameField
        case .change(_, _, let profiles):
            let pill = ProfilePill(scheme: scheme)
            pill.choose = { [weak self] id in
                guard let self else { return }
                if let id { self.draft.chosen = id; self.refresh() } else { self.dispatch(ProfileDraft.newProfileCommand) }
            }
            pill.profiles = profiles
            let row = PickerRow(label: ProfileDialogCopy.spaceProfile(spaceName), pill: pill, scheme: scheme)
            picker = row
            dialog = ArcDialogView(scheme: scheme, icon: .profile(badge: "?", color: ProfileFace.blue),
                                   title: ArcDialogView.title(ProfileDialogCopy.changeTitle(spaceName), bold: [spaceName].filter { !$0.isEmpty }, scheme: scheme),
                                   rows: [body(ProfileCopy.changeExplanation), ArcDialogRow(view: row, gap: m.pickerGap.value[0], height: m.pickerGap.value[1])],
                                   buttonGap: m.changeButtonGap.value, buttonRight: ArcDialog.buttonRight.value[1], confirm: ProfileCopy.changeButton)
        case .delete(let row):
            var rows = [body(draft.explanation)]
            if let detail = draft.detail { rows.append(ArcDialogRow(view: ArcDialogView.body(detail, scheme: scheme), gap: 6)) }
            if ProfileCopy.deleteRefusal(row) == nil {
                typedField.placeholderString = row.name
                rows += [ArcDialogRow(view: ArcDialogView.body(ProfileCopy.deleteTypePrompt, scheme: scheme, size: 15), gap: m.promptGap.value[0], height: m.promptGap.value[1]),
                         ArcDialogRow(view: typedField, gap: m.nameField.value[0], height: 36),
                         ArcDialogRow(view: Self.note(ProfileCopy.cannotBeUndone, bold: nil, symbol: "exclamationmark.triangle", scheme: scheme), gap: m.hintGap.value[0], height: m.hintGap.value[1])]
            }
            dialog = ArcDialogView(scheme: scheme, icon: .profile(badge: "−", color: ProfileFace.red),
                                   title: ArcDialogView.title(ProfileCopy.deleteTitle, scheme: scheme), rows: rows,
                                   buttonGap: m.createButtonGap.value, buttonRight: ArcDialog.buttonRight.value[1],
                                   confirm: ProfileCopy.deleteButton, destructive: true)
            if ProfileCopy.deleteRefusal(row) == nil { dialog.firstField = typedField }
        }
        for field in [nameField, typedField] {
            field.delegate = self
            field.target = self
            field.action = #selector(confirm)
        }
        nameField.identify(.spaceToolsControl("profile-name"))
        typedField.identify(.spaceToolsControl("profile-typed-name"))
        dialog.card.identify(.profileDialog)
        dialog.onCancel = { [dispatch] in dispatch(ProfileDraft.cancelCommand) }
        dialog.onConfirm = { [weak self] in self?.confirm() }
        addSubview(dialog)
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        dialog.frame = bounds
    }

    private func nameRows() -> [ArcDialogRow] {
        let m = ProfileDialogLayout
        return [ArcDialogRow(view: ArcDialogView.body(ProfileDialogCopy.createExplanation, scheme: scheme), gap: m.bodyGap.value),
                ArcDialogRow(view: ArcDialogView.body(ProfileCopy.namePrompt, scheme: scheme, size: 15), gap: m.promptGap.value[0], height: m.promptGap.value[1]),
                ArcDialogRow(view: nameField, gap: m.nameField.value[0], height: m.nameField.value[1]),
                ArcDialogRow(view: hint, gap: m.hintGap.value[0], height: m.hintGap.value[1])]
    }

    /// The grey line under a field, with a symbol in front and one part bold ("Profiles are **not synced** …").
    static func note(_ text: String, bold: String?, symbol: String, scheme: Scheme, color: NSColor? = nil) -> NSTextField {
        let ink = color ?? OverlayColors.of(scheme).foregroundSecondary
        let result = NSMutableAttributedString()
        if let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)) {
            let attachment = NSTextAttachment()
            attachment.image = image
            result.append(NSAttributedString(attachment: attachment))
            result.append(NSAttributedString(string: " "))
        }
        result.append(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 12.5), .foregroundColor: ink]))
        if let bold {
            let range = (result.string as NSString).range(of: bold)
            if range.location != NSNotFound { result.addAttribute(.font, value: NSFont.systemFont(ofSize: 12.5, weight: .bold), range: range) }
        }
        result.addAttribute(.foregroundColor, value: ink, range: NSRange(location: 0, length: result.length))
        let label = NSTextField(labelWithAttributedString: result)
        return label
    }

    private func refresh() {
        switch draft.dialog {
        case .create:
            if step == 0 {
                let error = draft.error
                let note = Self.note(error ?? ProfileDialogCopy.notSynced, bold: error == nil ? ProfileDialogCopy.notSyncedBold : nil,
                                     symbol: error == nil ? "clock.arrow.circlepath" : "exclamationmark.circle", scheme: scheme,
                                     color: error == nil ? nil : .systemRed)
                hint.attributedStringValue = note.attributedStringValue
                dialog.confirm.isEnabled = ProfileCopy.acceptsName(draft.name, among: draft.refusedName.map { [$0] } ?? [])
            } else {
                dialog.confirm.isEnabled = draft.confirmCommand != nil
            }
        case .change:
            dialog.confirm.isEnabled = true
            picker?.pill.render(name: profileName(draft.chosen), scheme: scheme, chosen: draft.chosen)
        case .delete:
            dialog.confirm.isEnabled = draft.confirmCommand != nil
        }
    }

    private func profileName(_ id: ProfileID?) -> String {
        guard case .change(_, _, let profiles) = draft.dialog else { return "" }
        return profiles.first { $0.id == id }?.name ?? "Default"
    }

    func controlTextDidChange(_ obj: Notification) {
        if (obj.object as? NSTextField) === nameField { draft.name = nameField.stringValue }
        if (obj.object as? NSTextField) === typedField { draft.typedName = typedField.stringValue }
        refresh()
    }

    @objc private func confirm() {
        switch draft.dialog {
        case .create where step == 0:
            guard dialog.confirm.isEnabled else { return }
            step = 1
            let grid = IconGrid(selected: draft.icon, scheme: scheme) { [weak self] icon in
                self?.draft.icon = icon
            }
            dialog.setRows([ArcDialogRow(view: grid, gap: 16, height: grid.height)],
                           title: ArcDialogView.title(ProfileDialogCopy.iconTitle(ProfileCopy.trimmed(draft.name)), scheme: scheme))
            dialog.confirm.setTitle(ProfileCopy.createButton)
            _ = window?.makeFirstResponder(dialog)
            refresh()
        case .create:
            guard let command = draft.confirmCommand else { return }
            dispatch(command)
            draft.confirmed()
            // Still here: the name was refused. Back to it, with the message.
            step = 0
            dialog.setRows(nameRows(), title: ArcDialogView.title(ProfileCopy.createTitle, scheme: scheme))
            dialog.confirm.setTitle(ProfileDialogCopy.next)
            _ = dialog.focus()
            refresh()
        case .change:
            dispatch(draft.confirmCommand ?? ProfileDraft.cancelCommand)
        case .delete:
            if let command = draft.confirmCommand { dispatch(command) }
        }
    }
}

/// Change Profile's row: "X’s Profile" and the pill.
@MainActor
private final class PickerRow: NSView {
    override var isFlipped: Bool { true }
    let label: NSTextField
    let pill: ProfilePill

    init(label text: String, pill: ProfilePill, scheme: Scheme) {
        label = NSTextField(labelWithString: text)
        self.pill = pill
        super.init(frame: .zero)
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = OverlayColors.of(scheme).foregroundPrimary
        addSubview(label)
        addSubview(pill)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        let size = label.intrinsicContentSize
        label.frame = CGRect(x: 0, y: (bounds.height - size.height) / 2, width: ceil(size.width) + 2, height: size.height)
        let width = pill.fittingWidth
        pill.frame = CGRect(x: label.frame.maxX + 6, y: 0, width: width, height: bounds.height)
    }
}

/// The profile pill of Change Profile (Q04 a): ProfilePicker blue, a check and the profile's name. A left or right
/// click opens the menu of every profile and New Profile….
@MainActor
final class ProfilePill: NSView {
    var profiles: [ProfileRow] = []
    var choose: (ProfileID?) -> Void = { _ in }
    private var name = ""
    private var chosen: ProfileID?
    private var scheme: Scheme
    private var items: [NSMenuItem: ProfileID] = [:]

    init(scheme: Scheme) {
        self.scheme = scheme
        super.init(frame: .zero)
        identify(.spaceToolsControl("profile-pill"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func render(name: String, scheme: Scheme, chosen: ProfileID?) {
        self.name = name
        self.scheme = scheme
        self.chosen = chosen
        needsDisplay = true
        superview?.needsLayout = true
    }

    private var text: NSAttributedString {
        let ink = scheme == .light ? NSColor(srgbRed: 0x06 / 255.0, green: 0x0E / 255.0, blue: 0x2B / 255.0, alpha: 1) : NSColor(srgbRed: 0xE3 / 255.0, green: 0xE2 / 255.0, blue: 0xEE / 255.0, alpha: 1)
        return NSAttributedString(string: name, attributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: ink])
    }

    var fittingWidth: Double { ceil(text.size().width) + 52 }

    override func draw(_ dirtyRect: NSRect) {
        let blue = ArcDialog.primary.value.color
        blue.withAlphaComponent(scheme == .light ? 0.1 : 0.9).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 6, yRadius: 6).fill()
        let ink = (text.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor) ?? .black
        if let check = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)) {
            let tinted = NSImage(size: check.size, flipped: false) { rect in
                check.draw(in: rect)
                ink.set()
                rect.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: CGRect(x: 10, y: (bounds.height - check.size.height) / 2, width: check.size.width, height: check.size.height))
        }
        let size = text.size()
        text.draw(at: CGPoint(x: 32, y: (bounds.height - size.height) / 2))
    }

    override func mouseDown(with event: NSEvent) { popUp() }
    override func rightMouseDown(with event: NSEvent) { popUp() }

    private func popUp() {
        let menu = NSMenu()
        items = [:]
        for row in profiles {
            let item = NSMenuItem(title: row.name, action: #selector(pick(_:)), keyEquivalent: "")
            item.target = self
            item.state = row.id == chosen ? .on : .off
            items[item] = row.id
            menu.addItem(item)
        }
        menu.addItem(.separator())
        let create = NSMenuItem(title: ProfileCopy.createFromChange, action: #selector(pick(_:)), keyEquivalent: "")
        create.target = self
        menu.addItem(create)
        menu.popUp(positioning: nil, at: CGPoint(x: 0, y: bounds.height + 4), in: self)
    }

    @objc private func pick(_ item: NSMenuItem) { choose(items[item]) }
}

/// New Profile's icon step: the default person glyph, then Arc's named icons.
@MainActor
private final class IconGrid: NSView {
    override var isFlipped: Bool { true }
    private var buttons: [(NSButton, CustomIcon?)] = []
    private var selected: CustomIcon?
    private let pick: (CustomIcon?) -> Void
    let height: Double

    init(selected: CustomIcon?, scheme: Scheme, pick: @escaping (CustomIcon?) -> Void) {
        self.selected = selected
        self.pick = pick
        let icons: [CustomIcon?] = [nil] + NamedIcon.allCases.map { CustomIcon.named($0) }
        let columns = Int(ProfileDialogLayout.iconGrid.value[0]), pitch = ProfileDialogLayout.iconGrid.value[1]
        height = Double((icons.count + columns - 1) / columns) * pitch
        super.init(frame: .zero)
        for (index, icon) in icons.enumerated() {
            let symbol = icon.map { if case .named(let name) = $0 { NamedIconSymbol.of(name) } else { ProfileGlyph.defaultSymbol } } ?? ProfileGlyph.defaultSymbol
            let button = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: nil) ?? NSImage(), target: self, action: #selector(clicked(_:)))
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerCurve = .continuous
            button.layer?.cornerRadius = ArcDialog.fieldRadius.value
            button.contentTintColor = OverlayColors.of(scheme).foregroundPrimary
            button.tag = index
            button.setAccessibilityLabel(icon.map(ProfileGlyph.name) ?? "Default")
            button.identify(.spaceToolsControl("profile-icon-\(index)"))
            addSubview(button)
            buttons.append((button, icon))
        }
        restyle()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func layout() {
        super.layout()
        let columns = Int(ProfileDialogLayout.iconGrid.value[0]), pitch = ProfileDialogLayout.iconGrid.value[1]
        let left = (bounds.width - Double(columns) * pitch) / 2
        for (index, (button, _)) in buttons.enumerated() {
            button.frame = CGRect(x: left + Double(index % columns) * pitch + 2, y: Double(index / columns) * pitch + 2, width: pitch - 4, height: pitch - 4)
        }
    }

    private func restyle() {
        for (button, icon) in buttons {
            button.layer?.backgroundColor = (icon == selected ? ArcDialog.primary.value.color.withAlphaComponent(0.14) : NSColor.black.withAlphaComponent(0.04)).cgColor
        }
    }

    @objc private func clicked(_ sender: NSButton) {
        selected = buttons[sender.tag].1
        pick(selected)
        restyle()
    }
}

extension AlertButton {
    func setTitle(_ title: String) {
        for case let label as NSTextField in subviews where label.stringValue != "ESC" && label.stringValue != "↵" {
            label.stringValue = title
            setAccessibilityLabel(title)
        }
        superview?.needsLayout = true
        needsLayout = true
    }
}
