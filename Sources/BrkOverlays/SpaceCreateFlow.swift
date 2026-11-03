import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit
import SwiftUI

// Owner: W4 (dialogs). Arc's Create a Space flow (Spaces > New Space…), matched to the 2026-11-03 captures P24 a–e
// and the flow recording: the sidebar's contents give way to an illustration, "Create a Space" and its subtitle, the
// "Space name…" field with an icon button (the Emoji / Icon popover), the Profile row with its Default ⌄ menu (each
// profile, then New Profile…), the Choose a Theme row (the theme panel as a popover beside it), and at the bottom
// Create Space and Cancel. The draft theme shows on the window at once (`onDraft`); Create Space dispatches
// `.space(.create(...))`, Cancel and Esc close the flow.

struct CreateFlowMetrics: MetricGroup {
    let top = Metric(44.0, .guess("the flow starts under the title row (4 + 40), measured on P24-a-arc.png"))
    let illustration = Metric(CGRect(x: 81.5, y: 80, width: 65, height: 43), .guess("three-card illustration, measured on P24 a"))
    let titleTop = Metric(138.0, .guess("\"Create a Space\" label top (20 pt bold), measured on P24 a"))
    let subtitleTop = Metric(170.0, .guess("subtitle label top (14.5 pt, two lines 17 apart), measured on P24 a"))
    let field = Metric(CGRect(x: 14, y: 238, width: 200, height: 34), .guess("name field, measured on P24 a"))
    let profileRow = Metric(CGRect(x: 14, y: 280, width: 200, height: 35), .guess("Profile row, measured on P24 a"))
    let themeRow = Metric(CGRect(x: 14, y: 324, width: 200, height: 36), .guess("Choose a Theme row, measured on P24 a"))
    let rowRadius = Metric(8.0, .guess("field and row corner radius, measured on P24 a"))
    let createButton = Metric(CGSize(width: 200, height: 38), .guess("Create Space button, its bottom 44 pt above the dock, measured on P24 a"))
    let createBottom = Metric(44.0, .guess("Create Space bottom edge above the dock's top, measured on P24 a"))
    let cancelCentre = Metric(24.0, .guess("Cancel's centre above the dock's top, measured on P24 a"))
    let leading = Metric([29.0, 46.0], .guess("row glyph centre and row label start from the sidebar edge, measured on P24 a"))
    /// Arc's blue for the button while no theme is chosen, and the window color then.
    let defaultAccent = Metric(RGBAValue(0x1E, 0x2C, 0xFF), .guess("Create Space blue #1E2CFF before a theme is chosen, sampled on P24 b and c"))
}

let CreateFlow = CreateFlowMetrics()

enum CreateFlowCopy {
    /// Observed on P24 a.
    static let title = "Create a Space"
    static let subtitle = "Separate your tabs for life, work, projects, and more."
    static let namePlaceholder = "Space name…"
    static let profile = "Profile"
    static let chooseTheme = "Choose a Theme"
    static let createSpace = "Create Space"
    static let cancel = "Cancel"
    static let newProfile = "New Profile…"
    static let profileHelp = "Spaces on the same profile share website sign-ins, history and favorites."
}

/// What the flow edits, and the command Create Space sends. Plain data, so the decisions are testable without SwiftUI.
struct SpaceCreateDraft: Equatable {
    var name = ""
    var icon = SpaceIcon.none
    var theme = SpaceCreateDraft.defaultTheme
    /// False until a color is picked; until then the pad says "Tap to pick a color for this space".
    var themeChosen = false
    var profile = ProfileID.default

    /// Arc's look for a space with no theme chosen yet: the lavender to blush window of P24 a (sidebar #E0DCF4, the
    /// lower right #FDF8F7 under the wash), created as is when no theme is picked.
    static let defaultTheme = SpaceTheme(colors: [RGBA(hex: "#CDC7F0"), RGBA(hex: "#F4DDE6")], texture: .grain, intensity: SpaceTheme.default.intensity, appearance: .auto)

    /// Arc's Create Space needs a name.
    var canCreate: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var createCommand: Command? {
        guard canCreate else { return nil }
        return .space(.create(title: name.trimmingCharacters(in: .whitespacesAndNewlines), icon: icon, theme: theme, profile: profile))
    }

