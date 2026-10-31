import BrkBase
import Foundation

extension AppState {
    func siteTarget(in window: WindowID, allowLoading: Bool = false) -> SiteTarget? {
        guard let item = resolveTab(.focused, in: window) else { return nil }
        let page = PageID(window: window, item: item)
        guard session.loaded.contains(page), let live = session.live[page], live.requestedURL == nil else { return nil }
        let document: DocumentToken
        switch live.document {
        case .ready(let value): document = value
        case .loading(let value) where allowLoading: document = value
        default: return nil
        }
        guard let url = address(of: item, in: window, for: .savedDocument), let origin = SiteOrigin(url) else { return nil }
        return SiteTarget(document: document, context: browsingContext(of: item), origin: origin)
    }

    func validSiteTarget(_ target: SiteTarget, allowLoading: Bool = false) -> Bool {
        let document = session.live[target.page]?.document
        return owns(target.page) && session.loaded.contains(target.page) && session.live[target.page]?.requestedURL == nil
            && (document == .ready(target.document) || (allowLoading && document == .loading(target.document)))
            && browsingContext(of: target.page.item) == target.context
            && address(of: target.page.item, in: target.page.window, for: .savedDocument).flatMap(SiteOrigin.init) == target.origin
    }

    func sitePreferences(_ context: BrowsingContext) -> SitePreferences {
        switch context {
        case .profile(let id): doc.sitePreferences[id] ?? SitePreferences()
        case .incognito(let id): session.sites.privatePreferences[id] ?? SitePreferences()
        }
    }

    func websitePolicy(for page: PageID, systemScheme: Scheme = .light) -> WebsitePolicy {
        let context = browsingContext(of: page.item)
        var policy = WebsitePolicy()
        policy.preferences = sitePreferences(context)
        policy.appearance = policy.preferences.appearance ?? WebsiteAppearance(rawValue: doc.settings.general.webAppearance.rawValue) ?? .automatic
        policy.visible = visiblePages().contains(page)
        if doc.settings.advanced.themeToCSS, let window = doc.windows[page.window],
           let space = doc.spaces[role(of: page.item)?.space ?? window.space] {
            let values = resolveTheme(space.theme, systemScheme: systemScheme).websiteValues
            // Private pages receive their own fixed neutral theme, never a public space's color.
            let c = window.kind == .incognito ? RGBA(0.2, 0.2, 0.2) : values.accent
            func byte(_ v: Double) -> Int { Int((min(1, max(0, v.isFinite ? v : 0)) * 255).rounded()) }
            policy.themeCSS = ["--brk-space-color": "rgb(\(byte(c.red)), \(byte(c.green)), \(byte(c.blue)))",
                               "--brk-space-text": window.kind == .incognito || values.scheme == .dark ? "white" : "black"]
        }
        return policy
    }

    func visiblePages() -> Set<PageID> {
        Set(doc.windows.keys.flatMap { window -> [PageID] in
            if case .library? = session.windows[window]?.overlay { return [] }
            let shown = shownItem(in: window)
            let items: [ItemID]
            if let shown, session.windows[window]?.expandedSplit == shown,
               let focused = focusedPane(of: shown, in: window) { items = [focused] }
            else { items = shown.map { panes(of: $0) } ?? [] }
            return items.map { PageID(window: window, item: $0) }
                + (peekedTab(in: window).map { [PageID(window: window, item: $0)] } ?? [])
        })
    }

