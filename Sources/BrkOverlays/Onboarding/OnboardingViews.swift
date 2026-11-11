import AppKit
import BrkBase
import BrkDomain
import BrkUIKit
import SwiftUI
import UniformTypeIdentifiers

// Owner: onboarding round (2026-11-12). The first-run window and the Import from Another Browser… window. Layout and
// flow follow Arc 1.170's Unboxing and Setup wizard (research report §1.2–§1.4): one 1280 x 800 window; a full-bleed
// welcome; then every step as two columns, the left one on its own background with the title, text, choices and the
// footer ("← Back", a skip button, the main button), the right one an illustration. The visuals and the words are
// Brk's own: nothing of Arc's or Dia's artwork, video, sound or exact copy ships here.

/// The numbers, from Arc's window and assets where the research found them, guessed where it did not.
struct OnboardingMetrics: MetricGroup {
    let window = Metric(CGSize(width: 1280, height: 800), .anatomy("Arc 1.170 sign-in window: 1280 and 800 beside its title, bin:0x10189095c (research report §1.2)"))
    let leftWidth = Metric(560.0, .guess("Arc's left column (SplitViewLeftBackground) width was not recovered; 560 leaves the right column room for a 600 pt illustration"))
    let leftInset = Metric(64.0, .guess("left column side inset"))
    let titleTop = Metric(112.0, .guess("left column title's top"))
    let titleSize = Metric(40.0, .guess("Arc's two-line step titles (\"Get us up\\nto speed.\"), read as large bold display type"))
    let bodySize = Metric(15.0, .guess("step body text"))
    let footerBottom = Metric(44.0, .guess("footer buttons' distance from the window's bottom"))
    let buttonHeight = Metric(40.0, .guess("main button height"))
    let illustration = Metric(CGSize(width: 300, height: 211), .anatomy("Arc's ContentIntro1.png is 602 x 422 px at 2x (research arc-assets)"))
    let tile = Metric(CGSize(width: 112, height: 96), .guess("browser tile; Arc's browser logos are 100 x 100 px"))
    let transition = Metric(0.35, .guess("step cross-fade; Arc's timing was not recovered"))
}

let OnboardingLayout = OnboardingMetrics()

@MainActor
final class OnboardingViewModel: ObservableObject {
    @Published var snapshot = OnboardingSnapshot()
    let dispatch: @MainActor (OnboardingAction) -> Void
    let appIcon: NSImage?
    fileprivate(set) var frames: [String: CGRect] = [:]
    /// Which view instance wrote each frame: during a cross-fade the old screen's control disappears after the new
    /// screen's control of the same name appeared, and must not take the new frame with it.
    private var owners: [String: UUID] = [:]
    lazy var theme = ThemeEditorModel(draft: ThemeDraft(theme: snapshot.theme), chosen: true) { [weak self] draft in
        self?.dispatch(.theme(draft.theme))
    }

    init(dispatch: @escaping @MainActor (OnboardingAction) -> Void, appIcon: NSImage?) {
        self.dispatch = dispatch
        self.appIcon = appIcon
    }

    func record(_ id: String, _ frame: CGRect, by owner: UUID) { frames[id] = frame; owners[id] = owner }
    func forget(_ id: String, by owner: UUID) {
        guard owners[id] == owner else { return }
        frames[id] = nil; owners[id] = nil
    }
}

/// The NSView BrkApp puts in the onboarding window (through BrkContent).
public final class OnboardingHostView: NSView, OnboardingSurface {
    private let model: OnboardingViewModel
    private let hosting: NSHostingView<OnboardingRoot>

    public init(dispatch: @escaping @MainActor (OnboardingAction) -> Void, appIcon: NSImage?) {
        model = OnboardingViewModel(dispatch: dispatch, appIcon: appIcon)
        hosting = NSHostingView(rootView: OnboardingRoot(model: model))
        super.init(frame: CGRect(origin: .zero, size: OnboardingLayout.window.value))
        hosting.frame = bounds
        hosting.autoresizingMask = [.width, .height]
        // Full bleed under the transparent title bar, as Arc's window; control frames then start at the window's top.
        hosting.safeAreaRegions = []
        addSubview(hosting)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }

    public var view: NSView { self }
    public var controlFrames: [String: CGRect] { model.frames }

    public func render(_ snapshot: OnboardingSnapshot) {
        guard snapshot != model.snapshot else { return }

        if snapshot.step == .theme, model.theme.draft.theme != snapshot.theme { model.theme.draft = ThemeDraft(theme: snapshot.theme) }
        model.snapshot = snapshot
    }
}

// MARK: Shared pieces

private enum Ink {
    static func left(_ dark: Bool) -> Color { dark ? Color(red: 0.11, green: 0.105, blue: 0.12) : Color(red: 0.975, green: 0.965, blue: 0.955) }
    static func right(_ dark: Bool) -> Color { dark ? Color(red: 0.07, green: 0.07, blue: 0.08) : Color(red: 0.93, green: 0.915, blue: 0.9) }
    static func primary(_ dark: Bool) -> Color { dark ? .white : Color(red: 0.08, green: 0.08, blue: 0.09) }
    static func secondary(_ dark: Bool) -> Color { primary(dark).opacity(0.62) }
    static func card(_ dark: Bool) -> Color { dark ? Color(white: 0.16) : .white }
    static func stroke(_ dark: Bool) -> Color { primary(dark).opacity(0.12) }
    static let accent = Color(red: 0.36, green: 0.31, blue: 0.95)
}

