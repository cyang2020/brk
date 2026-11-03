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
            case .appIcon(let icon): state.doc.settings.general.appIcon = icon == .original ? nil : icon
            case .javaScriptFromAppleEvents(let on): state.doc.settings.general.javaScriptFromAppleEvents = on ? true : nil
            case .toggleJavaScriptFromAppleEvents:
                state.doc.settings.general.javaScriptFromAppleEvents = state.doc.settings.general.javaScriptFromAppleEvents == true ? nil : true
            }
        case .profile(let profile, let setting):
            guard state.doc.profiles[profile] != nil else { return }
            let newSearchID = SearchEngineID("site-" + ctx.newID())
            setProfileSetting(profile) { s in
                switch setting {
                case .addSiteSearch(let name, let keyword, let template):
                    let engine = SearchEngine(id: newSearchID, name: name.trimmingCharacters(in: .whitespacesAndNewlines), keyword: keyword.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), template: template.trimmingCharacters(in: .whitespacesAndNewlines), suggestTemplate: nil)
                    guard engine.isValidSiteSearch, !(SearchEngine.builtIn + (s.siteSearchEngines ?? [])).contains(where: { $0.keyword == engine.keyword }) else { return }
                    s.siteSearchEngines = (s.siteSearchEngines ?? []) + [engine]
                case .removeSiteSearch(let id):
                    s.siteSearchEngines?.removeAll { $0.id == id }
                    if s.searchEngine == id { s.searchEngine = SearchEngine.google.id }
                case .searchEngine(let engine): if (SearchEngine.builtIn + (s.siteSearchEngines ?? [])).contains(where: { $0.id == engine }) { s.searchEngine = engine }
                case .searchSuggestions(let on): s.searchSuggestions = on
                case .autoArchive(let threshold): s.autoArchive = threshold
                case .downloadsDirectory(let path):
                    // An absolute folder path, standardized ("/a/b/../c/" is "/a/c"); empty is the system Downloads
                    // folder; a relative or "~" path is refused (the reducer does not know the home directory).
                    let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if trimmed.isEmpty { s.downloadsDirectory = nil }
                    else if trimmed.hasPrefix("/") { s.downloadsDirectory = URL(fileURLWithPath: trimmed, isDirectory: true).standardized.path }
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
            case .globalLittleArcShortcut(let on): state.doc.settings.links.globalLittleArcShortcut = on ? nil : false
            case .defaultRoute(let destination):
                if case .space(let id)? = destination, state.doc.spaces[id] == nil { return }
                // nil and `.mostRecentSpace` say the same; the saved value has one spelling.
                state.doc.settings.links.defaultRoute = destination == .mostRecentSpace ? nil : destination
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
            case .feature(let feature, let on):
                if state.doc.settings.max.features == nil { state.doc.settings.max.features = [:] }
                state.doc.settings.max.features?[feature] = on
            case .resetTranslationExclusions: state.doc.settings.max.translationExclusions = nil
            case .provider(let choice): state.doc.settings.max.provider = choice
            case .renamePinnedTabs(let on): state.doc.settings.max.renamePinnedTabs = on
            case .tidyTabs(let on): state.doc.settings.max.tidyTabs = on
            case .autoEnableFutureFeatures(let on): state.doc.settings.max.autoEnableFutureFeatures = on ? true : nil
            case .enable(let on):
                var max = state.doc.settings.max
                if on {
                    if max.provider == .off { max.provider = .auto }
                    // Tidy Tab Titles and Tidy Tabs are plain switches: on only the first time Max is turned on.
                    if max.features == nil { max.renamePinnedTabs = true; max.tidyTabs = true }
                    var features = max.features ?? [:]
                    for feature in AIFeature.allCases where features[feature] == nil { features[feature] = true }
                    max.features = features
                } else {
                    max.provider = .off
                }
                if state.doc.settings.max != max { state.doc.settings.max = max }
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
            // One settings window, app-wide (BrkApp's SettingsWindowController follows this pane); opening another
            // pane switches it. Session state: the window is closed after a restart.
            if state.session.settingsPane != pane { state.session.settingsPane = pane }
            effects.append(.app(.showSettings))
        case .closeWindow:
            if state.session.settingsPane != nil { state.session.settingsPane = nil }
        case .openBrowserPage(let page, let profile):
            // A standard window's space of that profile: the one it shows, else the first in dock order. An
            // incognito window or a profile no space uses has nowhere to open the page.
            guard let shown = state.doc.windows[window], shown.kind == .standard else { effects.append(.app(.beep)); return }
            let wanted = profile ?? state.doc.spaces[shown.space]?.profile
            let space = state.doc.spaces[shown.space]?.profile == wanted ? shown.space
                : state.doc.spaceOrder.first { state.doc.spaces[$0]?.profile == wanted }
            guard let space else { effects.append(.app(.beep)); return }
            showSpace(space, in: window)
            openTab(page.url, inSpace: space, window: window, focus: true)
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
        let settings = profileSettings(in: window)
        return (SearchEngine.builtIn + (settings.siteSearchEngines ?? [])).first { $0.id == settings.searchEngine } ?? .google
    }
}
