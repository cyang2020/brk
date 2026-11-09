import BrkBase
import Foundation

// Conversation lists (docs/design/ai-threads.md). The panel's live conversation stays in `AISession.answers`, as
// before; the panel's page, the Space it belongs to and what each Space showed last are kept beside it. After every input
// `reconcilePanels` swaps the panel when the window moved to another Space (the conversation it showed is put away, the
// new Space's last one comes back), opens the conversation page when a new answer arrives, closes the panel when the
// conversation page has nothing left, and marks replies seen once their conversation shows.

/// Where a conversation is in the sidebar: the Space it belongs to and whether only the archive has its row.
struct ConversationPlace: Equatable {
    var space: SpaceID?
    var archived: Bool
    /// Its open row, when it has one.
    var row: ItemID?
}

extension AppState {
    /// Where every conversation of `profile` is: the Space whose Pinned or Today holds its row; a Favorite, or one with no
    /// row at all, belongs to the Space it was started in; an archived one to the Space it was archived from. A Space that
    /// is gone gives way to the profile's first.
    func conversationPlaces(_ profile: ProfileID) -> [AIRequestID: ConversationPlace] {
        var out: [AIRequestID: ConversationPlace] = [:]
        let spaces = doc.spaceOrder.filter { doc.spaces[$0]?.profile == profile }
        func id(_ row: ItemID) -> AIRequestID? { ConversationPage.id(of: tab(row)?.url ?? tab(row)?.pinnedURL) }
        for sid in spaces {
            guard let space = doc.spaces[sid] else { continue }
            for row in doc.tree.tabs(under: space.pinnedRoot) + doc.tree.tabs(under: space.todayRoot) {
                guard let conversation = id(row), out[conversation] == nil, doc.conversations[conversation]?.profile == profile else { continue }
                out[conversation] = ConversationPlace(space: sid, archived: false, row: row)
            }
        }
        if let root = doc.favorites[profile] {
            for row in doc.tree.tabs(under: root) {
                guard let conversation = id(row), out[conversation] == nil, let stored = doc.conversations[conversation], stored.profile == profile else { continue }
                out[conversation] = ConversationPlace(space: stored.space, archived: false, row: row)
            }
        }
        for entry in doc.archive {
            guard let conversation = ConversationPage.id(of: entry.tab.url), out[conversation] == nil,
                  let stored = doc.conversations[conversation], stored.profile == profile else { continue }
            out[conversation] = ConversationPlace(space: entry.fromSpace ?? stored.space, archived: true, row: nil)
        }
        for stored in doc.conversations.values where stored.profile == profile && out[stored.id] == nil {
            out[stored.id] = ConversationPlace(space: stored.space, archived: false, row: nil)
        }
        for (key, place) in out where place.space.map({ !spaces.contains($0) }) ?? true { out[key]?.space = spaces.first }
        return out
    }

    /// The conversation's live state, wherever it is.
    func liveAnswer(_ id: AIRequestID) -> AIAnswerSnapshot? {
        session.ai.host(ofConversation: id).flatMap { session.ai[host: $0] }
    }

    /// The approval the agent waits for in conversation `id`, if any.
    func pendingApproval(_ id: AIRequestID) -> AIAgentApproval? {
        liveAnswer(id)?.conversation?.items.lazy.compactMap { item -> AIAgentApproval? in
            if case .approval(let value) = item, value.answer == nil { value } else { nil }
        }.first
    }

    func threadState(_ stored: StoredConversation, archived: Bool) -> AIThreadState {
        if pendingApproval(stored.id) != nil { return .waiting }
        if liveAnswer(stored.id)?.busy == true { return .running }
        if stored.unread { return .unread }
        return archived ? .archived : .idle
    }

    /// The language of a list's own words: the one most of the five most recent conversations that tell are in (the most
    /// recent one on a tie), else the system's. One message in another language does not turn the list over.
    func listLanguage(_ profile: ProfileID, system: String) -> AILanguage {
        var told: [AILanguage] = []
        for stored in conversations(of: profile) where told.count < Self.languageSample {
            for item in stored.items.reversed() {
                if case .user(let text) = item, let language = AILanguage.of(text: text) { told.append(language); break }
            }
        }
        guard let newest = told.first else { return AILanguage.system(system) }
        let zh = told.filter { $0 == .zh }.count, en = told.count - zh
        return zh == en ? newest : (zh > en ? .zh : .en)
    }
    static let languageSample = 5