private struct ControlFrame: ViewModifier {
    let id: String
    @ObservedObject var model: OnboardingViewModel
    @State private var token = UUID()
    func body(content: Content) -> some View {
        content
            .accessibilityIdentifier("onboarding-\(id)")
            .background(GeometryReader { geometry in
                let frame = geometry.frame(in: .named("onboarding"))
                Color.clear
                    .onAppear { model.record(id, frame, by: token) }
                    .onChange(of: frame) { _, new in model.record(id, new, by: token) }
                    .onDisappear { model.forget(id, by: token) }
            })
    }
}

extension View {
    fileprivate func control(_ id: String, _ model: OnboardingViewModel) -> some View { modifier(ControlFrame(id: id, model: model)) }
}

private struct PrimaryButton: View {
    let title: String
    var enabled = true
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 14, weight: .semibold))
                .foregroundStyle(scheme == .dark ? Color.black : Color.white)
                .padding(.horizontal, 22).frame(minWidth: 96, minHeight: OnboardingLayout.buttonHeight.value)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Ink.primary(scheme == .dark).opacity(enabled ? 1 : 0.3)))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).disabled(!enabled)
    }
}

private struct QuietButton: View {
    let title: String
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Button(action: action) {
            Text(title).font(.system(size: 14, weight: .medium)).foregroundStyle(Ink.secondary(scheme == .dark))
                .padding(.horizontal, 10).frame(minHeight: OnboardingLayout.buttonHeight.value).contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

/// A big YES / NO choice row (Arc's ad blocker and default browser steps: "YES, …" in bold, the rest plain).
private struct ChoiceRow: View {
    let lead: String
    let rest: String
    var tag: String? = nil
    let selected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle").font(.system(size: 17)).foregroundStyle(selected ? Ink.accent : Ink.secondary(scheme == .dark))
                (Text(lead).fontWeight(.bold) + Text(rest)).font(.system(size: 15)).foregroundStyle(Ink.primary(scheme == .dark))
                Spacer(minLength: 8)
                if let tag {
                    Text(tag).font(.system(size: 11, weight: .semibold)).foregroundStyle(Ink.accent)
                        .padding(.horizontal, 8).padding(.vertical, 3).background(Capsule().fill(Ink.accent.opacity(0.12)))
                }
            }
            .padding(.horizontal, 16).frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Ink.card(scheme == .dark)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(selected ? Ink.accent : Ink.stroke(scheme == .dark), lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle())
        }.buttonStyle(.plain)
    }
}

private struct Footer {
    var back = true
    var skip: String? = nil
    var primary: String = "Next"
    var primaryEnabled = true
    var primaryAction: OnboardingAction = .next
}

/// One Setup step: the left column (title, text, content, footer) and the right column's illustration.
private struct StepScreen<Content: View, Art: View>: View {
    @ObservedObject var model: OnboardingViewModel
    let title: String
    let text: String
    let footer: Footer
    @ViewBuilder let content: () -> Content
    @ViewBuilder let art: () -> Art
    @Environment(\.colorScheme) private var scheme
    private let m = OnboardingLayout

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.system(size: m.titleSize.value, weight: .bold)).tracking(-0.6).lineSpacing(-2)
                    .foregroundStyle(Ink.primary(scheme == .dark)).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, m.titleTop.value)
                Text(text).font(.system(size: m.bodySize.value)).lineSpacing(3).foregroundStyle(Ink.secondary(scheme == .dark))
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 18)
                content().padding(.top, 26)
                Spacer(minLength: 16)
                HStack(spacing: 6) {
                    if footer.back && model.snapshot.canGoBack {
                        Button { model.dispatch(.back) } label: {
                            HStack(spacing: 4) { Image(systemName: "arrow.left"); Text("Back") }
                                .font(.system(size: 14, weight: .medium)).foregroundStyle(Ink.secondary(scheme == .dark))
                                .frame(minHeight: m.buttonHeight.value).contentShape(Rectangle())
                        }.buttonStyle(.plain).control("back", model)
                    }
                    Spacer()
                    if let skip = footer.skip { QuietButton(title: skip) { model.dispatch(.skip) }.control("skip", model) }
                    PrimaryButton(title: footer.primary, enabled: footer.primaryEnabled) { model.dispatch(footer.primaryAction) }
                        .control("next", model).keyboardShortcut(.defaultAction)
                }
                .padding(.bottom, m.footerBottom.value)
            }
            .padding(.horizontal, m.leftInset.value)
            .frame(width: m.leftWidth.value)
            .frame(maxHeight: .infinity)
            .background(Ink.left(scheme == .dark))
            ZStack { Ink.right(scheme == .dark); art() }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// A browser's icon: the installed app's, else a letter tile.
private struct BrowserIcon: View {
    let tile: OnboardingBrowserTile
    var side: CGFloat = 48
    var body: some View {
        if let path = tile.appPath {
            Image(nsImage: NSWorkspace.shared.icon(forFile: path)).resizable().frame(width: side, height: side)
        } else if tile.id == "file" {
            Image(systemName: "doc.badge.arrow.up").font(.system(size: side * 0.55)).frame(width: side, height: side)
        } else {
            Text(String(tile.name.prefix(1))).font(.system(size: side * 0.5, weight: .bold)).foregroundStyle(.white)
                .frame(width: side, height: side).background(RoundedRectangle(cornerRadius: side * 0.24, style: .continuous).fill(Ink.accent.opacity(0.8)))
        }
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        content().padding(22)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Ink.card(scheme == .dark)))
            .shadow(color: .black.opacity(scheme == .dark ? 0.4 : 0.1), radius: 24, y: 10)
    }
}

