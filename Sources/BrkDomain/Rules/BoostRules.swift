import BrkBase
import Foundation

extension AppState {
    func boostProfile(in window: WindowID) -> ProfileID? {
        guard doc.windows[window]?.kind != .incognito, case .profile(let profile) = libraryContext(in: window),
              doc.profiles[profile] != nil, doc.deletingProfiles[profile] == nil else { return nil }
        return profile
    }
    func boostPickingTarget(in window: WindowID) -> SiteTarget? {
        guard let target = siteTarget(in: window), visiblePages().contains(target.page) else { return nil }
        return target
    }
    /// The open editor's site now: its own target while that document is current, else, after the page reloaded or
    /// navigated within the same origin and context, the page's new committed document (review #18: a reload no
    /// longer ends the preview and Zap). nil once the page shows another site or is gone.
    func boostEditorTarget(_ editor: BoostEditor) -> SiteTarget? {
        guard let target = editor.target else { return nil }
        if validSiteTarget(target) { return target }
        guard let now = siteTarget(in: target.page.window), now.page == target.page, now.origin == target.origin,
              now.context == target.context, validSiteTarget(now) else { return nil }
        return now
    }

    func boostPolicy(for page: PageID) -> BoostPolicy {
        guard doc.settings.advanced.boostsEnabled else { return BoostPolicy() }
        guard let window = doc.windows[page.window], let profile = doc.spaces[window.space]?.profile else { return BoostPolicy() }
        let context = browsingContext(of: page.item)
        let owner: ProfileID = if case .profile(let p) = context { p } else { profile }
        let isPrivate = if case .incognito = context { true } else { false }
        var boosts = session.boosts[owner]?.boosts ?? []
        if !isPrivate, let editor = session.windows[page.window]?.boostEditor, editor.profile == owner,
           let target = boostEditorTarget(editor), target.page == page {
            // Typing never runs code: the preview carries JavaScript only once that exact program, scope and
            // private permission were confirmed and written (the Code page's hammer, or an earlier save).
            let saved = boosts.first { $0.id == editor.draft.id }
            var preview = editor.draft
            preview.javascriptApproved = preview.javascriptApproved && saved?.javascriptApproved == true && saved?.javascript == preview.javascript
                && saved?.scope == preview.scope && saved?.allowPrivate == preview.allowPrivate
            boosts.removeAll { $0.id == editor.draft.id }
            boosts.append(preview)
        }
        return BoostPolicy(boosts: boosts.filter { $0.enabled && (!isPrivate || $0.allowPrivate) }.map {
            BoostInjection(id: $0.id, scope: $0.scope, css: $0.injectedCSS,
                           javascript: $0.javascriptApproved ? $0.javascript : "", allowPrivate: $0.allowPrivate)
        })
    }
}