    static let cancelCommand: Command = .sidebar(.openDialog(nil))

    /// The Create Space button's color: Arc's blue before a theme is chosen, else a deep shade of the primary (fitted
    /// to two Arc samples: cream #F2EAE4 gives brown #725137, lavender gives the blue; greys give a dark grey).
    func accent(systemScheme: Scheme) -> RGBA {
        guard themeChosen else {
            let blue = CreateFlow.defaultAccent.value
            return RGBA(Double(blue.red) / 255, Double(blue.green) / 255, Double(blue.blue) / 255)
        }
        let primary = ThemeDraft(theme: theme, systemScheme: systemScheme).colors.first ?? theme.colors.first ?? RGBA(0.5, 0.5, 0.5)
        let hsl = HSL(primary)
        guard hsl.saturation >= 0.05 else { return HSL(hue: 0, saturation: 0, lightness: 0.3).rgba }
        let t = min(max((hsl.saturation - 0.4) / 0.2, 0), 1)
        return HSL(hue: hsl.hue, saturation: 0.35 + 0.65 * t, lightness: 0.33 + 0.23 * t).rgba
    }
}

@MainActor
final class SpaceCreateModel: ObservableObject {
    @Published var draft = SpaceCreateDraft() { didSet { if draft != oldValue { changed(draft) } } }
    @Published var profiles: [ProfileRow] = []
    let theme: ThemeEditorModel
    let dispatch: Dispatch
    var systemScheme: Scheme = .light
    /// Opens the icon popover and the theme popover at the given rects (flow coordinates).
    var showIconPicker: () -> Void = {}
    var showThemeEditor: () -> Void = {}
    var changed: (SpaceCreateDraft) -> Void = { _ in }

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        theme = ThemeEditorModel(draft: ThemeDraft(theme: SpaceCreateDraft.defaultTheme), chosen: false)
        theme.onChange = { [weak self] value in
            self?.draft.theme = value.theme
            self?.draft.themeChosen = true
        }
    }

    func create() { if let command = draft.createCommand { dispatch(command) } }
    func cancel() { dispatch(SpaceCreateDraft.cancelCommand) }
}

struct SpaceCreateFlowView: View {
    @ObservedObject var model: SpaceCreateModel
    let height: Double
    @FocusState private var nameFocused: Bool
    private let m = CreateFlow
    private var ink: Color {
        resolveTheme(model.draft.theme, systemScheme: model.systemScheme).scheme == .dark ? .white : .black
    }