// MARK: Root

struct OnboardingRoot: View {
    @ObservedObject var model: OnboardingViewModel

    var body: some View {
        ZStack {
            screen.id(model.snapshot.step).transition(.opacity)
        }
        .animation(.easeInOut(duration: OnboardingLayout.transition.value), value: model.snapshot.step)
        .coordinateSpace(name: "onboarding")
        .frame(minWidth: 960, minHeight: 640)
    }

    @ViewBuilder private var screen: some View {
        let s = model.snapshot
        switch s.step {
        case .welcome: WelcomeScreen(model: model)
        case .name: NameScreen(model: model)
        case .pickBrowser: PickBrowserScreen(model: model)
        case .profiles: ProfilesScreen(model: model)
        case .keychain: KeychainScreen(model: model)
        case .safari: SafariScreen(model: model)
        case .safariLegacy: SafariLegacyScreen(model: model)
        case .progress: ProgressScreen(model: model)
        case .bookmarks: BookmarksScreen(model: model)
        case .favorites: FavoritesScreen(model: model)
        case .theme: ThemeScreen(model: model)
        case .adBlocker: AdBlockerScreen(model: model)
        case .max: MaxScreen(model: model)
        case .defaultBrowser: DefaultBrowserScreen(model: model)
        case .finish: FinishScreen(model: model)
        }
    }
}

// MARK: Welcome

/// Full bleed, as Arc's: a slowly drifting light over Brk's own colors, the icon, one line, a forward arrow.
private struct WelcomeScreen: View {
    @ObservedObject var model: OnboardingViewModel
    @State private var drift = false
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.95, green: 0.92, blue: 0.89), Color(red: 0.86, green: 0.84, blue: 0.97)], startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(RadialGradient(colors: [Color(red: 1, green: 0.78, blue: 0.62).opacity(0.75), .clear], center: .center, startRadius: 0, endRadius: 360))
                .frame(width: 720, height: 720).offset(x: drift ? 220 : -260, y: drift ? -120 : 140).blur(radius: 30)
            Circle().fill(RadialGradient(colors: [Color(red: 0.55, green: 0.5, blue: 1).opacity(0.55), .clear], center: .center, startRadius: 0, endRadius: 320))
                .frame(width: 640, height: 640).offset(x: drift ? -240 : 200, y: drift ? 160 : -100).blur(radius: 30)
            VStack(spacing: 22) {
                if let icon = model.appIcon { Image(nsImage: icon).resizable().frame(width: 112, height: 112).shadow(color: .black.opacity(0.15), radius: 18, y: 8) }
                Text("A browser made for you.").font(.system(size: 52, weight: .bold)).tracking(-1.2).foregroundStyle(Color(red: 0.08, green: 0.08, blue: 0.1))
                Text("Your Spaces, tabs and history live on this Mac. No account needed.")
                    .font(.system(size: 17)).foregroundStyle(Color(red: 0.08, green: 0.08, blue: 0.1).opacity(0.6))
                Button { model.dispatch(.next) } label: {
                    Image(systemName: "arrow.right").font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                        .frame(width: 56, height: 56).background(Circle().fill(Color(red: 0.08, green: 0.08, blue: 0.1))).contentShape(Circle())
                }
                .buttonStyle(.plain).keyboardShortcut(.defaultAction).control("welcome-next", model).padding(.top, 14)
            }
        }
        .environment(\.colorScheme, .light)
        .onAppear { withAnimation(.easeInOut(duration: 9).repeatForever(autoreverses: true)) { drift = true } }
    }
}

// MARK: Name (in place of Arc's sign-up)

private struct NameScreen: View {
    @ObservedObject var model: OnboardingViewModel
    @State private var text = ""
    @FocusState private var focused: Bool
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        StepScreen(model: model, title: "What should we\ncall you?",
                   text: "Any nickname is fine. Brk keeps it on this Mac and only uses it to say hello. There is no account to make.",
                   footer: Footer(skip: "Skip for now")) {
            TextField("Your name", text: $text)
                .textFieldStyle(.plain).font(.system(size: 18)).padding(.horizontal, 14).frame(height: 48)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Ink.card(scheme == .dark)))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(focused ? Ink.accent : Ink.stroke(scheme == .dark), lineWidth: focused ? 2 : 1))
                .focused($focused).frame(maxWidth: 380)
                .onSubmit { model.dispatch(.next) }
                .onChange(of: text) { _, value in model.dispatch(.setName(value)) }
                .control("name-field", model)
        } art: {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) { ForEach(0..<3) { _ in Circle().fill(Ink.stroke(scheme == .dark)).frame(width: 10, height: 10) } }
                    Text(text.trimmingCharacters(in: .whitespaces).isEmpty ? "Welcome to Brk." : "Welcome to Brk, \(text.trimmingCharacters(in: .whitespaces)).")
                        .font(.system(size: 26, weight: .bold)).foregroundStyle(Ink.primary(scheme == .dark)).lineLimit(2)
                    Text("Stored only on this Mac").font(.system(size: 13)).foregroundStyle(Ink.secondary(scheme == .dark))
                }.frame(width: 340, alignment: .leading)
            }
        }
        .onAppear { text = model.snapshot.name; focused = true }
    }
}

// MARK: Pick a browser