    /// One conversation as a list shows it.
    func threadRow(_ stored: StoredConversation, place: ConversationPlace?, now: Instant, calendar: Calendar, system: String) -> AIThreadRow {
        let live = liveAnswer(stored.id)
        let items = live?.conversation?.items ?? stored.items
        let language = AILanguage.of(items, system: system)
        let state = threadState(stored, archived: place?.archived ?? false)
        let pages = items.filter { if case .page = $0 { true } else { false } }.count
        let detail: String
        switch state {
        case .waiting: detail = pendingApproval(stored.id).map { AIThreadWords.wants($0, language) } ?? AIThreadWords.pill(language)
        case .unread: detail = AIThreadWords.replied(stored.repliedAt ?? stored.updatedAt, now: now, language)
        case .running:
            let turn = items.lastIndex { if case .user = $0 { true } else { false } }.map { items[($0 + 1)...] } ?? items[...]
            let steps = turn.compactMap { if case .step(let step) = $0 { step } else { nil } }
            detail = steps.isEmpty ? AIThreadWords.answering(language) : AIStepWords.summary(steps, language)
        case .archived: detail = AIThreadWords.archived(language)
        case .idle:
            let when = AIThreadWords.when(stored.updatedAt, now: now, calendar: calendar, language)
            detail = pages > 0 ? when + " · " + AIThreadWords.pages(pages, language) : when
        }
        // Its row's own title once someone gave it one (the user, Name Tabs), else its saved title (`conversationName`).
        let custom = place?.row.flatMap { tab($0)?.customTitle }.flatMap { $0.isEmpty ? nil : $0 }
        var row = AIThreadRow(id: stored.id, title: custom ?? stored.title, state: state, detail: detail, updatedAt: stored.updatedAt)
        if state == .waiting { row.pill = AIThreadWords.pill(language) }
        row.space = place?.space
        if let space = place?.space, let value = doc.spaces[space] {
            row.spaceTitle = displayTitle(of: space)
            row.spaceColor = resolveTheme(value.theme, systemScheme: .light).gradient.first ?? SpaceTheme.default.colors[0]
        }
        row.agent = live?.conversation?.agentName ?? stored.agentName
        row.pages = pages
        row.language = language
        return row
    }

