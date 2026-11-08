import BrkBase
import Foundation

extension Work {
    mutating func aiProvidersDetected(_ kinds: [AIProviderKind]) { state.session.detectedAI = kinds }

    mutating func assist(_ intent: AIIntent, in window: WindowID) {
        switch intent {
        case .cancel, .stop, .dismiss:
            cancelAI(in: window, slot: .panel)
            if intent == .dismiss { state.session.ai.answers[window] = nil }
            return
        case .approve(let approval, let option):
            answerApproval(approval, option: option, in: window)
            return
        case .undoOrganize: undoAIOrganize(in: window); return
        case .neverTranslateSite, .neverTranslateLanguage:
            guard case .profile(let profile) = state.libraryContext(in: window) else { return }
            let page = state.findPage(in: window)
            let translation = page.flatMap { state.session.ai.translations[$0] }
            let answer = state.session.ai.answers[window]
            let host = page.flatMap { state.address(of: $0.item, in: window, for: .visible)?.host?.lowercased() } ?? answer?.site
            let language = translation?.source ?? page.flatMap { state.session.live[$0]?.language }.map(AILanguages.base) ?? answer?.language
            guard host != nil || language != nil else { return }
            var exclusions = state.doc.settings.max.translationExclusions?[profile] ?? AITranslationExclusions()
            if intent == .neverTranslateSite, let host { exclusions.sites.insert(host) }
            if intent == .neverTranslateLanguage, let language, !language.isEmpty { exclusions.languages.insert(language) }
            if state.doc.settings.max.translationExclusions == nil { state.doc.settings.max.translationExclusions = [:] }
            state.doc.settings.max.translationExclusions?[profile] = exclusions
            cancelAI(in: window, slot: .translate)
            // Arc's Never Translate This Site: the page goes back to its own language and is not offered again.
            if let page, translation?.showingTranslation == true { showTranslation(page, false) }
            if answer != nil { state.session.ai.answers[window]?.text = "Never-translate preference saved for this profile. Reset it in Settings → Max." }
            return
        case .useOriginal:
            guard let page = state.findPage(in: window), let translation = state.session.ai.translations[page], translation.showingTranslation else { return }
            showTranslation(page, false)
            // P50-e: Arc's sentence here ends with a full stop.
            undoToast("Translated back to \(AILanguages.name(translation.source))! Use", trailing: "to undo.", undo: .translation(page), in: window, onPage: true)
            return
        case .languageSettings:
            guard let url = URL(string: "chrome://settings/languages"), let doc = state.doc.windows[window] else { return }
            if doc.kind == .standard { _ = openTab(url, inSpace: doc.space, window: window, focus: true) } else { openScratchTab(url, in: window, focus: true) }
            return
        case .previewHover(let inside):
            if inside { state.session.ai.previewHeld.insert(window) } else {
                state.session.ai.previewHeld.remove(window)
                if state.session.ai.hover[window] == nil { closePreview(in: window) }
            }
            return
        case .sharePreview:
            guard let url = state.session.ai.previews[window]?.url else { return }
            effects.append(.copyToPasteboard(url.absoluteString))
            toast("Copied Link to Clipboard", in: window)
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
            // The other modes' bars only lead to their feature: off, the person is told where to switch it on first.
            if let feature = mode.feature, !aiEnabled(feature, window) { return }
            openOverlay({ .commandBar(openID: $0, target: .ai(mode)) }, in: window)
            return
        }
        switch intent {
        case .ask(let question):
            guard aiEnabled(.commandBar, window), let q = aiQuestion(question) else { return }
            askAgent(q, choice: state.doc.settings.max.provider, in: window)
        case .askAgent(let question, let agent):
            guard aiEnabled(.commandBar, window), let q = aiQuestion(question) else { return }
            guard state.doc.settings.max.provider != .off, let kind = agent.kind, state.session.detectedAI.contains(kind) else {
                aiMessage("\(agent.rawValue.capitalized) is not available on this Mac. Nothing was sent.", in: window); return
            }
            askAgent(q, choice: agent, in: window)
        case .followUp(let text):
            guard let q = aiQuestion(text) else { return }
            followUp(q, in: window)
        case .chooseFolder:
            guard aiEnabled(.commandBar, window) else { return }
            effects.append(.aiChooseFolder(window))
        case .askPage(let question):
            guard aiEnabled(.askPage, window), let q = aiQuestion(question) else { return }
            readActiveAI(.askPage(q), title: q, in: window)
        case .translate(let language):
            guard aiEnabled(.translation, window), let language = aiQuestion(language), language.count <= 60,
                  let page = state.findPage(in: window) else { return }
            translatePage(page, to: language, in: window)
        case .organizeToday:
            // Arc's 🧹 Tidy on the Today divider (P46-b): the result is tab groups in Today and an undo toast.
            guard state.doc.settings.max.tidyOn, let space = state.doc.windows[window]?.space else {
                let text = state.doc.settings.max.isOn ? "Enable Tidy Tabs in Settings → Max." : Self.maxOff
                toast(text, link: ToastLink(title: "Max Preferences ↗", command: .settings(.openPane(.max))), in: window); return
            }
            let tabs = eligibleAITabs(space, in: window)
            guard tabs.count >= 2, tabs.count <= 50 else { toast("Tidy needs 2–50 ungrouped Today tabs.", in: window); return }
            _ = startAI(.tidyToday(space, tabs: tabs), purpose: .organize, title: "Organize Today Tabs", window: window)
            state.session.ai.tidying.insert(window)
        case .instant(let query):
            guard aiEnabled(.instantLinks, window), let q = aiQuestion(query) else { return }
            // Arc (P48-a): the command bar closes and "Searching the web for you…" heads Today while Max looks; the
            // proposed pages are verified by request-owned pages in this browsing context before they open.
            let id = startAI(.instant(q), purpose: .instant(q), title: "Instant Link: " + q, window: window)
            state.session.ai.requests[id]?.hidden = []
            if state.doc.windows[window]?.kind == .standard {
                state.session.ai.instantRows[window, default: []].insert(AIInstantRow(id: ItemID(Self.instantRowPrefix + id.rawValue), request: id), at: 0)
            }
        case .browse(let question, let sources):
            guard aiEnabled(.browse, window) else { return }
            guard let q = aiQuestion(question), (1...4).contains(sources.count),
                  Set(sources).count == sources.count, sources.allSatisfy({ AIValidation.destination($0.absoluteString) != nil }) else {
                aiMessage("Browse for Me needs a question and 1–4 HTTP(S) source URLs. Enter: question | URL, URL", in: window); return
            }
            let id = startAI(.ask(q), purpose: .browse(q), title: q, window: window, run: false)
            makeAIHidden(id, urls: sources)
        case .nameFolder(let folder): nameFolder(folder, in: window)
        case .acceptSuggestion(let tab): acceptSuggestion(tab, in: window)
        case .dismissSuggestion(let tab): state.session.ai.basic.suggestions[tab] = nil
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
        if !state.doc.settings.max.isOn { return Self.maxOff }
        if !state.doc.settings.max.enabled(.commandBar) { return "\(AIFeature.commandBar.title) not enabled" }
        return nil
    }
    static let maxOff = "Max is off. Turn it on in Settings → Max."
    /// Off, the feature says how to turn it on and where its switch is (the Max pane, or Advanced → More Settings… for
    /// Brk's own three): in the answer panel for the panel's features, as a notice for the ones that work in place
    /// (preview card, Today row, the page itself).
    private mutating func aiEnabled(_ feature: AIFeature, _ window: WindowID) -> Bool {
        guard state.doc.settings.max.enabled(feature) else {
            let max = state.doc.settings.max.isOn
            // "… → More Settings…" already ends the sentence.
            let place = feature.place
            let text = max ? "Enable \(feature.title) in \(place)" + (place.hasSuffix("…") ? "" : ".") : Self.maxOff
            let pane = max ? feature.pane : .max
            if [.instantLinks, .translation, .linkPreviews].contains(feature) {
                toast(text, link: ToastLink(title: pane == .max ? "Max Preferences ↗" : "Advanced Settings ↗", command: .settings(.openPane(pane))), in: window)
            } else { aiMessage(text, in: window) }
            return false
        }
        return true
    }
    private mutating func aiMessage(_ text: String, in window: WindowID) {
        state.session.ai.answerContexts[window] = state.libraryContext(in: window)
        state.session.ai.answers[window] = AIAnswerSnapshot(request: nil, title: "Max", text: text, busy: false, sources: [])
    }
    /// A new request replaces the window's earlier one of the same slot (one answer, one preview, one translation,
    /// one tidy); Instant Links searches run side by side, one Today row each. Only the panel's purposes write the
    /// answer panel.
    private mutating func startAI(_ task: AITask, purpose: AIPurpose, title: String, window: WindowID, run: Bool = true, seconds: Int = 120) -> AIRequestID {
        if purpose.slot != .instant { cancelAI(in: window, slot: purpose.slot) }
        let id = AIRequestID(ctx.newID())
        state.session.ai.requests[id] = AIRequest(window: window, context: state.libraryContext(in: window), task: task, purpose: purpose)
        if purpose != .barTranslation { state.session.ai.answerContexts[window] = state.libraryContext(in: window) }
        if !purpose.inPlace {
            state.session.ai.answers[window] = AIAnswerSnapshot(request: id, title: title, text: run ? Self.waiting : "Reading the selected page…", busy: true, sources: [])
        }
        if purpose != .barTranslation { state.session.windows[window]?.overlay = nil }
        effects.append(.aiWatch(id, seconds: seconds))
        if run { sendAI(id, task: task) }
        return id
    }
    /// A read-only panel turn's ceiling: the panel has Stop, and an agent writing a long answer is not stuck. A turn in
    /// a folder has none; a command the user allowed may run for as long as it needs.
    private static let panelSeconds = 300
    /// A question in the panel to `choice`'s agent, read-only; its follow-ups stay with that agent.
    private mutating func askAgent(_ q: String, choice: AIProviderChoice, in window: WindowID) {
        let id = startAI(.ask(q), purpose: .answer, title: q, window: window, run: false, seconds: Self.panelSeconds)
        openConversation(id, in: window)
        sendAI(id, task: .ask(q), choice: choice)
    }
    /// The request becomes the first turn of a conversation: its session stays for follow-ups, with tools off.
    private mutating func openConversation(_ id: AIRequestID, in window: WindowID) {
        state.session.ai.answers[window]?.conversation = AIConversationSnapshot(id: id)
        state.session.ai.turnText[id] = 0
        effects.append(.aiOpenConversation(id, folder: nil, choice: state.doc.settings.max.provider))
    }
    /// The next message in the panel's conversation. One turn at a time: the panel offers Stop while one runs.
    private mutating func followUp(_ q: String, in window: WindowID) {
        guard var answer = state.session.ai.answers[window], var conversation = answer.conversation, !conversation.ended, !answer.busy else { return }
        let turn = AIRequestID(ctx.newID())
        state.session.ai.requests[turn] = AIRequest(window: window, context: state.libraryContext(in: window), task: .ask(q), purpose: .followUp)
        state.session.pendingAI[turn] = .ask(q)
        conversation.items.append(.user(q))
        state.session.ai.turnText[conversation.id] = 0
        answer.conversation = conversation
        answer.request = turn
        answer.busy = true
        answer.text = Self.waiting
        state.session.ai.answers[window] = answer
        if conversation.folder == nil { effects.append(.aiWatch(turn, seconds: Self.panelSeconds)) }
        effects.append(.aiTurn(conversation: conversation.id, turn: turn, .ask(q)))
    }
    /// The user chose a folder: a new session with tools on and approvals on, waiting for the first message. Home and
    /// the disk's root are refused; a coding session needs a folder that holds one project.
    mutating func aiFolderChosen(_ folder: String?, in window: WindowID) {
        guard let folder, state.doc.windows[window] != nil, state.doc.windows[window]?.kind != .incognito else { return }
        if let refusal = AIValidation.workingFolderRefusal(folder, home: NSHomeDirectory()) { toast(refusal, in: window); return }
        cancelAI(in: window, slot: .panel)
        let id = AIRequestID(ctx.newID())
        var conversation = AIConversationSnapshot(id: id, folder: folder)
        conversation.items = [.notice("Working in \(folder). Tools are on; the agent asks here before it runs a command or changes a file.")]
        state.session.ai.answerContexts[window] = state.libraryContext(in: window)
        state.session.ai.answers[window] = AIAnswerSnapshot(request: nil, title: (folder as NSString).lastPathComponent, text: "", busy: false, sources: [], conversation: conversation)
        state.session.ai.turnText[id] = 0
        state.session.windows[window]?.overlay = nil
        effects.append(.aiOpenConversation(id, folder: folder, choice: state.doc.settings.max.provider))
    }
    private func conversationWindow(_ id: AIRequestID) -> WindowID? {
        state.session.ai.answers.first { $0.value.conversation?.id == id }?.key
    }
    mutating func aiConversation(_ id: AIRequestID, _ event: AIConversationEvent) {
        guard let window = conversationWindow(id), var conversation = state.session.ai.answers[window]?.conversation else { return }
        switch event {
        case .started(let agent, let name, let model, let effort):
            conversation.agent = agent; conversation.agentName = name; conversation.model = model; conversation.effort = effort
        case .step(let step, let turn):
            guard state.session.ai.answers[window]?.request == turn else { return }
            if let index = conversation.items.firstIndex(where: { if case .step(let s) = $0 { s.id == step.id } else { false } }) {
                conversation.items[index] = .step(step)
            } else {
                holdTurnText(conversation.id, in: window)
                conversation.items.append(.step(step))
            }
        case .approval(let approval, let turn):
            guard state.session.ai.answers[window]?.request == turn else { return }
            holdTurnText(conversation.id, in: window)
            conversation.items.append(.approval(approval))
        case .approvalClosed(let approval):
            conversation.items = conversation.items.compactMap {
                if case .approval(let a) = $0, a.id == approval, a.answer == nil { nil } else { $0 }
            }
        case .notice(let text): conversation.items.append(.notice(text))
        }
        state.session.ai.answers[window]?.conversation = conversation
    }
    /// A step or approval follows the text so far: the turn's later text goes into a new row under it.
    private mutating func holdTurnText(_ id: AIRequestID, in window: WindowID) {
        guard let answer = state.session.ai.answers[window], answer.busy, case .assistant? = answer.conversation?.items.last,
              answer.request.flatMap({ state.session.pendingAI[$0] }) != nil else { return }
        let shown = answer.text == Self.waiting ? 0 : answer.text.count
        state.session.ai.turnText[id] = shown
    }
    private mutating func answerApproval(_ approval: String, option: String, in window: WindowID) {
        guard var conversation = state.session.ai.answers[window]?.conversation, !conversation.ended,
              let index = conversation.items.firstIndex(where: { if case .approval(let a) = $0 { a.id == approval && a.answer == nil } else { false } }),
              case .approval(var value) = conversation.items[index], value.options.contains(where: { $0.id == option }) else { return }
        value.answer = option
        conversation.items[index] = .approval(value)
        state.session.ai.answers[window]?.conversation = conversation
        effects.append(.aiApprove(conversation: conversation.id, approval: approval, option: option))
    }
    /// The turn's text so far, minus what rows above the last step already show.
    private mutating func showTurnText(_ text: String, in window: WindowID) {
        guard var conversation = state.session.ai.answers[window]?.conversation else { return }
        let rest = String(text.dropFirst(state.session.ai.turnText[conversation.id] ?? 0))
        if case .assistant? = conversation.items.last { conversation.items[conversation.items.count - 1] = .assistant(rest) }
        else if !rest.isEmpty { conversation.items.append(.assistant(rest)) }
        state.session.ai.answers[window]?.conversation = conversation
    }
    mutating func aiAgents(_ statuses: [AIAgentStatus]) {
        for status in statuses { state.session.ai.agents[status.kind] = status }
    }
    private mutating func sendAI(_ id: AIRequestID, task: AITask, choice: AIProviderChoice? = nil) {
        state.session.pendingAI[id] = task
        state.session.ai.requests[id]?.task = task
        effects.append(.ai(id, task, choice: choice ?? state.doc.settings.max.provider))
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

    /// Arc's Translate to English (the page menu, P50-b) and the popover's Choose Another Language: the page's text is
    /// replaced in place; nothing else opens. A page that shows its own text again after Use Original gets the same
    /// translation back without asking the tool again.
    mutating func translatePage(_ page: PageID, to language: String, in window: WindowID) {
        guard state.doc.windows[window]?.kind != .incognito else { toast("AI page features are unavailable in private windows.", in: window); return }
        guard state.doc.settings.max.enabled(.translation) else { _ = aiEnabled(.translation, window); return }
        guard let live = state.session.live[page], case .ready(let document) = live.document,
              live.requestContext == state.libraryContext(in: window) else {
            toast("Wait for this page to finish loading, then retry.", in: window); return
        }
        if case .profile(let profile) = state.browsingContext(of: page.item), let exclusions = state.doc.settings.max.translationExclusions?[profile] {
            let source = state.session.ai.translations[page]?.source ?? live.language.map(AILanguages.base) ?? ""
            let host = state.address(of: page.item, in: window, for: .visible)?.host?.lowercased() ?? ""
            if exclusions.languages.contains(source) || exclusions.sites.contains(host) {
                toast("This profile never translates this language or site. Change the choice in Settings → Max.", in: window); return
            }
        }
        if let translation = state.session.ai.translations[page], translation.document == document, translation.target == language {
            if !translation.showingTranslation { showTranslation(page, true) }
            return
        }
        let id = startAI(.ask("Translate to " + language), purpose: .translate(language), title: "Translate to " + language, window: window, run: false)
        state.session.ai.requests[id]?.document = document
        state.session.ai.requests[id]?.page = page
        effects.append(.aiRead(id, document))
    }

    /// Swaps the page between its translation and its own text (the isolated world keeps both); ⌘Z after Use
    /// Original comes back here with `translated` true.
    mutating func showTranslation(_ page: PageID, _ translated: Bool) {
        guard var translation = state.session.ai.translations[page], state.session.live[page]?.document == .ready(translation.document) else { return }
        translation.showingTranslation = translated
        state.session.ai.translations[page] = translation
        effects.append(.aiShowTranslation(translation.document, translated: translated))
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
        // Time to load and read the pages; real pages take longer than fixtures, and a card that says it is reading
        // costs nothing. The tool's answer gets its own time after this.
        effects.append(.aiWatch(id, seconds: request.purpose.isPreview ? 15 : 30))
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
            // Instant Links drops a result that does not load and keeps the others.
            if case .instant = request.purpose {
                state.session.ai.requests[id]?.hidden.removeAll { $0.id == token.page }
                if state.session.ai.requests[id]?.hidden.isEmpty == true {
                    let opened = state.session.ai.instantRows[request.window]?.first { $0.request == id }?.opened.isEmpty == false
                    completeAI(id, text: "Oops, something went wrong.", success: opened)
                }
                return true
            }
            completeAI(id, text: "This source is unavailable. Check its address or sign in in a normal tab, then retry.")
        default: break
        }
        return true
    }
    private mutating func aiHiddenReady(_ id: AIRequestID, document: DocumentToken) {
        // A reader that moved on to a new document (a redirect by script, a reload) is read again; the read of the old
        // one fails or is ignored.
        guard let r = state.session.ai.requests[id], r.hiddenDocuments[document.browser.page] != document else { return }
        state.session.ai.requests[id]?.hiddenDocuments[document.browser.page] = document
        state.session.ai.requests[id]?.extracting.insert(document.browser.page)
        effects.append(.aiRead(id, document))
    }

    mutating func aiReadResult(_ id: AIRequestID, page: PageID, content: AIPageContent?) {
        if let request = state.session.ai.requests[id], request.document == nil {
            // A reader's read: only the one still wanted counts, and only once.
            guard request.hidden.contains(where: { $0.id == page }), let current = request.hiddenDocuments[page] else { return }
            if let content, content.document != current { return }
            // A busy machine can drop one read of a page that is fine: it gets a second.
            if content == nil, !request.readAgain.contains(page) {
                state.session.ai.requests[id]?.readAgain.insert(page)
                effects.append(.aiRead(id, current))
                return
            }
        }
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
            openConversation(id, in: request.window)
            effects.append(.aiWatch(id, seconds: Self.panelSeconds))
            sendAI(id, task: .pageQuestion(question, content))
        case .translate(let target):
            guard case .profile(let profile) = request.context else { return }
            let exclusions = state.doc.settings.max.translationExclusions?[profile] ?? AITranslationExclusions()
            let language = AILanguages.base(content.language.isEmpty ? state.session.live[page]?.language ?? "" : content.language)
            if exclusions.languages.contains(language) || exclusions.sites.contains(content.url.host?.lowercased() ?? "") {
                completeAI(id, text: "This profile never translates this language or site. Change the choice in Settings → Max."); return
            }
            guard !content.nodes.isEmpty else { completeAI(id, text: "No visible text is available to translate."); return }
            sendAI(id, task: .translate(target: target, content: content))
        case .preview:
            state.session.ai.requests[id]?.hidden = []
            // Reading the link had its own few seconds; the tool's answer gets its own time (a real agent takes 2 to
            // 6 seconds to answer, and more when its account is busy).
            effects.append(.aiWatch(id, seconds: 60))
            sendAI(id, task: .summarize(content))
        case .instant:
            // A real main-frame ready document establishes reachability using the original context: the page opens
            // as a Today tab under the row (several results open in the tool's order, the first one shown), and the
            // row goes once every result has answered.
            state.session.ai.requests[id]?.hidden.removeAll { $0.id == page }
            openInstantResult(content.url, request: id, in: request.window)
            if state.session.ai.requests[id]?.hidden.isEmpty == true { completeAI(id, text: "Opened " + content.url.absoluteString, success: true) }
        case .browse(let question):
            guard request.contents.count == request.hidden.count else { return }
            let pages = request.hidden.compactMap { request.contents[$0.id] }
            state.session.ai.requests[id]?.hidden = []
            state.session.ai.answers[request.window]?.sources = pages.map { AISource(title: $0.title, url: $0.url) }
            openConversation(id, in: request.window)
            effects.append(.aiWatch(id, seconds: Self.panelSeconds))
            sendAI(id, task: .browse(question, pages))
        default: break
        }
    }