private struct PickBrowserScreen: View {
    @ObservedObject var model: OnboardingViewModel
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let s = model.snapshot
        StepScreen(model: model, title: "Bring your\nbrowser along.",
                   text: "Start where you left off. Bring your tabs, bookmarks, history, passwords and logins from the browser you use now.",
                   footer: Footer(back: s.mode == .firstRun, skip: s.mode == .firstRun ? "Skip for now" : nil, primaryEnabled: s.selectedBrowser != nil)) {
            VStack(alignment: .leading, spacing: 14) {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(OnboardingLayout.tile.value.width), spacing: 10), count: 3), alignment: .leading, spacing: 10) {
                    ForEach(s.browsers, id: \.id) { tile in
                        Button { model.dispatch(.pickBrowser(tile.id)) } label: {
                            VStack(spacing: 6) {
                                BrowserIcon(tile: tile, side: 40)
                                Text(tile.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(Ink.primary(scheme == .dark)).lineLimit(1)
                                Text(tile.detail).font(.system(size: 11)).foregroundStyle(Ink.secondary(scheme == .dark)).lineLimit(1)
                            }
                            .frame(width: OnboardingLayout.tile.value.width, height: OnboardingLayout.tile.value.height)
                            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Ink.card(scheme == .dark)))
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(s.selectedBrowser == tile.id ? Ink.accent : Ink.stroke(scheme == .dark), lineWidth: s.selectedBrowser == tile.id ? 2 : 1))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain).control("browser-\(tile.id)", model)
                    }
                }
                Text(s.browserSentence.isEmpty ? " " : s.browserSentence).font(.system(size: 13)).foregroundStyle(Ink.secondary(scheme == .dark))
                    .fixedSize(horizontal: false, vertical: true)
                if let quit = s.mustQuit {
                    Label(quit, systemImage: "exclamationmark.triangle.fill").font(.system(size: 13, weight: .medium)).foregroundStyle(.orange)
                }
                if s.mode == .firstRun {
                    Button { model.dispatch(.skip) } label: {
                        Text("No thanks, I'll start from scratch.").font(.system(size: 13)).underline().foregroundStyle(Ink.secondary(scheme == .dark))
                    }.buttonStyle(.plain).control("start-fresh", model)
                }
            }
        } art: {
            let chosen = s.browsers.first { $0.id == s.selectedBrowser }
            HStack(spacing: 28) {
                if let chosen { BrowserIcon(tile: chosen, side: 96) } else {
                    RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Ink.stroke(scheme == .dark), style: StrokeStyle(lineWidth: 2, dash: [6]))
                        .frame(width: 96, height: 96)
                }
                Image(systemName: "arrow.right").font(.system(size: 30, weight: .semibold)).foregroundStyle(Ink.secondary(scheme == .dark))
                if let icon = model.appIcon { Image(nsImage: icon).resizable().frame(width: 104, height: 104) }
            }
        }
    }
}

// MARK: Profiles

private struct ProfilesScreen: View {
    @ObservedObject var model: OnboardingViewModel
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let s = model.snapshot
        let arc = s.selectedBrowser == "arc"
        StepScreen(model: model, title: "Choose what\nto bring.",
                   text: arc ? "Pick the Arc profiles to bring over. Every Arc Space becomes a Brk Space, and each Arc profile keeps a Brk profile of the same name."
                             : "Pick the \(s.browserName) profiles to bring over. Everything lands in this Brk profile.",
                   footer: Footer(primaryEnabled: s.profiles.contains(where: \.selected))) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(s.profiles, id: \.id) { profile in
                    Button { model.dispatch(.toggleProfile(profile.id)) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: profile.selected ? "checkmark.square.fill" : "square").font(.system(size: 17))
                                .foregroundStyle(profile.selected ? Ink.accent : Ink.secondary(scheme == .dark))
                            Image(systemName: "person.crop.circle").font(.system(size: 17)).foregroundStyle(Ink.secondary(scheme == .dark))
                            Text(profile.name).font(.system(size: 15, weight: .medium)).foregroundStyle(Ink.primary(scheme == .dark))
                            Spacer()
                        }
                        .padding(.horizontal, 14).frame(height: 46)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Ink.card(scheme == .dark)))
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain).control("profile-\(profile.id)", model)
                }
            }.frame(maxWidth: 400)
        } art: {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text("\(s.profiles.filter(\.selected).count) of \(s.profiles.count) profiles").font(.system(size: 13, weight: .semibold)).foregroundStyle(Ink.secondary(scheme == .dark))
                    ForEach(s.profiles.filter(\.selected).prefix(5), id: \.id) { profile in
                        HStack { Image(systemName: "person.crop.circle.fill"); Text(profile.name).lineLimit(1) }.font(.system(size: 17, weight: .medium))
                    }
                }.frame(width: 300, alignment: .leading)
            }
        }
    }
}

// MARK: Keychain explanation (Dia's step before macOS asks)

