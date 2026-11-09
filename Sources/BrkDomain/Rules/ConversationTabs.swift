import BrkBase
import Foundation

// Conversations as tabs (docs/design/ai-conversations.md). A conversation's live state is an `AIAnswerSnapshot` in one
// of two places: a window's panel (`AISession.answers`, as before) or its own entry in `AISession.tabAnswers` while its
// tab shows it or a turn of it still runs out of sight. Once its first message goes out it is saved in
// `Doc.conversations` and gets a sidebar row; every finished turn writes the transcript back. A conversation shows in one
// place at a time: showing its tab takes it out of any panel.

/// Where a live conversation is.
enum AIAnswerHost: Hashable, Sendable {
    case panel(WindowID)
    case tab(AIRequestID)
}

extension AISession {
    subscript(host host: AIAnswerHost) -> AIAnswerSnapshot? {
        get {
            switch host {
            case .panel(let window): answers[window]
            case .tab(let id): tabAnswers[id]
            }
        }
        set {
            switch host {
            case .panel(let window): answers[window] = newValue
            case .tab(let id): tabAnswers[id] = newValue
            }
        }
    }

    /// The live answer whose running turn is `id`.
    func host(ofRequest id: AIRequestID) -> AIAnswerHost? {
        if let window = answers.first(where: { $0.value.request == id })?.key { return .panel(window) }
        if let conversation = tabAnswers.first(where: { $0.value.request == id })?.key { return .tab(conversation) }
        return nil
    }

    func host(ofConversation id: AIRequestID) -> AIAnswerHost? {
        if let window = answers.first(where: { $0.value.conversation?.id == id })?.key { return .panel(window) }
        return tabAnswers[id] != nil ? .tab(id) : nil
    }

    /// Every conversation with live state, wherever it is.
    var liveConversations: Set<AIRequestID> {
        Set(answers.values.compactMap { $0.conversation?.id }).union(tabAnswers.keys)
    }
}

extension StoredConversation {
    /// What the searches read (`ConversationSearch`): the title, and everything that was said.
    public var candidate: ConversationCandidate {
        let text = messages.compactMap { _, item -> String? in
            switch item {
            case .user(let value) where value == title: nil
            case .user(let value), .assistant(let value): value
            case .page(let page): page.title
            default: nil
            }
        }.joined(separator: "\n")
        return ConversationCandidate(id: id, title: title, text: text)
    }

    /// The saved transcript as a view shows it, with no session behind it: the next message starts one.
    func snapshot() -> AIAnswerSnapshot {
        var conversation = AIConversationSnapshot(id: id, folder: folder, tabs: tabs)
        conversation.agent = agent
        conversation.agentName = agentName
        conversation.model = model
        conversation.effort = effort
        conversation.items = items
        conversation.dormant = true
        return AIAnswerSnapshot(request: nil, title: title, text: "", busy: false, sources: [], conversation: conversation)
    }

    /// The transcript as text, for an agent that cannot continue its own session: what the user and the agent said,
    /// the newest last, at most `limit` characters.
    func history(limit: Int = 24_000) -> String {
        var lines: [String] = []
        for (_, item) in messages {
            switch item {
            case .user(let text): lines.append("User: " + text)
            case .assistant(let text): lines.append("Assistant: " + text)
            case .page(let page): lines.append("Assistant rendered a page: “\(page.title)” (pageId \(page.id.rawValue))")
            default: break
            }
        }
        var out = lines.joined(separator: "\n\n")
        if out.count > limit { out = "…" + String(out.suffix(limit)) }
        return out
    }
}

extension AppState {
    /// Every saved conversation and rendered page, for the files that keep them and the agent's read tools.
    public var savedConversations: [AIRequestID: StoredConversation] { doc.conversations }
    public var savedPages: [AIPageID: AIPageRecord] { doc.aiPages }

    /// The conversations of `profile`, most recently changed first.
    public func conversations(of profile: ProfileID) -> [StoredConversation] {
        doc.conversations.values.filter { $0.profile == profile }.sorted { ($0.updatedAt, $0.id.rawValue) > ($1.updatedAt, $1.id.rawValue) }
    }