    mutating func aiResult(_ id: AIRequestID, _ outcome: AIOutcome) {
        guard let task = state.session.pendingAI.removeValue(forKey: id) else { return }
        let background = state.session.ai.backgroundWindows.removeValue(forKey: id)
        if let context = state.session.ai.backgroundContexts.removeValue(forKey: id), backgroundAIContext(task) != context {
            basicFailed(id, task, "The tab or download changed.", in: nil)
            return
        }
        func fail(_ reason: String) {
            completeAI(id, text: reason)
            backgroundFailed(task, reason, in: background)
            basicFailed(id, task, reason, in: background)
        }
        switch outcome {
        case .unavailable: fail("No selected local AI tool is available. Choose an installed provider in Settings → Max and sign in to it in Terminal.")
        case .failed(let reason): fail(reason)
        case .text(let text):
            // Only a conversation answers in prose; a basic task always comes back in its schema.
            guard !task.isBasic else { fail(Self.wrongShape); return }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { fail("The AI tool returned no answer. Check its sign-in in Terminal, then retry."); return }
            switch task {
            case .browse(_, let pages):
                let answer = String(text.prefix(60_000))
                guard AIValidation.citations(answer, sourceCount: pages.count) else {
                    completeAI(id, text: "The tool did not cite the selected sources correctly. Retry Browse for Me or open the sources below."); return
                }
                completeAI(id, text: answer, answered: true)
            default:
                completeAI(id, text: String(text.prefix(60_000)), success: true, answered: true)
            }
        case .reply(let reply):
            if let reason = basicReply(id, task, reply, background: background) { fail(reason) }
        }
    }
    static let wrongShape = "The AI tool's answer did not match what Brk asked for. Nothing was changed."