private struct KeychainScreen: View {
    @ObservedObject var model: OnboardingViewModel
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let s = model.snapshot
        StepScreen(model: model, title: "Unlock your data\nfor import.",
                   text: "\(s.browserName) keeps your passwords and logins encrypted. To read them, macOS will ask for your computer password once for each profile. Brk never sees or keeps your computer password.",
                   footer: Footer(primary: s.waitingForPassword ? "Waiting for password…" : "Begin Importing", primaryEnabled: !s.waitingForPassword, primaryAction: .beginImport)) {
            VStack(alignment: .leading, spacing: 14) {
                // The whole row switches, not only the switch itself.
                Button { model.dispatch(.importSecrets(!s.importSecrets)) } label: {
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Import passwords and stay logged in").font(.system(size: 14, weight: .semibold)).foregroundStyle(Ink.primary(scheme == .dark))
                            Text("Your saved passwords and your website logins (cookies)").font(.system(size: 12)).foregroundStyle(Ink.secondary(scheme == .dark))
                        }
                        Spacer(minLength: 8)
                        Toggle("", isOn: .constant(s.importSecrets)).labelsHidden().toggleStyle(.switch).allowsHitTesting(false)
                    }
                    .padding(.horizontal, 14).frame(height: 58)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Ink.card(scheme == .dark)))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).disabled(s.waitingForPassword).control("secrets-toggle", model)
                if s.waitingForPassword {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Enter your macOS password to import passwords from profile \(s.waitingProfile)").font(.system(size: 13)).foregroundStyle(Ink.secondary(scheme == .dark))
                    }
                }
            }.frame(maxWidth: 420, alignment: .leading)
        } art: {
            VStack(spacing: 18) {
                Image(systemName: "lock.shield").font(.system(size: 64, weight: .light)).foregroundStyle(Ink.accent)
                Card {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("What macOS will show").font(.system(size: 11, weight: .semibold)).foregroundStyle(Ink.secondary(scheme == .dark))
                        Text("Brk wants to use your confidential information stored in “\(s.browserName) Safe Storage” in your keychain.")
                            .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                        Text("Type your Mac's login password, then choose Allow.").font(.system(size: 12)).foregroundStyle(Ink.secondary(scheme == .dark))
                    }.frame(width: 320, alignment: .leading)
                }
            }
        }
    }
}

// MARK: Safari

private struct SafariScreen: View {
    @ObservedObject var model: OnboardingViewModel
    @State private var targeted = false
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let s = model.snapshot
        StepScreen(model: model, title: "Import from\nSafari.",
                   text: "Safari can hand over your passwords, history and bookmarks in one file. No special permission needed.",
                   footer: Footer(skip: "Skip", primaryEnabled: s.safariFile != nil, primaryAction: .beginImport)) {
            VStack(alignment: .leading, spacing: 12) {
                step(1, "Open Safari") { Button("Open Safari") { model.dispatch(.openSafari) }.control("safari-open", model) }
                step(2, "Choose File › Export Browsing Data to File…") { EmptyView() }
                step(3, "Click Export and save the file") { EmptyView() }
                step(4, "Drop the .zip file here") { EmptyView() }
                Button { model.dispatch(.chooseSafariFile) } label: {
                    VStack(spacing: 6) {
                        Image(systemName: s.safariFile == nil ? "square.and.arrow.down" : "checkmark.circle.fill").font(.system(size: 22))
                            .foregroundStyle(s.safariFile == nil ? Ink.secondary(scheme == .dark) : Ink.accent)
                        Text(s.safariFile.map { ($0 as NSString).lastPathComponent } ?? "Choose .zip file or drag it here").font(.system(size: 13, weight: .medium))
                            .foregroundStyle(Ink.primary(scheme == .dark))
                    }
                    .frame(maxWidth: 420).frame(height: 92)
                    .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(targeted ? Ink.accent.opacity(0.08) : Ink.card(scheme == .dark)))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(targeted ? Ink.accent : Ink.stroke(scheme == .dark), style: StrokeStyle(lineWidth: 1.5, dash: [5])))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).control("safari-choose", model)
                .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
                    guard let provider = providers.first else { return false }
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        guard let url else { return }
                        Task { @MainActor in model.dispatch(.useSafariFile(url)) }
                    }
                    return true
                }
                if let error = s.safariError { Text(error).font(.system(size: 12, weight: .medium)).foregroundStyle(.red) }
                Button { model.dispatch(.openFullDiskAccess) } label: {
                    Text("Using Safari 17 or earlier?").font(.system(size: 12)).underline().foregroundStyle(Ink.secondary(scheme == .dark))
                }.buttonStyle(.plain).control("safari-legacy", model)
            }
        } art: {
            Card {
                VStack(alignment: .leading, spacing: 0) {
                    Text("File").font(.system(size: 13, weight: .semibold)).padding(.bottom, 8)
                    ForEach(["New Window", "Open File…", "Close Window"], id: \.self) { Text($0).font(.system(size: 13)).foregroundStyle(Ink.secondary(scheme == .dark)).padding(.vertical, 4) }
                    Text("Export Browsing Data to File…").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 5).background(RoundedRectangle(cornerRadius: 5).fill(Ink.accent)).padding(.horizontal, -8)
                    ForEach(["Import From", "Print…"], id: \.self) { Text($0).font(.system(size: 13)).foregroundStyle(Ink.secondary(scheme == .dark)).padding(.vertical, 4) }
                }.frame(width: 260, alignment: .leading)
            }
        }
    }

    private func step<Accessory: View>(_ number: Int, _ text: String, @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack(spacing: 10) {
            Text("\(number)").font(.system(size: 12, weight: .bold)).foregroundStyle(.white).frame(width: 22, height: 22).background(Circle().fill(Ink.primary(scheme == .dark)))
            Text(text).font(.system(size: 14)).foregroundStyle(Ink.primary(scheme == .dark))
            accessory()
        }
    }
}

