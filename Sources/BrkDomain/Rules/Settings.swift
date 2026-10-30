import BrkBase
import Foundation

// Owner: F1. The settings window and every settings field. Each setter writes one field of `Doc.settings` (or one
// `KeyOverride`); the window itself is `Session.settingsPane`. Values are clamped or ignored, never trapped: an
// unknown profile or action is a no-op (totality).

extension Work {
    mutating func settings(_ command: SettingsCommand, in window: WindowID) {
        switch command {
        case .autoArchive(let threshold):
            // The archive page's picker: the current space's profile ("Archive tabs after").
            guard let profile = state.doc.windows[window].flatMap({ state.doc.spaces[$0.space] })?.profile else { return }
            setProfileSetting(profile) { $0.autoArchive = threshold }
        case .general(let setting):
            switch setting {
            case .warnBeforeQuitting(let on): state.doc.settings.general.warnBeforeQuitting = on
            case .dismissDefaultBrowserPrompt: state.doc.settings.general.defaultBrowserPromptDismissed = true
            case .webAppearance(let appearance): state.doc.settings.general.webAppearance = appearance
            }
        case .profile(let profile, let setting):
            guard state.doc.profiles[profile] != nil else { return }
            setProfileSetting(profile) { s in
                switch setting {
                case .searchEngine(let engine): if SearchEngine.builtIn(engine) != nil { s.searchEngine = engine }
                case .searchSuggestions(let on): s.searchSuggestions = on
                case .autoArchive(let threshold): s.autoArchive = threshold
                case .downloadsDirectory(let path): s.downloadsDirectory = path.flatMap { $0.isEmpty ? nil : $0 }
                case .promptForDownloadLocation(let on): s.promptForDownloadLocation = on
                }
            }
        case .links(let setting):
            switch setting {
            case .externalLinksInLittleArc(let on): state.doc.settings.links.externalLinksInLittleArc = on
            case .optionCommandClickLittleArc(let on): state.doc.settings.links.optionCommandClickLittleArc = on
            case .shiftClickPeek(let on): state.doc.settings.links.shiftClickPeek = on
            case .peekFromPinnedAndFavorites(let on): state.doc.settings.links.peekFromPinnedAndFavorites = on
            case .littleArcAutoArchive(let threshold): state.doc.settings.links.littleArcAutoArchive = threshold
            case .defaultRoute(let destination):
                if case .space(let id)? = destination, state.doc.spaces[id] == nil { return }
                state.doc.settings.links.defaultRoute = destination
            case .addRoute(let route):
                // F3: the pattern is normalized to the host glob `LinkRoute.matches` compares (`normalizedPattern`); an
                // unusable pattern or a destination naming a missing space is refused (`AppState.validRoute`).
                guard !state.doc.linkRoutes.contains(where: { $0.id == route.id }), let valid = state.validRoute(route) else { return }
                state.doc.linkRoutes.append(valid)
            case .updateRoute(let route):
                guard let index = state.doc.linkRoutes.firstIndex(where: { $0.id == route.id }), let valid = state.validRoute(route) else { return }
                if state.doc.linkRoutes[index] != valid { state.doc.linkRoutes[index] = valid }
            case .removeRoute(let id):
                state.doc.linkRoutes.removeAll { $0.id == id }
            case .moveRoute(let id, let index):
                guard let from = state.doc.linkRoutes.firstIndex(where: { $0.id == id }) else { return }
                let route = state.doc.linkRoutes.remove(at: from)
                state.doc.linkRoutes.insert(route, at: min(max(index, 0), state.doc.linkRoutes.count))
            }
        case .shortcuts(let setting):
            // TODO(F4): refuse chords AppKit reserves (Cmd+Q is fine; Cmd+Tab is the system's) and report conflicts
            // through `SettingsSnapshot.shortcuts` (they are a state, never a refusal).
            switch setting {
            case .setChord(let action, let chord):
                var override = state.doc.keyOverrides[action] ?? KeyOverride(chord: action.spec.bindings.first?.chord, priority: nil)
                override.chord = chord
                state.doc.keyOverrides[action] = override
            case .setPriority(let action, let priority):
                var override = state.doc.keyOverrides[action] ?? KeyOverride(chord: action.spec.bindings.first?.chord, priority: nil)
                override.priority = priority
                state.doc.keyOverrides[action] = override
            case .reset(let action):
                state.doc.keyOverrides[action] = nil
            case .resetAll:
                if !state.doc.keyOverrides.isEmpty { state.doc.keyOverrides = [:] }
            }
        case .max(let setting):
            switch setting {
            case .provider(let choice): state.doc.settings.max.provider = choice
            case .renamePinnedTabs(let on): state.doc.settings.max.renamePinnedTabs = on
            case .tidyTabs(let on): state.doc.settings.max.tidyTabs = on
            }
        case .advanced(let setting):
            switch setting {
            case .restoreWindowsOnLaunch(let on): state.doc.settings.advanced.restoreWindowsOnLaunch = on
            case .soundEffects(let on): state.doc.settings.advanced.soundEffects = on
            case .hapticsOnReorder(let on): state.doc.settings.advanced.hapticsOnReorder = on
            case .showFullURLInToolbar(let on): state.doc.settings.advanced.showFullURLInToolbar = on
            case .windowDraggingFromPages(let on): state.doc.settings.advanced.windowDraggingFromPages = on
            case .autoPictureInPicture(let on): state.doc.settings.advanced.autoPictureInPicture = on
            case .themeToCSS(let on): state.doc.settings.advanced.themeToCSS = on
            case .boostsEnabled(let on): state.doc.settings.advanced.boostsEnabled = on
            case .sharedQuotes(let on): state.doc.settings.advanced.sharedQuotes = on
            }
        case .openPane(let pane):
            // One settings window, app-wide; opening another pane switches it. TODO(F1): the host window.
            if state.session.settingsPane != pane { state.session.settingsPane = pane }
        case .closeWindow:
            if state.session.settingsPane != nil { state.session.settingsPane = nil }
        }
    }

    /// Writes one profile's settings record, creating it from the defaults when the profile has none.
    mutating func setProfileSetting(_ profile: ProfileID, _ change: (inout ProfileSettings) -> Void) {
        var settings = state.doc.settings.profiles[profile] ?? .default
        change(&settings)
        if state.doc.settings.profiles[profile] != settings { state.doc.settings.profiles[profile] = settings }
    }
}

extension AppState {
    /// A profile's settings record, else the defaults (normalize keeps a record for every profile).
    func profileSettings(_ profile: ProfileID) -> ProfileSettings { doc.settings.profiles[profile] ?? .default }

    /// The settings of the current space's profile in a window.
    func profileSettings(in window: WindowID) -> ProfileSettings {
        doc.windows[window].flatMap { doc.spaces[$0.space] }.map { profileSettings($0.profile) } ?? .default
    }

    /// The default search engine of the current space's profile in a window.
    func searchEngine(in window: WindowID) -> SearchEngine {
        SearchEngine.builtIn(profileSettings(in: window).searchEngine) ?? .google
    }
}