    /// A basic task's answer, already in its schema's shape; checked against the browser before anything changes.
    /// Returns why it failed, for the caller to say; nil when the answer was applied or quietly dropped.
    private mutating func basicReply(_ id: AIRequestID, _ task: AITask, _ reply: AIReply, background: WindowID?) -> String? {
        switch (task, reply) {
        case (.renameTab(let tab, _, let url), .text(let text)):
            guard let title = AIValidation.name(text, limit: 60), let scope = state.locate(tab), state.tab(tab)?.pinnedURL == url, state.tab(tab)?.customTitle == nil else { return nil }
            state.withTree(scope) { $0.updateTab(tab) { $0.customTitle = title } }
        case (.renameDownload(let download, let original), .text(let text)):
            guard let value = state.doc.downloads.first(where: { $0.id == download }), value.state == .finished,
                  value.filename == original, let path = value.path,
                  let name = AIValidation.filename(text, original: original) else {
                return "The tool returned an unsafe filename, or the download changed. No file was renamed."
            }
            if let background { state.session.ai.renamingDownloads[download] = background }
            effects.append(.aiRenameDownload(download, originalPath: path, filename: name))
        case (.instant, .links(let links)):
            let urls = AIValidation.destinations(links)
            guard !urls.isEmpty else { completeAI(id, text: "The tool did not propose a safe web address."); return nil }
            makeAIHidden(id, urls: urls)
        case (.tidyToday(let space, let tabs), .groups(let groups)):
            guard let request = state.session.ai.requests[id], eligibleAITabs(space, in: request.window) == tabs,
                  let plan = AIValidation.plan(groups, eligible: tabs) else { completeAI(id, text: "The plan was invalid or Today changed. No tabs were moved. Retry Organize Today Tabs."); return nil }
            applyAIOrganize(id, space: space, tabs: tabs, plan: plan)
        case (.translate(_, let content), .translation(let nodes)):
            guard nodes.count == content.nodes.count, Set(nodes.map(\.id)).count == nodes.count,
                  Set(nodes.map(\.id)) == Set(content.nodes.map(\.id)), nodes.allSatisfy({ $0.text.count <= 4000 }),
                  state.session.ai.requests[id] != nil else { completeAI(id, text: "The tool returned an invalid translation. The page was left unchanged."); return nil }
            state.session.ai.requests[id]?.translated = nodes
            effects.append(.aiTranslate(id, content, nodes))
        case (.summarize, .preview(let answer)):
            guard let request = state.session.ai.requests[id], state.session.ai.previews[request.window]?.request == id else { completeAI(id, text: ""); return nil }
            guard let card = AIValidation.preview(answer), card.blocked != true else { completeAI(id, text: AICopy.noPreview); return nil }
            state.session.ai.previews[request.window]?.title = card.quickSummary ?? ""
            state.session.ai.previews[request.window]?.details = card.details ?? []
            completeAI(id, text: "", success: true)
        case (.translateText, .text(let text)):
            completeAI(id, text: String(text.prefix(60_000)), success: true, answered: true)
        case (.nameTabs, .tabNames(let names)): applyTabNames(id, names)
        case (.nameFolder, .text(let name)): applyFolderName(id, name, in: background)
        case (.decide(let request, _), .decision(let answers)):
            guard request.accepts(answers) else { return Self.wrongShape }
            applyDecision(id, answers)
        default: return Self.wrongShape
        }
        return nil
    }
    /// Tidy Tab Titles and Tidy Downloads run in the background: a failure says so in the window it came from, or the
    /// person would never learn why nothing was renamed.
    private mutating func backgroundFailed(_ task: AITask, _ reason: String, in window: WindowID?) {
        guard let window, state.doc.windows[window] != nil else { return }
        let feature = switch task {
        case .renameTab: "Tidy Tab Titles"
        case .renameDownload: AIFeature.downloadRename.title
        default: ""
        }
        guard !feature.isEmpty else { return }
        toast("\(feature): \(reason)", in: window)
    }
    mutating func aiPartial(_ id: AIRequestID, _ text: String) {
        guard let request = state.session.ai.requests[id], state.session.pendingAI[id] != nil else { return }
        switch request.task {
        case .ask, .pageQuestion, .browse:
            // The bar's row shows the finished answer; the answer panel is someone else's.
            guard !request.purpose.inPlace, state.session.ai.answers[request.window]?.request == id else { return }
            state.session.ai.answers[request.window]?.text = String(text.prefix(60_000))
            showTurnText(String(text.prefix(60_000)), in: request.window)
        default: break
        }
    }
    mutating func aiDeadline(_ id: AIRequestID) {
        guard state.session.ai.requests[id] != nil else { return }
        completeAI(id, text: "The source or AI tool did not answer in time. The request was stopped; retry or use ordinary search.")
    }
    mutating func aiTranslated(_ id: AIRequestID, success: Bool) {
        if success, let request = state.session.ai.requests[id], let page = request.page, let document = request.document,
           case .translate(let target) = request.purpose, state.session.live[page]?.document == .ready(document) {
            // The page's own language stays the first translation's (Choose Another Language translates the
            // translation; Use Original still brings the page's own text back).
            let earlier = state.session.ai.translations[page].flatMap { $0.document == document ? $0.source : nil }
            // A page that declares no language: what its text was recognized as (`PageEvent.languageDetected`).
            let declared = request.contents[page]?.language ?? ""
            let source = earlier ?? AILanguages.base(declared.isEmpty ? state.session.live[page]?.language ?? "" : declared)
            state.session.ai.translations[page] = AIPageTranslation(document: document, source: source, target: target, showingTranslation: true)
        }
        completeAI(id, text: success ? "Page translated. Controls and page structure were preserved. Reload to restore the original text." : "The document or text changed. Translation was not applied; reload and retry.", success: success)
    }
    private static let cancelled = "Request cancelled."
    private static let waiting = "Waiting for the local AI tool…"
    static let instantRowPrefix = "instant-"
    /// `success`: the in-place purposes' good ending (their result is already applied); otherwise `text` says what
    /// went wrong, in the panel, on the preview card, as the Today row's "Oops, something went wrong." or a notice.
    private mutating func completeAI(_ id: AIRequestID, text: String, success: Bool = false, answered: Bool = false) {
        guard let request = state.session.ai.requests.removeValue(forKey: id) else { return }
        state.session.pendingAI[id] = nil
        effects.append(.aiCancel(id))
        if request.purpose.inPlace { finishInPlace(id, request, text: text, success: success); return }
        guard state.session.ai.answers[request.window]?.request == id else { return }
        state.session.ai.answers[request.window]?.text = text
        state.session.ai.answers[request.window]?.busy = false
        state.session.ai.answers[request.window]?.request = nil
        guard var conversation = state.session.ai.answers[request.window]?.conversation else { return }
        // An approval the agent still waits for goes with the turn.
        conversation.items.removeAll { if case .approval(let a) = $0 { a.answer == nil } else { false } }
        state.session.ai.answers[request.window]?.conversation = conversation
        // The answer's text; otherwise what went wrong goes under whatever the agent had written.
        if answered { showTurnText(text, in: request.window) }
        else { state.session.ai.answers[request.window]?.conversation?.items.append(.notice(text == Self.cancelled ? "Stopped." : text)) }
    }
    private mutating func finishInPlace(_ id: AIRequestID, _ request: AIRequest, text: String, success: Bool) {
        let window = request.window
        switch request.purpose {
        case .preview:
            guard state.session.ai.previews[window]?.request == id else { return }
            state.session.ai.previews[window]?.busy = false
            state.session.ai.previews[window]?.request = nil
            if !success { state.session.ai.previews[window]?.failure = text }
        case .instant:
            guard let index = state.session.ai.instantRows[window]?.firstIndex(where: { $0.request == id }) else { return }
            if success || text == Self.cancelled || state.session.ai.instantRows[window]![index].opened.count > 0 {
                state.session.ai.instantRows[window]!.remove(at: index)
                if state.session.ai.instantRows[window]!.isEmpty { state.session.ai.instantRows[window] = nil }
            } else {
                state.session.ai.instantRows[window]![index].failed = true
                // The row keeps Arc's words; why it failed (the agent signed out, no answer in time) goes beside it.
                if text != AICopy.instantFailed { toast("Instant Links: " + text, in: window) }
            }
        case .translate:
            if !success, text != Self.cancelled { toast(text, in: window) }
        case .organize:
            state.session.ai.tidying.remove(window)
            if !success, text != Self.cancelled { toast(text, in: window) }
        case .barTranslation:
            guard state.session.windows[window]?.barTranslationRequest == id else { return }
            state.session.windows[window]?.barTranslationRequest = nil
            if success { state.session.windows[window]?.barTranslation?.answer = text.trimmingCharacters(in: .whitespacesAndNewlines) }
            else if text != Self.cancelled { state.session.windows[window]?.barTranslation?.failure = text }
        case .answer, .askPage, .browse, .followUp: break
        }
    }

