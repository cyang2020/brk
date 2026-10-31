import BrkBase
import Foundation

// Owner: F2. Profiles: records in `Doc.profiles`, one Favorites root and one settings record per profile, a space's
// profile assignment, and the dialogs. Arc's rules and copy (visual-and-copy.md "Profiles"): "Only Profiles not
// assigned to any Spaces can be deleted.", "The Default Profile cannot be deleted.", "A Profile with that name
// already exists."

extension Work {
    /// The settings confirmation submits a data request; deletion is a different command and effect.
    mutating func clearProfileData(_ profile: ProfileID, kinds: Set<SiteDataKind>) {
        guard state.doc.profiles[profile] != nil, !kinds.isEmpty,
              state.session.sites.profileClears[profile] == nil else { return }
        let request = ClearProfileData(id: ctx.newID(), profile: profile, kinds: kinds)
        state.session.sites.profileClears[profile] = request
        state.session.sites.profileResults[profile] = nil
        effects.append(.clearProfileData(request))
    }

    mutating func profileDataCleared(_ result: ClearProfileDataResult) {
        let request = result.request
        guard state.session.sites.profileClears[request.profile] == request else { return }
        state.session.sites.profileClears[request.profile] = nil
        guard state.doc.profiles[request.profile] != nil else { return }
        if result.completed.contains(.history) { state.doc.history.removeAll { $0.profile == request.profile } }
        state.session.sites.profileResults[request.profile] = result
    }

    mutating func profiles(_ command: ProfileCommand, in window: WindowID) {
        switch command {
        case .create(let name, let icon):
            // A new profile with its own Favorites root and default settings. A blank or duplicate name is refused
            // (the dialog stays open and says why: `ProfileCopy.isTaken`).
            guard ProfileCopy.acceptsName(name, among: state.doc.profiles.values.map(\.name)) else { return }
            let id = ProfileID(ctx.newID()), favorites = ItemID(ctx.newID())
            guard state.doc.tree.makeRoot(favorites, .favorites(id), createdAt: ctx.now) else { return }
            state.doc.profiles[id] = Profile(id: id, name: ProfileCopy.trimmed(name), icon: icon)
            state.doc.favorites[id] = favorites
            state.doc.settings.profiles[id] = .default
            closeProfileDialog(in: window)
        case .rename(let id, let name):
            guard var profile = state.doc.profiles[id],
                  ProfileCopy.acceptsName(name, among: state.doc.profiles.values.filter { $0.id != id }.map(\.name)) else { return }
            profile.name = ProfileCopy.trimmed(name)
            state.doc.profiles[id] = profile
        case .delete(let id):
            if let pending = state.doc.deletingProfiles[id], pending.failure != nil {
                let disposal = DisposalID(ctx.newID())
                state.doc.deletingProfiles[id] = ProfileDeletion(id: disposal, name: pending.name)
                effects.append(.disposeContext(ContextDisposal(id: disposal, context: .profile(id))))
                return
            }
            // Refused for the default profile and for a profile some space uses (the dialog's `deleteRefusal`). Its
            // Favorites are archived (reason containerDeleted), its history and downloads entries go, and the engine
            // forgets its browsing data (the Chromium directory goes at the next launch).
            guard let profile = state.doc.profiles[id], ProfileCopy.deleteRefusal(state.profileRow(profile)) == nil else { return }
            if let root = state.doc.favorites[id] {
                archiveTabs(state.doc.tree[root]?.children ?? [], reason: .containerDeleted)
                for (tab, _) in state.doc.tree.removeRoot(root) ?? [] { unload(tab) }
            }
            state.doc.favorites[id] = nil
            state.doc.settings.profiles[id] = nil
            state.doc.profiles[id] = nil
            if state.doc.history.contains(where: { $0.profile == id }) { state.doc.history.removeAll { $0.profile == id } }
            if state.doc.downloads.contains(where: { $0.profile == id }) { state.doc.downloads.removeAll { $0.profile == id } }
            let disposal = DisposalID(ctx.newID())
            state.doc.deletingProfiles[id] = ProfileDeletion(id: disposal, name: profile.name)
            effects.append(.disposeContext(ContextDisposal(id: disposal, context: .profile(id))))
            closeProfileDialog(in: window)
        case .assign(let ref, let profile):
            // "Change Profile": the space's Favorites, settings and new pages follow the profile. Every loaded tab
            // whose browsing context this changes is unloaded: off-screen ones reopen in the new context when
            // focused; on-screen ones stay loaded (normalize) and the engine replaces their page, because a page's
            // context is fixed at creation and its spec now names another one (Arc's dialog warns: "you might get
            // logged out of some websites").
            guard state.doc.profiles[profile] != nil else { return }
            let space: SpaceID? = switch ref {
            case .current: state.doc.windows[window]?.space
            case .space(let id): id
            }
            guard let space, let old = state.doc.spaces[space]?.profile else { return }
            if old != profile {
                let before = state.session.loaded.map { ($0, state.browsingContext(of: $0.item)) }
                state.doc.spaces[space]!.profile = profile
                for (tab, context) in before where state.browsingContext(of: tab.item) != context { unload(tab) }
            }
            closeProfileDialog(in: window)
        case .openDialog(let request):
            let dialog: ProfileDialog?
            switch request {
            case nil: dialog = nil
            case .create?: dialog = .create
            case .change(.current)?: dialog = state.doc.windows[window].map { .change($0.space) }
            case .change(.space(let id))?:
                guard state.doc.spaces[id] != nil else { return }
                dialog = .change(id)
            case .delete(let id)?:
                guard state.doc.profiles[id] != nil else { return }
                dialog = .delete(id)
            }
            if state.session.windows[window]?.profileDialog != dialog { state.session.windows[window]!.profileDialog = dialog }
        }
    }