/// Safari 17 and older: Arc's Full Disk Access route.
private struct SafariLegacyScreen: View {
    @ObservedObject var model: OnboardingViewModel
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let s = model.snapshot
        StepScreen(model: model, title: "Import from\nSafari.",
                   text: "Older Safari versions cannot export a file, so Brk reads Safari's bookmarks and history directly. That needs Full Disk Access. You can turn it off again when this step is done.",
                   footer: Footer(skip: "Skip", primary: "Check and Import", primaryAction: .beginImport)) {
            VStack(alignment: .leading, spacing: 12) {
                Button("Open Full Disk Access Settings") { model.dispatch(.openFullDiskAccess) }.control("fda-open", model)
                Text("Click + and choose Brk in Applications, then come back and click Check and Import. Passwords: export them from Safari's Passwords settings and use Import from a file… later.")
                    .font(.system(size: 13)).foregroundStyle(Ink.secondary(scheme == .dark)).fixedSize(horizontal: false, vertical: true).frame(maxWidth: 420, alignment: .leading)
                if let error = s.safariError { Text(error).font(.system(size: 12, weight: .medium)).foregroundStyle(.red) }
            }
        } art: {
            Card {
                HStack(spacing: 14) {
                    Image(systemName: "lock.open.laptopcomputer").font(.system(size: 40)).foregroundStyle(Ink.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Privacy & Security › Full Disk Access").font(.system(size: 13, weight: .semibold))
                        HStack { Image(systemName: "checkmark.square.fill").foregroundStyle(Ink.accent); Text("Brk") }.font(.system(size: 13))
                    }
                }.frame(width: 320, alignment: .leading)
            }
        }
    }
}

// MARK: Progress and failures (Dia's)

private struct ProgressScreen: View {
    @ObservedObject var model: OnboardingViewModel
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let s = model.snapshot
        StepScreen(model: model, title: s.progressTitle.isEmpty ? "Importing…" : s.progressTitle,
                   text: s.progressDone ? (s.failures.isEmpty ? "All set. Everything came through." : "Most of it came through.") : "Hold on while we fetch your data…",
                   footer: Footer(back: false, primaryEnabled: s.progressDone)) {
            VStack(alignment: .leading, spacing: 10) {
                if !s.progressDone {
                    HStack(spacing: 10) { ProgressView().controlSize(.small); Text(s.progressDetail).font(.system(size: 13)).foregroundStyle(Ink.secondary(scheme == .dark)) }
                }
                if !s.failures.isEmpty {
                    Text("Some import steps failed:").font(.system(size: 13, weight: .semibold)).foregroundStyle(Ink.primary(scheme == .dark))
                    ForEach(s.failures, id: \.self) { line in
                        Label(line, systemImage: "exclamationmark.circle").font(.system(size: 12)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                    Text("You can try again later from Brk › Import from Another Browser…").font(.system(size: 12)).foregroundStyle(Ink.secondary(scheme == .dark))
                }
            }.frame(maxWidth: 440, alignment: .leading)
        } art: {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(s.summary, id: \.self) { line in
                        HStack(spacing: 8) { Image(systemName: "checkmark.circle.fill").foregroundStyle(Ink.accent); Text(line) }.font(.system(size: 15, weight: .medium))
                    }
                    if s.summary.isEmpty { ProgressView() }
                }.frame(width: 300, alignment: .leading)
            }
        }
    }
}

// MARK: Bookmarks

private struct BookmarksScreen: View {
    @ObservedObject var model: OnboardingViewModel
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let s = model.snapshot
        StepScreen(model: model, title: "Give your bookmarks\na fresh start.",
                   text: s.recommendedCount > 0
                    ? (s.recommendedCount == 1 ? "We picked the bookmark you visit most to start." : "We picked the \(s.recommendedCount) bookmarks you visit most to start.")
                        + " Add more now, or import the rest any time later."
                    : "Choose which bookmarks to bring. They go into a folder called “Imported from \(s.browserName)” in Pinned.",
                   footer: Footer(skip: "Do this later", primary: s.bookmarkSelected > 0 ? "Import \(s.bookmarkSelected)" : "Next")) {
            VStack(alignment: .leading, spacing: 8) {
                Button { model.dispatch(.selectAllBookmarks(s.bookmarkSelected < s.bookmarkTotal)) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: s.bookmarkSelected == s.bookmarkTotal ? "checkmark.square.fill" : (s.bookmarkSelected == 0 ? "square" : "minus.square.fill"))
                            .foregroundStyle(s.bookmarkSelected > 0 ? Ink.accent : Ink.secondary(scheme == .dark))
                        Text("Select All").font(.system(size: 13, weight: .semibold))
                        Text("\(s.bookmarkSelected) of \(s.bookmarkTotal)").font(.system(size: 12)).foregroundStyle(Ink.secondary(scheme == .dark))
                    }.contentShape(Rectangle())
                }.buttonStyle(.plain).control("bookmarks-all", model)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(s.bookmarks, id: \.id) { row in BookmarkRowView(model: model, row: row) }
                    }
                }
                .frame(height: 330)
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Ink.card(scheme == .dark)))
            }.frame(maxWidth: 432)
        } art: {
            Card {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) { Image(systemName: "folder.fill").foregroundStyle(Ink.accent); Text("Imported from \(s.browserName)").font(.system(size: 15, weight: .semibold)) }
                    ForEach(s.bookmarks.filter { $0.selected && !$0.isFolder }.prefix(7), id: \.id) { row in
                        HStack(spacing: 8) { Image(systemName: "globe").foregroundStyle(Ink.secondary(scheme == .dark)); Text(row.title).lineLimit(1) }
                            .font(.system(size: 13)).padding(.leading, 22)
                    }
                }.frame(width: OnboardingLayout.illustration.value.width, alignment: .leading)
            }
        }
    }
}

