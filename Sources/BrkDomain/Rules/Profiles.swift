import BrkBase
import Foundation

// Owner: F2. Profiles: records in `Doc.profiles`, one Favorites root and one settings record per profile, a space's
// profile assignment, and the dialogs. First-pass bodies; F2 replaces them with Arc's rules and copy
// (visual-and-copy.md "Profiles": "Only Profiles not assigned to any Spaces can be deleted.", "The Default Profile
// cannot be deleted.", "A Profile with that name already exists.").

extension Work {
    mutating func profiles(_ command: ProfileCommand, in window: WindowID) {
        switch command {
        case .create(let name, let icon):
            // A new profile with its own Favorites root and default settings. A blank or duplicate name is refused.
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !state.doc.profiles.values.contains(where: { $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
            let id = ProfileID(ctx.newID()), favorites = ItemID(ctx.newID())
            guard state.doc.tree.makeRoot(favorites, .favorites(id), createdAt: ctx.now) else { return }
            state.doc.profiles[id] = Profile(id: id, name: trimmed, icon: icon)
            state.doc.favorites[id] = favorites
            state.doc.settings.profiles[id] = .default
            if state.session.windows[window]?.profileDialog != nil { state.session.windows[window]!.profileDialog = nil }
        case .rename(let id, let name):
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard var profile = state.doc.profiles[id], !trimmed.isEmpty else { return }
            guard !state.doc.profiles.values.contains(where: { $0.id != id && $0.name.caseInsensitiveCompare(trimmed) == .orderedSame }) else { return }
            profile.name = trimmed
            state.doc.profiles[id] = profile
        case .delete(let id):
            // Refused for the default profile and for a profile some space uses. Its Favorites are archived
            // (reason containerDeleted) and the engine forgets its browsing data.
            guard id != .default, state.doc.profiles[id] != nil, !state.doc.spaces.values.contains(where: { $0.profile == id }) else { return }
            if let root = state.doc.favorites[id] {
                archiveTabs(state.doc.tree[root]?.children ?? [], reason: .containerDeleted)
                for (tab, _) in state.doc.tree.removeRoot(root) ?? [] { unload(tab) }
            }
            state.doc.favorites[id] = nil
            state.doc.settings.profiles[id] = nil
            state.doc.profiles[id] = nil
            effects.append(.forgetBrowsingData(.profile(id)))
            if state.session.windows[window]?.profileDialog != nil { state.session.windows[window]!.profileDialog = nil }
        case .assign(let ref, let profile):
            // "Change Profile": the space's Favorites, settings and new pages follow the profile; loaded pages keep
            // their context until unloaded (Arc behaves the same). TODO(F2): unload the space's pages so they reopen
            // in the new context, as Arc's dialog warns ("you might get logged out of some websites").
            guard state.doc.profiles[profile] != nil else { return }
            let space: SpaceID? = switch ref {
            case .current: state.doc.windows[window]?.space
            case .space(let id): id
            }
            guard let space, state.doc.spaces[space] != nil else { return }
            if state.doc.spaces[space]!.profile != profile { state.doc.spaces[space]!.profile = profile }
            if state.session.windows[window]?.profileDialog != nil { state.session.windows[window]!.profileDialog = nil }
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
}
