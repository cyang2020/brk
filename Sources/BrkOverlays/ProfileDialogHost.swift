import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit
import SwiftUI

/// Owner: F2. Arc's three profile dialogs (`ProfilesUI`: `CreateProfileDialog`, `ChangeProfileDialog`,
/// `DeleteProfileDialog`) as one card centred in the content area, SwiftUI in an `NSHostingView` like the space
/// dialog. Copy and rules come from `ProfileCopy` (BrkDomain), so the dialog says no exactly when the reducer does.
/// The form's fields are local state seeded from the snapshot and kept while the same dialog stays open; the
/// confirm button dispatches one `.profile(...)` command, Cancel and Esc dispatch `.profile(.openDialog(nil))`.
///
/// - Create: a name and an icon. A taken name is refused by the reducer and the dialog stays open; the form then
///   shows "A Profile with that name already exists." (the snapshot does not list names for this dialog). Arc's
///   second step ("Which Spaces should use this Profile?") is left out: the change dialog assigns spaces.
/// - Change: the space's profile, one row per profile, and "New Profile…".
/// - Delete: refused for the default profile and a profile with spaces (Arc's two rules, with the spaces named);
///   otherwise Arc's warning and "To continue, please type the name of this Profile:".
@MainActor
public final class ProfileDialogHost: NSView {
    let dispatch: Dispatch
    private var form: NSHostingController<ProfileDialogForm>?
    private var hosting: NSView? { form?.view }
    private var dialog: ProfileDialogSnapshot?
    private var area: CGRect?
    private var scheme: Scheme?

    public init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        isHidden = true
        identify(.profileDialog)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = OverlayMetrics.dialog.cornerRadius.value
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    public override var isFlipped: Bool { true }

    /// W2's root holds the space dialog; until it holds this host too, these two calls keep it as the space
    /// dialog's sibling, just above it, with the same dispatch (added on the first dialog).
    public static func render(_ dialog: ProfileDialogSnapshot?, over sibling: SpaceDialogHost, frames: WindowFrames, palette: Palette) {
        guard let root = sibling.superview else { return }
        var host = root.subviews.lazy.compactMap { $0 as? ProfileDialogHost }.first
        if host == nil, dialog != nil {
            host = ProfileDialogHost(dispatch: sibling.dispatch)
            root.addSubview(host!, positioned: .above, relativeTo: sibling)
        }
        host?.render(dialog, frames: frames, palette: palette)
    }

    public static func focus(over sibling: SpaceDialogHost) -> Bool {
        sibling.superview?.subviews.lazy.compactMap { $0 as? ProfileDialogHost }.first?.focusForm() ?? false
    }

    /// Keyboard focus into the form: its text field (create, delete), else the form itself (Esc and Return work).
    public func focusForm() -> Bool {
        guard !isHidden, let hosting, let window else { return false }
        hosting.layoutSubtreeIfNeeded()
        return window.makeFirstResponder(Self.firstEditableField(in: hosting) ?? hosting)
    }

    private static func firstEditableField(in view: NSView) -> NSTextField? {
        for child in view.subviews {
            if let field = child as? NSTextField, field.isEditable { return field }
            if let field = firstEditableField(in: child) { return field }
        }
        return nil
    }

    public func render(_ dialog: ProfileDialogSnapshot?, frames: WindowFrames, palette: Palette) {
        guard let dialog else { return hide() }
        show(dialog, in: frames.contentArea, scheme: palette.scheme)
    }

    /// Another dialog (or another space's change dialog) starts a fresh form; the same one keeps what was typed.
    func show(_ dialog: ProfileDialogSnapshot, in area: CGRect, scheme: Scheme) {
        guard isHidden || dialog != self.dialog || area != self.area || scheme != self.scheme else { return }
        if dialog != self.dialog || form == nil {
            hosting?.removeFromSuperview()
            let controller = NSHostingController(rootView: ProfileDialogForm(draft: ProfileDraft(dialog), dispatch: dispatch))
            controller.safeAreaRegions = []
            addSubview(controller.view)
            form = controller
        }
        self.dialog = dialog
        self.area = area
        if scheme != self.scheme {
            self.scheme = scheme
            let colors = OverlayColors.of(scheme)
            appearance = .of(scheme)
            layer?.backgroundColor = colors.popover.cgColor
            shadow = .popover(colors)
        }
        isHidden = false
        let margin = Metrics.commandBar.minVerticalMargin.value
        let width = min(OverlayMetrics.dialog.width.value, area.width - 2 * margin)
        let fitted = form?.sizeThatFits(in: CGSize(width: width, height: area.height)).height ?? 0
        let height = min(fitted, area.height - 2 * margin)
        frame = CGRect(x: area.midX - width / 2, y: area.midY - height / 2, width: width, height: height).integral
        hosting?.frame = bounds
    }

    private func hide() {
        guard !isHidden else { return }
        isHidden = true
        hosting?.removeFromSuperview()
        form = nil
        dialog = nil
    }
}