    private mutating func closeProfileDialog(in window: WindowID) {
        if state.session.windows[window]?.profileDialog != nil { state.session.windows[window]!.profileDialog = nil }
    }
}

extension AppState {
    public var pendingContextDisposals: [ContextDisposal] {
        doc.deletingProfiles.map { ContextDisposal(id: $0.value.id, context: .profile($0.key)) }
    }

    /// A profile as the dialogs and the Profiles pane list it.
    func profileRow(_ profile: Profile) -> ProfileRow {
        ProfileRow(id: profile.id, name: profile.name, icon: profile.icon,
                   spaceTitles: doc.spaceOrder.filter { doc.spaces[$0]?.profile == profile.id }.map(displayTitle(of:)),
                   isDefault: profile.id == .default)
    }
}

/// Arc's ProfilesUI copy (visual-and-copy.md "Profiles"; the strings around `ProfilesUI/ProfileDialogUtils.swift`,
/// `SpaceCreationView.swift` and the Profiles preferences pane in Arc 1.170's binary), and the two rules the dialogs,
/// the Profiles pane and the reducer share: which name is acceptable, which profile can be deleted. One place, so
/// the dialog (BrkOverlays), the pane (BrkSettings) and `ProfileCommand` never disagree. Button labels Arc's binary
/// only describes ("Action button in the Create a Profile dialog for creating a profile") are ours.
public enum ProfileCopy {
    /// Menu rows (nib:393, nib:84).
    public static let newProfile = "New Profile"
    public static let changeProfile = "Change Profile"
    /// The URL pill's badge for an incognito window (Arc: `BrowserWindow.isIncognito`).
    public static let incognito = "Incognito"

    // Create a Profile (`ProfileCreationSheetWindow`).
    public static let createTitle = "Create a new Profile"
    public static let createExplanation = "Profiles make your Spaces truly separate with their own history, saved passwords, extensions, and other browsing data. No more flipping between work and personal accounts!"
    public static let namePrompt = "What do you want to call this Profile?"
    public static let namePlaceholder = "Profile Name"
    public static let nameTaken = "A Profile with that name already exists."
    public static let createButton = "Create Profile"

    // Change the space's profile (`ProfileChangeSheetWindow`).
    public static let changeTitle = "Edit Space profile"
    public static let changeExplanation = "Each Profile has different browser data, so you might get logged out of some websites, see different Favorites up top, or need to re-install extensions."
    public static let spaceExplanation = "You can use a Profile to give\nthis Space its own logins,\nhistory, and browsing data."
    public static let changeButton = "Change Profile"
    public static let createFromChange = "New Profile…"

    // Delete a profile.
    public static let deleteTitle = "Delete this Profile"
    public static let deleteTypePrompt = "To continue, please type the name of this Profile:"
    public static let cannotBeUndone = "This action cannot be undone."
    public static let deleteButton = "Delete Profile"
    public static let onlyUnassigned = "Only Profiles not assigned to any Spaces can be deleted."
    public static let defaultCannotBeDeleted = "The Default Profile cannot be deleted."

    // Delete unused Profiles.
    public static let deleteUnusedTitle = "Delete unused Profiles"
    public static let deleteUnusedWarning = "Deleting unused Profiles will permanently remove any cookies, history, preferences, and logins that belong to those Profiles."
    public static let deleteUnusedList = "The unused Profiles to be deleted are: "

    // Rename (the Profiles pane).
    public static let renameTitle = "Rename your Profile"
    public static let renameNote = "This won’t affect the names of any of the Spaces associated with this Profile."

    // The Profiles pane.
    public static let paneIntro = "Profiles help keep your data separate across Spaces — like history, logins, cookies, and extensions. You can use any Profile across one or more Spaces."

    public static let cancel = "Cancel"

    /// "Deleting “Work” will permanently remove …" (Arc keeps the name in front of the observed tail).
    public static func deleteWarning(_ name: String) -> String {
        "Deleting “\(name)” will permanently remove any cookies, history, preferences, and logins that belong to this Profile."
    }

    /// Arc's pane says how many spaces use a profile; its three strings were not recovered, so these are ours.
    public static func spaceCount(_ titles: [String]) -> String {
        switch titles.count {
        case 0: "Not used by any Spaces"
        case 1: "Used by \(titles[0])"
        default: "Used by \(titles.count) Spaces: \(titles.joined(separator: ", "))"
        }
    }

    /// The name a profile is stored under.
    public static func trimmed(_ name: String) -> String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// A name can name a profile when, trimmed, it is not blank and not taken. A blank name has no message (the
    /// button is disabled); a taken one shows `nameTaken`.
    public static func acceptsName(_ name: String, among existing: [String]) -> Bool {
        !trimmed(name).isEmpty && !isTaken(name, among: existing)
    }

    /// Another profile already has this name, compared trimmed and case-insensitively.
    public static func isTaken(_ name: String, among existing: [String]) -> Bool {
        let name = trimmed(name)
        return existing.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
    }

    /// Why the profile cannot be deleted, or nil when it can: the default profile never; a profile with spaces
    /// only once none uses it.
    public static func deleteRefusal(_ row: ProfileRow) -> String? {
        if row.isDefault { return defaultCannotBeDeleted }
        return row.spaceTitles.isEmpty ? nil : onlyUnassigned
    }
}