    /// The panel's snapshot in a standard window whose panel is open.
    func panelSnapshot(in window: WindowID, now: Instant, calendar: Calendar, system: String) -> AIPanelSnapshot? {
        guard let page = session.ai.panelPage[window], let doc = doc.windows[window], doc.kind == .standard,
              let profile = agentProfile(in: window) else { return nil }
        let here = doc.space
        let places = conversationPlaces(profile)
        let language = listLanguage(profile, system: system)
        let current = session.ai.answers[window]?.conversation?.id
        var all: [AIThreadRow] = conversations(of: profile).map { threadRow($0, place: places[$0.id], now: now, calendar: calendar, system: system) }
        for index in all.indices where all[index].id == current { all[index].current = true }
        let strips = all.filter { $0.space != here && $0.state.needsUser }
        var mine = all.filter { $0.space == here }
        let search = session.ai.panelSearch[window] ?? ""
        if !search.trimmingCharacters(in: .whitespaces).isEmpty {
            let candidates = mine.compactMap { row in self.doc.conversations[row.id].map { $0.candidate } }
            let found = ConversationSearch.search(search, in: candidates)
            let byID = Dictionary(mine.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            mine = found.compactMap { candidate, how in
                guard var row = byID[candidate.id] else { return nil }
                if case .text(let snippet) = how { row.snippet = snippet }
                return row
            }
        }
        var groups: [AIThreadGroup] = []
        func add(_ kind: AIThreadGroupKind, _ rows: [AIThreadRow]) {
            if !rows.isEmpty { groups.append(AIThreadGroup(kind: kind, title: AIThreadWords.group(kind, language), rows: rows)) }
        }
        add(.needsUser, mine.filter { $0.state.needsUser })
        add(.running, mine.filter { $0.state == .running })
        let rest = mine.filter { !$0.state.needsUser && $0.state != .running }
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: Double(now.milliseconds) / 1000))
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today) ?? today
        func day(_ row: AIThreadRow) -> Date { Date(timeIntervalSince1970: Double(row.updatedAt.milliseconds) / 1000) }
        add(.today, rest.filter { day($0) >= today })
        add(.yesterday, rest.filter { day($0) < today && day($0) >= yesterday })
        add(.earlier, rest.filter { day($0) < yesterday })
        let spaces = self.doc.spaceOrder.compactMap { sid -> AIThreadSpace? in
            guard let value = self.doc.spaces[sid], value.profile == profile else { return nil }
            return AIThreadSpace(id: sid, title: displayTitle(of: sid), color: resolveTheme(value.theme, systemScheme: .light).gradient.first ?? SpaceTheme.default.colors[0])
        }
        return AIPanelSnapshot(page: session.ai.answers[window] == nil ? .list : page, hasConversation: session.ai.answers[window] != nil, space: here,
                               spaceTitle: displayTitle(of: here), language: language, search: search, strips: strips, groups: groups,
                               waiting: all.filter { $0.state.needsUser }.count, spaces: spaces,
                               renaming: session.ai.renamingConversation[window].flatMap { id in mine.contains { $0.id == id } ? id : nil })
    }

    /// The + menu's agent list: what Settings → Max lists, the ready agents with their models.
    var agentMenu: AIAgentMenu? {
        let ready = AIProviderKind.allCases.compactMap { session.ai.agents[$0] }.filter { $0.state == .ready }
        guard !ready.isEmpty else { return nil }
        var models: [AIProviderKind: String] = [:]
        for status in ready { if let model = doc.settings.max.agentOptions?[status.kind]?.model { models[status.kind] = model } }
        return AIAgentMenu(agents: ready, models: models, active: activeAgent)
    }

    /// The command bar's conversations: the newest of the profile, each with all that was said and the Space it is in.
    func conversationCandidates(_ profile: ProfileID) -> [ConversationCandidate] {
        let places = conversationPlaces(profile)
        return conversations(of: profile).prefix(ConversationCandidate.limit).map { stored in
            var candidate = stored.candidate
            candidate.title = conversationName(stored.id) ?? stored.title
            candidate.space = places[stored.id]?.space.map { displayTitle(of: $0) }
            return candidate
        }
    }

    /// Spaces of `profile` other than `except` with a conversation that waits for the user: their dots get a ring.
    func spacesNeedingUser(_ profile: ProfileID, except: SpaceID) -> Set<SpaceID> {
        // Most conversations wait for nobody: where they are is looked up only for those that do.
        let waiting = doc.conversations.values.filter { $0.profile == profile && ($0.unread || pendingApproval($0.id) != nil) }
        guard !waiting.isEmpty else { return [] }
        let places = conversationPlaces(profile)
        return Set(waiting.compactMap { places[$0.id]?.space }.filter { $0 != except })
    }

    /// The Library's "AI 对话" page for a window.
    func libraryConversations(in window: WindowID, now: Instant, calendar: Calendar, system: String) -> LibraryConversationsSnapshot? {
        guard let profile = agentProfile(in: window) else { return nil }
        let query = session.ai.libraryQuery[window] ?? ConversationLibraryQuery()
        let places = conversationPlaces(profile)
        let language = listLanguage(profile, system: system)
        let all = conversations(of: profile).map { threadRow($0, place: places[$0.id], now: now, calendar: calendar, system: system) }
        var rows = all
        if !query.text.trimmingCharacters(in: .whitespaces).isEmpty {
            let byID = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
            rows = ConversationSearch.search(query.text, in: conversations(of: profile).map(\.candidate)).compactMap { candidate, how in
                guard var row = byID[candidate.id] else { return nil }
                if case .text(let snippet) = how { row.snippet = snippet }
                return row
            }
            // Newest first, as the rest of the page; the search decides only what stays.
            rows.sort { ($0.updatedAt, $0.id.rawValue) > ($1.updatedAt, $1.id.rawValue) }
        }
        switch query.chip {
        case .all: break
        case .needsUser: rows = rows.filter { $0.state.needsUser }
        case .withPages: rows = rows.filter { $0.pages > 0 }
        }
        if !query.spaces.isEmpty { rows = rows.filter { $0.space.map(query.spaces.contains) ?? false } }
        if !query.agents.isEmpty { rows = rows.filter { $0.agent.map(query.agents.contains) ?? false } }
        if !query.states.isEmpty { rows = rows.filter { query.states.contains($0.state) } }
        if query.withPages { rows = rows.filter { $0.pages > 0 } }
        let spaces = doc.spaceOrder.compactMap { sid -> AIThreadSpace? in
            guard let value = doc.spaces[sid], value.profile == profile else { return nil }
            return AIThreadSpace(id: sid, title: displayTitle(of: sid), color: resolveTheme(value.theme, systemScheme: .light).gradient.first ?? SpaceTheme.default.colors[0])
        }
        var detail: LibraryConversationDetail?
        // Nothing chosen yet: the first row shows, as the mockup has it.
        if let id = session.ai.librarySelection[window] ?? rows.first?.id, let stored = doc.conversations[id], stored.profile == profile,
           let row = all.first(where: { $0.id == id }) {
            let answer = withPages(liveAnswer(id) ?? stored.snapshot())
            let meta = [row.spaceTitle.isEmpty ? nil : row.spaceTitle, stored.agentName ?? row.agent, stored.model].compactMap { $0 }.joined(separator: " · ")
            detail = LibraryConversationDetail(id: id, title: row.title, meta: meta, space: row.space, state: row.state, answer: answer)
        }
        return LibraryConversationsSnapshot(query: query, rows: rows, waiting: all.filter { $0.state.needsUser }.count, withPages: all.filter { $0.pages > 0 }.count,
                                            spaces: spaces, agents: Array(Set(all.compactMap(\.agent))).sorted(), language: language, selected: detail)
    }
}

