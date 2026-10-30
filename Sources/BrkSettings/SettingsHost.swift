import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit
import SwiftUI

/// Owner: F1. The settings window's content: Arc's panes (General, Max, Profiles, Shortcuts, Links, Advanced;
/// anatomy-m 4.1) as SwiftUI in an `NSHostingView`, like the space dialog. BrkApp hosts it in its own NSWindow
/// (SettingsWindowController) and feeds it `AppSnapshot.settings` after every change; every control dispatches a
/// `.settings(...)` command and never keeps state of its own, so the control socket's `settings` op and the window
/// cannot disagree.
///
/// Public surface (what BrkApp may call): `init(dispatch:)`, `render(_:)`.
/// First pass: the pane picker and the switches of General, Max and Advanced, the Links switches, read-only
/// Profiles and Shortcuts lists. TODO(F1): Arc's layout and copy per pane (visual-and-copy.md "Settings page
/// labels"), the route editor (F3), the shortcut recorder with conflicts (F4), profile dialogs (F2).
@MainActor
public final class SettingsHost: NSView {
    private let model: SettingsModel
    private let hosting: NSHostingView<SettingsRootView>

    public init(dispatch: @escaping Dispatch) {
        model = SettingsModel(dispatch: dispatch)
        hosting = NSHostingView(rootView: SettingsRootView(model: model))
        super.init(frame: .zero)
        hosting.autoresizingMask = [.width, .height]
        hosting.frame = bounds
        addSubview(hosting)
        identify(.settingsWindow)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("not used") }

    /// The whole settings slice; equal slices change nothing.
    public func render(_ settings: SettingsSnapshot) {
        if model.settings != settings { model.settings = settings }
    }
}

@MainActor
final class SettingsModel: ObservableObject {
    @Published var settings: SettingsSnapshot?
    let dispatch: Dispatch
    init(dispatch: @escaping Dispatch) { self.dispatch = dispatch }
}

struct SettingsRootView: View {
    @ObservedObject var model: SettingsModel

