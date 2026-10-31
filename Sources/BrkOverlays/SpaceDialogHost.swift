import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit
import SwiftUI

/// Owner: W4 (dialogs). The new-space and edit-space dialog: name, icon (an emoji, one of the named icons, or none),
/// Arc's four preset sets of nine colors (Brand, Drab, Greyscale, Pastel), and the theme editor's controls (color
/// wheel, texture, noise, intensity, appearance) with a live preview tile.
/// SwiftUI inside an `NSHostingView`, the one kind of place SwiftUI is used (as Arc does with
/// `ThemeAwareHostingController`). The form's fields are local state seeded from the snapshot and kept while the same
/// dialog stays open; Save dispatches `.space(.create(...))` or `.space(.update(...))`, Cancel and Esc dispatch
/// `.sidebar(.openDialog(nil))`. Nothing is dispatched before Save, so Cancel needs no undo.
///
/// The card is centred in the content area at Arc's popover look; its height is the form's own.
@MainActor
public final class SpaceDialogHost: NSView {
    let dispatch: Dispatch
    public var profiles: [ProfileRow] = [] {
        didSet {
            guard profiles != oldValue, let dialog, let form else { return }
            form.rootView = SpaceDialogForm(draft: SpaceDraft(dialog), profiles: profiles, dispatch: dispatch)
        }
    }
    private var form: NSHostingController<SpaceDialogForm>?
    var hosting: NSView? { form?.view }
    private var dialog: SpaceDialogSnapshot?
    private var area: CGRect?
    private var scheme: Scheme?

    public init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        isHidden = true
        identify(.spaceDialog)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = OverlayMetrics.dialog.cornerRadius.value
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    public override var isFlipped: Bool { true }

    /// Keyboard focus into the form (its first field, the name). False while hidden or not in a window.
    public func focusForm() -> Bool {
        guard !isHidden, let hosting, let window else { return false }
        hosting.layoutSubtreeIfNeeded()
        return window.makeFirstResponder(Self.firstEditableField(in: hosting) ?? hosting)
    }

    /// SwiftUI's text fields are NSTextFields underneath; the first in view order is the name.
    private static func firstEditableField(in view: NSView) -> NSTextField? {
        for child in view.subviews {
            if let field = child as? NSTextField, field.isEditable { return field }
            if let field = firstEditableField(in: child) { return field }
        }
        return nil
    }

    public func render(_ dialog: SpaceDialogSnapshot?, frames: WindowFrames, palette: Palette) {
        guard let dialog else { return hide() }
        show(dialog, in: frames.contentArea, scheme: palette.scheme)
    }