extension Work {
    /// The intents of the conversation lists. False: not one of them.
    mutating func threadIntent(_ intent: AIIntent, in window: WindowID) -> Bool {
        switch intent {
        case .panelPage(let page): setPanelPage(page, in: window)
        case .showConversation(let id): showConversationInPanel(id, in: window)
        case .listSearch(let text):
            guard state.session.ai.panelPage[window] != nil else { return true }
            let trimmed = String(text.prefix(200))
            state.session.ai.panelSearch[window] = trimmed.isEmpty ? nil : trimmed
        case .listAsk(let text):
            let q = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !q.isEmpty, q.count <= 2000, state.doc.windows[window]?.kind == .standard else { return true }
            state.session.ai.panelSearch[window] = nil
            assist(.ask(q), in: window)
            if state.session.ai.answers[window] != nil { state.session.ai.panelPage[window] = .conversation }
        case .beginRenameConversation(let id):
            guard let profile = state.agentProfile(in: window), state.doc.conversations[id]?.profile == profile else { return true }
            state.session.ai.renamingConversation[window] = id
        case .renameConversation(let id, let title):
            if state.session.ai.renamingConversation[window] == id { state.session.ai.renamingConversation[window] = nil }
            if let title { renameConversation(id, title, in: window) }
        case .archiveConversation(let id): archiveConversation(id, in: window)
        case .restoreConversation(let id): _ = restoreConversation(id, in: window)
        case .moveConversation(let id, let space): moveConversation(id, to: space, in: window)
        case .pickAgent(let kind, let model): pickAgent(kind, model: model, at: .panel(window))
        default: return false
        }
        return true
    }

    /// The + menu's agent list: the conversation's next messages go to this agent and model. A session already running
    /// is changed by the app at the next turn (another agent: a new session with the transcript, this agent's own session
    /// continued where it can be). Only an agent that is ready on this Mac.
    mutating func pickAgent(_ kind: AIProviderKind, model: String?, at host: AIAnswerHost) {
        guard var conversation = state.session.ai[host: host]?.conversation, !conversation.ended,
              state.session.ai.agents[kind]?.state == .ready || state.session.detectedAI.contains(kind) else { return }
        if let model, let models = state.session.ai.agents[kind]?.models, !models.isEmpty, !models.contains(where: { $0.id == model }) { return }
        let pick = AIAgentPick(kind: kind, model: model)
        conversation.pick = pick
        state.session.ai[host: host]?.conversation = conversation
        if state.doc.conversations[conversation.id] != nil { state.doc.conversations[conversation.id]?.pick = pick }
        effects.append(.aiPick(conversation.id, pick))
    }

    // MARK: Names

