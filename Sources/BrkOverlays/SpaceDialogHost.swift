import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit
import SwiftUI

/// Owner: W4 (dialogs). Every space dialog of a window, matched to the 2026-11-03 Arc 1.170 captures:
/// - New Space: the Create a Space flow in place of the sidebar's contents, a blank card over the content area, the
///   icon popover from the name field's icon button and the theme panel as a popover from Choose a Theme
///   (`SpaceCreateFlow.swift`). The draft's theme and icon are reported through `onDraft` while it is open.
/// - Rename Space and the delete confirmation: the small centred dialogs (`SpaceAlertView.swift`).
/// - Change Space Icon…: the Emoji / Icon popover under the space header (`SpaceIconPicker.swift`).
/// - Edit Theme…: the theme panel beside the sidebar (`ThemeEditor.swift`); each edit is saved as it is made.
/// - Edit Space (the Library's Spaces page): the name and icon form centred in the content area.
///
/// The host spans the window and takes clicks only on what it shows.
@MainActor
public final class SpaceDialogHost: NSView {
    let dispatch: Dispatch
    public var profiles: [ProfileRow] = [] {
        didSet {
            guard profiles != oldValue else { return }
            create?.profiles = profiles
        }
    }
    /// The Create a Space draft (theme and icon) whenever it changes, nil once the flow closes.
    public var onDraft: ((SpaceTheme, SpaceIcon)?) -> Void = { _ in }

    private var dialog: SpaceDialogSnapshot?
    private var deletion: SpaceDeletionRequest?
    private var scheme: Scheme = .light
    private var frames: WindowFrames?

    // Edit Space.
    private let card = NSView()
    private var form: NSHostingController<SpaceDialogForm>?
    var hosting: NSView? { form?.view }
    // Create a Space.
    private var create: SpaceCreateModel?
    private var flow: NSHostingView<SpaceCreateFlowView>?
    private let blank = NSView()
    private var themePopover: ThemePopover?
    // Rename and delete.
    private(set) var alert: SpaceAlertView?
    // Icon and theme.
    private var iconPopover: IconPickerPopover?
    private var themePanel: ThemePanelWindow?

    public init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        isHidden = true
        card.wantsLayer = true
        card.layer?.cornerCurve = .continuous
        card.layer?.cornerRadius = OverlayMetrics.dialog.cornerRadius.value
        card.isHidden = true
        addSubview(card)
        blank.wantsLayer = true
        blank.layer?.cornerCurve = .continuous
        blank.isHidden = true
        addSubview(blank)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    public override var isFlipped: Bool { true }