    // MARK: The `translate` prefix

    /// The text changed: whatever was asking stops at once, and the row waits for a pause in typing.
    mutating func barTranslationText(_ text: String, in window: WindowID) {
        guard state.session.windows[window]?.barTranslation?.text != text else { return }
        cancelAI(in: window, slot: .bar)
        state.session.windows[window]?.barTranslationRequest = nil
        guard !text.isEmpty, case .text(_, let target)? = QuickTranslation.parse(text) else {
            state.session.windows[window]?.barTranslation = nil
            return
        }
        state.session.windows[window]?.barTranslation = BarTranslation(text: text, target: target)
        effects.append(.barTranslationDue(window, text))
    }

    mutating func barTranslationDue(_ window: WindowID, _ text: String) {
        guard case .commandBar(_, .newTab)? = state.session.windows[window]?.overlay, let current = state.session.windows[window]?.barTranslation, current.text == text,
              current.answer == nil, current.failure == nil, state.session.windows[window]?.barTranslationRequest == nil,
              state.doc.windows[window]?.kind != .incognito, state.doc.settings.max.enabled(.translation),
              case .text(let source, let target)? = QuickTranslation.parse(text), source.count <= 2000 else { return }
        let request = startAI(.translateText(source, target: target), purpose: .barTranslation, title: source, window: window)
        state.session.windows[window]?.barTranslationRequest = request
    }

