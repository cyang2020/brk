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
/// `ProfilesPane(context:)`.
///
/// Every control dispatches a command (`.profile(...)` or `.settings(.profile(...))`); the only local state is what
/// is being typed and which confirmation is open. Copy and the delete and name rules are `ProfileCopy`'s, so the pane,
/// the dialogs and the reducer agree.
struct ProfilesPane: View {
    let context: PaneContext
    private var settings: SettingsSnapshot { context.settings }
    private var dispatch: Dispatch { context.dispatch }

    @State private var newName = ""
    @State private var renames: [ProfileID: String] = [:]
    @State private var deleting: ProfileRow?
    @State private var typedName = ""
    @State private var deletingUnused = false

    private var names: [String] { settings.profiles.map(\.profile.name) }
    private var unused: [ProfileRow] { settings.profiles.map(\.profile).filter { ProfileCopy.deleteRefusal($0) == nil } }

    var body: some View {
        Form {
            Section {
                Text(ProfileCopy.paneIntro).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    SettingsTextField(field: "newProfileName", text: newName, placeholder: ProfileCopy.namePlaceholder,
                                      edit: { newName = $0 }, submit: create) { newName = $0 }
                    SettingsButton(title: ProfileCopy.createButton, field: "createProfile") { create(newName) }
                        .disabled(!ProfileCopy.acceptsName(newName, among: names))
                }
                if ProfileCopy.isTaken(newName, among: names) { Text(ProfileCopy.nameTaken).foregroundStyle(.red) }
            }
            ForEach(settings.profiles, id: \.profile.id) { row in
                Section { profileSection(row) } header: {
                    HStack { ProfilePaneGlyph(icon: row.profile.icon); Text(row.profile.name) }
                }
            }
            ForEach(settings.deletingProfiles, id: \.profile) { pending in
                Section(pending.name) {
                    if let failure = pending.failure {
                        Text("Profile deletion could not finish: " + failure)
                        Button("Retry deletion") { dispatch(.profile(.delete(pending.profile))) }
                    } else { Text("Stopping this profile's browsers and downloads…") }
                }
            }
            Section {
                SettingsButton(title: ProfileCopy.deleteUnusedTitle, field: "deleteUnusedProfiles") { deletingUnused = true }
                    .disabled(unused.isEmpty)
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
        SettingsTextField(field: "profileName-\(id)", text: row.profile.name, placeholder: ProfileCopy.renameTitle,
                          edit: { renames[id] = $0 }) { name in
            if ProfileCopy.acceptsName(name, among: others) {
                dispatch(.profile(.rename(id, name: name)))
                renames[id] = nil
            }
        }
            .help(ProfileCopy.renameNote)
        if ProfileCopy.isTaken(renames[id] ?? row.profile.name, among: others) { Text(ProfileCopy.nameTaken).foregroundStyle(.red) }
        Text(ProfileCopy.spaceCount(row.profile.spaceTitles)).foregroundStyle(.secondary)
        ProfileSettingsForm(context: context, row: row)
        let refusal = ProfileCopy.deleteRefusal(row.profile)
        SettingsButton(title: ProfileCopy.deleteTitle, field: "deleteProfile-\(id)") {
            typedName = ""
            deleting = row.profile
        }
        .disabled(refusal != nil)
        .help(refusal ?? ProfileCopy.deleteWarning(row.profile.name))
        if let refusal { Text(refusal).font(.caption).foregroundStyle(.secondary) }
    }

    private func create(_ name: String) {
        guard ProfileCopy.acceptsName(name, among: names) else { return }
        dispatch(.profile(.create(name: ProfileCopy.trimmed(name), icon: nil)))
        newName = ""
    }
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
        icon.systemSymbolName
    }
}