    /// The pages a conversation's items show, as views need them.
    func withPages(_ answer: AIAnswerSnapshot) -> AIAnswerSnapshot {
        guard let items = answer.conversation?.items, let id = answer.conversation?.id else { return answer }
        var out = answer
        out.pages = items.compactMap { item in
            guard case .page(let ref) = item, let record = doc.aiPages[ref.id] else { return nil }
            return pageSnapshot(record, height: ref.height)
        }
        out.name = conversationName(id)
        return out
    }

    /// What a conversation is called: its tab's own title once someone (the user, Name Tabs) gave it one, else its saved
    /// title, which starts as its first message.
    func conversationName(_ id: AIRequestID) -> String? {
        let url = ConversationPage.url(id)
        if let custom = doc.tree.allTabs().lazy.compactMap({ tab($0) }).first(where: { $0.url == url })?.customTitle, !custom.isEmpty { return custom }
        return doc.conversations[id]?.title
    }

    func pageSnapshot(_ record: AIPageRecord, height: Int? = nil) -> AIPageSnapshot {
        let kept = doc.tree.allTabs().contains { AIPageTab.id(of: tab($0)?.url) == record.id }
            || doc.archive.contains { AIPageTab.id(of: $0.tab.url) == record.id }
        var snapshot = AIPageSnapshot(id: record.id, title: record.title, html: record.html, height: height ?? record.height, data: record.data, kept: kept)
        snapshot.saved = record.saved
        snapshot.saveSchema = record.saveSchema
        snapshot.revision = record.revision ?? 0
        snapshot.schedule = record.live?.schedule
        return snapshot
    }

    /// The conversation tabs a window's cards show, with what each shows: its live state or its saved transcript.
    func conversationCards(in window: WindowID) -> [ConversationCard] {
        shownNativePages(in: window).compactMap { page, url in
            guard let id = ConversationPage.id(of: url) else { return nil }
            if case .tab? = session.ai.host(ofConversation: id), let live = session.ai.tabAnswers[id] { return ConversationCard(page: page, answer: withPages(live)) }
            guard let stored = doc.conversations[id] else {
                return ConversationCard(page: page, answer: AIAnswerSnapshot(request: nil, title: ConversationPage.untitled,
                                                                             text: "This conversation is no longer saved.", busy: false, sources: []))
            }
            return ConversationCard(page: page, answer: withPages(stored.snapshot()))
        }
    }

    func aiPageCards(in window: WindowID) -> [AIPageCard] {
        shownNativePages(in: window).compactMap { page, url in
            guard let id = AIPageTab.id(of: url) else { return nil }
            return AIPageCard(page: page, content: doc.aiPages[id].map { pageSnapshot($0) })
        }
    }

    /// The panes a window shows that hold one of Brk's own pages, and their addresses.
    func shownNativePages(in window: WindowID) -> [(PageID, URL)] {
        guard let shown = shownItem(in: window) else { return [] }
        return panes(of: shown).compactMap { pane in
            let page = PageID(window: window, item: pane)
            guard session.loaded.contains(page), let url = address(of: pane, in: window, for: .visible), NativePages.shows(url) else { return nil }
            return (page, url)
        }
    }

    /// Conversations some window's cards show now.
    var shownConversations: Set<AIRequestID> {
        Set(doc.windows.keys.flatMap { window in shownNativePages(in: window).compactMap { ConversationPage.id(of: $0.1) } })
    }

    /// A conversation is busy in a panel or tab.
    func conversationBusy(_ id: AIRequestID) -> Bool {
        session.ai.host(ofConversation: id).flatMap { session.ai[host: $0]?.busy } ?? false
    }
}

extension Work {
    /// Where a conversation intent from `window` acts: the conversation tab that sent it, else the window's panel.
    func host(for window: WindowID, tab: AIRequestID?) -> AIAnswerHost {
        guard let tab else { return .panel(window) }
        if case .panel(let other)? = state.session.ai.host(ofConversation: tab) { return .panel(other) }
        return .tab(tab)
    }