    func siteSnapshots() -> [WindowID: SiteControlSnapshot] {
        Dictionary(uniqueKeysWithValues: session.sites.controls.compactMap { window in
            guard doc.windows[window] != nil else { return nil }
            let target = siteTarget(in: window, allowLoading: true)
            let context = target?.context ?? libraryContext(in: window)
            let preferences = sitePreferences(context)
            let name: String
            switch context { case .profile(let id): name = doc.profiles[id]?.name ?? "Profile"; case .incognito: name = "Private session" }
            return (window, SiteControlSnapshot(context: context, applied: target.flatMap { session.live[$0.page]?.websitePolicyStatus }.flatMap { status in target?.document == status.document ? status : nil }, rulesVersion: preferences.blockingRules?.version ?? WebsiteBlockingRules.builtIn.version, rulesError: session.sites.rulesErrors[context], extensionsLoaded: session.sites.catalogs[context] != nil, extensions: session.sites.catalogs[context]?.extensions ?? [], pinnedExtensions: preferences.pinnedExtensions ?? [], extensionError: session.sites.extensionErrors[context] ?? session.sites.catalogs[context]?.error, target: target, profileName: name,
                rule: target.map { preferences.rule(for: $0.origin) } ?? SiteRule(),
                appearance: preferences.appearance ?? WebsiteAppearance(rawValue: doc.settings.general.webAppearance.rawValue) ?? .automatic,
                clearing: session.sites.running.values.contains { $0.target.page.window == window },
                result: session.sites.results[window]))
        })
    }
}

extension Work {
    mutating func updateSitePreferences(_ context: BrowsingContext, _ edit: (inout SitePreferences) -> Void) {
        var value = state.sitePreferences(context)
        edit(&value)
        switch context {
        case .profile(let id): guard state.doc.profiles[id] != nil else { return }; state.doc.sitePreferences[id] = value
        case .incognito(let id): guard state.session.privateSession == id else { return }; state.session.sites.privatePreferences[id] = value
        }
    }