    /// `render` once the slice is known. A different dialog (another space, or new instead of edit) starts a fresh
    /// form; the same one keeps what the user has entered.
    func show(_ dialog: SpaceDialogSnapshot, in area: CGRect, scheme: Scheme) {
        guard isHidden || dialog != self.dialog || area != self.area || scheme != self.scheme else { return }
        if dialog != self.dialog || form == nil {
            hosting?.removeFromSuperview()
            let controller = NSHostingController(rootView: SpaceDialogForm(draft: SpaceDraft(dialog), profiles: profiles, dispatch: dispatch))
            // The card never sits under the titlebar; without this the window's titlebar inset pads the form.
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
        let fitted = profiles.isEmpty ? (form?.sizeThatFits(in: CGSize(width: width, height: area.height)).height ?? 0) : min(710, area.height - 32)
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

/// What the form edits, and the commands its two buttons send. Plain data, so the decisions are testable without
/// SwiftUI.
struct SpaceDraft: Equatable {
    /// The space being edited; nil for a new one.
    let editing: SpaceID?
    var title: String
    var icon: SpaceIcon
    var theme: SpaceTheme
    var profile: ProfileID = .default

    init(_ dialog: SpaceDialogSnapshot) {
        switch dialog {
        case .newSpace:
            editing = nil
            title = ""
            icon = SpaceIcon.none
            theme = .default
        case .editSpace(let id, let title, let icon, let theme):
            editing = id
            self.title = title
            self.icon = icon
            self.theme = theme
        }
    }

    /// Save: the trimmed name (blank is stored as "" and shown as "Space N"), the icon and the whole theme.
    var saveCommand: Command {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if let editing { return .space(.update(editing, title: name, icon: icon, theme: theme)) }
        return .space(.create(title: name, icon: icon, theme: theme, profile: profile))
    }

    static let cancelCommand: Command = .sidebar(.openDialog(nil))

    /// A preset swatch becomes the primary color; the other base colors and the editor's settings stay.
    mutating func pickColor(_ color: RGBA) {
        if theme.colors.isEmpty { theme.colors = [color] } else { theme.colors[0] = color }
    }

    func isPicked(_ color: RGBA) -> Bool { theme.colors.first == color }

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

/// Arc's preset sets in the editor's order (the page order in Arc is unknown; ThemePresets' order).
let presetSets: [(name: String, colors: [RGBA])] = [
    ("Brand", ThemePresets.brand), ("Drab", ThemePresets.drab), ("Greyscale", ThemePresets.greyscale), ("Pastel", ThemePresets.pastel),
]

extension RGBA {
    var hex: String {
        String(format: "#%02X%02X%02X", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    var swiftUI: Color { Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha) }
}

struct SpaceDialogForm: View {
    @State private var draft: SpaceDraft
    let dispatch: Dispatch
    let profiles: [ProfileRow]
    @State private var stage = 0
    @Environment(\.colorScheme) private var colorScheme

    init(draft: SpaceDraft, profiles: [ProfileRow] = [], dispatch: @escaping Dispatch) {
        _draft = State(initialValue: draft)
        self.dispatch = dispatch
        self.profiles = profiles
    }

    private var colors: OverlayColors { .of(colorScheme == .dark ? .dark : .light) }
    private var m: DialogOverlayMetrics { OverlayMetrics.dialog }

    private var staged: Bool { draft.editing == nil && !profiles.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(draft.editing == nil ? OverlayCopy.newSpaceTitle : OverlayCopy.editSpaceTitle).font(.headline)
            if staged { Text(["1. Name and icon", "2. Theme", "3. Profile"][stage]).font(.subheadline).foregroundStyle(.secondary) }
            preview
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if !staged || stage == 0 {
                        TextField(OverlayCopy.spaceName, text: $draft.title, prompt: Text(OverlayCopy.spaceNamePlaceholder))
                            .textFieldStyle(.roundedBorder).labelsHidden().onSubmit(save)
                            .spaceToolsID("name")
                        section(OverlayCopy.icon) { iconPicker }
                    }
                    if profiles.isEmpty {
                        section(OverlayCopy.color) { swatches }
                        themeControls
                    } else if !staged || stage == 1 {
                        ThemeToolsEditor(theme: $draft.theme)
                    }
                    if staged && stage == 2 {
                        Text("This profile keeps website sign-ins and Favorites separate.").font(.caption).foregroundStyle(.secondary)
                        if !profiles.contains(where: { $0.id == draft.profile }) {
                            Text("That profile is no longer available. Choose another profile.").font(.caption).foregroundStyle(.red)
                        }
                        ForEach(profiles, id: \.id) { profile in
                            SpaceToolsButton(title: profile.name + (profile.isDefault ? " · Default" : " · Separate website data"), id: "profile-\(profile.id)", selected: draft.profile == profile.id) { draft.profile = profile.id }
                                .frame(maxWidth: .infinity, minHeight: 42)

                        }
                    }
                }.padding(.trailing, 4)
            }.frame(maxHeight: profiles.isEmpty ? 440 : (stage == 0 && staged ? 235 : 420))
            HStack {
                if staged && stage > 0 { SpaceToolsButton(title: "Back", id: "back") { withAnimation(.easeInOut(duration: 0.18)) { stage -= 1 } } }
                Spacer()
                if profiles.isEmpty {
                    Button(OverlayCopy.cancel, action: cancel).keyboardShortcut(.cancelAction)
                    Button(draft.editing == nil ? OverlayCopy.createSpace : OverlayCopy.save, action: save).keyboardShortcut(.defaultAction)
                } else {
                    SpaceToolsButton(title: OverlayCopy.cancel, id: "cancel", key: "\u{1b}", action: cancel)
                    SpaceToolsButton(title: staged && stage < 2 ? "Continue" : (draft.editing == nil ? OverlayCopy.createSpace : OverlayCopy.save), id: "save", key: "\r", action: save)
                        .disabled(staged && stage == 2 && !profiles.contains(where: { $0.id == draft.profile }))
                }
            }
        }.padding(m.padding.value).onExitCommand(perform: cancel)
    }

    private func save() {
        if staged && stage < 2 { withAnimation(.easeInOut(duration: 0.18)) { stage += 1 } }
        else { dispatch(draft.saveCommand) }
    }
    private func cancel() { dispatch(SpaceDraft.cancelCommand) }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: m.padding.value / 3) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            content()
        }
    }

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
        let perRow = (NamedIcon.allCases.count + 1) / 2
        let rows = stride(from: 0, to: NamedIcon.allCases.count, by: perRow).map { Array(NamedIcon.allCases[$0..<min($0 + perRow, NamedIcon.allCases.count)]) }
        return VStack(alignment: .leading, spacing: m.padding.value / 4) {
            HStack(spacing: m.padding.value / 4) {
                TextField(OverlayCopy.emojiPlaceholder, text: Binding(get: { draft.emoji }, set: { draft.setEmoji($0) }))
                    .spaceToolsID("emoji")
                    .textFieldStyle(.roundedBorder)
                    .frame(width: side * 2.5)
                choice(selected: draft.icon == SpaceIcon.none, help: OverlayCopy.noIcon) {
                    Circle().fill(draft.theme.colors.first?.swiftUI ?? .gray).frame(width: side / 3, height: side / 3)
                } action: { draft.icon = SpaceIcon.none }
            }
            ForEach(rows, id: \.self) { row in
                HStack(spacing: m.padding.value / 4) {
                    ForEach(row, id: \.self) { name in
                        choice(selected: draft.icon == .custom(.named(name)), help: name.rawValue.capitalized) {
                            Image(systemName: NamedIconSymbol.of(name))
                        } action: { draft.icon = .custom(.named(name)) }
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

    private var swatches: some View {
        let side = m.swatchSize.value
        return VStack(alignment: .leading, spacing: side / 3) {
            ForEach(presetSets, id: \.name) { set in
                HStack(spacing: side / 3) {
                    ForEach(Array(set.colors.enumerated()), id: \.offset) { _, color in
                        let picked = draft.isPicked(color)
                        Button { draft.pickColor(color) } label: {
                            Circle()
                                .fill(color.swiftUI)
                                .overlay(Circle().stroke(Color.primary.opacity(0.15)))
                                .padding(picked ? m.ringGap.value : 0)
                                .overlay(Circle().stroke(picked ? Color(nsColor: colors.focusRing) : .clear, lineWidth: m.ringWidth.value))
                                .frame(width: side, height: side)
                        }
                        .buttonStyle(.plain)
                        .help(OverlayCopy.setColor(color.hex))
                        .accessibilityLabel(OverlayCopy.setColor(color.hex))
                        .accessibilityAddTraits(picked ? .isSelected : [])
                    }
                }
            }
        }
    }

    private var themeControls: some View {
        Grid(alignment: .leading, horizontalSpacing: m.padding.value / 2, verticalSpacing: m.padding.value / 3) {
            GridRow {
                label(OverlayCopy.wheel)
                Picker(OverlayCopy.wheel, selection: $draft.theme.wheel) {
                    ForEach(ColorWheel.allCases, id: \.self) { Text(OverlayCopy.wheelName($0)).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
            }
            GridRow {
                label(OverlayCopy.noise)
                HStack {
                    Picker(OverlayCopy.texture, selection: $draft.theme.texture) {
                        ForEach(Texture.allCases, id: \.self) { Text(OverlayCopy.textureName($0)).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden().help(OverlayCopy.texture)
                    Slider(value: $draft.theme.noise, in: 0...1).accessibilityLabel(OverlayCopy.noise)
                }
            }
            GridRow {
                label(OverlayCopy.intensity)
                Slider(value: $draft.theme.intensity, in: 0...1).accessibilityLabel(OverlayCopy.intensity)
            }
            GridRow {
                label(OverlayCopy.appearance)
                Picker(OverlayCopy.appearance, selection: $draft.theme.appearance) {
                    ForEach(AppearanceChoice.allCases, id: \.self) { choice in
                        Image(systemName: appearanceSymbol(choice)).help(OverlayCopy.appearanceName(choice))
                            .accessibilityLabel(OverlayCopy.appearanceName(choice)).tag(choice)
                    }
                }
                .pickerStyle(.segmented).labelsHidden()
            }
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.subheadline).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
    }

    /// Arc animates sun, moon and "automatic" Lottie files; these are the SF Symbol equivalents.
    private func appearanceSymbol(_ choice: AppearanceChoice) -> String {
        switch choice {
        case .auto: "circle.lefthalf.filled"
        case .light: "sun.max"
        case .dark: "moon"
        }
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