private struct BookmarkRowView: View {
    @ObservedObject var model: OnboardingViewModel
    let row: OnboardingBookmarkRow
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        HStack(spacing: 6) {
            Spacer().frame(width: CGFloat(row.level) * 16)
            if row.isFolder {
                Button { model.dispatch(.expandBookmark(row.id)) } label: {
                    Image(systemName: row.expanded ? "chevron.down" : "chevron.right").font(.system(size: 10, weight: .bold)).frame(width: 14, height: 28).contentShape(Rectangle())
                }.buttonStyle(.plain).control("bookmark-expand-\(row.id)", model)
            } else { Spacer().frame(width: 14) }
            Button { model.dispatch(.toggleBookmark(row.id)) } label: {
                HStack(spacing: 7) {
                    Image(systemName: row.selected ? "checkmark.square.fill" : (row.mixed ? "minus.square.fill" : "square"))
                        .foregroundStyle(row.selected || row.mixed ? Ink.accent : Ink.secondary(scheme == .dark))
                    Image(systemName: row.isFolder ? "folder" : "globe").foregroundStyle(Ink.secondary(scheme == .dark))
                    Text(row.title.isEmpty ? row.detail : row.title).font(.system(size: 13)).foregroundStyle(Ink.primary(scheme == .dark)).lineLimit(1)
                    if !row.isFolder { Text(row.detail).font(.system(size: 11)).foregroundStyle(Ink.secondary(scheme == .dark)).lineLimit(1) }
                    Spacer(minLength: 4)
                    if row.starred { Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(.yellow) }
                }.frame(height: 28).contentShape(Rectangle())
            }.buttonStyle(.plain).control("bookmark-\(row.id)", model)
        }
        .padding(.horizontal, 10)
    }
}

// MARK: Favorites (Arc's top apps)

private struct FavoritesScreen: View {
    @ObservedObject var model: OnboardingViewModel
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let s = model.snapshot
        StepScreen(model: model, title: "Choose the sites\nyou use most.",
                   text: "Favorites sit at the top of your sidebar, one click away in every Space.",
                   footer: Footer(skip: "Skip for now")) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(100), spacing: 10), count: 4), alignment: .leading, spacing: 10) {
                ForEach(s.sites, id: \.id) { site in
                    Button { model.dispatch(.toggleSite(site.id)) } label: {
                        VStack(spacing: 6) {
                            SiteMark(host: site.host, side: 34)
                            Text(site.title).font(.system(size: 11, weight: .medium)).foregroundStyle(Ink.primary(scheme == .dark)).lineLimit(1)
                        }
                        .frame(width: 100, height: 82)
                        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Ink.card(scheme == .dark)))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(site.selected ? Ink.accent : Ink.stroke(scheme == .dark), lineWidth: site.selected ? 2 : 1))
                        .overlay(alignment: .topTrailing) {
                            if site.selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Ink.accent).padding(6) }
                        }
                        .contentShape(Rectangle())
                    }.buttonStyle(.plain).control("site-\(site.id)", model)
                }
            }
        } art: {
            Card {
                LazyVGrid(columns: Array(repeating: GridItem(.fixed(60), spacing: 10), count: 4), spacing: 10) {
                    ForEach(Array(s.sites.filter(\.selected).prefix(8)), id: \.id) { site in
                        SiteMark(host: site.host, side: 30).frame(width: 60, height: 48)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Ink.right(scheme == .dark)))
                    }
                    ForEach(0..<max(0, 8 - s.sites.filter(\.selected).count), id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Ink.right(scheme == .dark)).frame(width: 60, height: 48)
                    }
                }.frame(width: 270)
            }
        }
    }
}

/// A site's mark without fetching anything: its first letter on a color picked from its name.
private struct SiteMark: View {
    let host: String
    var side: CGFloat
    var body: some View {
        let name = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let hue = Double(name.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xffff } % 360) / 360
        Text(String(name.prefix(1)).uppercased()).font(.system(size: side * 0.5, weight: .bold)).foregroundStyle(.white)
            .frame(width: side, height: side).background(RoundedRectangle(cornerRadius: side * 0.26, style: .continuous).fill(Color(hue: hue, saturation: 0.55, brightness: 0.78)))
    }
}

// MARK: Theme