    /// The bar went away, by whatever command: its translation stops too.
    mutating func cancelBarTranslationsWithNoBar() {
        let asking = state.session.ai.requests.values.filter { $0.purpose == .barTranslation }.map(\.window)
        for window in Set(asking) {
            if case .commandBar(_, .newTab)? = state.session.windows[window]?.overlay { continue }
            cancelAI(in: window, slot: .bar)
        }
    }

    private mutating func cancelAI(in window: WindowID, slot: AIPurpose.Slot) {
        let ids = state.session.ai.requests.filter { $0.value.window == window && $0.value.purpose.slot == slot }.map(\.key)
        for id in ids { completeAI(id, text: Self.cancelled) }
    }
    /// Opens a verified Instant Links result as a Today tab under the window's rows (an ephemeral window: in its own
    /// container); the first result is shown.
    private mutating func openInstantResult(_ url: URL, request id: AIRequestID, in window: WindowID) {
        guard let doc = state.doc.windows[window] else { return }
        let index = state.session.ai.instantRows[window]?.firstIndex { $0.request == id }
        let count = index.map { state.session.ai.instantRows[window]![$0].opened.count } ?? 0
        let tab: ItemID?
        if doc.kind == .standard { tab = openTab(url, inSpace: doc.space, window: window, focus: count == 0, at: count) }
        else { openScratchTab(url, in: window, focus: count == 0); tab = nil }
        if let index, let tab { state.session.ai.instantRows[window]![index].opened.append(tab) }
    }
    /// The × on an Instant Links row ("Oops, something went wrong." or still searching): the row goes and its search
    /// stops. True when every target was such a row.
    mutating func closeInstantRows(_ ids: [ItemID], in window: WindowID) -> Bool {
        guard !ids.isEmpty, let rows = state.session.ai.instantRows[window], ids.allSatisfy({ id in rows.contains { $0.id == id } }) else { return false }
        for row in rows where ids.contains(row.id) {
            if state.session.ai.requests[row.request] != nil { completeAI(row.request, text: Self.cancelled) }
            state.session.ai.instantRows[window]?.removeAll { $0.id == row.id }
        }
        if state.session.ai.instantRows[window]?.isEmpty == true { state.session.ai.instantRows[window] = nil }
        return true
    }
    private mutating func closePreview(in window: WindowID) {
        for (id, request) in state.session.ai.requests where request.window == window && request.purpose.slot == .preview { completeAI(id, text: Self.cancelled) }
        state.session.ai.previews[window] = nil
        state.session.ai.previewHeld.remove(window)
    }
    mutating func reconcileAI(from previous: AppState) {
        let providerChanged = previous.doc.settings.max.provider != state.doc.settings.max.provider
        // Max's Tidy Tab Titles: a Today tab that became Pinned by any route (Pin Tab, a drag into Pinned, a move from
        // the menu) asks for its tidier title; Arc renames a tab dragged into Pinned within a few seconds (P47-a).
        if state.doc.settings.max.titlesOn {
            let asked = Set(state.session.pendingAI.values.compactMap { if case .renameTab(let tab, _, _) = $0 { tab } else { nil } })
            for tab in state.doc.tree.allTabs() where !asked.contains(tab) && state.role(of: tab)?.kind == .pinned && previous.role(of: tab)?.kind == .today {
                guard let window = state.doc.windows.first(where: { state.displayedTab(tab, in: $0.key) != nil })?.key,
                      let t = state.displayedTab(tab, in: window), let url = state.tab(tab)?.pinnedURL ?? t.url, t.customTitle == nil else { continue }
                requestAI(.renameTab(tab, title: t.displayTitle, url: url), from: window)
            }
        }
        for (id, task) in state.session.pendingAI where state.session.ai.requests[id] == nil {
            let valid: Bool
            switch task {
            case .renameTab(let tab, _, let url): valid = state.doc.settings.max.titlesOn && state.session.ai.backgroundContexts[id] == backgroundAIContext(task) && state.tab(tab)?.pinnedURL == url && state.tab(tab)?.customTitle == nil && (state.role(of: tab)?.kind == .pinned || state.role(of: tab)?.kind == .favorites)
            case .renameDownload(let download, _): valid = state.doc.settings.max.enabled(.downloadRename) && state.session.ai.backgroundContexts[id] == backgroundAIContext(task) && state.doc.downloads.contains { $0.id == download && $0.state == .finished && state.doc.profiles[$0.profile] != nil }
            case .nameTabs: valid = state.doc.settings.max.enabled(.tabNames)
            case .nameFolder(let folder, _): valid = state.doc.settings.max.enabled(.folderNames) && state.doc.tree[folder] != nil
            case .decide(_, let feature): valid = state.doc.settings.max.enabled(feature)
            default: valid = true
            }
            if !valid || providerChanged {
                state.session.pendingAI[id] = nil; state.session.ai.backgroundContexts[id] = nil; state.session.ai.backgroundWindows[id] = nil
                effects.append(.aiCancel(id))
            }
        }
        for (id, request) in state.session.ai.requests {
            let ownerExists = state.doc.windows[request.window] != nil
            let sameContext = state.libraryContext(in: request.window) == request.context
            let sameDocument = request.document.map { document in
                state.session.live[document.browser.page]?.document == .ready(document) && (request.page != nil || state.findPage(in: request.window) == document.browser.page)
            } ?? true
            let featureEnabled: Bool = switch request.purpose {
            case .answer:
                if case .renameDownload = request.task { state.doc.settings.max.enabled(.downloadRename) }
                else { state.doc.settings.max.enabled(.commandBar) }
            case .followUp: [AIFeature.commandBar, .askPage, .browse].contains { state.doc.settings.max.enabled($0) }
            case .askPage: state.doc.settings.max.enabled(.askPage)
            case .preview: state.doc.settings.max.enabled(.linkPreviews)
            case .instant: state.doc.settings.max.enabled(.instantLinks)
            case .browse: state.doc.settings.max.enabled(.browse)
            case .translate, .barTranslation: state.doc.settings.max.enabled(.translation)
            case .organize: state.doc.settings.max.tidyOn
            }
            if !ownerExists || !sameContext || !sameDocument || !featureEnabled || providerChanged { completeAI(id, text: "The page or browsing context changed. Request cancelled.") }
        }
        for window in Set(state.session.ai.answers.keys).union(state.session.ai.undo.keys).union(state.session.ai.hover.keys).union(state.session.ai.answerContexts.keys)
            .union(state.session.ai.previews.keys).union(state.session.ai.instantRows.keys)
            where state.doc.windows[window] == nil || (state.session.ai.answerContexts[window] != nil && state.session.ai.answerContexts[window] != state.libraryContext(in: window)) {
            state.session.ai.answerContexts[window] = nil
            state.session.ai.answers[window] = nil; state.session.ai.undo[window] = nil; state.session.ai.hover[window] = nil; state.session.ai.hoverDocuments[window] = nil
            state.session.ai.previews[window] = nil; state.session.ai.previewHeld.remove(window); state.session.ai.instantRows[window] = nil
            state.session.ai.tidying.remove(window)
        }
        // A conversation that left the panel takes its session and every process it started with it. Another agent
        // chosen ends the one on screen; its transcript stays to read.
        let shown = Set(state.session.ai.answers.values.compactMap { $0.conversation?.id })
        for answer in previous.session.ai.answers.values {
            if let id = answer.conversation?.id, !shown.contains(id) {
                effects.append(.aiCloseConversation(id)); state.session.ai.turnText[id] = nil
            }
        }
        if providerChanged {
            for (window, answer) in state.session.ai.answers {
                guard let id = answer.conversation?.id, answer.conversation?.ended == false else { continue }
                state.session.ai.answers[window]?.conversation?.ended = true
                state.session.ai.answers[window]?.conversation?.items.append(.notice("Max's agent changed. Ask again to talk to the new one."))
                effects.append(.aiCloseConversation(id))
            }
        }
        // A translation belongs to one document: a reload or a new page shows the page's own text.
        for (page, translation) in state.session.ai.translations where state.session.live[page]?.document != .ready(translation.document) {
            state.session.ai.translations[page] = nil
        }
        reconcileBasic(from: previous)
        // Rows whose search is gone (a cancelled request) go with it; failed rows stay until their × is clicked.
        for (window, rows) in state.session.ai.instantRows {
            let kept = rows.filter { $0.failed || state.session.ai.requests[$0.request] != nil }
            if kept != rows { state.session.ai.instantRows[window] = kept.isEmpty ? nil : kept }
        }
    }