    /// A conversation is named by the basic model after an answer, once, as Name Tabs names tabs and under its switch: a
    /// short name in the conversation's language in place of its first message. Never one the user named, and nothing
    /// without a route for the basic model (no agent, no key): it keeps its first message.
    mutating func nameConversationIfDue(_ id: AIRequestID) {
        guard state.doc.settings.max.enabled(.tabNames), let stored = state.doc.conversations[id], stored.aiNamed != true, stored.userNamed != true,
              !state.session.ai.namedAsked.contains(id), !conversationRowNamed(id) else { return }
        if case .unavailable = state.basicRoute { return }
        let items = state.liveAnswer(id)?.conversation?.items ?? stored.items
        guard let question = items.lazy.compactMap({ if case .user(let text) = $0 { text } else { nil } }).first,
              let answer = items.lazy.compactMap({ if case .assistant(let text) = $0, !text.isEmpty { text } else { nil } }).first else { return }
        state.session.ai.namedAsked.insert(id)
        let task = AITask.nameConversation(id, question: String(question.prefix(1_000)), answer: String(answer.prefix(1_500)),
                                           language: AILanguage.of(items, system: ctx.systemLanguage))
        let host = state.session.ai.host(ofConversation: id)
        let owner: WindowID? = host.flatMap { self.window(of: $0) }
        let request = requestAI(task, from: owner)
        state.session.ai.conversationNaming[request] = id
    }

    /// One of its rows has a name someone typed (the sidebar's rename).
    private func conversationRowNamed(_ id: AIRequestID) -> Bool {
        let url = ConversationPage.url(id)
        return state.doc.tree.allTabs().contains { row in
            guard let tab = state.tab(row), tab.url == url else { return false }
            return tab.userNamed || !(tab.customTitle ?? "").isEmpty
        }
    }

    mutating func applyConversationName(_ request: AIRequestID, _ raw: String) {
        guard let id = state.session.ai.conversationNaming.removeValue(forKey: request), let stored = state.doc.conversations[id],
              stored.userNamed != true, !conversationRowNamed(id), let name = AIValidation.name(raw, limit: AINaming.maxLength) else { return }
        state.doc.conversations[id]?.title = name
        state.doc.conversations[id]?.aiNamed = true
        let url = ConversationPage.url(id)
        for row in state.doc.tree.allTabs() where state.tab(row)?.url == url {
            state.doc.tree.updateTab(row) { $0.title = name }
        }
        if let host = state.session.ai.host(ofConversation: id) { state.session.ai[host: host]?.title = name }
    }

    /// The list row's menu, in the conversation's language.
    func conversationMenu(_ id: AIRequestID, in window: WindowID) -> [MenuEntry] {
        guard let profile = state.agentProfile(in: window), let stored = state.doc.conversations[id], stored.profile == profile else { return [] }
        let language = AILanguage.of(state.liveAnswer(id)?.conversation?.items ?? stored.items, system: ctx.systemLanguage)
        let place = state.conversationPlaces(profile)[id]
        let others = state.doc.spaceOrder.filter { $0 != place?.space && state.doc.spaces[$0]?.profile == profile }
        var entries: [MenuEntry] = [
            .action(title: AIThreadWords.openInTab(language), command: .assist(.openConversation(id)), enabled: true),
            .action(title: AIThreadWords.rename(language), command: .assist(.beginRenameConversation(id)), enabled: true),
            place?.row == nil && place?.archived == true
                ? .action(title: AIThreadWords.restore(language), command: .assist(.restoreConversation(id)), enabled: true)
                : .action(title: AIThreadWords.archive(language), command: .assist(.archiveConversation(id)), enabled: place?.row != nil),
        ]
        entries.append(others.isEmpty
            ? .action(title: AIThreadWords.move(language), command: .assist(.moveConversation(id, place?.space ?? state.doc.windows[window]?.space ?? SpaceID(""))), enabled: false)
            : .submenu(title: AIThreadWords.move(language), entries: others.map { .action(title: state.displayTitle(of: $0), command: .assist(.moveConversation(id, $0)), enabled: true) }))
        entries.append(.separator)
        entries.append(.action(title: AIThreadWords.deleteEllipsis(language), command: .library(.requestDeleteConversation(id)), enabled: true))
        return entries
    }

    private mutating func setPanelPage(_ page: AIPanelPage, in window: WindowID) {
        guard state.doc.windows[window]?.kind == .standard, state.agentProfile(in: window) != nil else { return }
        switch page {
        case .list:
            if state.session.ai.panelPage[window] == nil { state.session.ai.panelSpace[window] = state.doc.windows[window]?.space }
            state.session.ai.panelPage[window] = .list
        case .conversation:
            guard state.session.ai.answers[window] != nil else { return }
            state.session.ai.panelPage[window] = .conversation
        }
    }