    /// The window a live conversation's turns run in.
    func window(of host: AIAnswerHost) -> WindowID? {
        switch host {
        case .panel(let window): window
        case .tab(let id): state.session.ai.tabWindows[id]
        }
    }

    /// The conversation's live state, made from its saved transcript when it has none (a tab shown after a relaunch,
    /// a conversation put away). Only the window's own profile. The session starts with the next message.
    mutating func reviveConversation(_ id: AIRequestID, in window: WindowID) -> AIAnswerHost? {
        if let host = state.session.ai.host(ofConversation: id) {
            if case .tab = host { state.session.ai.tabWindows[id] = window }
            return host
        }
        guard let stored = state.doc.conversations[id], stored.profile == state.agentProfile(in: window) else { return nil }
        state.session.ai.tabAnswers[id] = stored.snapshot()
        state.session.ai.tabWindows[id] = window
        state.session.ai.turnText[id] = 0
        return .tab(id)
    }

    /// The first message of a conversation went out: it is saved, and gets a row at the top of the window's Today
    /// (where a new tab goes), not shown; the panel keeps showing it.
    mutating func saveConversation(_ id: AIRequestID, title: String, in window: WindowID) {
        guard state.doc.conversations[id] == nil, let profile = state.agentProfile(in: window),
              let live = state.session.ai.host(ofConversation: id).flatMap({ state.session.ai[host: $0]?.conversation }) else { return }
        var stored = StoredConversation(id: id, profile: profile, title: ConversationPage.title(from: title), createdAt: ctx.now, tabs: live.tabs, folder: live.folder)
        stored.items = Self.kept(live.items)
        stored.space = state.doc.windows[window]?.space
        state.doc.conversations[id] = stored
        _ = conversationRow(id, in: window, create: true)
    }

    /// The live transcript written back into the saved conversation.
    mutating func commitConversation(_ id: AIRequestID) {
        guard var stored = state.doc.conversations[id], let host = state.session.ai.host(ofConversation: id),
              let live = state.session.ai[host: host]?.conversation else { return }
        let items = Self.kept(live.items)
        guard items != stored.items || live.agent != stored.agent || live.model != stored.model else { return }
        stored.items = items
        stored.agent = live.agent ?? stored.agent
        stored.agentName = live.agentName ?? stored.agentName
        stored.model = live.model ?? stored.model
        stored.effort = live.effort ?? stored.effort
        stored.updatedAt = ctx.now
        state.doc.conversations[id] = stored
    }

    /// What a saved transcript keeps: approvals still waiting go with their turn.
    static func kept(_ items: [AIConversationItem]) -> [AIConversationItem] {
        items.filter { if case .approval(let a) = $0 { a.answer != nil } else { true } }
    }

    /// The row that shows conversation `id`: one of this profile's open rows (Pinned and Today of every Space, then
    /// Favorites); else one from the archive, brought back; else a new one at the top of the window's Today.
    mutating func conversationRow(_ id: AIRequestID, in window: WindowID, create: Bool) -> ItemID? {
        rowShowing(ConversationPage.url(id), in: window, create: create, title: state.doc.conversations[id]?.title ?? ConversationPage.untitled,
                   favicon: ConversationPage.favicon)
    }

    private mutating func rowShowing(_ url: URL, in window: WindowID, create: Bool, title: String, favicon: URL) -> ItemID? {
        guard let doc = state.doc.windows[window], doc.kind == .standard, let profile = state.agentProfile(in: window) else { return nil }
        let same: (ItemID) -> Bool = { [state] row in state.tab(row)?.url == url && state.browsingContext(of: row) == .profile(profile) }
        let order = [doc.space] + state.doc.spaceOrder.filter { $0 != doc.space }
        for space in order.compactMap({ state.doc.spaces[$0] }) where space.profile == profile {
            if let row = (state.doc.tree.tabs(under: space.pinnedRoot) + state.doc.tree.tabs(under: space.todayRoot)).first(where: same) { return row }
        }
        if let root = state.doc.favorites[profile], let row = state.doc.tree.tabs(under: root).first(where: same) { return row }
        if let archived = state.doc.archive.first(where: { $0.tab.url == url }) {
            let before = Set(state.doc.tree.allTabs())
            run(.archive(.restore(archived.id)), in: window)
            if let row = state.doc.tree.allTabs().first(where: { !before.contains($0) && state.tab($0)?.url == url }) { return row }
        }
        guard create, let today = state.doc.spaces[doc.space]?.todayRoot else { return nil }
        let row = ItemID(ctx.newID())
        do {
            try state.doc.tree.insert(row, .tab(Tab(url: url, title: title, favicon: favicon, lastActiveAt: ctx.now)), at: .into(parent: today, index: 0), createdAt: ctx.now)
        } catch { return nil }
        return row
    }

