import BrkBase
import Foundation

// Giving tabs to the panel's conversation (docs/design/ai-native.md, "把 tab 交给 agent"): a drop on the panel, Ask AI in
// a sidebar menu, or a pick after @. What is given shows as chips in the input and goes with the next message; the agent
// reads the text itself with Brk's tools, so nothing here copies page text.

extension Work {
    /// At most this many tabs wait in the chips at once.
    static let attachedTabsLimit = 50

    mutating func attachToConversation(_ sources: [AIAttachmentSource], in window: WindowID) {
        // The window's panel takes what is given; with no conversation in it, the conversation tab the window shows does.
        if state.session.ai.answers[window]?.conversation == nil, let shown = state.conversationCards(in: window).first?.answer.conversation?.id,
           let host = reviveConversation(shown, in: window) {
            attachToConversation(sources, at: host, window: window)
            return
        }
        attachToConversation(sources, at: .panel(window), window: window)
    }

    mutating func attachToConversation(_ sources: [AIAttachmentSource], at host: AIAnswerHost, window: WindowID) {
        guard let profile = state.agentProfile(in: window) else { return }
        let made = sources.flatMap { attachments(for: $0, profile: profile, window: window) }
        guard !made.isEmpty else { return }
        if var answer = state.session.ai[host: host], var conversation = answer.conversation, !conversation.ended {
            guard conversation.tabs else {
                conversation.items.append(.notice(AIWords.cannotReadTabs(aiLanguage(conversation.items))))
                answer.conversation = conversation
                state.session.ai[host: host] = answer
                return
            }
            conversation.attached = Self.merged(conversation.attached, made)
            conversation.mention = nil
            answer.conversation = conversation
            state.session.ai[host: host] = answer
            return
        }
        guard case .panel = host else { return }
        startFreshConversation(in: window, attached: made)
    }

    /// A new conversation in the panel with Brk's tab tools, waiting for its first message; its session starts with that
    /// message. The one the panel showed is put away first (its tab keeps it).
    mutating func startFreshConversation(in window: WindowID, attached made: [AIAttachment]) {
        putAwayPanelConversation(in: window)
        cancelAI(in: window, slot: .panel)
        let id = AIRequestID(ctx.newID())
        var conversation = AIConversationSnapshot(id: id, tabs: true)
        conversation.fresh = true
        conversation.attached = Self.merged([], made)
        state.session.ai.answerContexts[window] = state.libraryContext(in: window)
        state.session.ai.answers[window] = AIAnswerSnapshot(request: nil, title: Self.freshTitle, text: "", busy: false, sources: [], conversation: conversation)
        state.session.ai.turnText[id] = 0
        state.session.windows[window]?.overlay = nil
    }
    static let freshTitle = "Ask about your tabs"

    /// The chips with the new ones after them: each thing once, and no more tabs than the limit.
    static func merged(_ existing: [AIAttachment], _ new: [AIAttachment]) -> [AIAttachment] {
        var out = existing
        for attachment in new where !out.contains(where: { $0.kind == attachment.kind && $0.id == attachment.id }) {
            guard out.reduce(0, { $0 + $1.tabs.count }) + attachment.tabs.count <= attachedTabsLimit else { break }
            out.append(attachment)
        }
        return out
    }

    private func attachments(for source: AIAttachmentSource, profile: ProfileID, window: WindowID) -> [AIAttachment] {
        func tab(_ facts: AgentTabFacts) -> AIAttachedTab {
            AIAttachedTab(id: facts.id, title: facts.title, url: facts.url, otherProfile: facts.profile != profile)
        }
        func tabs(under root: ItemID) -> [AIAttachedTab] {
            state.doc.tree.tabs(under: root).compactMap { state.agentTab($0.rawValue, window: window).map(tab) }
        }
        switch source {
        case .tab(let id):
            if state.locate(ItemID(id)) == .global, case .split? = state.doc.tree[ItemID(id)]?.body {
                return tabs(under: ItemID(id)).map { AIAttachment(kind: .tab, id: $0.id, title: $0.title, tabs: [$0]) }
            }
            guard let facts = state.agentTab(id, window: window) else { return [] }
            return [AIAttachment(kind: .tab, id: facts.id, title: facts.title, tabs: [tab(facts)])]
        case .folder(let id):
            guard state.locate(id) == .global, case .folder(let folder)? = state.doc.tree[id]?.body else { return [] }
            let inside = tabs(under: id)
            return inside.isEmpty ? [] : [AIAttachment(kind: .folder, id: id.rawValue, title: folder.title, tabs: Array(inside.prefix(Self.attachedTabsLimit)))]
        case .space(let id):
            guard let space = state.doc.spaces[id] else { return [] }
            let inside = tabs(under: space.pinnedRoot) + tabs(under: space.todayRoot)
            return inside.isEmpty ? [] : [AIAttachment(kind: .space, id: id.rawValue, title: state.displayTitle(of: id), tabs: Array(inside.prefix(Self.attachedTabsLimit)))]
        }
    }

    mutating func detachFromConversation(_ id: String, at host: AIAnswerHost) {
        guard var conversation = state.session.ai[host: host]?.conversation else { return }
        conversation.attached.removeAll { $0.id == id }
        state.session.ai[host: host]?.conversation = conversation
    }

