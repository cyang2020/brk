import BrkBase
import Foundation

// Live conversations (docs/design/ai-conversations.md, ai-right-panel.md). A conversation's live state is an
// `AIAnswerSnapshot` in one of two places: a window's panel (`AISession.answers`), or out of sight in
// `AISession.awayAnswers` while a turn of it still runs after the panel closed, the window moved to another Space or
// another conversation took the panel. Once its first message goes out it is saved in `Doc.conversations` with the Space
// it was started in; it gets no sidebar row. Every finished turn writes the transcript back.

/// Where a live conversation is.
enum AIAnswerHost: Hashable, Sendable {
    case panel(WindowID)
    /// Out of sight: its turn runs on and its answer lands in the saved transcript.
    case away(AIRequestID)
}

extension AISession {
    subscript(host host: AIAnswerHost) -> AIAnswerSnapshot? {
        get {
            switch host {
            case .panel(let window): answers[window]
            case .away(let id): awayAnswers[id]
            }
        }
        set {
            switch host {
            case .panel(let window): answers[window] = newValue
            case .away(let id): awayAnswers[id] = newValue
            }
        }
    }

    /// The live answer whose running turn is `id`.
    func host(ofRequest id: AIRequestID) -> AIAnswerHost? {
        if let window = answers.first(where: { $0.value.request == id })?.key { return .panel(window) }
        if let conversation = awayAnswers.first(where: { $0.value.request == id })?.key { return .away(conversation) }
        return nil
    }

    func host(ofConversation id: AIRequestID) -> AIAnswerHost? {
        if let window = answers.first(where: { $0.value.conversation?.id == id })?.key { return .panel(window) }
        return awayAnswers[id] != nil ? .away(id) : nil
    }

    /// Every conversation with live state, wherever it is.
    var liveConversations: Set<AIRequestID> {
        Set(answers.values.compactMap { $0.conversation?.id }).union(awayAnswers.keys)
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
        conversation.pick = pick
        return AIAnswerSnapshot(request: nil, title: title, text: "", busy: false, sources: [], conversation: conversation)
    }