    /// Conversation `id` in this window's panel. Archived, its row comes back first; another Space's, the window switches
    /// there and the panel brings it back as that Space's (`reconcilePanels`); its tab already shown here, the tab stays.
    mutating func showConversationInPanel(_ id: AIRequestID, in window: WindowID) {
        guard let doc = state.doc.windows[window], doc.kind == .standard, let profile = state.agentProfile(in: window),
              let stored = state.doc.conversations[id], stored.profile == profile else { return }
        var place = state.conversationPlaces(profile)[id]
        if place?.row == nil, let entry = state.doc.archive.first(where: { $0.tab.url == ConversationPage.url(id) }), restoreEntry(entry.id, in: window) != nil {
            place = state.conversationPlaces(profile)[id]
        }
        let space = place?.space ?? doc.space
        if state.shownNativePages(in: window).contains(where: { ConversationPage.id(of: $0.1) == id }) { return }
        if space != doc.space {
            if state.session.ai.panelPage[window] == nil { state.session.ai.panelPage[window] = .conversation; state.session.ai.panelSpace[window] = doc.space }
            state.session.ai.panelMemory[window, default: [:]][space] = AIPanelMemory(conversation: id, page: .conversation)
            showSpace(space, in: window)
            return
        }
        bringToPanel(id, in: window)
        state.session.ai.panelPage[window] = .conversation
        state.session.ai.panelSpace[window] = doc.space
    }

    /// The conversation moves into the window's panel from wherever it lives: another window's panel, out of sight, or
    /// its saved transcript. What the panel showed is put away.
    private mutating func bringToPanel(_ id: AIRequestID, in window: WindowID) {
        if state.session.ai.answers[window]?.conversation?.id == id { return }
        clearPanel(in: window)
        switch state.session.ai.host(ofConversation: id) {
        case .panel(let other)?:
            state.session.ai.answers[window] = state.session.ai.answers[other]
            state.session.ai.answers[other] = nil
            state.session.ai.answerContexts[other] = nil
        case .tab?:
            state.session.ai.answers[window] = state.session.ai.tabAnswers[id]
            state.session.ai.tabAnswers[id] = nil
            state.session.ai.tabWindows[id] = nil
        case nil:
            guard let stored = state.doc.conversations[id] else { return }
            state.session.ai.answers[window] = stored.snapshot()
            state.session.ai.turnText[id] = 0
        }
        state.session.ai.answerContexts[window] = state.libraryContext(in: window)
    }

    /// The panel shows nothing: a saved conversation is put away (a running turn goes on out of sight); anything else
    /// (a plain message, a conversation that has not said anything yet) goes, with any request still running for it.
    private mutating func clearPanel(in window: WindowID) {
        if putAwayPanelConversation(in: window) { return }
        guard state.session.ai.answers[window] != nil else { return }
        cancelAI(in: window, slot: .panel)
        state.session.ai.answers[window] = nil
        state.session.ai.answerContexts[window] = nil
    }

    private mutating func renameConversation(_ id: AIRequestID, _ title: String, in window: WindowID) {
        guard let profile = state.agentProfile(in: window), state.doc.conversations[id]?.profile == profile else { return }
        let trimmed = String(title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(120))
        guard !trimmed.isEmpty else { return }
        state.doc.conversations[id]?.title = trimmed
        state.doc.conversations[id]?.userNamed = true
        let url = ConversationPage.url(id)
        for row in state.doc.tree.allTabs() where state.tab(row)?.url == url && state.browsingContext(of: row) == .profile(profile) {
            // The item rule itself: a nested `run` would apply the overlay rule and close the Library.
            items(.rename(row, title: trimmed), in: window)
        }
    }

    private mutating func archiveConversation(_ id: AIRequestID, in window: WindowID) {
        guard let profile = state.agentProfile(in: window), let row = state.conversationPlaces(profile)[id]?.row else { return }
        run(.tab(.archive(.item(row))), in: window)
    }

    /// The archived conversation's row back in the Space it came from, not shown. True when it came back.
    private mutating func restoreConversation(_ id: AIRequestID, in window: WindowID) -> Bool {
        guard let profile = state.agentProfile(in: window), state.doc.conversations[id]?.profile == profile,
              state.conversationPlaces(profile)[id]?.row == nil,
              let entry = state.doc.archive.first(where: { $0.tab.url == ConversationPage.url(id) }) else { return false }
        return restoreEntry(entry.id, in: window) != nil
    }