    mutating func sites(_ command: SiteCommand, in window: WindowID) {
        switch command {
        case .controls: state.session.sites.controls.insert(window)
        case .closeControls: state.session.sites.controls.remove(window)
        case .rule(let target, let rule):
            guard target.page.window == window, state.validSiteTarget(target) else { return }
            updateSitePreferences(target.context) { $0.rules[target.origin.value] = rule }
        case .permission(let target, let origin, let capabilities, let decision):
            // Device requests may precede load completion, but the requesting main document must already have
            // committed its origin. Pending navigation and superseded document tokens still reject persistence.
            guard target.page.window == window, state.validSiteTarget(target, allowLoading: true) else { return }
            updateSitePreferences(target.context) { preferences in
                if origin == target.origin {
                    var rule = preferences.rule(for: origin)
                    for capability in capabilities { rule.permissions[capability] = decision }
                    preferences.rules[origin.value] = rule
                } else {
                    var map = preferences.embeddedPermissions ?? [:]
                    let key = target.origin.value + "\n" + origin.value
                    var decisions = map[key] ?? [:]
                    for capability in capabilities { decisions[capability] = decision }
                    map[key] = decisions
                    preferences.embeddedPermissions = map
                }
            }
        case .appearance(let appearance):
            let context = state.siteTarget(in: window)?.context ?? state.libraryContext(in: window)
            updateSitePreferences(context) { $0.appearance = appearance }
        case .clear(let kinds, let scope, let reload):
            guard !kinds.isEmpty, let target = state.siteTarget(in: window),
                  !state.session.sites.running.values.contains(where: { $0.target.context == target.context }) else { return }
            let request = ClearSiteData(id: ctx.newID(), target: target, kinds: kinds, scope: scope, reload: reload)
            state.session.sites.confirmations[request.id] = request
            state.session.sites.results[window] = nil
            state.session.sites.controls.insert(window)
            effects.append(.confirmSiteData(request))
        case .cancelClearing:
            for request in state.session.sites.running.values where request.target.page.window == window { effects.append(.cancelSiteData(request.id)) }
        case .confirmClear(let id, let confirmed):
            guard let request = state.session.sites.confirmations.removeValue(forKey: id), request.target.page.window == window,
                  confirmed, state.validSiteTarget(request.target) else { return }
            state.session.sites.running[id] = request
            effects.append(.clearSiteData(request))
        case .loadBlockingRules:
            let context = state.siteTarget(in: window)?.context ?? state.libraryContext(in: window)
            effects.append(.chooseWebsiteRules(window, context))
        case .selectedBlockingRules(let file, let context):
            guard file.isFileURL, context == (state.siteTarget(in: window)?.context ?? state.libraryContext(in: window)) else { return }
            effects.append(.loadWebsiteRules(file, context))
        case .resetBlockingRules:
            let context = state.siteTarget(in: window)?.context ?? state.libraryContext(in: window)
            updateSitePreferences(context) { $0.blockingRules = nil }
            state.session.sites.rulesErrors[context] = nil
        case .nativeExtensions:
            let context = state.siteTarget(in: window)?.context ?? state.libraryContext(in: window)
            state.session.sites.extensionErrors[context] = nil
            state.session.sites.controls.insert(window)
            if case .profile = context {
                let present = state.session.loaded.contains { page in
                    guard state.browsingContext(of: page.item) == context else { return false }
                    let live = state.session.live[page]
                    let url = (live?.requestContext == context ? live?.requestedURL : nil) ?? state.address(of: page.item, in: page.window, for: .savedDocument)
                    return url?.scheme == "chrome" && url?.host == "extensions"
                }
                if !present { _ = openTab(URL(string: "chrome://extensions/")!, inSpace: state.doc.windows[window]!.space, window: window, focus: false) }
            }
            effects.append(.queryExtensions(context))
        case .extensionIncognito(let id, let allowed):
            let context = state.siteTarget(in: window)?.context ?? state.libraryContext(in: window)
            guard case .profile = context, let item = state.session.sites.catalogs[context]?.extensions.first(where: { $0.id == id }), item.canChangeIncognito == true else { return }
            state.session.sites.extensionErrors[context] = nil
            effects.append(.editExtension(id, .incognito(allowed), context))
        case .extensionShortcut(let id, let command, let text):
            let context = state.siteTarget(in: window)?.context ?? state.libraryContext(in: window)
            guard case .profile = context, let catalog = state.session.sites.catalogs[context]?.extensions,
                  catalog.contains(where: { $0.id == id && $0.commands?.contains(where: { $0.name == command }) == true }) else { return }
            let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let chord = ExtensionShortcuts.chord(input)
            let error: String?
            if input.isEmpty { error = nil }
            else if let chord { error = ExtensionShortcuts.error(for: chord, extensionID: id, command: command, catalog: catalog, overrides: state.doc.keyOverrides) }
            else { error = "Use a shortcut such as cmd+shift+u, or leave empty to clear." }
            state.session.sites.extensionErrors[context] = error
            guard error == nil else { return }
            effects.append(.editExtension(id, .shortcut(command: command, chord: chord), context))
        case .pinExtension(let id, let pinned):
            let context = state.siteTarget(in: window)?.context ?? state.libraryContext(in: window)
            guard case .profile = context, state.session.sites.catalogs[context]?.extensions.contains(where: { $0.id == id }) == true else { return }
            updateSitePreferences(context) { preferences in
                var pins = preferences.pinnedExtensions ?? []
                pins.removeAll { $0 == id }; if pinned { pins.append(id) }
                preferences.pinnedExtensions = pins
            }
        case .invokeExtension(let id):
            guard let target = state.siteTarget(in: window), case .profile = target.context,
                  state.session.sites.catalogs[target.context]?.extensions.contains(where: { $0.id == id && $0.enabled }) == true else { return }
            effects.append(.invokeExtension(id, target))
        case .removeExtension(let id):
            let context = state.siteTarget(in: window)?.context ?? state.libraryContext(in: window)
            guard case .profile = context, state.session.sites.catalogs[context]?.extensions.contains(where: { $0.id == id }) == true else { return }
            guard let manager = openTab(URL(string: "chrome://extensions/")!, inSpace: state.doc.windows[window]!.space, window: window, focus: true) else { return }
            effects.append(.removeExtension(id, context, PageID(window: window, item: manager)))
        case .extensions, .extensionShortcuts:
            let url = URL(string: command == .extensions ? "chrome://extensions/" : "chrome://extensions/shortcuts")!
            if state.doc.windows[window]?.kind == .incognito { effects.append(.app(.beep)); return }
            _ = openTab(url, inSpace: state.doc.windows[window]!.space, window: window, focus: true)
        case .installSelectedExtension(let directory):
            let context = state.siteTarget(in: window)?.context ?? state.libraryContext(in: window)
            guard case .profile = context, directory.isFileURL, directory.path.hasPrefix("/") else { return }
            state.session.sites.extensionErrors[context] = nil
            effects.append(.confirmLocalExtension(window, context, directory))
        case .executeExtensionInstall(let directory, let context):
            guard case .profile = context, directory.isFileURL,
                  context == (state.siteTarget(in: window)?.context ?? state.libraryContext(in: window)) else { return }
            guard let item = openTab(URL(string: "chrome://extensions/")!, inSpace: state.doc.windows[window]!.space, window: window, focus: true) else { return }
            effects.append(.installLocalExtension(PageID(window: window, item: item), context, directory))
        case .addExtension:
            let context = state.siteTarget(in: window)?.context ?? state.libraryContext(in: window)
            guard case .profile = context else { effects.append(.app(.beep)); return }
            effects.append(.addLocalExtension(window, context))
        }
    }

