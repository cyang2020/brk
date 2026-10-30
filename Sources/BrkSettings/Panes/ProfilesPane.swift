import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit
import SwiftUI

/// Owner: F2. The Profiles pane's contents (Arc: "Profile Preferences"; anatomy-m 4.2 Profiles): Arc's intro, a new
/// profile field, one section per profile (rename, the spaces using it, the per-profile settings the rules read:
/// default search engine and suggestions, "Archive tabs after", the download location), delete with Arc's rules and
/// its type-the-name confirmation, and "Delete unused Profiles". F1's `SettingsHost` mounts it in its Profiles slot:
/// `ProfilesPane(settings: snapshot, dispatch: model.dispatch)`.
///
/// Every control dispatches a command (`.profile(...)` or `.settings(.profile(...))`); the only local state is what
/// is being typed and which confirmation is open. Copy and the delete and name rules are `ProfileCopy`'s, so the pane,
/// the dialogs and the reducer agree.
struct ProfilesPane: View {
    let settings: SettingsSnapshot
    let dispatch: Dispatch

    @State private var newName = ""
    @State private var renames: [ProfileID: String] = [:]
    @State private var deleting: ProfileRow?
    @State private var typedName = ""
    @State private var deletingUnused = false

    init(settings: SettingsSnapshot, dispatch: @escaping Dispatch) {
        self.settings = settings
        self.dispatch = dispatch
    }

    private var names: [String] { settings.profiles.map(\.profile.name) }
    private var unused: [ProfileRow] { settings.profiles.map(\.profile).filter { ProfileCopy.deleteRefusal($0) == nil } }

    var body: some View {
        Form {
            Section {
                Text(ProfileCopy.paneIntro).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    TextField(ProfileCopy.namePrompt, text: $newName, prompt: Text(ProfileCopy.namePlaceholder))
                        .onSubmit(create)
                        .accessibilityIdentifier(ViewID.settingsField("newProfileName").identifier)
                    Button(ProfileCopy.createButton, action: create)
                        .disabled(!ProfileCopy.acceptsName(newName, among: names))
                        .accessibilityIdentifier(ViewID.settingsField("createProfile").identifier)
                }
                if ProfileCopy.isTaken(newName, among: names) { Text(ProfileCopy.nameTaken).foregroundStyle(.red) }
            }
            ForEach(settings.profiles, id: \.profile.id) { row in
                Section { profileSection(row) } header: {
                    HStack { ProfilePaneGlyph(icon: row.profile.icon); Text(row.profile.name) }
                }
            }
            Section {
                Button(ProfileCopy.deleteUnusedTitle) { deletingUnused = true }
                    .disabled(unused.isEmpty)
                    .accessibilityIdentifier(ViewID.settingsField("deleteUnusedProfiles").identifier)
            }
        }
        .alert(ProfileCopy.deleteTitle, isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            TextField(ProfileCopy.deleteTypePrompt, text: $typedName)
            Button(ProfileCopy.deleteButton, role: .destructive) {
                if let row = deleting, ProfileCopy.trimmed(typedName) == row.name { dispatch(.profile(.delete(row.id))) }
                deleting = nil
            }
            Button(ProfileCopy.cancel, role: .cancel) { deleting = nil }
        } message: {
            Text("\(ProfileCopy.deleteWarning(deleting?.name ?? ""))\n\n\(ProfileCopy.deleteTypePrompt)")
        }
        .alert(ProfileCopy.deleteUnusedTitle, isPresented: $deletingUnused) {
            Button(ProfileCopy.deleteButton, role: .destructive) {
                for row in unused { dispatch(.profile(.delete(row.id))) }
            }
            Button(ProfileCopy.cancel, role: .cancel) {}
        } message: {
            Text("\(ProfileCopy.deleteUnusedWarning)\n\n\(ProfileCopy.deleteUnusedList)\(unused.map(\.name).joined(separator: ", "))")
        }
    }

    @ViewBuilder
    private func profileSection(_ row: ProfileSettingsRow) -> some View {
        let id = row.profile.id, others = settings.profiles.filter { $0.profile.id != id }.map(\.profile.name)
        let draft = renames[id] ?? row.profile.name
        TextField(ProfileCopy.renameTitle, text: Binding(get: { draft }, set: { renames[id] = $0 }))
            .onSubmit {
                if ProfileCopy.acceptsName(draft, among: others) { dispatch(.profile(.rename(id, name: draft))) }
                renames[id] = nil
            }
            .help(ProfileCopy.renameNote)
            .accessibilityIdentifier(ViewID.settingsField("profileName-\(id)").identifier)
        if ProfileCopy.isTaken(draft, among: others) { Text(ProfileCopy.nameTaken).foregroundStyle(.red) }
        Text(ProfileCopy.spaceCount(row.profile.spaceTitles)).foregroundStyle(.secondary)
        Picker(SettingsCopy.searchEngine, selection: Binding(get: { row.settings.searchEngine },
                                                            set: { dispatch(.settings(.profile(id, .searchEngine($0)))) })) {
            ForEach(settings.engines, id: \.id) { Text($0.name).tag($0.id) }
        }
        .accessibilityIdentifier(ViewID.settingsField("searchEngine-\(id)").identifier)
        Toggle(SettingsCopy.searchSuggestions, isOn: Binding(get: { row.settings.searchSuggestions },
                                                            set: { dispatch(.settings(.profile(id, .searchSuggestions($0)))) }))
            .accessibilityIdentifier(ViewID.settingsField("searchSuggestions-\(id)").identifier)
        Picker(SettingsCopy.autoArchive, selection: Binding(get: { row.settings.autoArchive },
                                                           set: { dispatch(.settings(.profile(id, .autoArchive($0)))) })) {
            ForEach(AutoArchiveThreshold.allCases, id: \.self) { Text(SettingsCopy.threshold($0)).tag($0) }
        }
        .accessibilityIdentifier(ViewID.settingsField("autoArchive-\(id)").identifier)
        LabeledContent(ProfilesPaneCopy.downloadLocation) {
            HStack {
                Text(row.settings.downloadsDirectory.map { ($0 as NSString).abbreviatingWithTildeInPath } ?? ProfilesPaneCopy.downloadsFolder)
                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                Button(ProfilesPaneCopy.chooseFolder) { chooseDownloads(for: id) }
                if row.settings.downloadsDirectory != nil {
                    Button(ProfilesPaneCopy.useDownloads) { dispatch(.settings(.profile(id, .downloadsDirectory(nil)))) }
                }
            }
        }
        .accessibilityIdentifier(ViewID.settingsField("downloadsDirectory-\(id)").identifier)
        Toggle(SettingsCopy.promptForDownloadLocation, isOn: Binding(get: { row.settings.promptForDownloadLocation },
                                                                    set: { dispatch(.settings(.profile(id, .promptForDownloadLocation($0)))) }))
            .accessibilityIdentifier(ViewID.settingsField("promptForDownloadLocation-\(id)").identifier)
        let refusal = ProfileCopy.deleteRefusal(row.profile)
        Button(ProfileCopy.deleteTitle, role: .destructive) {
            typedName = ""
            deleting = row.profile
        }
        .disabled(refusal != nil)
        .help(refusal ?? ProfileCopy.deleteWarning(row.profile.name))
        .accessibilityIdentifier(ViewID.settingsField("deleteProfile-\(id)").identifier)
        if let refusal { Text(refusal).font(.caption).foregroundStyle(.secondary) }
    }

    private func create() {
        guard ProfileCopy.acceptsName(newName, among: names) else { return }
        dispatch(.profile(.create(name: ProfileCopy.trimmed(newName), icon: nil)))
        newName = ""
    }

    /// Arc's "Download Location" choices are the Downloads folder, a chosen folder ("Button to confirm selection of
    /// directory for file downloads"), or asking each time (the toggle below).
    private func chooseDownloads(for id: ProfileID) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = ProfilesPaneCopy.chooseFolderPrompt
        guard panel.runModal() == .OK, let url = panel.url else { return }
        dispatch(.settings(.profile(id, .downloadsDirectory(url.path))))
    }
}

