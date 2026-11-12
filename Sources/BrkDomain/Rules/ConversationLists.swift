import BrkBase
import Foundation

// Conversation lists (docs/design/ai-threads.md, ai-right-panel.md). The panel's live conversation stays in
// `AISession.answers`, as before; the panel's page, the Space it belongs to and what each Space showed last are kept
// beside it. After every input `reconcilePanels` swaps the panel when the window moved to another Space (the
// conversation it showed is put away, the new Space's last one comes back), opens the conversation page when a new answer
// arrives, closes the panel when the conversation page has nothing left, and marks replies seen once their conversation
// shows. Conversations live only here: the list keeps rename, move and delete; hovering a row lights the tabs it used.

extension AppState {
    /// The Space every conversation of `profile` belongs to: the one it records, or the profile's first when that one is
    /// gone. A profile with no Space has none.
    func conversationSpaces(_ profile: ProfileID) -> [AIRequestID: SpaceID] {
        let spaces = doc.spaceOrder.filter { doc.spaces[$0]?.profile == profile }
        guard let first = spaces.first else { return [:] }
        var out: [AIRequestID: SpaceID] = [:]
        for stored in doc.conversations.values where stored.profile == profile {
            out[stored.id] = stored.space.flatMap { spaces.contains($0) ? $0 : nil } ?? first
        }
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

    func threadState(_ stored: StoredConversation) -> AIThreadState {
        if pendingApproval(stored.id) != nil { return .waiting }
        if liveAnswer(stored.id)?.busy == true { return .running }
        if stored.unread { return .unread }
        return .idle
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
    func threadRow(_ stored: StoredConversation, space: SpaceID?, now: Instant, calendar: Calendar, system: String) -> AIThreadRow {
        let live = liveAnswer(stored.id)
        let items = live?.conversation?.items ?? stored.items
        let language = AILanguage.of(items, system: system)
        let state = threadState(stored)
        let pages = items.filter { if case .page = $0 { true } else { false } }.count
        let detail: String
        switch state {
        case .waiting: detail = pendingApproval(stored.id).map { AIThreadWords.wants($0, language) } ?? AIThreadWords.pill(language)
        case .unread: detail = AIThreadWords.replied(stored.repliedAt ?? stored.updatedAt, now: now, language)
        case .running:
            let turn = items.lastIndex { if case .user = $0 { true } else { false } }.map { items[($0 + 1)...] } ?? items[...]
            let steps = turn.compactMap { if case .step(let step) = $0 { step } else { nil } }
            detail = steps.isEmpty ? AIThreadWords.answering(language) : AIStepWords.summary(steps, language)
        case .idle:
            let when = AIThreadWords.when(stored.updatedAt, now: now, calendar: calendar, language)
            detail = pages > 0 ? when + " · " + AIThreadWords.pages(pages, language) : when
        }
        var row = AIThreadRow(id: stored.id, title: stored.title, state: state, detail: detail, updatedAt: stored.updatedAt)
        if state == .waiting { row.pill = AIThreadWords.pill(language) }
        row.space = space
        if let space, let value = doc.spaces[space] {
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
        let spaces = conversationSpaces(profile)
        let language = listLanguage(profile, system: system)
        let current = session.ai.answers[window]?.conversation?.id
        let hovered = session.ai.hoveredConversation[window]
        var all: [AIThreadRow] = conversations(of: profile).map { threadRow($0, space: spaces[$0.id], now: now, calendar: calendar, system: system) }
        for index in all.indices where all[index].id == current { all[index].current = true }
        // The row under the pointer says how many tabs it used, and how many of those light up here.
        var hoveredDetail: String?
        if let hovered, let row = all.first(where: { $0.id == hovered }), let stored = self.doc.conversations[hovered] {
            let used = usedTabs(stored)
            let lit = Set(used.compactMap { lightTarget($0, in: window) == nil ? nil : $0 }).count
            hoveredDetail = AIThreadWords.used(used.count, lit: doc.sidebarVisible ? lit : 0, row.language)
        }
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
        let spaceRows = self.doc.spaceOrder.compactMap { sid -> AIThreadSpace? in
            guard let value = self.doc.spaces[sid], value.profile == profile else { return nil }
            return AIThreadSpace(id: sid, title: displayTitle(of: sid), color: resolveTheme(value.theme, systemScheme: .light).gradient.first ?? SpaceTheme.default.colors[0])
        }
        return AIPanelSnapshot(page: session.ai.answers[window] == nil ? .list : page, hasConversation: session.ai.answers[window] != nil, space: here,
                               spaceTitle: displayTitle(of: here), language: language, search: search, strips: strips, groups: groups,
                               waiting: all.filter { $0.state.needsUser }.count, spaces: spaceRows,
                               renaming: session.ai.renamingConversation[window].flatMap { id in mine.contains { $0.id == id } ? id : nil },
                               hovered: hovered.flatMap { id in mine.contains { $0.id == id } ? id : nil }, hoveredDetail: hoveredDetail)
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
        let spaces = conversationSpaces(profile)
        return conversations(of: profile).prefix(ConversationCandidate.limit).map { stored in
            var candidate = stored.candidate
            candidate.space = spaces[stored.id].map { displayTitle(of: $0) }
            return candidate
        }
    }

    /// Spaces of `profile` other than `except` with a conversation that waits for the user: their dots get a ring.
    func spacesNeedingUser(_ profile: ProfileID, except: SpaceID) -> Set<SpaceID> {
        // Most conversations wait for nobody: where they are is looked up only for those that do.
        let waiting = doc.conversations.values.filter { $0.profile == profile && ($0.unread || pendingApproval($0.id) != nil) }
        guard !waiting.isEmpty else { return [] }
        let spaces = conversationSpaces(profile)
        return Set(waiting.compactMap { spaces[$0.id] }.filter { $0 != except })
    }

    /// The Library's "AI 对话" page for a window.
    func libraryConversations(in window: WindowID, now: Instant, calendar: Calendar, system: String) -> LibraryConversationsSnapshot? {
        guard let profile = agentProfile(in: window) else { return nil }
        let query = session.ai.libraryQuery[window] ?? ConversationLibraryQuery()
        let places = conversationSpaces(profile)
        let language = listLanguage(profile, system: system)
        let all = conversations(of: profile).map { threadRow($0, space: places[$0.id], now: now, calendar: calendar, system: system) }
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

// MARK: The panel's entries and lighting the tabs a conversation used (docs/design/ai-right-panel.md)

extension AppState {
    /// Whether a window can open the AI panel: a standard window of a profile (not private) with Ask in Command Bar on, the
    /// switch the panel's conversations need. Off, the title row has no chat button and stays as Arc draws it.
    func canOpenPanel(_ window: WindowID) -> Bool {
        guard doc.windows[window]?.kind == .standard, agentProfile(in: window) != nil else { return false }
        return doc.settings.max.enabled(.commandBar)
    }

    /// The window's panel width, its title row's chat button, the right-edge drop area and the lit sidebar rows.
    func projectPanelEntries(into snapshot: inout WindowSnapshot, _ window: WindowID, system: String) {
        snapshot.aiPanelWidth = doc.windows[window]?.aiPanelWidth
        guard canOpenPanel(window), let profile = agentProfile(in: window) else { return }
        let open = session.ai.panelPage[window] != nil || session.ai.answers[window] != nil
        let waiting = conversations(of: profile).filter { threadState($0).needsUser }.count
        let language = listLanguage(profile, system: system)
        snapshot.aiToggle = AIToggleSnapshot(open: open, waiting: waiting, language: language)
        if !open { snapshot.aiEdgeDrop = AIEdgeDropSnapshot(language: language) }
        snapshot.sidebar.lit = litRows(in: window)
    }

    /// The tabs a conversation used, by id, oldest first.
    func usedTabs(_ stored: StoredConversation) -> [ItemID] { stored.usedTabs ?? [] }

    /// The sidebar row that lights for `tab` in `window`: the tab's own row in this Space's Pinned or Today, the collapsed
    /// folder that hides it, the split row it is a pane of, or its Favorites tile. Nil for a tab of another Space, one
    /// that is closed or archived (gone from the sidebar), another profile's, or one under a collapsed Pinned section.
    func lightTarget(_ tab: ItemID, in window: WindowID) -> ItemID? {
        guard let doc = doc.windows[window], doc.kind == .standard, locate(tab) == .global, self.tab(tab) != nil,
              let space = self.doc.spaces[doc.space], let role = role(of: tab) else { return nil }
        switch role {
        case .favorites(let profile): return profile == space.profile ? tab : nil
        case .pinned(let sid), .today(let sid):
            guard sid == doc.space else { return nil }
            if case .pinned = role, space.pinnedCollapsed { return nil }
            // The outermost collapsed folder above it, else the split it is a pane of, else the row itself.
            var target = tab
            var current = self.doc.tree[tab]?.parent
            if let parent = current, case .split? = self.doc.tree[parent]?.body { target = parent }
            while let id = current, let node = self.doc.tree[id] {
                if case .folder = node.body, !folderIsExpanded(id, in: window) { target = id }
                current = node.parent
            }
            return target
        case .scratch: return nil
        }
    }

    /// The rows a window's sidebar lights now: the tabs of the list row under the pointer, or the one tab of the chip under
    /// it. Nothing while the sidebar is hidden.
    func litRows(in window: WindowID) -> Set<ItemID> {
        guard let doc = doc.windows[window], doc.sidebarVisible, session.ai.panelPage[window] != nil || session.ai.answers[window] != nil,
              let profile = agentProfile(in: window) else { return [] }
        var tabs: [ItemID] = []
        if let chip = session.ai.hoveredChip[window] {
            tabs = [ItemID(chip)]
        } else if let id = session.ai.hoveredConversation[window], let stored = self.doc.conversations[id], stored.profile == profile {
            tabs = usedTabs(stored)
        }
        return Set(tabs.compactMap { lightTarget($0, in: window) })
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
            guard !q.isEmpty, q.count <= AIValidation.messageLimit, state.doc.windows[window]?.kind == .standard else { tooLong(q, in: window); return true }
            state.session.ai.panelSearch[window] = nil
            assist(.ask(q), in: window)
            if state.session.ai.answers[window] != nil { state.session.ai.panelPage[window] = .conversation }
        case .beginRenameConversation(let id):
            guard let profile = state.agentProfile(in: window), state.doc.conversations[id]?.profile == profile else { return true }
            state.session.ai.renamingConversation[window] = id
        case .renameConversation(let id, let title):
            if state.session.ai.renamingConversation[window] == id { state.session.ai.renamingConversation[window] = nil }
            if let title { renameConversation(id, title, in: window) }
        case .moveConversation(let id, let space): moveConversation(id, to: space, in: window)
        case .togglePanel: togglePanel(in: window)
        case .panelWidth(let width):
            guard width.isFinite, state.doc.windows[window]?.kind == .standard else { return true }
            let clamped = min(max(width.rounded(), Metrics.ai.minimumWidth.value), Metrics.ai.maximumStoredWidth.value)
            if state.doc.windows[window]?.aiPanelWidth != clamped { state.doc.windows[window]?.aiPanelWidth = clamped }
        case .hoverConversation(let id):
            let valid = id.flatMap { id in state.agentProfile(in: window).flatMap { state.doc.conversations[id]?.profile == $0 ? id : nil } }
            if state.session.ai.hoveredConversation[window] != valid { state.session.ai.hoveredConversation[window] = valid }
        case .hoverChip(let chip):
            let attached = state.session.ai.answers[window]?.conversation?.attached ?? []
            let valid = chip.flatMap { chip in attached.contains { $0.kind == .tab && $0.id == chip } ? chip : nil }
            if state.session.ai.hoveredChip[window] != valid { state.session.ai.hoveredChip[window] = valid }
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
              !state.session.ai.namedAsked.contains(id) else { return }
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

    mutating func applyConversationName(_ request: AIRequestID, _ raw: String) {
        guard let id = state.session.ai.conversationNaming.removeValue(forKey: request), let stored = state.doc.conversations[id],
              stored.userNamed != true, let name = AIValidation.name(raw, limit: AINaming.maxLength) else { return }
        state.doc.conversations[id]?.title = name
        state.doc.conversations[id]?.aiNamed = true
        if let host = state.session.ai.host(ofConversation: id) { state.session.ai[host: host]?.title = name }
    }

    /// The list row's menu, in the conversation's language: rename, move to another Space, delete for good. Nothing else:
    /// a conversation has no row to pin, file or archive (docs/design/ai-right-panel.md, 列表里只留删除).
    func conversationMenu(_ id: AIRequestID, in window: WindowID) -> [MenuEntry] {
        guard let profile = state.agentProfile(in: window), let stored = state.doc.conversations[id], stored.profile == profile else { return [] }
        let language = AILanguage.of(state.liveAnswer(id)?.conversation?.items ?? stored.items, system: ctx.systemLanguage)
        let space = state.conversationSpaces(profile)[id]
        let others = state.doc.spaceOrder.filter { $0 != space && state.doc.spaces[$0]?.profile == profile }
        var entries: [MenuEntry] = [.action(title: AIThreadWords.rename(language), command: .assist(.beginRenameConversation(id)), enabled: true)]
        entries.append(others.isEmpty
            ? .action(title: AIThreadWords.move(language), command: .assist(.moveConversation(id, space ?? state.doc.windows[window]?.space ?? SpaceID(""))), enabled: false)
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

    /// Whether the window can open the AI panel: a standard window of a profile (not private), with Ask in Command Bar on,
    /// the switch the panel's conversations need. Off, the title row has no chat button and stays as Arc draws it.
    func canOpenPanel(_ window: WindowID) -> Bool { state.canOpenPanel(window) }

    /// The title row's chat button, ⌥⌘A, View › Show/Hide AI Conversations: an open panel closes (as its × does); a closed
    /// one opens on what this Space's panel showed last, the list when that was nothing or is gone.
    mutating func togglePanel(in window: WindowID) {
        if state.session.ai.panelPage[window] != nil || state.session.ai.answers[window] != nil {
            assist(.dismiss, in: window)
            return
        }
        guard canOpenPanel(window), let space = state.doc.windows[window]?.space, let profile = state.agentProfile(in: window) else {
            if state.doc.windows[window]?.kind == .standard, state.agentProfile(in: window) != nil, !state.doc.settings.max.enabled(.commandBar) {
                let text = state.doc.settings.max.isOn ? "\(AIFeature.commandBar.title) not enabled" : Self.maxOff
                toast(text, link: ToastLink(title: "Max Preferences ↗", command: .settings(.openPane(.max))), in: window)
            }
            return
        }
        state.session.ai.panelPage[window] = .list
        state.session.ai.panelSpace[window] = space
        if let memory = state.session.ai.panelMemory[window]?[space], let id = memory.conversation,
           state.doc.conversations[id]?.profile == profile, state.conversationSpaces(profile)[id] == space {
            bringToPanel(id, in: window)
            if state.session.ai.answers[window] != nil { state.session.ai.panelPage[window] = memory.page }
        }
    }

    /// Conversation `id` in this window's panel. Another Space's: the window switches there and the panel brings it back as
    /// that Space's (`reconcilePanels`).
    mutating func showConversationInPanel(_ id: AIRequestID, in window: WindowID) {
        guard let doc = state.doc.windows[window], doc.kind == .standard, let profile = state.agentProfile(in: window),
              let stored = state.doc.conversations[id], stored.profile == profile else { return }
        let space = state.conversationSpaces(profile)[id] ?? doc.space
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
        case .away?:
            state.session.ai.answers[window] = state.session.ai.awayAnswers[id]
            state.session.ai.awayAnswers[id] = nil
            state.session.ai.awayWindows[id] = nil
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
        if let host = state.session.ai.host(ofConversation: id) { state.session.ai[host: host]?.title = trimmed }
    }

    /// The conversation goes to another Space's list: the row menu's Move to, or its list row dropped on that Space's dot.
    /// Only Spaces of the conversation's profile: its agent sees that profile's tabs. A panel that shows it in the Space it
    /// left puts it away and shows its list.
    mutating func moveConversation(_ id: AIRequestID, to space: SpaceID, in window: WindowID) {
        guard let profile = state.agentProfile(in: window), let stored = state.doc.conversations[id], stored.profile == profile,
              let target = state.doc.spaces[space], target.profile == profile, state.conversationSpaces(profile)[id] != space else { return }
        state.doc.conversations[id]?.space = space
        for (other, answer) in state.session.ai.answers where answer.conversation?.id == id && state.session.ai.panelSpace[other] != space {
            putAwayPanelConversation(in: other)
            if state.session.ai.panelPage[other] != nil { state.session.ai.panelPage[other] = .list }
        }
    }

    /// Delete for good, from the panel's list or the Library: the transcript, every page it made with their rows wherever
    /// they are (open or archived), and its live state.
    mutating func deleteConversationForGood(_ id: AIRequestID, in window: WindowID) {
        guard let profile = state.agentProfile(in: window), let stored = state.doc.conversations[id], stored.profile == profile else { return }
        let language = AILanguage.of(stored.items, system: ctx.systemLanguage)
        let title = state.conversationName(id) ?? stored.title
        if state.session.ai.librarySelection[window] == id { state.session.ai.librarySelection[window] = nil }
        removeConversation(id)
        toast(AIThreadWords.deleted(title, language), in: window)
    }

    /// The transcript, every page it made with their rows wherever they are (open or archived), and its live state.
    mutating func removeConversation(_ id: AIRequestID) {
        let pages = state.doc.aiPages.values.filter { $0.conversation == id }.map(\.id)
        let urls = Set([ConversationPage.url(id)] + pages.map(AIPageTab.url))
        state.doc.conversations[id] = nil
        for page in pages { state.doc.aiPages[page] = nil }
        for (host, answer) in state.session.ai.answers where answer.conversation?.id == id {
            if let request = answer.request { cancelAI(request) }
            state.session.ai.answers[host] = nil
            state.session.ai.answerContexts[host] = nil
        }
        if let request = state.session.ai.awayAnswers[id]?.request { cancelAI(request) }
        state.session.ai.awayAnswers[id] = nil
        state.session.ai.awayWindows[id] = nil
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

    /// A reply counts as seen once its conversation shows in a panel's conversation page after it finished.
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
                   state.conversationSpaces(profile)[id] == space {
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
                } else if state.session.ai.panelPage[window] == .list, previous.session.ai.panelPage[window] != nil,
                          answer.conversation?.id != before?.conversation?.id || (answer.conversation == nil && answer.request != before?.request && answer.request != nil)
                            || (answer.conversation?.attached.count ?? 0) > (before?.conversation?.attached.count ?? 0) {
                    // Something new to show while the list was up (an answer, tabs dropped on the panel): the conversation page.
                    state.session.ai.panelPage[window] = .conversation
                }
            } else if answer == nil, state.session.ai.panelPage[window] == .conversation {
                // Closed, deleted, moved to another Space: the conversation page has nothing left.
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
        for (window, id) in state.session.ai.librarySelection where state.doc.conversations[id] == nil { state.session.ai.librarySelection[window] = nil }
        for (window, id) in state.session.ai.renamingConversation where state.doc.conversations[id] == nil || state.session.ai.panelPage[window] == nil {
            state.session.ai.renamingConversation[window] = nil
        }
        for (window, request) in state.session.ai.pendingConversationDeletion where state.doc.windows[window] == nil || state.doc.conversations[request.id] == nil {
            state.session.ai.pendingConversationDeletion[window] = nil
        }
        // The pointer can only be over a list row or a chip of a panel that is open.
        for (window, id) in state.session.ai.hoveredConversation where state.session.ai.panelPage[window] == nil || state.doc.conversations[id] == nil {
            state.session.ai.hoveredConversation[window] = nil
        }
        for (window, chip) in state.session.ai.hoveredChip where !(state.session.ai.answers[window]?.conversation?.attached.contains { $0.id == chip } ?? false) {
            state.session.ai.hoveredChip[window] = nil
        }
        for (id, _) in state.session.ai.turnStarted where state.liveAnswer(id)?.busy != true { state.session.ai.turnStarted[id] = nil }
    }
}