    /// The conversation's row goes to the top of another Space's Today (an archived one comes back there). Only Spaces of
    /// the conversation's profile: its agent sees that profile's tabs.
    mutating func moveConversation(_ id: AIRequestID, to space: SpaceID, in window: WindowID) {
        guard let profile = state.agentProfile(in: window), let stored = state.doc.conversations[id], stored.profile == profile,
              let target = state.doc.spaces[space], target.profile == profile else { return }
        var place = state.conversationPlaces(profile)[id]
        if place?.row == nil, restoreConversation(id, in: window) { place = state.conversationPlaces(profile)[id] }
        state.doc.conversations[id]?.space = space
        guard let row = place?.row, place?.space != space else { return }
        if state.doc.tree.role(of: row)?.kind == .favorites { return }
        items(.move(row, to: .space(space)), in: window)
    }

    /// Delete for good, from the panel's list or the Library: the transcript, every page it made, its rows wherever they
    /// are (open or archived), and its live state.
    mutating func deleteConversationForGood(_ id: AIRequestID, in window: WindowID) {
        guard let profile = state.agentProfile(in: window), let stored = state.doc.conversations[id], stored.profile == profile else { return }
        let language = AILanguage.of(stored.items, system: ctx.systemLanguage)
        let title = state.conversationName(id) ?? stored.title
        let pages = state.doc.aiPages.values.filter { $0.conversation == id }.map(\.id)
        let urls = Set([ConversationPage.url(id)] + pages.map(AIPageTab.url))
        state.doc.conversations[id] = nil
        for page in pages { state.doc.aiPages[page] = nil }
        for (host, answer) in state.session.ai.answers where answer.conversation?.id == id {
            if let request = answer.request { cancelAI(request) }
            state.session.ai.answers[host] = nil
            state.session.ai.answerContexts[host] = nil
        }
        if let request = state.session.ai.tabAnswers[id]?.request { cancelAI(request) }
        state.session.ai.tabAnswers[id] = nil
        state.session.ai.tabWindows[id] = nil
        if state.session.ai.librarySelection[window] == id { state.session.ai.librarySelection[window] = nil }
        state.doc.archive.removeAll { record in
            guard let url = record.tab.url, urls.contains(url) else { return false }
            if case .folder? = record.structure { return false }
            if case .split? = record.structure { return false }
            return true
        }
        for row in state.doc.tree.allTabs() where state.tab(row)?.url.map(urls.contains) == true {
            _ = removeItem(row)
            unload(row)
            replaceShown(row)
        }
        toast(AIThreadWords.deleted(title, language), in: window)
    }

    /// A request ended by Brk: its process told to stop, its turn ended in the transcript.
    private mutating func cancelAI(_ request: AIRequestID) {
        state.session.ai.requests[request] = nil
        state.session.pendingAI[request] = nil
        effects.append(.aiCancel(request))
    }

    // MARK: The Library page

    mutating func libraryConversations(_ command: LibraryCommand, in window: WindowID) {
        switch command {
        case .conversationQuery(var query):
            query.text = String(query.text.prefix(200))
            state.session.ai.libraryQuery[window] = query
        case .selectConversation(let id):
            if let id, let profile = state.agentProfile(in: window), state.doc.conversations[id]?.profile == profile {
                state.session.ai.librarySelection[window] = id
                markSeen(id)
            } else { state.session.ai.librarySelection[window] = nil }
        case .moveConversation(let id, let space): moveConversation(id, to: space, in: window)
        case .requestDeleteConversation(let id):
            guard let profile = state.agentProfile(in: window), let stored = state.doc.conversations[id], stored.profile == profile else { return }
            let pages = state.doc.aiPages.values.filter { $0.conversation == id }.count
            state.session.ai.pendingConversationDeletion[window] = ConversationDeletionRequest(
                id: id, title: state.conversationName(id) ?? stored.title, pages: pages,
                language: AILanguage.of(stored.items, system: ctx.systemLanguage), token: ctx.newID())
        case .confirmDeleteConversation(let id, let token, let confirmed):
            guard let request = state.session.ai.pendingConversationDeletion[window], request.id == id, request.token == token else { return }
            state.session.ai.pendingConversationDeletion[window] = nil
            if confirmed { deleteConversationForGood(id, in: window) }
        default: break
        }
    }

    // MARK: After every input

