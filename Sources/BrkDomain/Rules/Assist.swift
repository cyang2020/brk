import BrkBase
import Foundation

extension Work {
    mutating func aiProvidersDetected(_ kinds: [AIProviderKind]) { state.session.detectedAI = kinds }

    mutating func assist(_ intent: AIIntent, in window: WindowID) {
        switch intent {
        case .cancel, .dismiss:
            cancelAI(in: window)
            if intent == .dismiss { state.session.ai.answers[window] = nil }
            return
        case .searchFallback:
            guard let query = state.session.ai.answers[window]?.searchQuery else { return }
            cancelAI(in: window)
            commandBar(.submit(query), in: window)
            return
        case .undoOrganize: undoAIOrganize(in: window); return
        case .neverTranslateSite, .neverTranslateLanguage:
            guard case .profile(let profile) = state.libraryContext(in: window),
                  let answer = state.session.ai.answers[window] else { return }
            var exclusions = state.doc.settings.max.translationExclusions?[profile] ?? AITranslationExclusions()
            if intent == .neverTranslateSite, let host = answer.site { exclusions.sites.insert(host) }
            if intent == .neverTranslateLanguage, let lang = answer.language, !lang.isEmpty { exclusions.languages.insert(lang) }
            if state.doc.settings.max.translationExclusions == nil { state.doc.settings.max.translationExclusions = [:] }
            state.doc.settings.max.translationExclusions?[profile] = exclusions
            cancelAI(in: window)
            state.session.ai.answers[window]?.text = "Never-translate preference saved for this profile. Reset it in Settings → Max."
            return
        default: break
        }
        guard state.doc.windows[window]?.kind != .incognito else {
            aiMessage("AI page features are unavailable in private windows.", in: window); return
        }
        if case .open(let mode) = intent {
            // Arc with Max off answers Opt+Cmd+G with a notice ("ChatGPT in the Command Bar not enabled", "Arc Max
            // Preferences ↗") instead of an input. Ours asks the local CLI, so the notice says what is missing.
            if mode == .question, let missing = askBarMissing() {
                toast(missing, link: ToastLink(title: "Max Preferences ↗", command: .settings(.openPane(.max))), in: window)
                return
            }
            openOverlay({ .commandBar(openID: $0, target: .ai(mode)) }, in: window)
            return
        }
        switch intent {
        case .ask(let question):
            guard aiEnabled(.commandBar, window), let q = aiQuestion(question) else { return }
            _ = startAI(.ask(q), purpose: .answer, title: q, window: window)
        case .askPage(let question):
            guard aiEnabled(.askPage, window), let q = aiQuestion(question) else { return }
            readActiveAI(.askPage(q), title: q, in: window)
        case .translate(let language):
            guard aiEnabled(.translation, window), let language = aiQuestion(language), language.count <= 60 else { return }
            readActiveAI(.translate(language), title: "Translate to " + language, in: window)
        case .organizeToday:
            guard state.doc.settings.max.tidyTabs, let space = state.doc.windows[window]?.space else {
                aiMessage("Enable Organize Today Tabs in Settings → Max.", in: window); return
            }
            let tabs = eligibleAITabs(space, in: window)
            guard tabs.count >= 2, tabs.count <= 50 else { aiMessage("Organize needs 2–50 ungrouped Today tabs.", in: window); return }
            _ = startAI(.tidyToday(space, tabs: tabs), purpose: .organize, title: "Organize Today Tabs", window: window)
        case .instant(let query):
            guard aiEnabled(.instantLinks, window), let q = aiQuestion(query) else { return }
            let id = startAI(.instant(q), purpose: .instant(q), title: "Instant Link: " + q, window: window)
            state.session.ai.answers[window]?.searchQuery = q
            // The proposed URL is verified by a request-owned page in this browsing context before opening.
            state.session.ai.requests[id]?.hidden = []
        case .browse(let question, let sources):
            guard aiEnabled(.browse, window), let q = aiQuestion(question), (1...4).contains(sources.count),
                  Set(sources).count == sources.count, sources.allSatisfy({ AIValidation.destination($0.absoluteString) != nil }) else {
                aiMessage("Browse for Me needs a question and 1–4 HTTP(S) source URLs. Enter: question | URL, URL", in: window); return
            }
            let id = startAI(.ask(q), purpose: .browse(q), title: q, window: window, run: false)
            makeAIHidden(id, urls: sources)
        case .renameDownload(let id):
            guard aiEnabled(.downloadRename, window), let download = state.doc.downloads.first(where: { $0.id == id }),
                  state.libraryContext(in: window) == .profile(download.profile), download.state == .finished else { return }
            _ = startAI(.renameDownload(id, original: download.filename), purpose: .answer, title: "Tidy Download Name", window: window)
        default: break
        }
    }