    var body: some View {
        let top = m.top.value
        let width = m.field.value.maxX + m.field.value.minX
        ZStack(alignment: .topLeading) {
            CreateIllustration()
                .frame(width: m.illustration.value.width, height: m.illustration.value.height)
                .position(x: m.illustration.value.midX, y: m.illustration.value.midY - top)
            VStack(spacing: 0) {
                Text(CreateFlowCopy.title).font(.system(size: 20, weight: .bold)).foregroundStyle(ink.opacity(0.92))
                    .frame(height: 24)
                Text(CreateFlowCopy.subtitle).font(.system(size: 14.5)).foregroundStyle(ink.opacity(0.85))
                    .multilineTextAlignment(.center).lineSpacing(0.5).frame(width: width - 20)
                    .padding(.top, m.subtitleTop.value - m.titleTop.value - 24)
            }
            .frame(width: width).offset(y: m.titleTop.value - top)
            nameField.frame(width: m.field.value.width, height: m.field.value.height)
                .offset(x: m.field.value.minX, y: m.field.value.minY - top)
            profileRow.frame(width: m.profileRow.value.width, height: m.profileRow.value.height)
                .offset(x: m.profileRow.value.minX, y: m.profileRow.value.minY - top)
            themeRow.frame(width: m.themeRow.value.width, height: m.themeRow.value.height)
                .offset(x: m.themeRow.value.minX, y: m.themeRow.value.minY - top)
            createButton.frame(width: m.createButton.value.width, height: m.createButton.value.height)
                .offset(x: m.field.value.minX, y: height - m.createBottom.value - m.createButton.value.height)
            Button(CreateFlowCopy.cancel) { model.cancel() }
                .buttonStyle(.plain).font(.system(size: 14)).foregroundStyle(ink.opacity(0.62))
                .frame(width: width, height: 20)
                .offset(y: height - m.cancelCentre.value - 10)
                .spaceToolsID("cancel")
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .onAppear { nameFocused = true }
    }

    private var nameField: some View {
        HStack(spacing: 6) {
            Button { model.showIconPicker() } label: { iconButton }
                .buttonStyle(.plain)
                .help(OverlayCopy.icon)
                .spaceToolsID("icon-button")
            TextField("", text: $model.draft.name, prompt: Text(CreateFlowCopy.namePlaceholder).foregroundStyle(ink.opacity(0.4)))
                .textFieldStyle(.plain).font(.system(size: 15)).foregroundStyle(ink.opacity(0.9))
                .focused($nameFocused)
                .onSubmit { model.create() }
                .spaceToolsID("name")
        }
        .padding(.leading, 8).padding(.trailing, 10)
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: m.rowRadius.value, style: .continuous).fill(Color.white.opacity(ink == .white ? 0.1 : 0.6)))
    }

    @ViewBuilder private var iconButton: some View {
        switch model.draft.icon {
        case .none:
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(ink.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [2, 2]))
                .overlay(Image(systemName: "plus").font(.system(size: 10, weight: .medium)).foregroundStyle(ink.opacity(0.5)))
                .frame(width: 18, height: 18)
        case .custom(let icon):
            SpaceGlyph(icon: .custom(icon), dot: .clear).font(.system(size: 15)).foregroundStyle(ink.opacity(0.7))
                .frame(width: 18, height: 18)
        }
    }

    private var profileRow: some View {
        let current = model.profiles.first { $0.id == model.draft.profile }?.name ?? "Default"
        return HStack(spacing: 0) {
            Image(systemName: "face.smiling").font(.system(size: 13, weight: .medium)).foregroundStyle(ink.opacity(0.6))
                .frame(width: 2 * (m.leading.value[0] - m.profileRow.value.minX))
            Text(CreateFlowCopy.profile).font(.system(size: 15, weight: .medium)).foregroundStyle(ink.opacity(0.85))
                .padding(.leading, m.leading.value[1] - 2 * m.leading.value[0] + m.profileRow.value.minX)
            ProfileMenuButton(title: current, profiles: model.profiles, selected: model.draft.profile, ink: ink == .white ? .white : .black) { choice in
                if let choice { model.draft.profile = choice } else { model.dispatch(.profile(.openDialog(.create))) }
            }
            .frame(width: 72, height: 22).padding(.leading, 8)
            .spaceToolsID("profile")
            Spacer(minLength: 0)
            Image(systemName: "info.circle").font(.system(size: 14)).foregroundStyle(ink.opacity(0.6))
                .help(CreateFlowCopy.profileHelp).padding(.trailing, 9)
        }
        .frame(maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: m.rowRadius.value, style: .continuous).fill(ink.opacity(0.045)))
    }

    private var themeRow: some View {
        Button { model.showThemeEditor() } label: {
            HStack(spacing: 0) {
                Image(systemName: "paintbrush.pointed.fill").font(.system(size: 12, weight: .medium)).foregroundStyle(ink.opacity(0.6))
                    .frame(width: 2 * (m.leading.value[0] - m.themeRow.value.minX))
                Text(CreateFlowCopy.chooseTheme).font(.system(size: 15, weight: .medium)).foregroundStyle(ink.opacity(0.85))
                    .padding(.leading, m.leading.value[1] - 2 * m.leading.value[0] + m.themeRow.value.minX)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(RoundedRectangle(cornerRadius: m.rowRadius.value, style: .continuous).fill(ink.opacity(0.045)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .spaceToolsID("theme")
    }

    private var createButton: some View {
        let accent = model.draft.accent(systemScheme: model.systemScheme)
        let enabled = model.draft.canCreate
        return Button { model.create() } label: {
            Text(CreateFlowCopy.createSpace).font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color.white.opacity(enabled ? 1 : 0.7))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(accent.swiftUI.opacity(enabled ? 1 : 0.4)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .spaceToolsID("save")
    }
}

/// Arc's three-card picture above "Create a Space": a plant, a laptop and books on white cards fanned out.
private struct CreateIllustration: View {
    var body: some View {
        ZStack {
            card("leaf.fill", .green).rotationEffect(.degrees(-12)).offset(x: -17, y: 2)
            card("books.vertical.fill", .brown).rotationEffect(.degrees(12)).offset(x: 17, y: 2)
            card("laptopcomputer", Color(white: 0.25)).offset(y: -1)
        }
    }

    private func card(_ symbol: String, _ tint: Color) -> some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous).fill(Color.white)
            .frame(width: 30, height: 36)
            .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
            .overlay(Image(systemName: symbol).font(.system(size: 15)).foregroundStyle(tint))
    }
}

/// The Default ⌄ pill: an AppKit view so a left or right click opens its menu (each profile, checked when chosen,
/// then New Profile…). `choose(nil)` is New Profile….
private struct ProfileMenuButton: NSViewRepresentable {
    let title: String
    let profiles: [ProfileRow]
    let selected: ProfileID
    let ink: NSColor
    let choose: (ProfileID?) -> Void

    func makeNSView(context: NSViewRepresentableContext<Self>) -> PillView { PillView() }
    func updateNSView(_ view: PillView, context: NSViewRepresentableContext<Self>) {
        view.title = title
        view.ink = ink
        view.entries = profiles.map { ($0.name, $0.id, $0.id == selected) }
        view.choose = choose
        view.needsDisplay = true
    }

    final class PillView: NSView {
        var title = ""
        var ink: NSColor = .black
        var entries: [(String, ProfileID, Bool)] = []
        var choose: (ProfileID?) -> Void = { _ in }
        private var chosen: [NSMenuItem: ProfileID] = [:]

        override var isFlipped: Bool { true }

        override func draw(_ dirtyRect: NSRect) {
            let pill = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
            ink.withAlphaComponent(0.07).setFill()
            pill.fill()
            let text = NSAttributedString(string: title, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: ink.withAlphaComponent(0.85)])
            let size = text.size()
            let chevron = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
                .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 10, weight: .bold))
            let total = size.width + 5 + (chevron?.size.width ?? 0)
            let x = (bounds.width - total) / 2
            text.draw(at: CGPoint(x: x, y: (bounds.height - size.height) / 2))
            if let chevron {
                let tinted = NSImage(size: chevron.size, flipped: false) { rect in
                    chevron.draw(in: rect)
                    self.ink.withAlphaComponent(0.85).set()
                    rect.fill(using: .sourceAtop)
                    return true
                }
                tinted.draw(in: CGRect(x: x + size.width + 5, y: (bounds.height - chevron.size.height) / 2, width: chevron.size.width, height: chevron.size.height))
            }
        }

        override func mouseDown(with event: NSEvent) { popUp(event) }
        override func rightMouseDown(with event: NSEvent) { popUp(event) }

        private func popUp(_ event: NSEvent) {
            let menu = NSMenu()
            chosen = [:]
            for (name, id, on) in entries {
                let item = NSMenuItem(title: name, action: #selector(pick(_:)), keyEquivalent: "")
                item.target = self
                item.state = on ? .on : .off
                chosen[item] = id
                menu.addItem(item)
            }
            menu.addItem(.separator())
            let create = NSMenuItem(title: CreateFlowCopy.newProfile, action: #selector(pick(_:)), keyEquivalent: "")
            create.target = self
            menu.addItem(create)
            menu.popUp(positioning: nil, at: CGPoint(x: 0, y: bounds.height + 4), in: self)
        }

        @objc private func pick(_ item: NSMenuItem) { choose(chosen[item]) }
    }
}

/// The theme panel as a popover beside Choose a Theme (P24 c), sharing the flow's theme model.
@MainActor
final class ThemePopover: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()

    init(model: ThemeEditorModel) {
        super.init()
        popover.behavior = .transient
        popover.animates = false
        popover.contentSize = ThemePanel.card.value
        popover.contentViewController = NSHostingController(rootView: ThemeEditorView(model: model))
        popover.delegate = self
    }

    func show(relativeTo rect: CGRect, of view: NSView, scheme: Scheme) {
        popover.appearance = .of(scheme)
        popover.show(relativeTo: rect, of: view, preferredEdge: .maxX)
    }

    func dismiss() { popover.close() }
}