private struct ThemeScreen: View {
    @ObservedObject var model: OnboardingViewModel
    var body: some View {
        let colors = model.theme.draft.colors.map { Color(red: $0.red, green: $0.green, blue: $0.blue) }
        StepScreen(model: model, title: "Make it yours\nwith a theme.",
                   text: "Pick a color for your first Space. Every Space can have its own, and you can change them any time.",
                   footer: Footer(skip: "Skip for now")) {
            EmptyView()
        } art: {
            ZStack {
                LinearGradient(colors: colors.count > 1 ? colors : [colors.first ?? .gray, (colors.first ?? .gray).opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)
                ThemeEditorView(model: model.theme)
                    .background(RoundedRectangle(cornerRadius: ThemePanel.cornerRadius.value, style: .continuous).fill(.regularMaterial))
                    .control("theme-editor", model)
            }
        }
    }
}

// MARK: Ad blocker

private struct AdBlockerScreen: View {
    @ObservedObject var model: OnboardingViewModel
    var body: some View {
        let s = model.snapshot
        StepScreen(model: model, title: "Fewer ads,\nno trackers.",
                   text: "Brk has a blocker built in for ads, trackers and cookie banners, so pages load faster and follow you less. You can turn it off for any site.",
                   footer: Footer()) {
            VStack(spacing: 10) {
                ChoiceRow(lead: "YES", rest: ", block them.", tag: "Recommended", selected: s.blockAds) { model.dispatch(.blockAds(true)) }.control("adblock-yes", model)
                ChoiceRow(lead: "NO", rest: ", show me everything.", selected: !s.blockAds) { model.dispatch(.blockAds(false)) }.control("adblock-no", model)
            }.frame(maxWidth: 420)
        } art: {
            Image(systemName: s.blockAds ? "shield.lefthalf.filled" : "shield.slash").font(.system(size: 120, weight: .light))
                .foregroundStyle(s.blockAds ? Color.green.opacity(0.75) : Color.gray)
        }
    }
}

// MARK: Max (Brk's own copy)

private struct MaxScreen: View {
    @ObservedObject var model: OnboardingViewModel
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        StepScreen(model: model, title: "Move faster with\nAI in Brk?",
                   text: "Turn on Max to let the AI you already use work inside your browser.",
                   footer: Footer(skip: "Not now", primary: "Enable Max", primaryAction: .enableMax(true))) {
            VStack(alignment: .leading, spacing: 14) {
                feature("person.2.wave.2", "Your agent, in the sidebar", "Drag tabs into a conversation with Claude Code or Codex and have it compare, summarize or write things up.")
                feature("square.stack.3d.up", "Tidy tabs and names", "Brk sorts Today into folders and gives tabs and folders short, clear names.")
                feature("text.magnifyingglass", "Ask on Page", "Answers about the page you're on, with Command + F.")
                feature("eye", "5-Second Previews", "Hover a link and hold Shift for a quick summary.")
                Text("Max runs through the AI tools on this Mac, with your own account or API key, and small models that run on this Mac. Brk has no AI servers of its own, and nothing is sent anywhere until you turn Max on.")
                    .font(.system(size: 11)).foregroundStyle(Ink.secondary(scheme == .dark)).fixedSize(horizontal: false, vertical: true).padding(.top, 4)
            }.frame(maxWidth: 432, alignment: .leading)
        } art: {
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Image(systemName: "sparkles").foregroundStyle(Ink.accent); Text("Max").font(.system(size: 15, weight: .bold)) }
                    Text("Compare these three tabs and write a short summary.").font(.system(size: 13)).padding(10)
                        .background(RoundedRectangle(cornerRadius: 10).fill(Ink.right(scheme == .dark)))
                    Text("Here's how they differ…").font(.system(size: 13)).foregroundStyle(Ink.secondary(scheme == .dark))
                }.frame(width: 300, alignment: .leading)
            }
        }
    }

    private func feature(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(Ink.accent).frame(width: 22)
            (Text(title + ": ").fontWeight(.semibold) + Text(text)).font(.system(size: 13)).foregroundStyle(Ink.primary(scheme == .dark)).fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: Default browser

private struct DefaultBrowserScreen: View {
    @ObservedObject var model: OnboardingViewModel
    @State private var choice: Bool? = nil
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        StepScreen(model: model, title: "Make Brk your\neveryday browser?",
                   text: "Links you click in Mail, Messages and every other app will open here.",
                   footer: Footer(primaryEnabled: choice != nil, primaryAction: .makeDefault(choice ?? false))) {
            VStack(spacing: 10) {
                ChoiceRow(lead: "YES", rest: ", make Brk my default.", selected: choice == true) { choice = true }.control("default-yes", model)
                ChoiceRow(lead: "NO", rest: ", still deciding.", selected: choice == false) { choice = false }.control("default-no", model)
            }.frame(maxWidth: 420)
        } art: {
            Card {
                HStack(spacing: 14) {
                    Image(systemName: "link").font(.system(size: 30)).foregroundStyle(Ink.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("example.com/shared-link").font(.system(size: 14, weight: .medium))
                        Text("Opens in Brk").font(.system(size: 12)).foregroundStyle(Ink.secondary(scheme == .dark))
                    }
                }.frame(width: 280, alignment: .leading)
            }
        }
    }
}

// MARK: Finish

private struct FinishScreen: View {
    @ObservedObject var model: OnboardingViewModel
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        let s = model.snapshot
        let person = s.userName.map { ", \($0)" } ?? ""
        StepScreen(model: model, title: s.mode == .firstRun ? "Welcome to Brk\(person)." : "Import complete.",
                   text: s.mode == .firstRun
                    ? (s.summary.isEmpty ? "You're ready to go. Brk 101 opens next with the basics." : "Here's what came along with you. Brk 101 opens next with the basics.")
                    : "Here's what came over. You can import again any time; nothing is added twice.",
                   footer: Footer(back: false, primary: s.mode == .firstRun ? "Get Started" : "Done", primaryAction: .finish)) {
            if s.passwordsNeedRestart {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your passwords are ready after Brk restarts.").font(.system(size: 13)).foregroundStyle(Ink.secondary(scheme == .dark))
                    Button("Restart Brk Now") { model.dispatch(.restart) }.control("restart", model)
                }
            }
        } art: {
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        if let icon = model.appIcon { Image(nsImage: icon).resizable().frame(width: 40, height: 40) }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(s.userName ?? "Brk").font(.system(size: 18, weight: .bold))
                            Text(s.summary.isEmpty ? "A fresh start" : "Brought over").font(.system(size: 12)).foregroundStyle(Ink.secondary(scheme == .dark))
                        }
                    }
                    Divider()
                    ForEach(s.summary, id: \.self) { line in
                        HStack(spacing: 8) { Image(systemName: "checkmark").foregroundStyle(Ink.accent); Text(line) }.font(.system(size: 14))
                    }
                    if !s.failures.isEmpty {
                        Text("\(s.failures.count) part\(s.failures.count == 1 ? "" : "s") could not be imported").font(.system(size: 12)).foregroundStyle(.orange)
                    }
                }.frame(width: 320, alignment: .leading).control("summary", model)
            }
        }
    }
}