extension Work {
    mutating func boosts(_ command: BoostCommand, in window: WindowID) {
        guard let profile = state.boostProfile(in: window) else { return }
        let catalog = state.session.boosts[profile] ?? BoostCatalog()
        func find(_ id: String) -> Boost? { catalog.boosts.first { $0.id == id } }
        switch command {
        case .create, .legacy, .preset:
            library(.close, in: window)
            let target = state.siteTarget(in: window)
            let scope = target.map { BoostScope.origin($0.origin) } ?? .allSites
            var draft = Boost(id: ctx.newID(), name: "My Boost", scope: scope)
            if case .preset(let id) = command, let preset = BoostPresets.all.first(where: { $0.id == id }) {
                draft.name = preset.name; draft.css = preset.css
            }
            // Arc's first Boost opens on the "Edit the Internet with Boosts" card (P37-a).
            let page: BoostEditorPage = command == .create && catalog.boosts.isEmpty ? .intro : .style
            state.session.windows[window]?.boostEditor = BoostEditor(id: ctx.newID(), profile: profile, target: target, draft: draft, page: page)
        case .editCurrent:
            // Most specific scope first: an origin Boost beats a host Boost beats an all-sites Boost (review F6).
            func rank(_ scope: BoostScope) -> Int { switch scope { case .origin: 0; case .host: 1; case .allSites: 2 } }
            if let target = state.siteTarget(in: window),
               let boost = catalog.boosts.filter({ $0.scope.matches(target.origin.url) }).min(by: { rank($0.scope) < rank($1.scope) }) {
                boosts(.edit(boost.id), in: window)
            } else { boosts(.create, in: window) }
        case .edit(let id):
            guard let boost = find(id) else { return }
            library(.close, in: window)
            let target = state.siteTarget(in: window)
            state.session.windows[window]?.boostEditor = BoostEditor(id: ctx.newID(), profile: profile, target: target, draft: boost)
        case .gallery:
            library(.open(.boosts), in: window)
            state.session.windows[window]?.boostMessage = "Choose a local preset below, or import a Boost file."
        case .update(var draft):
            guard let editor = state.session.windows[window]?.boostEditor, editor.profile == profile, draft.id == editor.draft.id else { return }
            // Trust is internal: neither text controls nor command/socket clients can grant it.
            draft.javascriptApproved = editor.draft.javascriptApproved && draft.javascript == editor.draft.javascript
                && draft.scope == editor.draft.scope && draft.allowPrivate == editor.draft.allowPrivate
            if draft.style == BoostStyle() { draft.style = nil }
            guard draft.style?.valid ?? true else { return }
            state.session.windows[window]?.boostEditor?.draft = draft
            state.session.windows[window]?.boostEditor?.message = nil
        case .page(let page):
            guard let editor = state.session.windows[window]?.boostEditor, editor.profile == profile, editor.page != page else { return }
            stopBoostPick(in: window)
            state.session.windows[window]?.boostEditor?.page = page
            state.session.windows[window]?.boostEditor?.message = nil
        case .save:
            guard let editor = state.session.windows[window]?.boostEditor, editor.profile == profile else { return }
            do { try BoostCodec.validate(BoostCatalog(boosts: [editor.draft])) }
            catch { state.session.windows[window]?.boostEditor?.message = error.localizedDescription; return }
            if !editor.draft.javascript.isEmpty && !editor.draft.javascriptApproved {
                effects.append(.boost(.confirm(window, editor.id, editor.draft)))
            } else { writeBoost(editor.draft, profile: profile, window: window, editor: nil) }
        case .close:
            // Arc saves on close. JavaScript that was never confirmed is kept, inert, for the Code page's hammer.
            guard let editor = state.session.windows[window]?.boostEditor, editor.profile == profile else { return }
            stopBoostPick(in: window)
            let saved = find(editor.draft.id)
            if editor.draft == saved || (saved == nil && (editor.draft.isBlank || editor.page == .intro)) {
                state.session.windows[window]?.boostEditor = nil; return
            }
            do { try BoostCodec.validate(BoostCatalog(boosts: [editor.draft])) }
            catch { state.session.windows[window]?.boostEditor?.message = error.localizedDescription; return }
            writeBoost(editor.draft, profile: profile, window: window, editor: editor.id)
        case .discard:
            state.session.windows[window]?.boostEditor = nil
        case .zap, .inspect:
            let purpose: BoostPickPurpose = command == .zap ? .zap : .selector
            if let editor = state.session.windows[window]?.boostEditor, editor.picking {
                stopBoostPick(in: window)
                if editor.pickPurpose == purpose { return }
            }
            guard let editor = state.session.windows[window]?.boostEditor, editor.profile == profile,
                  let target = state.boostEditorTarget(editor), state.boostPickingTarget(in: window) == target else {
                state.session.windows[window]?.boostEditor?.message = "Open the Boost on a committed website to pick an element."
                return
            }
            state.session.windows[window]?.boostEditor?.target = target
            state.session.windows[window]?.boostEditor?.pickPurpose = purpose
            state.session.windows[window]?.boostEditor?.message = nil
            startBoostPick(target, in: window)
        case .enable(let id, let enabled):
            // Toggling from the Library keeps an open editor's draft (review F7).
            guard var boost = find(id) else { return }; boost.enabled = enabled
            writeBoost(boost, profile: profile, window: window, editor: nil)
        case .remove(let id):
            if state.session.windows[window]?.boostEditor?.draft.id == id { state.session.windows[window]?.boostEditor = nil }
            guard find(id) != nil else { return }
            var next = catalog; next.boosts.removeAll { $0.id == id }
            effects.append(.boost(.write(window, profile, next, editor: nil)))
        case .export(let id):
            guard let boost = find(id) else { return }; effects.append(.boost(.exportFile(window, boost, nil)))
        case .exportSelected(let id, let file):
            guard let boost = find(id), file.isFileURL else { return }; effects.append(.boost(.exportFile(window, boost, file)))
        case .importFile: effects.append(.boost(.importFile(window, profile, nil)))
        case .importSelected(let file):
            guard file.isFileURL else { return }; effects.append(.boost(.importFile(window, profile, file)))
        }
    }

    mutating func startBoostPick(_ target: SiteTarget, in window: WindowID) {
        let pickID = ctx.newID()
        state.session.windows[window]?.boostEditor?.picking = true
        state.session.windows[window]?.boostEditor?.pickID = pickID
        effects.append(.boost(.pick(window, pickID, target)))
    }

    mutating func stopBoostPick(in window: WindowID) {
        guard state.session.windows[window]?.boostEditor?.picking == true else { return }
        state.session.windows[window]?.boostEditor?.picking = false
        state.session.windows[window]?.boostEditor?.pickID = nil
    }

    static func jsLiteral(_ text: String) -> String {
        (try? String(data: JSONSerialization.data(withJSONObject: [text]), encoding: .utf8)).map { String($0.dropFirst().dropLast()) } ?? "\"\""
    }