    /// A reply counts as seen once its conversation shows in a panel's conversation page or in its tab after it finished.
    private mutating func markSeen(_ id: AIRequestID) {
        guard let stored = state.doc.conversations[id], stored.unread else { return }
        state.doc.conversations[id]?.seenAt = ctx.now
    }

    mutating func reconcilePanels(from previous: AppState) {
        let ai = state.session.ai
        for window in Set(ai.panelPage.keys).union(ai.panelSpace.keys).union(ai.panelMemory.keys).union(ai.panelSearch.keys)
            .union(ai.libraryQuery.keys).union(ai.librarySelection.keys) where state.doc.windows[window]?.kind != .standard {
            state.session.ai.panelPage[window] = nil; state.session.ai.panelSpace[window] = nil; state.session.ai.panelMemory[window] = nil
            state.session.ai.panelSearch[window] = nil; state.session.ai.libraryQuery[window] = nil; state.session.ai.librarySelection[window] = nil
        }
        for window in state.doc.windows.keys.sorted() where state.doc.windows[window]?.kind == .standard {
            guard let space = state.doc.windows[window]?.space else { continue }
            var restored = false
            // The window moved to another Space with the panel open: that Space's list and last conversation.
            if state.session.ai.panelPage[window] != nil, let old = state.session.ai.panelSpace[window], old != space {
                let shown = state.session.ai.answers[window]?.conversation?.id
                let saved = shown.flatMap { state.doc.conversations[$0] != nil ? $0 : nil }
                state.session.ai.panelMemory[window, default: [:]][old] = AIPanelMemory(conversation: saved, page: state.session.ai.panelPage[window] ?? .list)
                clearPanel(in: window)
                state.session.ai.panelSearch[window] = nil
                var page = AIPanelPage.list
                if let memory = state.session.ai.panelMemory[window]?[space], let id = memory.conversation,
                   let profile = state.agentProfile(in: window), state.doc.conversations[id]?.profile == profile,
                   state.conversationPlaces(profile)[id]?.space == space,
                   !state.shownConversations.contains(id) {
                    bringToPanel(id, in: window)
                    if state.session.ai.answers[window] != nil { page = memory.page }
                }
                state.session.ai.panelPage[window] = page
                state.session.ai.panelSpace[window] = space
                restored = true
            }
            let answer = state.session.ai.answers[window]
            let before = previous.session.ai.answers[window]
            if let answer, !restored {
                if state.session.ai.panelPage[window] == nil {
                    // The panel opened (a question, a drop of tabs, a message).
                    state.session.ai.panelPage[window] = .conversation
                    state.session.ai.panelSpace[window] = space
                } else if state.session.ai.panelPage[window] == .list,
                          answer.conversation?.id != before?.conversation?.id || (answer.conversation == nil && answer.request != before?.request && answer.request != nil)
                            || (answer.conversation?.attached.count ?? 0) > (before?.conversation?.attached.count ?? 0) {
                    // Something new to show while the list was up (an answer, tabs dropped on the panel): the conversation page.
                    state.session.ai.panelPage[window] = .conversation
                }
            } else if answer == nil, state.session.ai.panelPage[window] == .conversation {
                // Closed, opened as a tab, deleted: the conversation page has nothing left.
                state.session.ai.panelPage[window] = nil
                state.session.ai.panelSearch[window] = nil
            }
            if state.session.ai.panelPage[window] == nil { state.session.ai.panelSpace[window] = nil }
            // What shows now counts as seen.
            if state.session.ai.panelPage[window] == .conversation, let id = state.session.ai.answers[window]?.conversation?.id,
               state.session.windows[window]?.overlay.map({ if case .library = $0 { false } else { true } }) ?? true {
                markSeen(id)
            }
        }
        for id in state.shownConversations { markSeen(id) }
        for (window, id) in state.session.ai.librarySelection where state.doc.conversations[id] == nil { state.session.ai.librarySelection[window] = nil }
        for (window, id) in state.session.ai.renamingConversation where state.doc.conversations[id] == nil || state.session.ai.panelPage[window] == nil {
            state.session.ai.renamingConversation[window] = nil
        }
        for (window, request) in state.session.ai.pendingConversationDeletion where state.doc.windows[window] == nil || state.doc.conversations[request.id] == nil {
            state.session.ai.pendingConversationDeletion[window] = nil
        }
        for (id, _) in state.session.ai.turnStarted where state.liveAnswer(id)?.busy != true { state.session.ai.turnStarted[id] = nil }
    }
}