    @discardableResult
    mutating func requestAI(_ task: AITask, from window: WindowID? = nil) -> AIRequestID {
        let id = AIRequestID(ctx.newID())
        state.session.pendingAI[id] = task
        state.session.ai.backgroundContexts[id] = backgroundAIContext(task)
        if let window { state.session.ai.backgroundWindows[id] = window }
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

    /// A link under the pointer (CEF's status text) or none. BrkApp starts the card once Shift has been held over the
    /// same link for Arc's two seconds (`Effect.aiHover`); a new link or none closes the card, unless the pointer
    /// moved onto the card itself.
    mutating func aiHover(_ url: URL?, in window: WindowID) {
        guard state.doc.settings.max.enabled(.linkPreviews), state.doc.windows[window]?.kind != .incognito else { return }
        let url = url.flatMap { AIValidation.destination($0.absoluteString) }
        guard state.session.ai.hover[window] != url else { return }
        state.session.ai.hover[window] = url
        let document = state.findPage(in: window).flatMap { page -> DocumentToken? in
            if case .ready(let document) = state.session.live[page]?.document { document } else { nil }
        }
        state.session.ai.hoverDocuments[window] = document
        if url != nil || !state.session.ai.previewHeld.contains(window) { closePreview(in: window) }
        effects.append(.aiHover(window, url, document))
    }
    mutating func aiHoverReady(_ window: WindowID, url: URL, link: CGRect?) {
        guard state.session.ai.hover[window] == url, state.doc.settings.max.enabled(.linkPreviews), state.doc.windows[window]?.kind != .incognito,
              let document = state.session.ai.hoverDocuments[window],
              state.findPage(in: window) == document.browser.page,
              state.session.live[document.browser.page]?.document == .ready(document),
              state.session.live[document.browser.page]?.requestContext == state.libraryContext(in: window) else { return }
        let id = startAI(.ask("Summarize link"), purpose: .preview(url), title: "Link Preview", window: window, run: false)
        state.session.ai.previews[window] = AIPreviewSnapshot(url: url, page: document.browser.page, link: link, busy: true,
                                                              title: url.host ?? url.absoluteString, request: id)
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
        completeAI(id, text: "Organized \(tabs.count) Today tabs into \(plan.count) \(plan.count == 1 ? "group" : "groups").", success: true)
        // Arc names the undo "tidying"; the toast is Arc's undo toast (Cleared Tabs! Use ⌘Z to undo), its words ours.
        undoToast("Tidied Tabs! Use", undo: .tidy, in: request.window)
    }
    mutating func undoAIOrganize(in window: WindowID) {
        guard let undo = state.session.ai.undo[window], state.doc.windows[window]?.space == undo.space,
              let root = state.doc.spaces[undo.space]?.todayRoot,
              undo.folders.allSatisfy({ state.doc.tree[$0.key]?.parent == root && state.doc.tree[$0.key]?.children == $0.value }) else {
            toast("The groups changed. Undo was refused to protect your edits.", in: window); return
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
    }

    mutating func aiDownloadRenamed(_ id: DownloadID, original: String, new: String?, error: String?) {
        let asked = state.session.ai.requests.values.first { if case .renameDownload(id, _) = $0.task { true } else { false } }?.window
            ?? state.session.ai.renamingDownloads.removeValue(forKey: id)
        for (requestID, request) in state.session.ai.requests {
            if case .renameDownload(let downloadID, _) = request.task, downloadID == id {
                completeAI(requestID, text: new.map { "Renamed download to " + ($0 as NSString).lastPathComponent } ?? error ?? "The file could not be renamed.")
            }
        }
        guard let index = state.doc.downloads.firstIndex(where: { $0.id == id && $0.path == original && $0.state == .finished }), let new else {
            // The file could not be moved (a background rename has no panel to say so).
            if let asked, new == nil, state.doc.windows[asked] != nil { toast("\(AIFeature.downloadRename.title): " + (error ?? "The file could not be renamed."), in: asked) }
            return
        }
        state.doc.downloads[index].path = new
        state.doc.downloads[index].filename = (new as NSString).lastPathComponent
        // Arc's Tidy Downloads card: "Download renamed to:" and the new name; the file is where it was.
        if let asked, state.doc.windows[asked] != nil { toast(ToastCopy.downloadRenamed, in: asked, subtitle: (new as NSString).lastPathComponent) }
    }

    mutating func suggestions(_ window: WindowID, query: String, _ results: [String]) {
        guard state.session.windows[window] != nil, case .commandBar? = state.session.windows[window]!.overlay else { return }
        state.session.windows[window]!.suggestions = Suggestions(query: query, results: Array(results.prefix(Metrics.commandBar.maxSearchSuggestions.value)))
    }
}
extension AIPurpose {
    enum Slot: Equatable { case panel, preview, instant, translate, organize, bar }
    var slot: Slot {
        switch self {
        case .answer, .askPage, .browse, .followUp: .panel
        case .preview: .preview
        case .instant: .instant
        case .translate: .translate
        case .organize: .organize
        case .barTranslation: .bar
        }
    }
    var isPreview: Bool { slot == .preview }
}

extension AppState {
    /// The pill's second line for `page` (nil: none): Translated while the translation shows, Translating… while one
    /// runs, Translation Available on a page whose language is not the system's (`ProjectionContext.systemLanguage`)
    /// and that this profile translates.
    func pillTranslation(_ page: PageID, in window: WindowID, systemLanguage: String) -> PillTranslation? {
        guard doc.windows[window]?.kind != .incognito, let live = session.live[page], case .ready(let document) = live.document else { return nil }
        if let translation = session.ai.translations[page], translation.document == document, translation.showingTranslation {
            return .translated(from: AILanguages.name(translation.source))
        }
        if session.ai.requests.values.contains(where: { $0.page == page && $0.purpose.slot == .translate }) { return .translating }
        guard let language = live.language.map(AILanguages.base), !language.isEmpty, language != AILanguages.base(systemLanguage) else { return nil }
        if case .profile(let profile) = browsingContext(of: page.item), let exclusions = doc.settings.max.translationExclusions?[profile] {
            let host = address(of: page.item, in: window, for: .visible)?.host?.lowercased() ?? ""
            if exclusions.languages.contains(language) || exclusions.sites.contains(host) { return nil }
        }
        return .available
    }

    /// The local tool's name as the command bar's Ask row and the Max pane say it (Arc: ChatGPT): the chosen one,
    /// else under Automatic the first one found, else Claude. Nil while Max's tool is off.
    public var askProviderName: String? {
        switch doc.settings.max.provider {
        case .off: nil
        case .auto: (activeAgent ?? session.detectedAI.first ?? .claude).displayName
        case let choice: choice.kind?.displayName
        }
    }

    /// What the choice resolves to now, nil when nothing can answer: the chosen agent when it is installed; under
    /// Automatic the first installed one not known to be signed out, else the first installed one.
    public var activeAgent: AIProviderKind? {
        switch doc.settings.max.provider {
        case .off: return nil
        case .auto:
            let usable = session.detectedAI.first { session.ai.agents[$0]?.state != .notSignedIn }
            return usable ?? session.detectedAI.first
        case let choice:
            return choice.kind.flatMap { session.detectedAI.contains($0) ? $0 : nil }
        }
    }
}

extension AIProviderChoice {
    /// The agent this choice names; nil for Off and Automatic.
    public var kind: AIProviderKind? {
        switch self {
        case .off, .auto: nil
        case .claude: .claude
        case .codex: .codex
        case .gemini: .gemini
        case .cursor: .cursor
        case .opencode: .opencode
        }
    }
}

extension AIProviderKind {
    public var displayName: String {
        switch self {
        case .claude: "Claude"
        case .codex: "Codex"
        case .gemini: "Gemini"
        case .cursor: "Cursor"
        case .opencode: "OpenCode"
        }
    }
}