    mutating func writeBoost(_ boost: Boost, profile: ProfileID, window: WindowID, editor: String?) {
        var next = state.session.boosts[profile] ?? BoostCatalog()
        // Replace in place so a save, enable or disable does not move the Boost and change which CSS wins (review #17).
        if let index = next.boosts.firstIndex(where: { $0.id == boost.id }) { next.boosts[index] = boost } else { next.boosts.append(boost) }
        effects.append(.boost(.write(window, profile, next, editor: editor)))
    }

    mutating func boostEvent(_ event: BoostEvent) {
        switch event {
        case .loaded(let profile, let catalog, let error):
            guard state.doc.profiles[profile] != nil else { return }
            state.session.boosts[profile] = catalog
            state.session.boostErrors[profile] = error
        case .written(let window, let profile, let catalog, let editor):
            guard state.doc.profiles[profile] != nil else { return }
            state.session.boosts[profile] = catalog
            state.session.boostErrors[profile] = nil
            if state.boostProfile(in: window) == profile {
                if let editor, state.session.windows[window]?.boostEditor?.id == editor { state.session.windows[window]?.boostEditor = nil }
                else if let open = state.session.windows[window]?.boostEditor, let stored = catalog.boosts.first(where: { $0.id == open.draft.id }),
                        stored.javascriptApproved, stored.javascript == open.draft.javascript, !stored.javascript.isEmpty {
                    state.session.windows[window]?.boostEditor?.message = "JavaScript allowed and saved."
                }
                state.session.windows[window]?.boostMessage = "Boosts saved. Reload to undo JavaScript that already ran."
            }
        case .failed(let window, let message):
            state.session.windows[window]?.boostMessage = message
            state.session.windows[window]?.boostEditor?.message = message
        case .approved(let window, let id, var boost):
            guard let editor = state.session.windows[window]?.boostEditor, editor.id == id, editor.draft == boost,
                  state.boostProfile(in: window) == editor.profile else { return }
            // The editor stays open: the approval came from the Code page's hammer, and the preview now runs it.
            boost.javascriptApproved = true
            state.session.windows[window]?.boostEditor?.draft.javascriptApproved = true
            writeBoost(boost, profile: editor.profile, window: window, editor: nil)
        case .picked(let window, let id, let target, let selector):
            guard let editor = state.session.windows[window]?.boostEditor, editor.picking, editor.pickID == id else { return }
            if let current = editor.target, current != target, current.page == target.page, current.origin == target.origin {
                // The pick was armed on the document before a reload (Normalize rebound the editor): Zap goes on, on the
                // new document (review #18).
                stopBoostPick(in: window)
                if editor.pickPurpose == .zap, state.boostPickingTarget(in: window) == current { startBoostPick(current, in: window) }
                return
            }
            guard editor.target == target else { return }
            stopBoostPick(in: window)
            guard state.boostProfile(in: window) == editor.profile, state.validSiteTarget(target), state.boostPickingTarget(in: window) == target else {
                state.session.windows[window]?.boostEditor?.message = "The page changed. Reopen the Boost before using Zap."; return
            }
            // No selector: the user pressed Escape on the page (or the page went away); picking just ends.
            guard let selector else { return }
            guard !selector.isEmpty, selector.count <= 4096, !selector.contains("{"), !selector.contains("}"), !selector.contains("\n") else {
                state.session.windows[window]?.boostEditor?.message = "That element could not be selected."; return
            }
            switch editor.pickPurpose {
            case .zap:
                let rule = selector + " { display: none !important; }"
                if !editor.draft.css.contains(rule) { state.session.windows[window]?.boostEditor?.draft.css += (editor.draft.css.isEmpty ? "" : "\n") + rule + "\n" }
                // Arc keeps Zap on until its button is pressed again: arm the next click.
                startBoostPick(target, in: window)
            case .selector:
                if editor.page == .javascript {
                    state.session.windows[window]?.boostEditor?.draft.javascript += "document.querySelector(" + Self.jsLiteral(selector) + ")\n"
                    state.session.windows[window]?.boostEditor?.draft.javascriptApproved = false
                } else {
                    state.session.windows[window]?.boostEditor?.draft.css += (editor.draft.css.isEmpty ? "" : "\n") + selector + " {\n  \n}\n"
                }
            }
        case .imported(let window, let profile, let values):
            guard state.boostProfile(in: window) == profile else { return }
            // Imported Boosts arrive disabled so nothing runs before the user has looked at them (review #11).
            var next = state.session.boosts[profile] ?? BoostCatalog(); next.boosts += values.map { var b = $0; b.enabled = false; return b }
            effects.append(.boost(.write(window, profile, next, editor: nil)))
            if !values.isEmpty { toast(ToastCopy.boostInstalled, in: window) }
        }
    }
}