    private func aiQuestion(_ text: String) -> String? {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return !q.isEmpty && q.count <= 2000 ? q : nil
    }
    /// Why Ask in Command Bar cannot run, or nil: the Max switch is off, or the provider is set to off. (Whether a
    /// CLI is on PATH is only known to the app's seam; an answer without one says so, `AIOutcome.unavailable`.)
    private func askBarMissing() -> String? {
        if !state.doc.settings.max.enabled(.commandBar) { return "\(AIFeature.commandBar.title) not enabled" }
        if state.doc.settings.max.provider == .off { return "No local AI tool selected for Max" }
        return nil
    }
    private mutating func aiEnabled(_ feature: AIFeature, _ window: WindowID) -> Bool {
        guard state.doc.settings.max.enabled(feature) else { aiMessage("Enable \(feature.title) in Settings → Max.", in: window); return false }
        return true
    }
    private mutating func aiMessage(_ text: String, in window: WindowID) {
        state.session.ai.answerContexts[window] = state.libraryContext(in: window)
        state.session.ai.answers[window] = AIAnswerSnapshot(request: nil, title: "Max", text: text, busy: false, sources: [], searchQuery: nil)
    }
    private mutating func startAI(_ task: AITask, purpose: AIPurpose, title: String, window: WindowID, run: Bool = true) -> AIRequestID {
        cancelAI(in: window)
        let id = AIRequestID(ctx.newID())
        state.session.ai.requests[id] = AIRequest(window: window, context: state.libraryContext(in: window), task: task, purpose: purpose)
        state.session.ai.answerContexts[window] = state.libraryContext(in: window)
        state.session.ai.answers[window] = AIAnswerSnapshot(request: id, title: title, text: run ? "Waiting for the local AI tool…" : "Reading the selected page…", busy: true, sources: [], searchQuery: nil)
        state.session.windows[window]?.overlay = nil
        state.session.ai.answers[window]?.isPreview = purpose.isPreview
        effects.append(.aiWatch(id, seconds: 120))
        if run { sendAI(id, task: task) }
        return id
    }
    private mutating func sendAI(_ id: AIRequestID, task: AITask) {
        state.session.pendingAI[id] = task
        state.session.ai.requests[id]?.task = task
        effects.append(.ai(id, task, choice: state.doc.settings.max.provider))
    }
    private mutating func readActiveAI(_ purpose: AIPurpose, title: String, in window: WindowID) {
        guard let page = state.findPage(in: window), case .ready(let document) = state.session.live[page]?.document,
              state.session.live[page]?.requestContext == state.libraryContext(in: window) else {
            aiMessage("Wait for this page to finish loading, then retry.", in: window); return
        }
        let id = startAI(.ask(title), purpose: purpose, title: title, window: window, run: false)
        state.session.ai.requests[id]?.document = document
        effects.append(.aiRead(id, document))
    }
    private mutating func makeAIHidden(_ id: AIRequestID, urls: [URL]) {
        guard let request = state.session.ai.requests[id] else { return }
        let hidden = urls.enumerated().map { index, url in
            var spec = PageSpec(id: PageID(window: request.window, item: ItemID("ai-" + id.rawValue + "-" + String(index))), initialURL: url, context: request.context, muted: true)
            spec.isAIReader = true
            spec.websitePolicy = state.websitePolicy(for: state.findPage(in: request.window) ?? spec.id)
            return spec
        }
        state.session.ai.requests[id]?.hidden = hidden
        effects.append(.aiWatch(id, seconds: request.purpose.isPreview ? 5 : 30))
    }