    /// The transcript as text, for an agent that cannot continue its own session: what the user and the agent said,
    /// the newest last, at most `limit` characters.
    public func history(limit: Int = 24_000) -> String {
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

    /// What a conversation is called: its saved title, which starts as its first message and changes when the small model
    /// names it or the user renames it.
    func conversationName(_ id: AIRequestID) -> String? { doc.conversations[id]?.title }

    func pageSnapshot(_ record: AIPageRecord, height: Int? = nil) -> AIPageSnapshot {
        let kept = doc.tree.allTabs().contains { AIPageTab.id(of: tab($0)?.url) == record.id }
            || doc.archive.contains { AIPageTab.id(of: $0.tab.url) == record.id }
        var snapshot = AIPageSnapshot(id: record.id, title: record.title, html: record.html, height: height ?? record.height, data: record.data, kept: kept)
        snapshot.saved = record.saved
        snapshot.saveSchema = record.saveSchema
        snapshot.revision = record.revision ?? 0
        snapshot.schedule = record.live?.schedule
        if doc.conversations[record.conversation] != nil { snapshot.conversation = record.conversation }
        return snapshot
    }

    /// The kept pages a window's cards show. Their caption rows speak their conversation's language.
    func aiPageCards(in window: WindowID, system: String) -> [AIPageCard] {
        shownNativePages(in: window).compactMap { page, url in
            guard let id = AIPageTab.id(of: url) else { return nil }
            let content = doc.aiPages[id].map { record -> AIPageSnapshot in
                var snapshot = pageSnapshot(record)
                if let stored = doc.conversations[record.conversation] {
                    snapshot.language = AILanguage.of(liveAnswer(stored.id)?.conversation?.items ?? stored.items, system: system)
                } else { snapshot.language = AILanguage.system(system) }
                return snapshot
            }
            return AIPageCard(page: page, content: content)
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

    /// A conversation's turn runs, in a panel or out of sight.
    func conversationBusy(_ id: AIRequestID) -> Bool {
        session.ai.host(ofConversation: id).flatMap { session.ai[host: $0]?.busy } ?? false
    }
}

extension Work {
    /// The window a live conversation's turns run in.
    func window(of host: AIAnswerHost) -> WindowID? {
        switch host {
        case .panel(let window): window
        case .away(let id): state.session.ai.awayWindows[id]
        }
    }

    /// The first message of a conversation went out: it is saved, with the Space the window shows. It gets no sidebar row;
    /// the panel keeps showing it, and this Space's list has it.
    mutating func saveConversation(_ id: AIRequestID, title: String, in window: WindowID) {
        guard state.doc.conversations[id] == nil, let profile = state.agentProfile(in: window),
              let live = state.session.ai.host(ofConversation: id).flatMap({ state.session.ai[host: $0]?.conversation }) else { return }
        var stored = StoredConversation(id: id, profile: profile, title: ConversationPage.title(from: title), createdAt: ctx.now, tabs: live.tabs, folder: live.folder)
        stored.items = Self.kept(live.items)
        stored.space = state.doc.windows[window]?.space
        state.doc.conversations[id] = stored
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

    /// The panel is about to show something else, or close. A saved conversation in it is put away: a running turn
    /// goes on out of sight and lands in the saved transcript (its list row shows the spinner); an idle one keeps nothing
    /// live. True when it was moved.
    @discardableResult
    mutating func putAwayPanelConversation(in window: WindowID) -> Bool {
        guard let answer = state.session.ai.answers[window], let id = answer.conversation?.id, state.doc.conversations[id] != nil,
              answer.conversation?.ended == false else { return false }
        commitConversation(id)
        state.session.ai.answers[window] = nil
        state.session.ai.answerContexts[window] = nil
        if answer.busy {
            state.session.ai.awayAnswers[id] = answer
            state.session.ai.awayWindows[id] = window
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

    /// The row that shows `url`: one of this profile's open rows (Pinned and Today of every Space, then Favorites); else one
    /// from the archive, brought back; else, with `create`, a new one at the top of the window's Today.
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

    /// Conversations out of sight that are idle keep nothing live (their transcript is saved); a conversation that lost
    /// its live state closes its session and every process it started. A conversation row that came back into the
    /// sidebar (an old folder restored from the archive, an undo, a typed `brk://conversation/` address) goes again, and
    /// the conversation shows in that window's panel instead.
    mutating func reconcileConversations(from previous: AppState) {
        dropConversationRows(showing: true)
        for (id, answer) in state.session.ai.awayAnswers where !answer.busy {
            commitConversation(id)
            state.session.ai.awayAnswers[id] = nil
            state.session.ai.awayWindows[id] = nil
        }
        for (id, window) in state.session.ai.awayWindows where state.doc.windows[window] == nil {
            state.session.ai.awayWindows[id] = nil
            if state.session.ai.awayAnswers[id]?.busy == true { state.session.ai.awayAnswers[id] = nil }
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

    /// Takes every conversation row out of the shared sidebar: Pinned, Today, folders, splits and Favorites. With
    /// `showing`, a window that showed one shows its conversation in the panel instead.
    mutating func dropConversationRows(showing: Bool) {
        let rows = state.doc.tree.allTabs().compactMap { row -> (ItemID, AIRequestID)? in
            guard let tab = state.tab(row), let id = ConversationPage.id(of: tab.url) ?? ConversationPage.id(of: tab.pinnedURL) else { return nil }
            return (row, id)
        }
        guard !rows.isEmpty else { return }
        for (row, id) in rows {
            let showers = showing ? state.doc.windows.keys.sorted().filter { state.shownItem(in: $0).map { $0 == row || state.panes(of: $0).contains(row) } ?? false } : []
            _ = removeItem(row)
            unload(row)
            replaceShown(row)
            for window in showers where state.doc.conversations[id] != nil { showConversationInPanel(id, in: window) }
        }
    }
}

extension Work {
    /// The saved conversations and pages, read at launch. Those of a profile that is gone are left out.
    ///
    /// Before step 8 (docs/design/ai-right-panel.md) every conversation had a sidebar row, and its Space was where the row
    /// was. The first launch after it moves that into the conversation: each one records the Space its row was in (an
    /// archived row's Space before it was archived; a Favorite's, or none, the Space it was started in; a Space that is gone,
    /// the profile's first), takes a name the user gave the row, and gets the tabs it used back from its transcript. Then
    /// every conversation row and archived conversation entry goes. Folders left empty stay, as Arc keeps them; kept AI
    /// pages' rows are untouched.
    mutating func conversationsLoaded(_ conversations: [StoredConversation], _ pages: [AIPageRecord]) {
        for conversation in conversations where state.doc.profiles[conversation.profile] != nil && state.doc.conversations[conversation.id] == nil {
            var kept = conversation
            kept.items = Self.kept(conversation.items)
            state.doc.conversations[conversation.id] = kept
        }
        for page in pages where state.doc.profiles[page.profile] != nil && state.doc.aiPages[page.id] == nil {
            state.doc.aiPages[page.id] = page
        }
        migrateConversationRows()
    }

    private mutating func migrateConversationRows() {
        let places = state.legacyConversationPlaces()
        for (id, place) in places {
            guard var stored = state.doc.conversations[id] else { continue }
            let before = stored
            stored.space = place.space
            if let name = place.name, stored.userNamed != true, name != stored.title {
                stored.title = name
                stored.userNamed = true
            }
            if stored != before { state.doc.conversations[id] = stored }
        }
        for (id, stored) in state.doc.conversations where stored.usedTabs == nil {
            let recovered = state.recoveredTabs(stored)
            if !recovered.isEmpty { state.doc.conversations[id]?.usedTabs = recovered }
        }
        state.doc.archive.removeAll { $0.structure == nil && ConversationPage.shows($0.tab.url) }
        dropConversationRows(showing: false)
    }
}

extension AppState {
    /// Where the conversations of every profile were before step 8: the Space whose Pinned or Today held a row of it; a
    /// Favorite, or one with no row at all, the Space it was started in; an archived one the Space it was archived from. A
    /// Space that is gone gives way to the profile's first. With the name the user gave a row, if any.
    func legacyConversationPlaces() -> [AIRequestID: (space: SpaceID?, name: String?)] {
        var out: [AIRequestID: (space: SpaceID?, name: String?)] = [:]
        func id(_ row: ItemID) -> AIRequestID? { ConversationPage.id(of: tab(row)?.url) ?? ConversationPage.id(of: tab(row)?.pinnedURL) }
        func name(_ row: ItemID) -> String? { tab(row)?.customTitle.flatMap { $0.isEmpty ? nil : $0 } }
        for sid in doc.spaceOrder {
            guard let space = doc.spaces[sid] else { continue }
            for row in doc.tree.tabs(under: space.pinnedRoot) + doc.tree.tabs(under: space.todayRoot) {
                guard let conversation = id(row), out[conversation] == nil, doc.conversations[conversation]?.profile == space.profile else { continue }
                out[conversation] = (sid, name(row))
            }
        }
        for (profile, root) in doc.favorites {
            for row in doc.tree.tabs(under: root) {
                guard let conversation = id(row), out[conversation] == nil, let stored = doc.conversations[conversation], stored.profile == profile else { continue }
                out[conversation] = (stored.space, name(row))
            }
        }
        for entry in doc.archive where entry.structure == nil {
            guard let conversation = ConversationPage.id(of: entry.tab.url), out[conversation] == nil, let stored = doc.conversations[conversation] else { continue }
            out[conversation] = (entry.fromSpace ?? stored.space, entry.tab.customTitle.flatMap { $0.isEmpty ? nil : $0 })
        }
        for (key, place) in out {
            guard let profile = doc.conversations[key]?.profile else { continue }
            let spaces = doc.spaceOrder.filter { doc.spaces[$0]?.profile == profile }
            if place.space.map({ !spaces.contains($0) }) ?? true { out[key]?.space = spaces.first }
        }
        return out
    }

    /// The tabs an older conversation used, as far as its transcript tells: the `brk://tab/<id>` links in the agent's
    /// answers that name a tab still in the sidebar, and the tabs named in Brk's "附上 …" lines, found by their title in the
    /// conversation's Space and the profile's Favorites. The chips' ids were never saved, so a title is the best left.
    func recoveredTabs(_ stored: StoredConversation) -> [ItemID] {
        var out: [ItemID] = []
        func add(_ id: ItemID) { if !out.contains(id) { out.append(id) } }
        let pattern = try? NSRegularExpression(pattern: #"brk://tab/([^)\s\]]+)"#)
        var spaceTabs: [ItemID] = []
        if let space = stored.space.flatMap({ doc.spaces[$0] }) { spaceTabs = doc.tree.tabs(under: space.pinnedRoot) + doc.tree.tabs(under: space.todayRoot) }
        if let root = doc.favorites[stored.profile] { spaceTabs += doc.tree.tabs(under: root) }
        for item in stored.items {
            switch item {
            case .assistant(let text):
                guard let pattern else { continue }
                for match in pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                    guard let range = Range(match.range(at: 1), in: text) else { continue }
                    let raw = String(text[range])
                    let id = ItemID(raw.removingPercentEncoding ?? raw)
                    if locate(id) == .global, tab(id) != nil, browsingContext(of: id) == .profile(stored.profile) { add(id) }
                }
            case .notice(let text):
                guard let names = AIWords.attachedNames(text) else { continue }
                for name in names {
                    if let row = spaceTabs.first(where: { !out.contains($0) && tab($0)?.displayTitle == name }) { add(row) }
                }
            default: continue
            }
        }
        return out
    }
}