    public override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }

    /// Keyboard focus into what is open: the delete dialog, the rename field, the Create a Space name field, or the
    /// Edit Space form's first field. False while nothing is shown or the view is not in a window.
    public func focusForm() -> Bool {
        guard !isHidden, let window else { return false }
        if let alert { return alert.focus() }
        if let flow {
            flow.layoutSubtreeIfNeeded()
            return window.makeFirstResponder(Self.firstEditableField(in: flow) ?? flow)
        }
        if let hosting, !card.isHidden {
            hosting.layoutSubtreeIfNeeded()
            return window.makeFirstResponder(Self.firstEditableField(in: hosting) ?? hosting)
        }
        // The popovers and the theme panel leave the browser window's focus where it is.
        return iconPopover != nil || themePanel != nil
    }

    /// SwiftUI's text fields are NSTextFields underneath; the first in view order is the name.
    private static func firstEditableField(in view: NSView) -> NSTextField? {
        for child in view.subviews {
            if let field = child as? NSTextField, field.isEditable { return field }
            if let field = firstEditableField(in: child) { return field }
        }
        return nil
    }

    public func render(_ dialog: SpaceDialogSnapshot?, deletion: SpaceDeletionRequest?, frames: WindowFrames, palette: Palette) {
        if let superview { frame = superview.bounds }
        self.frames = frames
        let schemeChanged = palette.scheme != scheme
        scheme = palette.scheme
        let previous = self.dialog
        self.dialog = dialog
        self.deletion = deletion

        // What closed.
        if !Self.sameKind(previous, dialog) {
            closeCreate()
            closeEdit()
            iconPopover?.dismiss(); iconPopover = nil
            themePanel?.dismiss(); themePanel = nil
        }
        let wantsAlert: SpaceAlertKind? = deletion.map { .delete($0) } ?? {
            if case .rename(let id, let title)? = dialog { return .rename(id: id, title: title) }
            return nil
        }()
        if alert?.alert != wantsAlert || schemeChanged {
            alert?.removeFromSuperview()
            alert = wantsAlert.map { SpaceAlertView($0, scheme: scheme, dispatch: dispatch) }
            if let alert { addSubview(alert) }
        }
        alert?.frame = bounds
        // Shown before the popovers open: AppKit shows none relative to a hidden view.
        isHidden = dialog == nil && deletion == nil

        switch dialog {
        case .newSpace?: showCreate(frames: frames)
        case .editSpace?: showEdit(dialog!, in: frames.contentArea, schemeChanged: schemeChanged)
        case .icon(let id, let icon)?: showIconPicker(space: id, icon: icon, frames: frames)
        case .theme(let id, let theme)?: showThemePanel(space: id, theme: theme, frames: frames)
        case .rename?, nil: break
        }
    }

    private static func sameKind(_ a: SpaceDialogSnapshot?, _ b: SpaceDialogSnapshot?) -> Bool {
        switch (a, b) {
        case (nil, nil), (.newSpace?, .newSpace?): true
        case (.editSpace(let x, _, _, _)?, .editSpace(let y, _, _, _)?): x == y
        case (.rename(let x, _)?, .rename(let y, _)?): x == y
        case (.icon(let x, _)?, .icon(let y, _)?): x == y
        case (.theme(let x, _)?, .theme(let y, _)?): x == y
        default: false
        }
    }

    private var systemScheme: Scheme {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }

    // MARK: Create a Space

    private func showCreate(frames: WindowFrames) {
        guard let sidebar = frames.sidebar else { return }
        if create == nil {
            let model = SpaceCreateModel(dispatch: dispatch)
            model.profiles = profiles
            model.systemScheme = systemScheme
            model.theme.draft.systemScheme = systemScheme
            model.changed = { [weak self] draft in self?.onDraft((draft.theme, draft.icon)) }
            model.showIconPicker = { [weak self, weak model] in
                guard let self, let model, let flow = self.flow else { return }
                self.iconPopover?.dismiss()
                let popover = IconPickerPopover(icon: model.draft.icon, pick: { [weak model] icon in model?.draft.icon = icon }, closed: { [weak self] in self?.iconPopover = nil })
                self.iconPopover = popover
                let field = CreateFlow.field.value
                popover.show(relativeTo: CGRect(x: field.minX + 4, y: field.minY - CreateFlow.top.value, width: 22, height: field.height), of: flow,
                             scheme: resolveTheme(model.draft.theme, systemScheme: self.systemScheme).scheme)
            }
            model.showThemeEditor = { [weak self, weak model] in
                guard let self, let model, let flow = self.flow else { return }
                let popover = self.themePopover ?? ThemePopover(model: model.theme)
                self.themePopover = popover
                let row = CreateFlow.themeRow.value
                popover.show(relativeTo: CGRect(x: row.minX, y: row.minY - CreateFlow.top.value, width: row.width, height: row.height), of: flow, scheme: .light)
            }
            create = model
            onDraft((model.draft.theme, model.draft.icon))
        }
        guard let create else { return }
        let top = sidebar.frame.minY + CreateFlow.top.value
        let height = max(0, sidebar.dock.minY - top)
        if flow == nil {
            let view = NSHostingView(rootView: SpaceCreateFlowView(model: create, height: height))
            view.identify(.spaceDialog)
            addSubview(view)
            flow = view
        } else if flow?.rootView.height != height {
            flow?.rootView = SpaceCreateFlowView(model: create, height: height)
        }
        flow?.frame = CGRect(x: sidebar.frame.minX, y: top, width: sidebar.frame.width, height: height)
        blank.isHidden = false
        blank.frame = frames.contentArea
        blank.layer?.cornerRadius = Metrics.content.cornerRadius.value
        blank.layer?.backgroundColor = NSColor.white.withAlphaComponent(scheme == .light ? 0.75 : 0.08).cgColor
    }

    private func closeCreate() {
        guard create != nil || flow != nil else { return }
        themePopover?.dismiss(); themePopover = nil
        flow?.removeFromSuperview(); flow = nil
        create = nil
        blank.isHidden = true
        onDraft(nil)
    }

    // MARK: Icon and theme

    private func showIconPicker(space: SpaceID, icon: SpaceIcon, frames: WindowFrames) {
        guard iconPopover == nil, let header = frames.sidebar?.spaceHeader else { return }
        let popover = IconPickerPopover(icon: icon, pick: { [dispatch] icon in
            dispatch(.space(.update(space, title: nil, icon: icon, theme: nil)))
        }, closed: { [weak self, dispatch] in
            guard let self, case .icon(space, _)? = self.dialog else { return }
            self.iconPopover = nil
            dispatch(.sidebar(.openDialog(nil)))
        })
        iconPopover = popover
        popover.show(relativeTo: CGRect(x: header.minX + 8, y: header.minY, width: 22, height: header.height), of: self, scheme: scheme)
    }

    private func showThemePanel(space: SpaceID, theme: SpaceTheme, frames: WindowFrames) {
        guard let window else { return }
        let draft = ThemeDraft(theme: theme, systemScheme: systemScheme)
        if themePanel?.space != space {
            themePanel?.dismiss()
            themePanel = ThemePanelWindow(space: space, draft: draft, onChange: { [dispatch] draft in
                dispatch(.space(.update(space, title: nil, icon: nil, theme: draft.theme)))
            }, close: { [dispatch] in dispatch(.sidebar(.openDialog(nil))) })
        }
        themePanel?.update(draft)
        themePanel?.show(over: window, sidebarMaxX: Double(frames.sidebar?.frame.maxX ?? 0), scheme: scheme)
    }

    // MARK: Edit Space

    /// A different space starts a fresh form; the same one keeps what the user has entered.
    private func showEdit(_ dialog: SpaceDialogSnapshot, in area: CGRect, schemeChanged: Bool) {
        if form == nil {
            let controller = NSHostingController(rootView: SpaceDialogForm(draft: SpaceDraft(dialog), dispatch: dispatch))
            // The card never sits under the titlebar; without this the window's titlebar inset pads the form.
            controller.safeAreaRegions = []
            card.addSubview(controller.view)
            card.identify(.spaceDialog)
            form = controller
        }
        if schemeChanged || card.isHidden {
            let colors = OverlayColors.of(scheme)
            card.appearance = .of(scheme)
            card.layer?.backgroundColor = colors.popover.cgColor
            card.shadow = .popover(colors)
        }
        card.isHidden = false
        let margin = Metrics.commandBar.minVerticalMargin.value
        let width = min(OverlayMetrics.dialog.width.value, area.width - 2 * margin)
        let fitted = form?.sizeThatFits(in: CGSize(width: width, height: area.height)).height ?? 0
        let height = min(fitted, area.height - 2 * margin)
        card.frame = CGRect(x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height).integral
        hosting?.frame = card.bounds
    }

    private func closeEdit() {
        hosting?.removeFromSuperview()
        form = nil
        card.isHidden = true
    }

    /// The card's frame while Edit Space is open (tests).
    var editCardFrame: CGRect? { card.isHidden ? nil : card.frame }
}