    /// Shows conversation `id` in its tab in `window`. Its live state, if a panel had it, moves with it.
    mutating func openConversationTab(_ id: AIRequestID, in window: WindowID) {
        guard let stored = state.doc.conversations[id], stored.profile == state.agentProfile(in: window),
              let row = conversationRow(id, in: window, create: true) else { return }
        focus(row, in: window)
        request(ConversationPage.url(id), for: PageID(window: window, item: row))
        moveToTab(id, window: window)
    }

    /// A panel's conversation becomes a tab conversation: same session, same turn.
    mutating func moveToTab(_ id: AIRequestID, window: WindowID) {
        guard case .panel(let panel)? = state.session.ai.host(ofConversation: id), let answer = state.session.ai.answers[panel] else { return }
        state.session.ai.answers[panel] = nil
        state.session.ai.answerContexts[panel] = nil
        state.session.ai.tabAnswers[id] = answer
        state.session.ai.tabWindows[id] = window
    }

    /// The panel's Open as Tab. A conversation that has no message yet is saved first, so it has a row.
    mutating func openPanelAsTab(in window: WindowID) {
        guard let conversation = state.session.ai.answers[window]?.conversation, !conversation.ended else { return }
        if state.doc.conversations[conversation.id] == nil {
            let first = conversation.items.lazy.compactMap { if case .user(let text) = $0 { text } else { nil } }.first
            saveConversation(conversation.id, title: first ?? ConversationPage.untitled, in: window)
        }
        openConversationTab(conversation.id, in: window)
    }

    /// The panel is about to show something else, or close. A saved conversation in it is put away: a running turn
    /// goes on out of sight and lands in the saved transcript; an idle one keeps nothing live. True when it was moved.
    @discardableResult
    mutating func putAwayPanelConversation(in window: WindowID) -> Bool {
        guard let answer = state.session.ai.answers[window], let id = answer.conversation?.id, state.doc.conversations[id] != nil,
              answer.conversation?.ended == false else { return false }
        commitConversation(id)
        state.session.ai.answers[window] = nil
        state.session.ai.answerContexts[window] = nil
        if answer.busy {
            state.session.ai.tabAnswers[id] = answer
            state.session.ai.tabWindows[id] = window
        }
        return true
    }

    // MARK: Pages

    /// The agent rendered a page: its record is saved and it shows in the transcript where it was made.
    mutating func aiPageRendered(_ id: AIRequestID, _ record: AIPageRecord) {
        guard record.conversation == id, let host = state.session.ai.host(ofConversation: id), var answer = state.session.ai[host: host],
              var conversation = answer.conversation, record.profile == state.doc.conversations[id]?.profile ?? record.profile else { return }
        var record = record
        record.createdAt = ctx.now
        record.height = AIPageLimits.height(record.height)
        record.title = String(record.title.trimmingCharacters(in: .whitespacesAndNewlines).prefix(AIPageLimits.titleMax))
        state.doc.aiPages[record.id] = record
        // The page comes after what the agent has written so far; its next words start a new row under it.
        if answer.busy, case .assistant? = conversation.items.last { state.session.ai.turnText[id] = answer.text == Self.waitingText ? 0 : answer.text.count }
        conversation.items.append(.page(AIPageRef(id: record.id, title: record.title, height: record.height)))
        answer.conversation = conversation
        state.session.ai[host: host] = answer
        commitConversation(id)
    }
    static let waitingText = "Waiting for the local AI tool…"