/// The pane's labels that are not `ProfileCopy` or `SettingsCopy`: Arc's "Download Location" (observed) and the
/// choices around it (ours: Arc's tags `arc.folder`, `arc.other` carry no visible text).
enum ProfilesPaneCopy {
    static let downloadLocation = "Download Location"
    static let downloadsFolder = "Downloads"
    static let chooseFolder = "Choose…"
    static let chooseFolderPrompt = "Select"
    static let useDownloads = "Use Downloads"
}

/// A profile's icon in a section header: its emoji, named icon or symbol; a person glyph without one.
struct ProfilePaneGlyph: View {
    let icon: CustomIcon?

    var body: some View {
        switch icon {
        case nil: Image(systemName: "person.crop.circle")
        case .emoji(let emoji)?: Text(emoji)
        case .named(let name)?: Image(systemName: Self.symbol(name))
        case .symbol(let symbol)?: Image(systemName: symbol)
        }
    }

    /// The same SF Symbols the sidebar and the dialogs draw for Arc's named icons.
    static func symbol(_ icon: NamedIcon) -> String {
        switch icon {
        case .star: "star.fill"
        case .bookmark: "bookmark.fill"
        case .heart: "heart.fill"
        case .flag: "flag.fill"
        case .folder: "folder.fill"
        case .calendar: "calendar"
        case .mail: "envelope.fill"
        case .terminal: "terminal.fill"
        case .egg: "oval.portrait.fill"
        case .home: "house.fill"
        case .briefcase: "briefcase.fill"
        case .book: "book.fill"
        case .camera: "camera.fill"
        case .music: "music.note"
        case .globe: "globe"
        case .code: "chevron.left.forwardslash.chevron.right"
        }
    }
}