    mutating func aiHiddenEvent(_ event: PageEvent, token: BrowserToken) -> Bool {
        guard let id = state.session.ai.requests.first(where: { $0.value.hidden.contains(where: { $0.id == token.page }) })?.key,
              let request = state.session.ai.requests[id] else { return false }
        switch event {
        case .browserCreated(let context, let availability):
            guard context == request.context else { return true }
            if case .ready(let doc) = availability, doc.browser == token { aiHiddenReady(id, document: doc) }
        case .documentChanged(.ready(let doc)):
            guard doc.browser == token else { return true }
            aiHiddenReady(id, document: doc)
        case .loadFailed, .rendererGone, .closedByPage:
            completeAI(id, text: "This source is unavailable. Check its address or sign in in a normal tab, then retry.")
        default: break
        }
        return true
    }
    private mutating func aiHiddenReady(_ id: AIRequestID, document: DocumentToken) {
        guard let r = state.session.ai.requests[id], !r.extracting.contains(document.browser.page) else { return }
        state.session.ai.requests[id]?.hiddenDocuments[document.browser.page] = document
        state.session.ai.requests[id]?.extracting.insert(document.browser.page)
        effects.append(.aiRead(id, document))
    }

    mutating func aiReadResult(_ id: AIRequestID, page: PageID, content: AIPageContent?) {
        guard var request = state.session.ai.requests[id],
              state.libraryContext(in: request.window) == request.context,
              let content, content.document.browser.page == page,
              content.text.utf8.count <= 100_000, content.nodes.count <= 200,
              (request.document == content.document || request.hiddenDocuments[page] == content.document),
              AIValidation.destination(content.url.absoluteString) != nil else {
            if state.session.ai.requests[id] != nil { completeAI(id, text: "The page changed or could not be read. Reload it and retry.") }; return
        }
        if let doc = request.document, state.session.live[page]?.document != .ready(doc) { return }
        request.contents[page] = content
        state.session.ai.requests[id] = request
        switch request.purpose {
        case .askPage(let question):
            state.session.ai.answers[request.window]?.sources = [AISource(title: content.title, url: content.url)]
            sendAI(id, task: .pageQuestion(question, content))
        case .translate(let target):
            guard case .profile(let profile) = request.context else { return }
            let exclusions = state.doc.settings.max.translationExclusions?[profile] ?? AITranslationExclusions()
            state.session.ai.answers[request.window]?.language = content.language.lowercased()
            state.session.ai.answers[request.window]?.site = content.url.host?.lowercased()
            if exclusions.languages.contains(content.language.lowercased()) || exclusions.sites.contains(content.url.host?.lowercased() ?? "") {
                completeAI(id, text: "This profile never translates this language or site. Change the choice in Settings → Max."); return
            }
            guard !content.nodes.isEmpty else { completeAI(id, text: "No visible text is available to translate."); return }
            state.session.ai.answers[request.window]?.sources = [AISource(title: content.title, url: content.url)]
            sendAI(id, task: .translate(target: target, content: content))
        case .preview:
            state.session.ai.requests[id]?.hidden = []
            state.session.ai.answers[request.window]?.sources = [AISource(title: content.title, url: content.url)]
            sendAI(id, task: .summarize(content))
        case .instant:
            // A real main-frame ready document establishes reachability using the original context.
            commandBar(.submit(content.url.absoluteString), in: request.window)
            completeAI(id, text: "Opened " + content.url.absoluteString)
        case .browse(let question):
            guard request.contents.count == request.hidden.count else { return }
            let pages = request.hidden.compactMap { request.contents[$0.id] }
            state.session.ai.requests[id]?.hidden = []
            state.session.ai.answers[request.window]?.sources = pages.map { AISource(title: $0.title, url: $0.url) }
            sendAI(id, task: .browse(question, pages))
        default: break
        }
    }