    mutating func mentionChanged(_ query: String?, at host: AIAnswerHost, window: WindowID) {
        guard var conversation = state.session.ai[host: host]?.conversation, conversation.tabs, !conversation.ended else { return }
        guard let query, query.count <= 200, let profile = state.agentProfile(in: window) else {
            conversation.mention = nil
            state.session.ai[host: host]?.conversation = conversation
            return
        }
        let candidates = state.agentOpenTabs(profile: profile, window: window) + state.agentArchivedTabs(profile: profile) + state.agentHistory(profile: profile)
        let matches = AgentMentions.matches(query, in: candidates, currentSpace: state.doc.windows[window]?.space)
        conversation.mention = AIMentionSnapshot(query: query, matches: matches.map { AIAttachedTab(id: $0.id, title: $0.title, url: $0.url, otherProfile: false) })
        state.session.ai[host: host]?.conversation = conversation
        effects.append(.aiMentionSearch(window, query))
    }

    /// The live conversation whose @ list a window's search answers: the panel's, else the shown conversation tab's.
    private func mentionHost(in window: WindowID, query: String) -> AIAnswerHost? {
        if state.session.ai.answers[window]?.conversation?.mention?.query == query { return .panel(window) }
        return state.session.ai.tabAnswers.first { state.session.ai.tabWindows[$0.key] == window && $0.value.conversation?.mention?.query == query }.map { .tab($0.key) }
    }

    mutating func aiMentionMatches(_ window: WindowID, query: String, ids: [String]) {
        guard let host = mentionHost(in: window, query: query), var conversation = state.session.ai[host: host]?.conversation,
              var mention = conversation.mention, mention.query == query, let profile = state.agentProfile(in: window) else { return }
        for id in ids where mention.matches.count < AgentMentions.limit && !mention.matches.contains(where: { $0.id == id }) {
            guard let facts = state.agentTab(id, window: window), facts.profile == profile else { continue }
            mention.matches.append(AIAttachedTab(id: facts.id, title: facts.title, url: facts.url, otherProfile: false))
        }
        conversation.mention = mention
        state.session.ai[host: host]?.conversation = conversation
    }

    /// A tab link in an answer: shows the tab, or brings it back from the archive, or opens the visit's address again.
    /// Only the conversation's own profile; a link to anything else does nothing.
    mutating func openTabLink(_ id: String, in window: WindowID) {
        guard let profile = state.agentProfile(in: window), let facts = state.agentTab(id, window: window), facts.profile == profile else { return }
        switch facts.place {
        case .archive:
            run(.archive(.restore(ArchiveID(String(id.dropFirst(AgentTabID.archivePrefix.count))))), in: window)
        case .history:
            guard let url = facts.url, let space = state.doc.windows[window]?.space else { return }
            openTab(url, inSpace: space, window: window, focus: true)
        case .favorite, .pinned, .today:
            if let space = facts.space, state.doc.windows[window]?.space != space { run(.space(.focus(space)), in: window) }
            run(.tab(.focus(ItemID(id))), in: window)
        }
    }

    /// What goes with a message: the chips' tabs, and one quiet line in the transcript naming them.
    mutating func takeAttachments(_ conversation: inout AIConversationSnapshot) -> [AIAttachment] {
        let attached = conversation.attached
        conversation.attached = []
        conversation.mention = nil
        guard !attached.isEmpty else { return [] }
        let language = aiLanguage(conversation.items)
        let names = attached.map { $0.kind == .tab ? $0.title : AIWords.group($0.title, tabs: $0.tabs.count, language) }
        conversation.items.append(.notice(AIWords.with(names, language)))
        return attached
    }

    /// The language Brk's own words take in a conversation with these items (`AILanguage.of`).
    func aiLanguage(_ items: [AIConversationItem]) -> AILanguage { AILanguage.of(items, system: ctx.systemLanguage) }

    /// The user's message goes into the transcript. The first one sets the conversation's language: Brk's notices from
    /// before it, written in the system's language, are written again in that one (`AIWords.reword`).
    func appendUserMessage(_ text: String, to conversation: inout AIConversationSnapshot) {
        let first = !conversation.items.contains { if case .user = $0 { true } else { false } }
        if first, let language = AILanguage.of(text: text), language != aiLanguage(conversation.items) {
            conversation.items = conversation.items.map { if case .notice(let notice) = $0 { .notice(AIWords.reword(notice, to: language)) } else { $0 } }
        }
        conversation.items.append(.user(text))
    }
}

/// The @ list's plain matching: words of the query in the title, then in the address. A search by meaning adds its own
/// matches through `SystemEvent.aiMentionMatches`.
public enum AgentMentions {
    public static let limit = 8

    public static func matches(_ query: String, in candidates: [AgentTabFacts], currentSpace: SpaceID?) -> [AgentTabFacts] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        var seen = Set<String>()
        var unique: [AgentTabFacts] = []
        for facts in candidates {
            // A visit to an address that is open, or a second visit, adds nothing.
            let key = facts.url?.absoluteString ?? facts.id
            guard seen.insert(key).inserted else { continue }
            unique.append(facts)
        }
        guard !words.isEmpty else {
            return Array(unique.filter { $0.space == currentSpace && $0.place != .archive && $0.place != .history }.sorted { $0.at > $1.at }.prefix(limit))
        }
        func all(_ text: String) -> Bool { let lower = text.lowercased(); return words.allSatisfy(lower.contains) }
        let byTitle = unique.filter { all($0.title) }
        let byAddress = unique.filter { !all($0.title) && all($0.url?.absoluteString ?? "") }
        return Array((byTitle + byAddress).prefix(limit))
    }
}