/// What the Edit Space form edits, and the commands its two buttons send. Plain data, so the decisions are testable
/// without SwiftUI.
struct SpaceDraft: Equatable {
    let editing: SpaceID
    var title: String
    var icon: SpaceIcon
    let theme: SpaceTheme

    /// Nil for anything but Edit Space.
    init?(_ dialog: SpaceDialogSnapshot) {
        guard case .editSpace(let id, let title, let icon, let theme) = dialog else { return nil }
        editing = id
        self.title = title
        self.icon = icon
        self.theme = theme
    }

    /// Save: the trimmed name (blank keeps the old one) and the icon. The theme is the theme panel's.
    var saveCommand: Command {
        .space(.update(editing, title: title.trimmingCharacters(in: .whitespacesAndNewlines), icon: icon, theme: nil))
    }

    static let cancelCommand: Command = .sidebar(.openDialog(nil))

    /// The emoji field shows the emoji icon, if that is the icon.
    var emoji: String {
        if case .custom(.emoji(let emoji)) = icon { return emoji }
        return ""
    }

    /// Typing into the emoji field: the last character typed is the icon (so a second emoji replaces the first);
    /// emptying the field while an emoji is the icon goes back to none.
    mutating func setEmoji(_ text: String) {
        if let last = text.trimmingCharacters(in: .whitespacesAndNewlines).last {
            icon = .custom(.emoji(String(last)))
        } else if case .custom(.emoji) = icon {
            icon = SpaceIcon.none
        }
    }
}