/// What a profile dialog edits and says, and the command its confirm button sends. Plain data, so the decisions
/// are testable without SwiftUI.
struct ProfileDraft: Equatable {
    let dialog: ProfileDialogSnapshot
    var name = ""
    var icon: CustomIcon?
    /// The change dialog's chosen profile (starts at the space's current one).
    var chosen: ProfileID?
    /// What the user typed to confirm a deletion.
    var typedName = ""
    /// The name a create was refused for: with a non-blank name that means it is taken.
    var refusedName: String?

    init(_ dialog: ProfileDialogSnapshot) {
        self.dialog = dialog
        if case .change(_, let current, _) = dialog { chosen = current }
    }

    var title: String {
        switch dialog {
        case .create: ProfileCopy.createTitle
        case .change: ProfileCopy.changeTitle
        case .delete: ProfileCopy.deleteTitle
        }
    }

    var explanation: String {
        switch dialog {
        case .create: ProfileCopy.createExplanation
        case .change: ProfileCopy.changeExplanation
        case .delete(let row): ProfileCopy.deleteRefusal(row) ?? ProfileCopy.deleteWarning(row.name)
        }
    }

    /// The delete dialog of a profile that cannot be deleted lists what holds it.
    var detail: String? {
        guard case .delete(let row) = dialog, !row.isDefault, ProfileCopy.deleteRefusal(row) != nil else { return nil }
        return ProfileCopy.spaceCount(row.spaceTitles)
    }

    var confirmTitle: String {
        switch dialog {
        case .create: ProfileCopy.createButton
        case .change: ProfileCopy.changeButton
        case .delete: ProfileCopy.deleteButton
        }
    }

    var error: String? {
        guard case .create = dialog, let refusedName, !ProfileCopy.trimmed(name).isEmpty,
              ProfileCopy.isTaken(name, among: [refusedName]) else { return nil }
        return ProfileCopy.nameTaken
    }

    /// Nil while the button is disabled.
    var confirmCommand: Command? {
        switch dialog {
        case .create:
            guard ProfileCopy.acceptsName(name, among: refusedName.map { [$0] } ?? []) else { return nil }
            return .profile(.create(name: ProfileCopy.trimmed(name), icon: icon))
        case .change(let space, let current, _):
            guard let chosen, chosen != current else { return nil }
            return .profile(.assign(.space(space), to: chosen))
        case .delete(let row):
            guard ProfileCopy.deleteRefusal(row) == nil, ProfileCopy.trimmed(typedName) == row.name else { return nil }
            return .profile(.delete(row.id))
        }
    }

    /// Called right after the confirm command went out: if this dialog is still showing, a create was refused.
    mutating func confirmed() {
        if case .create = dialog { refusedName = ProfileCopy.trimmed(name) }
    }

    static let cancelCommand: Command = .profile(.openDialog(nil))
    static let newProfileCommand: Command = .profile(.openDialog(.create))
}

struct ProfileDialogForm: View {
    @State private var draft: ProfileDraft
    let dispatch: Dispatch
    @Environment(\.colorScheme) private var colorScheme

    init(draft: ProfileDraft, dispatch: @escaping Dispatch) {
        _draft = State(initialValue: draft)
        self.dispatch = dispatch
    }

    private var colors: OverlayColors { .of(colorScheme == .dark ? .dark : .light) }
    private var m: DialogOverlayMetrics { OverlayMetrics.dialog }

    var body: some View {
        VStack(alignment: .leading, spacing: m.padding.value * 0.6) {
            Text(draft.title).font(.headline)
            Text(draft.explanation).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if let detail = draft.detail { Text(detail).font(.callout).fixedSize(horizontal: false, vertical: true) }
            fields
            if let error = draft.error { Text(error).font(.callout).foregroundStyle(.red) }
            HStack {
                if case .change = draft.dialog {
                    Button(ProfileCopy.createFromChange) { dispatch(ProfileDraft.newProfileCommand) }
                }
                Spacer()
                Button(ProfileCopy.cancel, action: cancel).keyboardShortcut(.cancelAction)
                Button(draft.confirmTitle, action: confirm)
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(isDelete ? .red : Color(nsColor: colors.primaryButton))
                    .disabled(draft.confirmCommand == nil)
            }
        }
        .padding(m.padding.value)
        .onExitCommand(perform: cancel)
    }

    private var isDelete: Bool { if case .delete = draft.dialog { true } else { false } }