    /// Keep as Tab on a page in a transcript, or `brk_page_save`: the page gets a row at the top of the window's Today,
    /// shown when the user asked for it. Nil when the page is unknown or another profile's.
    mutating func keepPage(_ id: AIPageID, title: String?, in window: WindowID, show: Bool) -> ItemID? {
        guard let record = state.doc.aiPages[id], record.profile == state.agentProfile(in: window) else { return nil }
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            state.doc.aiPages[id]?.title = String(title.prefix(AIPageLimits.titleMax))
        }
        guard let row = rowShowing(AIPageTab.url(id), in: window, create: true, title: state.doc.aiPages[id]?.title ?? record.title, favicon: AIPageTab.favicon) else { return nil }
        if show {
            focus(row, in: window)
            request(AIPageTab.url(id), for: PageID(window: window, item: row))
        }
        return row
    }

    /// A click on a link in an agent's page. Only http and https; an address new to the profile asks first when the page
    /// was written after page text reached its conversation, as `brk_tab_open` does.
    mutating func pageLink(_ page: AIPageID, _ url: URL, in window: WindowID) {
        guard let record = state.doc.aiPages[page], let profile = state.agentProfile(in: window), record.profile == profile,
              let url = AIValidation.destination(url.absoluteString) else { return }
        let conversation = state.doc.conversations[record.conversation]
        if (record.readPages || conversation?.flagged == true), !state.agentKnows(url, profile: profile) {
            state.session.ai.linkPrompts[window] = AIPageLinkPrompt(page: page, url: url)
            return
        }
        openPageLink(url, in: window)
    }

    mutating func answerPageLink(_ open: Bool, in window: WindowID) {
        guard let prompt = state.session.ai.linkPrompts.removeValue(forKey: window), open else { return }
        openPageLink(prompt.url, in: window)
    }

    private mutating func openPageLink(_ url: URL, in window: WindowID) {
        guard let space = state.doc.windows[window]?.space, state.doc.windows[window]?.kind == .standard else { return }
        openTab(url, inSpace: space, window: window, focus: true)
    }

    // MARK: After every input

    /// Conversations shown in a tab leave any panel; tab conversations that are neither shown nor running keep nothing
    /// live. A conversation that lost its live state closes its session and every process it started.
    mutating func reconcileConversations(from previous: AppState) {
        let shown = state.shownConversations
        for id in shown {
            guard case .panel? = state.session.ai.host(ofConversation: id),
                  let window = state.doc.windows.keys.sorted().first(where: { w in state.shownNativePages(in: w).contains { ConversationPage.id(of: $0.1) == id } }) else { continue }
            moveToTab(id, window: window)
        }
        for (id, answer) in state.session.ai.tabAnswers where !answer.busy && !shown.contains(id) {
            commitConversation(id)
            state.session.ai.tabAnswers[id] = nil
            state.session.ai.tabWindows[id] = nil
        }
        for (id, window) in state.session.ai.tabWindows where state.doc.windows[window] == nil {
            state.session.ai.tabWindows[id] = nil
            if state.session.ai.tabAnswers[id]?.busy == true { state.session.ai.tabAnswers[id] = nil }
        }
        for (window, prompt) in state.session.ai.linkPrompts where state.doc.windows[window] == nil || state.doc.aiPages[prompt.page] == nil {
            state.session.ai.linkPrompts[window] = nil
        }
        let now = state.session.ai.liveConversations
        for id in previous.session.ai.liveConversations.subtracting(now) {
            effects.append(.aiCloseConversation(id))
            state.session.ai.turnText[id] = nil
        }
    }
}

extension Work {
    /// The saved conversations and pages, read at launch. Those of a profile that is gone are left out.
    mutating func conversationsLoaded(_ conversations: [StoredConversation], _ pages: [AIPageRecord]) {
        for conversation in conversations where state.doc.profiles[conversation.profile] != nil && state.doc.conversations[conversation.id] == nil {
            var kept = conversation
            kept.items = Self.kept(conversation.items)
            state.doc.conversations[conversation.id] = kept
        }
        for page in pages where state.doc.profiles[page.profile] != nil && state.doc.aiPages[page.id] == nil {
            state.doc.aiPages[page.id] = page
        }
    }
}