    var body: some View {
        if let settings = model.settings {
            VStack(spacing: 0) {
                HStack {
                    ForEach(SettingsPane.allCases, id: \.self) { pane in
                        Button(SettingsCopy.title(pane)) { model.dispatch(.settings(.openPane(pane))) }
                            .buttonStyle(.bordered)
                            .tint(pane == settings.pane ? .accentColor : .secondary)
                            .accessibilityIdentifier(ViewID.settingsPane(pane).identifier)
                    }
                }
                .padding()
                Divider()
                ScrollView { pane(settings).padding() }
            }
        } else {
            Text("").frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private func pane(_ s: SettingsSnapshot) -> some View {
        switch s.pane ?? .general {
        case .general:
            Form {
                toggle(SettingsCopy.warnBeforeQuitting, "warnBeforeQuitting", s.general.warnBeforeQuitting) { .settings(.general(.warnBeforeQuitting($0))) }
                Picker(SettingsCopy.webAppearance, selection: Binding(get: { s.general.webAppearance },
                                                                     set: { model.dispatch(.settings(.general(.webAppearance($0)))) })) {
                    ForEach(WebAppearance.allCases, id: \.self) { Text(SettingsCopy.appearance($0)).tag($0) }
                }
                .accessibilityIdentifier(ViewID.settingsField("webAppearance").identifier)
                Button(SettingsCopy.setAsDefaultBrowser) { model.dispatch(.app(.setAsDefaultBrowser)) }
                    .accessibilityIdentifier(ViewID.settingsField("setAsDefaultBrowser").identifier)
            }
        case .max:
            Form {
                Picker(SettingsCopy.aiProvider, selection: Binding(get: { s.max.settings.provider },
                                                                  set: { model.dispatch(.settings(.max(.provider($0)))) })) {
                    ForEach(AIProviderChoice.allCases, id: \.self) { Text(SettingsCopy.provider($0)).tag($0) }
                }
                .accessibilityIdentifier(ViewID.settingsField("aiProvider").identifier)
                Text(SettingsCopy.detected(s.max.detected, active: s.max.active)).font(.caption).foregroundStyle(.secondary)
                toggle(SettingsCopy.renamePinnedTabs, "renamePinnedTabs", s.max.settings.renamePinnedTabs) { .settings(.max(.renamePinnedTabs($0))) }
                toggle(SettingsCopy.tidyTabs, "tidyTabs", s.max.settings.tidyTabs) { .settings(.max(.tidyTabs($0))) }
            }
        case .profiles:
            Form {
                ForEach(s.profiles, id: \.profile.id) { row in
                    Section(row.profile.name) {
                        Picker(SettingsCopy.searchEngine, selection: Binding(get: { row.settings.searchEngine },
                                                                            set: { model.dispatch(.settings(.profile(row.profile.id, .searchEngine($0)))) })) {
                            ForEach(s.engines, id: \.id) { Text($0.name).tag($0.id) }
                        }
                        .accessibilityIdentifier(ViewID.settingsField("searchEngine-\(row.profile.id)").identifier)
                        toggle(SettingsCopy.searchSuggestions, "searchSuggestions-\(row.profile.id)", row.settings.searchSuggestions) {
                            .settings(.profile(row.profile.id, .searchSuggestions($0)))
                        }
                        Picker(SettingsCopy.autoArchive, selection: Binding(get: { row.settings.autoArchive },
                                                                           set: { model.dispatch(.settings(.profile(row.profile.id, .autoArchive($0)))) })) {
                            ForEach(AutoArchiveThreshold.allCases, id: \.self) { Text(SettingsCopy.threshold($0)).tag($0) }
                        }
                        .accessibilityIdentifier(ViewID.settingsField("autoArchive-\(row.profile.id)").identifier)
                        toggle(SettingsCopy.promptForDownloadLocation, "promptForDownloadLocation-\(row.profile.id)", row.settings.promptForDownloadLocation) {
                            .settings(.profile(row.profile.id, .promptForDownloadLocation($0)))
                        }
                    }
                }
            }
        case .shortcuts:
            Form {
                ForEach(s.shortcuts, id: \.action) { row in
                    HStack {
                        Text(row.title.replacingOccurrences(of: "{app}", with: Product.name))
                        Spacer()
                        Text(SettingsCopy.state(row.state)).foregroundStyle(row.source == .userDefined ? .primary : .secondary)
                    }
                    .accessibilityIdentifier(ViewID.settingsField("shortcut-\(row.action.rawValue)").identifier)
                }
            }
        case .links:
            Form {
                toggle(SettingsCopy.externalLinksInLittleArc, "externalLinksInLittleArc", s.links.externalLinksInLittleArc) { .settings(.links(.externalLinksInLittleArc($0))) }
                toggle(SettingsCopy.optionCommandClickLittleArc, "optionCommandClickLittleArc", s.links.optionCommandClickLittleArc) { .settings(.links(.optionCommandClickLittleArc($0))) }
                toggle(SettingsCopy.shiftClickPeek, "shiftClickPeek", s.links.shiftClickPeek) { .settings(.links(.shiftClickPeek($0))) }
                toggle(SettingsCopy.peekFromPinnedAndFavorites, "peekFromPinnedAndFavorites", s.links.peekFromPinnedAndFavorites) { .settings(.links(.peekFromPinnedAndFavorites($0))) }
                Picker(SettingsCopy.littleArcAutoArchive, selection: Binding(get: { s.links.littleArcAutoArchive },
                                                                            set: { model.dispatch(.settings(.links(.littleArcAutoArchive($0)))) })) {
                    ForEach(AutoArchiveThreshold.allCases, id: \.self) { Text(SettingsCopy.threshold($0)).tag($0) }
                }
                .accessibilityIdentifier(ViewID.settingsField("littleArcAutoArchive").identifier)
                Section(SettingsCopy.airTrafficControl) {
                    ForEach(s.routes, id: \.route.id) { row in
                        HStack { Text(row.route.pattern); Spacer(); Text(row.destinationTitle).foregroundStyle(.secondary) }
                    }
                }
            }
        case .advanced:
            Form {
                toggle(SettingsCopy.restoreWindowsOnLaunch, "restoreWindowsOnLaunch", s.advanced.restoreWindowsOnLaunch) { .settings(.advanced(.restoreWindowsOnLaunch($0))) }
                toggle(SettingsCopy.soundEffects, "soundEffects", s.advanced.soundEffects) { .settings(.advanced(.soundEffects($0))) }
                toggle(SettingsCopy.hapticsOnReorder, "hapticsOnReorder", s.advanced.hapticsOnReorder) { .settings(.advanced(.hapticsOnReorder($0))) }
                toggle(SettingsCopy.showFullURLInToolbar, "showFullURLInToolbar", s.advanced.showFullURLInToolbar) { .settings(.advanced(.showFullURLInToolbar($0))) }
                toggle(SettingsCopy.windowDraggingFromPages, "windowDraggingFromPages", s.advanced.windowDraggingFromPages) { .settings(.advanced(.windowDraggingFromPages($0))) }
                toggle(SettingsCopy.autoPictureInPicture, "autoPictureInPicture", s.advanced.autoPictureInPicture) { .settings(.advanced(.autoPictureInPicture($0))) }
                toggle(SettingsCopy.themeToCSS, "themeToCSS", s.advanced.themeToCSS) { .settings(.advanced(.themeToCSS($0))) }
                toggle(SettingsCopy.boostsEnabled, "boostsEnabled", s.advanced.boostsEnabled) { .settings(.advanced(.boostsEnabled($0))) }
                toggle(SettingsCopy.sharedQuotes, "sharedQuotes", s.advanced.sharedQuotes) { .settings(.advanced(.sharedQuotes($0))) }
            }
        }
    }

    private func toggle(_ title: String, _ field: String, _ value: Bool, _ command: @escaping (Bool) -> Command) -> some View {
        Toggle(title, isOn: Binding(get: { value }, set: { model.dispatch(command($0)) }))
            .accessibilityIdentifier(ViewID.settingsField(field).identifier)
    }
}

/// Arc's settings copy (anatomy-m 4.2, visual-and-copy.md "Settings page labels"), with Brk's own words where the
/// user's decisions replaced Arc's (Max: the local command-line tool instead of Arc Max).
public enum SettingsCopy {
    public static func title(_ pane: SettingsPane) -> String {
        switch pane {
        case .general: "General"
        case .max: "Max"
        case .profiles: "Profiles"
        case .shortcuts: "Shortcuts"
        case .links: "Links"
        case .advanced: "Advanced"
        }
    }

    public static let warnBeforeQuitting = "Warn before quitting"
    public static let webAppearance = "Websites, Easels, and Notes will use:"
    public static let setAsDefaultBrowser = "Set as Default Browser"
    public static let aiProvider = "AI assistant"
    public static let renamePinnedTabs = "Have your tabs automatically renamed with tidier, shorter titles when you Pin them."
    public static let tidyTabs = "Tidy Tabs"
    public static let searchEngine = "Default Search Engine"
    public static let searchSuggestions = "Include search engine suggestions"
    public static let autoArchive = "Archive tabs after"
    public static let promptForDownloadLocation = "Ask where to save each download"
    public static let externalLinksInLittleArc = "Links from other apps open in Little Arc"
    public static let optionCommandClickLittleArc = "Open Little Arc when clicking on links with ⌥⌘ held"
    public static let shiftClickPeek = "Open a Peek window when clicking on links with Shift held"
    public static let peekFromPinnedAndFavorites = "Open a Peek window when clicking on links to other sites"
    public static let littleArcAutoArchive = "Archive Little Arcs after:"
    public static let airTrafficControl = "Air Traffic Control"
    public static let restoreWindowsOnLaunch = "When opening \(Product.name), restore windows from previous session"
    public static let soundEffects = "Play \(Product.name) sound effects"
    public static let hapticsOnReorder = "Haptic feedback when reordering tabs"
    public static let showFullURLInToolbar = "Show full URL when Toolbar is enabled"
    public static let windowDraggingFromPages = "Allow window dragging from the top of webpages"
    public static let autoPictureInPicture = "Enable Picture in Picture when you leave a video tab"
    public static let themeToCSS = "Allow websites to get your theme data"
    public static let boostsEnabled = "Enable Boosts on websites you visit"
    public static let sharedQuotes = "Enable Shared Quotes when highlighting text."

    public static func appearance(_ appearance: WebAppearance) -> String {
        switch appearance {
        case .automatic: "Automatic"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    public static func provider(_ choice: AIProviderChoice) -> String {
        switch choice {
        case .off: "Off"
        case .auto: "Automatic (claude, then codex)"
        case .claude: "claude (command line)"
        case .codex: "codex (command line)"
        }
    }

    public static func detected(_ kinds: [AIProviderKind], active: AIProviderKind?) -> String {
        let found = kinds.isEmpty ? "No local AI command-line tool found on PATH." : "Found on PATH: \(kinds.map(\.rawValue).joined(separator: ", "))."
        return active.map { "\(found) Using \($0.rawValue)." } ?? found
    }

    /// Arc's seven choices (visual-and-copy.md "Auto-archive options and durations").
    public static func threshold(_ threshold: AutoArchiveThreshold) -> String {
        switch threshold {
        case .oneHour: "1 hour"
        case .sixHours: "6 hours"
        case .twelveHours: "12 hours"
        case .twentyFourHours: "24 hours"
        case .sevenDays: "7 days"
        case .thirtyDays: "30 days"
        case .never: "Never"
        }
    }

    public static func state(_ state: KeyBindingState) -> String {
        switch state {
        case .valid(let chord): chord.description
        case .conflict(let chord, _): "\(chord.description) (conflict)"
        case .unset: "unset"
        }
    }
}