    @ViewBuilder
    private var fields: some View {
        switch draft.dialog {
        case .create:
            Text(ProfileCopy.namePrompt).font(.subheadline)
            TextField(ProfileCopy.namePrompt, text: $draft.name, prompt: Text(ProfileCopy.namePlaceholder))
                .textFieldStyle(.roundedBorder).labelsHidden().onSubmit(confirm)
            iconPicker
        case .change(_, _, let profiles):
            VStack(spacing: 2) {
                ForEach(profiles, id: \.id) { row in profileRow(row) }
            }
        case .delete(let row):
            if ProfileCopy.deleteRefusal(row) == nil {
                Text(ProfileCopy.deleteTypePrompt).font(.subheadline)
                TextField(ProfileCopy.deleteTypePrompt, text: $draft.typedName, prompt: Text(row.name))
                    .textFieldStyle(.roundedBorder).labelsHidden().onSubmit(confirm)
                Text(ProfileCopy.cannotBeUndone).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Arc's profile picker row: the profile's icon and name, the chosen one on ProfilePicker blue.
    private func profileRow(_ row: ProfileRow) -> some View {
        let chosen = draft.chosen == row.id
        let pick = ProfilePickerColors.of(colorScheme == .dark ? .dark : .light)
        return Button { draft.chosen = row.id } label: {
            HStack {
                ProfileGlyph(icon: row.icon)
                Text(row.name)
                Spacer()
                Text(ProfileCopy.spaceCount(row.spaceTitles)).font(.caption).foregroundStyle(.secondary)
                if chosen { Image(systemName: "checkmark.circle.fill") }
            }
            .padding(.horizontal, m.padding.value / 2)
            .frame(height: m.iconButtonSize.value + 4)
            .foregroundStyle(chosen ? pick.text : Color.primary)
            .background(RoundedRectangle(cornerRadius: m.iconButtonSize.value / 4, style: .continuous).fill(chosen ? pick.fill : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(row.name)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private var iconPicker: some View {
        let side = m.iconButtonSize.value
        let icons: [CustomIcon?] = [nil] + NamedIcon.allCases.map { CustomIcon.named($0) }
        let perRow = (icons.count + 1) / 2
        let rows = stride(from: 0, to: icons.count, by: perRow).map { Array(icons[$0..<min($0 + perRow, icons.count)]) }
        return VStack(alignment: .leading, spacing: m.padding.value / 4) {
            ForEach(rows.indices, id: \.self) { r in
                HStack(spacing: m.padding.value / 4) {
                    ForEach(rows[r].indices, id: \.self) { i in
                        let icon = rows[r][i], selected = draft.icon == icon
                        Button { draft.icon = icon } label: {
                            ProfileGlyph(icon: icon)
                                .frame(width: side, height: side)
                                .background(RoundedRectangle(cornerRadius: side / 4, style: .continuous)
                                    .fill(selected ? Color(nsColor: colors.focusRing).opacity(0.18) : Color(nsColor: colors.accessoryBackground)))
                                .overlay(RoundedRectangle(cornerRadius: side / 4, style: .continuous)
                                    .stroke(selected ? Color(nsColor: colors.focusRing) : .clear, lineWidth: m.ringWidth.value))
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(icon.map(ProfileGlyph.name) ?? "Default")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                    }
                }
            }
        }
    }

    private func confirm() {
        guard let command = draft.confirmCommand else { return }
        dispatch(command)
        draft.confirmed()
    }

    private func cancel() { dispatch(ProfileDraft.cancelCommand) }
}

/// ARC_ProfilesUI's two colors (visual-and-copy.md "ARC_ProfilesUI"): ProfilePicker #3139FB @ 0.1 light, @ 0.898
/// dark; ProfilePickerText #060E2B light, #E3E2EE dark.
struct ProfilePickerColors {
    let fill: Color
    let text: Color

    static func of(_ scheme: Scheme) -> ProfilePickerColors {
        let blue = (red: 0x31 / 255.0, green: 0x39 / 255.0, blue: 0xFB / 255.0)
        return scheme == .light
            ? ProfilePickerColors(fill: Color(.sRGB, red: blue.red, green: blue.green, blue: blue.blue, opacity: 0.1),
                                  text: Color(.sRGB, red: 0x06 / 255.0, green: 0x0E / 255.0, blue: 0x2B / 255.0))
            : ProfilePickerColors(fill: Color(.sRGB, red: blue.red, green: blue.green, blue: blue.blue, opacity: 0.898),
                                  text: Color(.sRGB, red: 0xE3 / 255.0, green: 0xE2 / 255.0, blue: 0xEE / 255.0))
    }
}

/// A profile's icon: its emoji, named icon or symbol; Arc's person glyph when it has none.
struct ProfileGlyph: View {
    let icon: CustomIcon?

    static let defaultSymbol = "person.crop.circle"

    static func name(_ icon: CustomIcon) -> String {
        switch icon {
        case .emoji(let emoji): emoji
        case .named(let name): name.rawValue.capitalized
        case .symbol(let symbol): symbol
        }
    }

    var body: some View {
        switch icon {
        case nil: Image(systemName: Self.defaultSymbol)
        case .emoji(let emoji)?: Text(emoji)
        case .named(let name)?: Image(systemName: NamedIconSymbol.of(name))
        case .symbol(let symbol)?: Image(systemName: symbol)
        }
    }
}