    mutating func websiteRulesLoaded(_ context: BrowsingContext, _ update: WebsiteRulesUpdate) {
        switch context {
        case .profile(let id): guard state.doc.profiles[id] != nil else { return }
        case .incognito(let id): guard state.session.privateSession == id else { return }
        }
        switch update {
        case .failed(let error): state.session.sites.rulesErrors[context] = error
        case .loaded(let rules): updateSitePreferences(context) { $0.blockingRules = rules }; state.session.sites.rulesErrors[context] = nil
        }
    }

    mutating func extensionOperationFailed(_ context: BrowsingContext, _ error: String) {
        guard case .profile(let id) = context, state.doc.profiles[id] != nil else { return }
        state.session.sites.extensionErrors[context] = error
    }

    mutating func extensionsRead(_ catalog: ExtensionCatalog) {
        guard case .profile(let id) = catalog.context, state.doc.profiles[id] != nil else { return }
        if catalog.error != nil, let old = state.session.sites.catalogs[catalog.context] {
            state.session.sites.catalogs[catalog.context] = ExtensionCatalog(context: catalog.context, extensions: old.extensions, error: catalog.error)
        } else { state.session.sites.catalogs[catalog.context] = catalog }
    }

    mutating func siteDataCleared(_ result: ClearSiteDataResult) {
        let request = result.request
        guard state.session.sites.running.removeValue(forKey: request.id) == request else { return }
        if result.completed.contains(.history), case .profile(let id) = request.target.context {
            state.doc.history.removeAll { entry in
                entry.profile == id && (request.scope == .profile || SiteOrigin(entry.url) == request.target.origin)
            }
        }
        if state.doc.windows[request.target.page.window] != nil { state.session.sites.results[request.target.page.window] = result }
        if result.error == nil, request.reload, state.validSiteTarget(request.target) {
            effects.append(.page(request.target.page, .reload(ignoringCache: request.kinds.contains(.cache))))
        }
    }
}

func normalizeSitePolicies(_ state: inout AppState) {
    func valid(_ context: BrowsingContext) -> Bool {
        switch context { case .profile(let id): state.doc.profiles[id] != nil; case .incognito(let id): state.session.privateSession == id }
    }
    state.session.sites.rulesErrors = state.session.sites.rulesErrors.filter { valid($0.key) }
    state.session.sites.extensionErrors = state.session.sites.extensionErrors.filter { valid($0.key) }
    state.session.sites.running = state.session.sites.running.filter { valid($0.value.target.context) }
    state.session.sites.catalogs = state.session.sites.catalogs.filter { if case .profile(let id) = $0.key { state.doc.profiles[id] != nil } else { false } }
    state.doc.sitePreferences = state.doc.sitePreferences.filter { state.doc.profiles[$0.key] != nil }
    state.session.sites.privatePreferences = state.session.sites.privatePreferences.filter { $0.key == state.session.privateSession }
    state.session.sites.controls = state.session.sites.controls.filter { state.doc.windows[$0] != nil }
    state.session.sites.results = state.session.sites.results.filter { state.doc.windows[$0.key] != nil }
    state.session.sites.confirmations = state.session.sites.confirmations.filter { state.validSiteTarget($0.value.target) }
}