    mutating func aiResult(_ id: AIRequestID, _ outcome: AIOutcome) {
        guard let task = state.session.pendingAI.removeValue(forKey: id) else { return }
        if let context = state.session.ai.backgroundContexts.removeValue(forKey: id), backgroundAIContext(task) != context { return }
        guard case .text(let text) = outcome else {
            switch outcome {
            case .unavailable: completeAI(id, text: "No selected local AI tool is available. Choose an installed provider in Settings → Max and sign in to it in Terminal.")
            case .failed(let reason): completeAI(id, text: reason)
            default: break
            }
            return
        }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            completeAI(id, text: "The AI tool returned no answer. Check its sign-in in Terminal, then retry.")
            return
        }
        switch task {
        case .renameTab(let tab, _, let url):
            let title = String(text.split(whereSeparator: \.isNewline).first ?? "").trimmingCharacters(in: .whitespacesAndNewlines).prefix(60)
            guard !title.isEmpty, let scope = state.locate(tab), state.tab(tab)?.pinnedURL == url, state.tab(tab)?.customTitle == nil else { return }
            state.withTree(scope) { $0.updateTab(tab) { $0.customTitle = String(title) } }
        case .renameDownload(let download, let original):
            guard let value = state.doc.downloads.first(where: { $0.id == download }), value.state == .finished,
                  value.filename == original, let path = value.path,
                  let name = AIValidation.filename(text, original: original) else { completeAI(id, text: "The tool returned an unsafe filename, or the download changed. No file was renamed."); return }
            effects.append(.aiRenameDownload(download, originalPath: path, filename: name))
        case .instant:
            guard let url = AIValidation.destination(text) else { completeAI(id, text: "The tool did not propose a safe web address. Choose Search Instead."); return }
            makeAIHidden(id, urls: [url])
            state.session.ai.answers[state.session.ai.requests[id]!.window]?.text = "Checking the destination in this profile…"
        case .tidyToday(let space, let tabs):
            guard let request = state.session.ai.requests[id], eligibleAITabs(space, in: request.window) == tabs,
                  let plan = AIValidation.plan(text, eligible: tabs) else { completeAI(id, text: "The plan was invalid or Today changed. No tabs were moved. Retry Organize Today Tabs."); return }
            applyAIOrganize(id, space: space, tabs: tabs, plan: plan)
        case .translate(_, let content):
            guard let nodes = AIReplyCodec.nodes(text),
                  nodes.count == content.nodes.count, Set(nodes.map(\.id)).count == nodes.count,
                  Set(nodes.map(\.id)) == Set(content.nodes.map(\.id)), nodes.allSatisfy({ $0.text.count <= 4000 }),
                  state.session.ai.requests[id] != nil else { completeAI(id, text: "The tool returned an invalid translation. The page was left unchanged."); return }
            effects.append(.aiTranslate(id, content, nodes))
        case .browse(_, let pages):
            let answer = String(text.prefix(60_000))
            guard AIValidation.citations(answer, sourceCount: pages.count) else {
                completeAI(id, text: "The tool did not cite the selected sources correctly. Retry Browse for Me or open the sources below."); return
            }
            completeAI(id, text: answer)
        case .ask, .pageQuestion:
            completeAI(id, text: String(text.prefix(60_000)))
        case .summarize: completeAI(id, text: String(text.prefix(700)))
        }
    }
    mutating func aiPartial(_ id: AIRequestID, _ text: String) {
        guard let request = state.session.ai.requests[id], state.session.pendingAI[id] != nil else { return }
        switch request.task {
        case .ask, .pageQuestion, .browse, .summarize:
            state.session.ai.answers[request.window]?.text = String(text.prefix(request.purpose.isPreview ? 700 : 60_000))
        default: break
        }
    }
    mutating func aiDeadline(_ id: AIRequestID) {
        guard state.session.ai.requests[id] != nil else { return }
        completeAI(id, text: "The source or AI tool did not answer in time. The request was stopped; retry or use ordinary search.")
    }
    mutating func aiTranslated(_ id: AIRequestID, success: Bool) {
        completeAI(id, text: success ? "Page translated. Controls and page structure were preserved. Reload to restore the original text." : "The document or text changed. Translation was not applied; reload and retry.")
    }
    private mutating func completeAI(_ id: AIRequestID, text: String) {
        guard let request = state.session.ai.requests.removeValue(forKey: id) else { return }
        state.session.pendingAI[id] = nil
        effects.append(.aiCancel(id))
        guard state.session.ai.answers[request.window]?.request == id else { return }
        state.session.ai.answers[request.window]?.text = text
        state.session.ai.answers[request.window]?.busy = false
        state.session.ai.answers[request.window]?.request = nil
    }
    private mutating func cancelAI(in window: WindowID) {
        let ids = state.session.ai.requests.filter { $0.value.window == window }.map(\.key)
        for id in ids { completeAI(id, text: "Request cancelled.") }
    }
    mutating func reconcileAI(from previous: AppState) {
        let providerChanged = previous.doc.settings.max.provider != state.doc.settings.max.provider
        for (id, task) in state.session.pendingAI where state.session.ai.requests[id] == nil {
            let valid: Bool
            switch task {
            case .renameTab(let tab, _, let url): valid = state.doc.settings.max.renamePinnedTabs && state.session.ai.backgroundContexts[id] == backgroundAIContext(task) && state.tab(tab)?.pinnedURL == url && state.tab(tab)?.customTitle == nil && (state.role(of: tab)?.kind == .pinned || state.role(of: tab)?.kind == .favorites)
            case .renameDownload(let download, _): valid = state.doc.settings.max.enabled(.downloadRename) && state.session.ai.backgroundContexts[id] == backgroundAIContext(task) && state.doc.downloads.contains { $0.id == download && $0.state == .finished && state.doc.profiles[$0.profile] != nil }
            default: valid = true
            }
            if !valid || providerChanged { state.session.pendingAI[id] = nil; state.session.ai.backgroundContexts[id] = nil; effects.append(.aiCancel(id)) }
        }
        for (id, request) in state.session.ai.requests {
            let ownerExists = state.doc.windows[request.window] != nil
            let sameContext = state.libraryContext(in: request.window) == request.context
            let sameDocument = request.document.map { state.session.live[$0.browser.page]?.document == .ready($0) && state.findPage(in: request.window) == $0.browser.page } ?? true
            let featureEnabled: Bool = switch request.purpose {
            case .answer:
                if case .renameDownload = request.task { state.doc.settings.max.enabled(.downloadRename) }
                else { state.doc.settings.max.enabled(.commandBar) }
            case .askPage: state.doc.settings.max.enabled(.askPage)
            case .preview: state.doc.settings.max.enabled(.linkPreviews)
            case .instant: state.doc.settings.max.enabled(.instantLinks)
            case .browse: state.doc.settings.max.enabled(.browse)
            case .translate: state.doc.settings.max.enabled(.translation)
            case .organize: state.doc.settings.max.tidyTabs
            }
            if !ownerExists || !sameContext || !sameDocument || !featureEnabled || providerChanged { completeAI(id, text: "The page or browsing context changed. Request cancelled.") }
        }
        for window in Set(state.session.ai.answers.keys).union(state.session.ai.undo.keys).union(state.session.ai.hover.keys).union(state.session.ai.answerContexts.keys) where state.doc.windows[window] == nil || (state.session.ai.answerContexts[window] != nil && state.session.ai.answerContexts[window] != state.libraryContext(in: window)) {
            state.session.ai.answerContexts[window] = nil
            state.session.ai.answers[window] = nil; state.session.ai.undo[window] = nil; state.session.ai.hover[window] = nil; state.session.ai.hoverDocuments[window] = nil
        }
    }

    @discardableResult
    mutating func requestAI(_ task: AITask) -> AIRequestID {
        let id = AIRequestID(ctx.newID())
        state.session.pendingAI[id] = task
        state.session.ai.backgroundContexts[id] = backgroundAIContext(task)
        effects.append(.ai(id, task, choice: state.doc.settings.max.provider))
        return id
    }

    private func backgroundAIContext(_ task: AITask) -> BrowsingContext? {
        switch task {
        case .renameTab(let tab, _, _): state.locate(tab).map { _ in state.browsingContext(of: tab) }
        case .renameDownload(let id, _): state.doc.downloads.first { $0.id == id }.map { .profile($0.profile) }
        default: nil
        }
    }

    mutating func aiHover(_ url: URL?, in window: WindowID) {
        guard state.doc.settings.max.enabled(.linkPreviews), state.doc.windows[window]?.kind != .incognito else { return }
        let url = url.flatMap { AIValidation.destination($0.absoluteString) }
        guard state.session.ai.hover[window] != url else { return }
        state.session.ai.hover[window] = url
        state.session.ai.hoverDocuments[window] = state.findPage(in: window).flatMap { page in
            if case .ready(let document) = state.session.live[page]?.document { document } else { nil }
        }
        for (id, request) in state.session.ai.requests where request.window == window && request.purpose.isPreview { completeAI(id, text: "Preview cancelled.") }
        if state.session.ai.answers[window]?.isPreview == true { state.session.ai.answers[window] = nil }
        effects.append(.aiHover(window, url))
    }
    mutating func aiHoverReady(_ window: WindowID, url: URL) {
        guard state.session.ai.hover[window] == url, state.doc.settings.max.enabled(.linkPreviews), state.doc.windows[window]?.kind != .incognito,
              let document = state.session.ai.hoverDocuments[window],
              state.findPage(in: window) == document.browser.page,
              state.session.live[document.browser.page]?.document == .ready(document),
              state.session.live[document.browser.page]?.requestContext == state.libraryContext(in: window),
              !state.session.ai.requests.values.contains(where: { $0.window == window && !$0.purpose.isPreview }),
              state.session.ai.answers[window] == nil || state.session.ai.answers[window]?.isPreview == true else { return }
        let id = startAI(.ask("Summarize link"), purpose: .preview(url), title: "Link Preview", window: window, run: false)
        makeAIHidden(id, urls: [url])
    }

    private func eligibleAITabs(_ space: SpaceID, in window: WindowID) -> [AITab] {
        guard state.doc.windows[window]?.kind == .standard, state.doc.windows[window]?.space == space,
              let root = state.doc.spaces[space]?.todayRoot else { return [] }
        return (state.doc.tree[root]?.children ?? []).compactMap { id in
            guard state.doc.tree[id]?.kind == .tab, let tab = state.displayedTab(id, in: window), let url = tab.url else { return nil }
            return AITab(id: id, title: tab.displayTitle, url: url)
        }
    }
    private mutating func applyAIOrganize(_ id: AIRequestID, space: SpaceID, tabs: [AITab], plan: [AIGroupPlan]) {
        guard let request = state.session.ai.requests[id], let root = state.doc.spaces[space]?.todayRoot else { return }
        var tree = state.doc.tree
        let original = tree[root]!.children
        var folders: [ItemID: [ItemID]] = [:]
        do {
            for group in plan {
                let folder = ItemID(ctx.newID())
                var payload = Folder(title: group.folder, collapsed: false); payload.isGroup = true
                try tree.insert(folder, .folder(payload), at: .into(parent: root, index: Int.max), createdAt: ctx.now)
                let items = group.tabs.map(ItemID.init)
                for tab in items { _ = try tree.move(tab, to: .into(parent: folder, index: Int.max)) }
                folders[folder] = items
            }
        } catch { completeAI(id, text: "The plan could not be applied. No tabs were moved."); return }
        state.doc.tree = tree
        state.session.ai.undo[request.window] = AIOrganizeUndo(space: space, original: original, folders: folders)
        completeAI(id, text: "Organized \(tabs.count) Today tabs into \(plan.count) \(plan.count == 1 ? "group" : "groups").")
        state.session.ai.answers[request.window]?.canUndo = true
    }
    private mutating func undoAIOrganize(in window: WindowID) {
        guard let undo = state.session.ai.undo[window], state.doc.windows[window]?.space == undo.space,
              let root = state.doc.spaces[undo.space]?.todayRoot,
              undo.folders.allSatisfy({ state.doc.tree[$0.key]?.parent == root && state.doc.tree[$0.key]?.children == $0.value }) else {
            aiMessage("The groups changed. Undo was refused to protect your edits.", in: window); return
        }
        var tree = state.doc.tree
        do {
            for id in undo.original where undo.folders.values.contains(where: { $0.contains(id) }) {
                _ = try tree.move(id, to: .into(parent: root, index: Int.max))
            }
            for id in undo.folders.keys { _ = tree.removeSubtree(id) }
            // Restore prior siblings without disturbing newly added tabs.
            for (index, id) in undo.original.enumerated() where tree[id]?.parent == root { _ = try tree.move(id, to: .into(parent: root, index: index)) }
        } catch { return }
        state.doc.tree = tree
        state.session.ai.undo[window] = nil
        aiMessage("Restored Today tab order.", in: window)
    }

    mutating func aiDownloadRenamed(_ id: DownloadID, original: String, new: String?, error: String?) {
        let asked = state.session.ai.requests.values.first { if case .renameDownload(id, _) = $0.task { true } else { false } }?.window
        for (requestID, request) in state.session.ai.requests {
            if case .renameDownload(let downloadID, _) = request.task, downloadID == id {
                completeAI(requestID, text: new.map { "Renamed download to " + ($0 as NSString).lastPathComponent } ?? error ?? "The file could not be renamed.")
            }
        }
        guard let index = state.doc.downloads.firstIndex(where: { $0.id == id && $0.path == original && $0.state == .finished }), let new else { return }
        state.doc.downloads[index].path = new
        state.doc.downloads[index].filename = (new as NSString).lastPathComponent
        if let asked { toast(ToastCopy.downloadRenamed, in: asked) }
    }

    mutating func suggestions(_ window: WindowID, query: String, _ results: [String]) {
        guard state.session.windows[window] != nil, case .commandBar? = state.session.windows[window]!.overlay else { return }
        state.session.windows[window]!.suggestions = Suggestions(query: query, results: Array(results.prefix(Metrics.commandBar.maxSearchSuggestions.value)))
    }
}
private extension AIPurpose {
    var isPreview: Bool { if case .preview = self { true } else { false } }
}