extension RGBA {
    var hex: String {
        String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    var swiftUI: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
}

/// Edit Space: the name and the icon, with Save and Cancel. Its theme is edited in the theme panel.
struct SpaceDialogForm: View {
    @State private var draft: SpaceDraft
    let dispatch: Dispatch
    @State private var symbolDraft: String
    @FocusState private var emojiFocused: Bool
    @Environment(\.colorScheme) private var colorScheme

    init(draft: SpaceDraft?, dispatch: @escaping Dispatch) {
        let draft = draft ?? SpaceDraft(.editSpace(id: SpaceID(""), title: "", icon: .none, theme: .default))!
        _draft = State(initialValue: draft)
        let symbol: String = if case .custom(.symbol(let value)) = draft.icon { value } else { "" }
        _symbolDraft = State(initialValue: symbol)
        self.dispatch = dispatch
    }

    private var colors: OverlayColors { .of(colorScheme == .dark ? .dark : .light) }
    private var m: DialogOverlayMetrics { OverlayMetrics.dialog }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(OverlayCopy.editSpaceTitle).font(.headline)
            preview
            TextField(OverlayCopy.spaceName, text: $draft.title, prompt: Text(OverlayCopy.spaceNamePlaceholder))
                .textFieldStyle(.roundedBorder).labelsHidden().onSubmit(save)
                .spaceToolsID("name")
            Text(OverlayCopy.icon).font(.subheadline).foregroundStyle(.secondary)
            iconPicker
            HStack {
                Spacer()
                SpaceToolsButton(title: OverlayCopy.cancel, id: "cancel", key: "\u{1b}", action: cancel)
                SpaceToolsButton(title: OverlayCopy.save, id: "save", key: "\r", action: save)
            }
        }.padding(m.padding.value).onExitCommand(perform: cancel)
    }

    private func save() { dispatch(draft.saveCommand) }
    private func cancel() { dispatch(SpaceDraft.cancelCommand) }

    /// The space as it will look: the resolved theme's gradient with the icon and name in its scheme's ink.
    private var preview: some View {
        let resolved = resolveTheme(draft.theme)
        let ink: Color = resolved.scheme == .dark ? .white : .black
        let name = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return ThemePadPreview(theme: resolved)
            .clipShape(RoundedRectangle(cornerRadius: Metrics.content.cornerRadius.value, style: .continuous))
            .overlay(alignment: .leading) {
                HStack(spacing: m.padding.value / 2) {
                    SpaceGlyph(icon: draft.icon, dot: resolved.gradient.first?.swiftUI ?? .gray)
                    Text(name.isEmpty ? OverlayCopy.spaceNamePlaceholder : name).font(.headline)
                }
                .foregroundStyle(ink.opacity(0.8))
                .padding(.horizontal, m.padding.value)
            }
            .frame(height: m.previewHeight.value)
    }

    private var iconPicker: some View {
        let side = m.iconButtonSize.value
        let perRow = 8
        let rows = stride(from: 0, to: NamedIcon.allCases.count, by: perRow).map { Array(NamedIcon.allCases[$0..<min($0 + perRow, NamedIcon.allCases.count)]) }
        return VStack(alignment: .leading, spacing: m.padding.value / 4) {
            HStack(spacing: m.padding.value / 4) {
                TextField(OverlayCopy.emojiPlaceholder, text: Binding(get: { draft.emoji }, set: { draft.setEmoji($0) }))
                    .spaceToolsID("emoji")
                    .focused($emojiFocused)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: side * 2.5)
                choice(selected: draft.icon == SpaceIcon.none, help: OverlayCopy.noIcon) {
                    Circle().fill(draft.theme.colors.first?.swiftUI ?? .gray).frame(width: side / 3, height: side / 3)
                } action: { draft.icon = SpaceIcon.none }.spaceToolsID("icon-none")
            }
            HStack {
                TextField("SF Symbol name", text: $symbolDraft)
                    .onChange(of: symbolDraft) { _, value in
                        if value.isEmpty, case .custom(.symbol) = draft.icon { draft.icon = .none }
                        else if NSImage(systemSymbolName: value, accessibilityDescription: nil) != nil { draft.icon = .custom(.symbol(value)) }
                    }.textFieldStyle(.roundedBorder).spaceToolsID("symbol")
                Button("Emoji & Symbols…") {
                    emojiFocused = true
                    Task { @MainActor in await Task.yield(); NSApp.orderFrontCharacterPalette(nil) }
                }
            }
            ForEach(rows, id: \.self) { row in
                HStack(spacing: m.padding.value / 4) {
                    ForEach(row, id: \.self) { name in
                        choice(selected: draft.icon == .custom(.named(name)), help: name.rawValue.capitalized) {
                            Image(systemName: NamedIconSymbol.of(name))
                        } action: { draft.icon = .custom(.named(name)); symbolDraft = "" }
                    }
                }
            }
        }
    }

    private func choice<Label: View>(selected: Bool, help: String, @ViewBuilder label: () -> Label, action: @escaping () -> Void) -> some View {
        let side = m.iconButtonSize.value
        return Button(action: action) {
            label()
                .frame(width: side, height: side)
                .background(RoundedRectangle(cornerRadius: side / 4, style: .continuous)
                    .fill(selected ? Color(nsColor: colors.focusRing).opacity(0.18) : Color(nsColor: colors.accessoryBackground)))
                .overlay(RoundedRectangle(cornerRadius: side / 4, style: .continuous)
                    .stroke(selected ? Color(nsColor: colors.focusRing) : .clear, lineWidth: m.ringWidth.value))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A space icon as the dock draws it: the emoji, the named icon's symbol, or a dot in the theme color.
struct SpaceGlyph: View {
    let icon: SpaceIcon
    let dot: Color

    var body: some View {
        switch icon {
        case .none:
            let side = OverlayMetrics.dialog.dotSize.value
            Circle().fill(dot).frame(width: side, height: side).overlay(Circle().stroke(.white.opacity(0.6)))
        case .custom(.emoji(let emoji)): Text(emoji)
        case .custom(.named(let name)): Image(systemName: NamedIconSymbol.of(name))
        case .custom(.symbol(let symbol)): Image(systemName: symbol)
        }
    }
}

/// A small preview of the resolved theme, with its texture (the Edit Space form's header).
struct ThemePadPreview: View {
    let theme: ResolvedTheme
    var body: some View {
        Canvas { context, size in
            let cells = 80
            for y in 0..<cells {
                for x in 0..<cells {
                    let color = themePreviewSample(theme, at: ThemePoint(x: (Double(x) + 0.5) / Double(cells), y: (Double(y) + 0.5) / Double(cells)))
                    context.fill(Path(CGRect(x: Double(x) / Double(cells) * size.width, y: Double(y) / Double(cells) * size.height,
                                             width: size.width / Double(cells) + 1, height: size.height / Double(cells) + 1)), with: .color(color.swiftUI))
                }
            }
        }
    }
}
