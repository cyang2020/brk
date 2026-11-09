import BrkBase
import Foundation

// Conversation lists (docs/design/ai-threads.md). The AI panel has two pages, this Space's conversation list and the
// conversation, and a two-finger swipe over the panel moves between them the way the sidebar's swipe moves between
// Spaces. Each Space has its own list: a conversation belongs to the Space whose sidebar holds its row (an archived one to
// the Space it was archived from), so switching Space on the left switches the panel's list and brings back the
// conversation that Space showed last. What waits for the user in another Space of the same profile shows as a strip at
// the top of the list, a ring on that Space's dot and a count on the list icon. The Library's "AI 对话" page lists every
// Space's conversations, and the command bar and both lists search conversations with one search (`ConversationSearch`).

/// The panel's two pages: the list first, as the Library comes before the first Space.
public enum AIPanelPage: String, Hashable, Sendable, Codable {
    case list, conversation
}

/// What a conversation is doing, for its row's second line and its mark.
public enum AIThreadState: String, Hashable, Sendable, Codable, CaseIterable {
    /// The agent waits for the user to answer an approval: a pill in the Space's color.
    case waiting
    /// A reply finished after the conversation was last shown in the panel or its tab: a dot.
    case unread
    /// A turn runs: a spinner.
    case running
    case idle
    /// Its row is in the archive: grey, and a click brings it back.
    case archived

    /// "等你处理": the agent waits, or a reply nobody has seen yet.
    public var needsUser: Bool { self == .waiting || self == .unread }
}

/// The list's groups, in order.
public enum AIThreadGroupKind: String, Hashable, Sendable, Codable, CaseIterable {
    case needsUser, running, today, yesterday, earlier
}

/// One conversation in a list: the panel's, a strip for another Space, or the Library's.
public struct AIThreadRow: Hashable, Sendable, Codable {
    public let id: AIRequestID
    public var title: String
    public var state: AIThreadState
    /// The second line: "想运行一条命令", "2 分钟前回复了", "读了 5 个 tab", "11:32 · 1 个 AI 页面", "已归档".
    public var detail: String
    /// The pill's word on a waiting row ("等你确认"), in the conversation's language; nil on other rows.
    public var pill: String? = nil
    /// The panel shows this conversation now.
    public var current = false
    /// What the search found in what was said, when the title did not have it.
    public var snippet: String? = nil
    public var space: SpaceID?
    public var spaceTitle: String = ""
    public var spaceColor: RGBA = RGBA(0.5, 0.5, 0.5)
    /// The agent's name ("Claude"), nil before a session started.
    public var agent: String? = nil
    public var updatedAt: Instant
    /// How many pages the agent drew in it.
    public var pages: Int = 0
    public var language: AILanguage = .en
    public init(id: AIRequestID, title: String, state: AIThreadState, detail: String, updatedAt: Instant) {
        self.id = id; self.title = title; self.state = state; self.detail = detail; self.updatedAt = updatedAt
    }
}

public struct AIThreadGroup: Hashable, Sendable, Codable {
    public let kind: AIThreadGroupKind
    public let title: String
    public var rows: [AIThreadRow]
    public init(kind: AIThreadGroupKind, title: String, rows: [AIThreadRow]) { self.kind = kind; self.title = title; self.rows = rows }
}

/// The panel as a window shows it (a standard window, the panel open): which page, this Space's list, and the strips of
/// what waits in the profile's other Spaces.
public struct AIPanelSnapshot: Hashable, Sendable, Codable {
    public var page: AIPanelPage
    /// The conversation page has something to show: the panel has two pages to swipe between.
    public var hasConversation: Bool
    public var space: SpaceID
    public var spaceTitle: String
    /// The language of the list's own words (headers, the search box, the composer's hint): the most recent conversations'
    /// that tell, else the system's.
    public var language: AILanguage
    public var search: String
    /// Other Spaces' conversations that wait for the user, newest first.
    public var strips: [AIThreadRow]
    public var groups: [AIThreadGroup]
    /// Everything that waits for the user in this profile, this Space included: the list icon's count.
    public var waiting: Int
    /// The profile's other Spaces, for Move to Another Space.
    public var spaces: [AIThreadSpace]
    /// The row shown as a text field for its new name.
    public var renaming: AIRequestID? = nil
}

/// Delete for good, waiting for Cancel or Delete in the window's dialog.
public struct ConversationDeletionRequest: Hashable, Sendable, Codable {
    public let id: AIRequestID
    public let title: String
    public let pages: Int
    public let language: AILanguage
    public let token: String
    public init(id: AIRequestID, title: String, pages: Int, language: AILanguage, token: String) {
        self.id = id; self.title = title; self.pages = pages; self.language = language; self.token = token
    }
}

/// A Space a conversation can move to, with its dot's color.
public struct AIThreadSpace: Hashable, Sendable, Codable {
    public let id: SpaceID
    public let title: String
    public let color: RGBA
    public init(id: SpaceID, title: String, color: RGBA) { self.id = id; self.title = title; self.color = color }
}

/// What the Library's "AI 对话" page narrows its list to. Empty sets keep everything.
public struct ConversationLibraryQuery: Hashable, Sendable, Codable {
    public enum Chip: String, Hashable, Sendable, Codable, CaseIterable { case all, needsUser, withPages }
    public var text = ""
    public var chip = Chip.all
    public var spaces: Set<SpaceID> = []
    /// Agent names as rows show them ("Claude", "Codex").
    public var agents: Set<String> = []
    public var states: Set<AIThreadState> = []
    public var withPages = false
    public init(text: String = "", chip: Chip = .all, spaces: Set<SpaceID> = [], agents: Set<String> = [], states: Set<AIThreadState> = [], withPages: Bool = false) {
        self.text = text; self.chip = chip; self.spaces = spaces; self.agents = agents; self.states = states; self.withPages = withPages
    }
}

/// The Library's "AI 对话" page: every Space's conversations of the window's profile, the search and filters, and the
/// selected conversation in full.
public struct LibraryConversationsSnapshot: Equatable, Sendable, Codable {
    public var query: ConversationLibraryQuery
    /// Newest first, after the query.
    public var rows: [AIThreadRow]
    public var waiting: Int
    public var withPages: Int
    public var spaces: [AIThreadSpace]
    public var agents: [String]
    public var language: AILanguage
    public var selected: LibraryConversationDetail?
}

public struct LibraryConversationDetail: Equatable, Sendable, Codable {
    public let id: AIRequestID
    public var title: String
    /// "购物 · Claude · Haiku 5.5".
    public var meta: String
    public var space: SpaceID?
    public var state: AIThreadState
    public var answer: AIAnswerSnapshot
}

/// A notice Brk posts to macOS while it is not the frontmost app: an agent waits for approval, or a long reply finished.
/// Clicking it opens the conversation (`AIIntent.showConversation`).
public struct AINotification: Hashable, Sendable, Codable {
    public enum Kind: String, Hashable, Sendable, Codable { case approval, replied }
    public let conversation: AIRequestID
    public let kind: Kind
    public let title: String
    public let body: String
    public init(conversation: AIRequestID, kind: Kind, title: String, body: String) {
        self.conversation = conversation; self.kind = kind; self.title = title; self.body = body
    }
}

// MARK: Search

/// The one conversation search the panel's list, the Library and the command bar share: the title has the text, else
/// every word of it was said (case and accents ignored), with a snippet around the first word.
public enum ConversationSearch {
    public enum Found: Hashable, Sendable { case title, text(snippet: String) }

    public static func fold(_ text: String) -> String { text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil) }

    /// Where `query` is found in a conversation, nil when it is not.
    public static func find(_ query: String, title: String, text: String) -> Found? {
        let needle = fold(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return nil }
        if fold(title).contains(needle) { return .title }
        let words = needle.split(whereSeparator: \.isWhitespace).map(String.init)
        let folded = fold(text)
        guard words.allSatisfy(folded.contains), let first = words.first, let range = folded.range(of: first) else { return nil }
        let at = folded.distance(from: folded.startIndex, to: range.lowerBound)
        let characters = Array(text)
        let start = max(0, min(at, characters.count) - 16), end = min(characters.count, start + 80)
        let snippet = (start > 0 ? "…" : "") + String(characters[start..<end]).split(whereSeparator: \.isNewline).joined(separator: " ")
        return .text(snippet: snippet)
    }

    /// The candidates `query` finds: title matches first, then those found in what was said, each in the given order.
    public static func search(_ query: String, in candidates: [ConversationCandidate]) -> [(ConversationCandidate, Found)] {
        var titled: [(ConversationCandidate, Found)] = [], said: [(ConversationCandidate, Found)] = []
        for candidate in candidates {
            switch find(query, title: candidate.title, text: candidate.text) {
            case .title?: titled.append((candidate, .title))
            case let found?: said.append((candidate, found))
            case nil: break
            }
        }
        return titled + said
    }
}

// MARK: Words

/// The list's and the Library page's own words (docs/design/ai-threads.md), in Chinese or English like the rest of Brk's
/// AI words (`AIWords`): a row's in its conversation's language, the list's own in the language of the most recent
/// conversations that tell.
public enum AIThreadWords {
    public static func listTitle(_ space: String, _ language: AILanguage) -> String { language == .zh ? "\(space) 的对话" : "Conversations in \(space)" }
    public static func search(_ language: AILanguage) -> String { language == .zh ? "搜索这个 Space 的对话" : "Search this Space's conversations" }
    /// The Library's page name: short enough for its 78 pt cell ("AI Conversations" is cut there).
    public static func libraryTitle(_ language: AILanguage) -> String { language == .zh ? "AI 对话" : "Conversations" }
    public static func librarySearch(_ language: AILanguage) -> String { language == .zh ? "搜索对话内容…" : "Search Conversations…" }
    public static func composer(_ language: AILanguage) -> String { language == .zh ? "在这个 Space 开一个新对话" : "Start a new conversation in this Space" }
    public static func empty(_ language: AILanguage) -> String {
        language == .zh ? "这个 Space 还没有对话。在下面输入，开一个新对话。" : "No conversations in this Space yet. Type below to start one."
    }
    public static func noMatches(_ language: AILanguage) -> String { language == .zh ? "没有找到对话" : "No conversations found" }
    public static func group(_ kind: AIThreadGroupKind, _ language: AILanguage) -> String {
        let zh = language == .zh
        switch kind {
        case .needsUser: return zh ? "等你处理" : "Needs You"
        case .running: return zh ? "进行中" : "Running"
        case .today: return zh ? "今天" : "Today"
        case .yesterday: return zh ? "昨天" : "Yesterday"
        case .earlier: return zh ? "更早" : "Earlier"
        }
    }
    public static func pill(_ language: AILanguage) -> String { language == .zh ? "等你确认" : "Needs you" }
    public static func archived(_ language: AILanguage) -> String { language == .zh ? "已归档" : "Archived" }
    public static func answering(_ language: AILanguage) -> String { language == .zh ? "正在回答…" : "Answering…" }
    public static func pages(_ n: Int, _ language: AILanguage) -> String {
        language == .zh ? "\(n) 个 AI 页面" : (n == 1 ? "1 AI page" : "\(n) AI pages")
    }

    /// "想运行一条命令": what the agent waits to do, without its name.
    public static func wants(_ approval: AIAgentApproval, _ language: AILanguage) -> String {
        let marker = "\u{1}"
        let sentence = AIStepWords.approval(approval, agent: marker, folder: nil, language)
        guard sentence.hasPrefix(marker) else { return sentence }
        var rest = String(sentence.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        if language == .en, let first = rest.first { rest = first.uppercased() + rest.dropFirst() }
        return rest
    }

    /// "2 分钟前回复了" / "Replied 2 min ago".
    public static func replied(_ at: Instant, now: Instant, _ language: AILanguage) -> String {
        let minutes = max(0, Int((now.milliseconds - at.milliseconds) / 60_000))
        let zh = language == .zh
        if minutes < 1 { return zh ? "刚刚回复了" : "Replied just now" }
        if minutes < 60 { return zh ? "\(minutes) 分钟前回复了" : "Replied \(minutes) min ago" }
        let hours = minutes / 60
        if hours < 24 { return zh ? "\(hours) 小时前回复了" : (hours == 1 ? "Replied 1 hour ago" : "Replied \(hours) hours ago") }
        let days = hours / 24
        return zh ? "\(days) 天前回复了" : (days == 1 ? "Replied yesterday" : "Replied \(days) days ago")
    }

    /// "11:32" today and yesterday, "11月3日" / "Nov 3" before.
    public static func when(_ at: Instant, now: Instant, calendar: Calendar, _ language: AILanguage) -> String {
        let date = Date(timeIntervalSince1970: Double(at.milliseconds) / 1000)
        let today = calendar.startOfDay(for: Date(timeIntervalSince1970: Double(now.milliseconds) / 1000))
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: today), date >= yesterday { return AIWords.clock(at, calendar: calendar) }
        let parts = calendar.dateComponents(in: calendar.timeZone, from: date)
        let month = parts.month ?? 1, day = parts.day ?? 1
        if language == .zh { return "\(month)月\(day)日" }
        let names = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return "\(names[max(0, min(11, month - 1))]) \(day)"
    }

    // The row menu.
    public static func openInTab(_ language: AILanguage) -> String { language == .zh ? "在 tab 里打开" : "Open in Tab" }
    public static func rename(_ language: AILanguage) -> String { language == .zh ? "重命名" : "Rename" }
    public static func archive(_ language: AILanguage) -> String { language == .zh ? "归档" : "Archive" }
    public static func restore(_ language: AILanguage) -> String { language == .zh ? "恢复" : "Restore" }
    public static func move(_ language: AILanguage) -> String { language == .zh ? "移到别的 Space" : "Move to Another Space" }
    public static func moveEllipsis(_ language: AILanguage) -> String { language == .zh ? "移到别的 Space…" : "Move to Another Space…" }
    public static func noOtherSpace(_ language: AILanguage) -> String { language == .zh ? "这个 profile 没有别的 Space" : "No other Space in this profile" }
    public static func deleteEllipsis(_ language: AILanguage) -> String { language == .zh ? "彻底删除…" : "Delete for Good…" }
    public static func continueConversation(_ language: AILanguage) -> String { language == .zh ? "继续这个对话" : "Continue Conversation" }
    public static func deleteQuestion(_ title: String, _ language: AILanguage) -> String {
        language == .zh ? "彻底删除「\(title)」？" : "Delete “\(title)” for good?"
    }
    public static func deleteDetail(pages: Int, _ language: AILanguage) -> String {
        if language == .zh {
            return pages == 0 ? "对话的全文会被删掉，不能恢复。" : "对话的全文和它画的 \(pages) 个页面都会被删掉，不能恢复。"
        }
        return pages == 0 ? "The whole transcript goes, and it cannot come back."
            : "The whole transcript and the \(pages == 1 ? "page" : "\(pages) pages") it made go, and they cannot come back."
    }
    public static func delete(_ language: AILanguage) -> String { language == .zh ? "删除" : "Delete" }
    public static func cancel(_ language: AILanguage) -> String { language == .zh ? "取消" : "Cancel" }
    public static func list(_ language: AILanguage) -> String { language == .zh ? "对话列表" : "Conversations" }
    public static func backToConversation(_ language: AILanguage) -> String { language == .zh ? "回到对话" : "Back to the conversation" }
    public static func listTip(waiting: Int, _ language: AILanguage) -> String {
        guard waiting > 0 else { return list(language) }
        return language == .zh ? "对话列表 · \(waiting) 个在等你" : "Conversations · \(waiting) need you"
    }
    public static func filterSpace(_ language: AILanguage) -> String { language == .zh ? "Space" : "Space" }
    public static func filterAgent(_ language: AILanguage) -> String { language == .zh ? "agent" : "Agent" }
    public static func filterState(_ language: AILanguage) -> String { language == .zh ? "状态" : "State" }
    public static func filterPages(_ language: AILanguage) -> String { language == .zh ? "有 AI 页面" : "Has AI Pages" }
    public static func filterClear(_ language: AILanguage) -> String { language == .zh ? "清除筛选" : "Clear Filters" }
    public static func filter(_ language: AILanguage) -> String { language == .zh ? "筛选" : "Filter" }
    public static func chip(_ chip: ConversationLibraryQuery.Chip, count: Int, _ language: AILanguage) -> String {
        switch chip {
        case .all: language == .zh ? "全部" : "All"
        case .needsUser: (language == .zh ? "等你处理" : "Needs You") + " \(count)"
        case .withPages: language == .zh ? "有 AI 页面" : "With AI Pages"
        }
    }
    public static func state(_ state: AIThreadState, _ language: AILanguage) -> String {
        let zh = language == .zh
        switch state {
        case .waiting: return zh ? "等你确认" : "Waiting for you"
        case .unread: return zh ? "有新回复" : "New reply"
        case .running: return zh ? "进行中" : "Running"
        case .idle: return zh ? "其他" : "Other"
        case .archived: return zh ? "已归档" : "Archived"
        }
    }
    public static func libraryEmpty(_ language: AILanguage) -> String {
        language == .zh ? "这个 profile 还没有 AI 对话。" : "This profile has no AI conversations yet."
    }
    public static func pickOne(_ language: AILanguage) -> String { language == .zh ? "选一个对话，在这里看全文。" : "Choose a conversation to read it here." }
    public static func notificationApproval(_ language: AILanguage) -> String { language == .zh ? "在等你确认" : "Waiting for your approval" }
    public static func notificationReplied(_ language: AILanguage) -> String { language == .zh ? "回复好了" : "Replied" }
    public static func deleted(_ title: String, _ language: AILanguage) -> String {
        language == .zh ? "已彻底删除「\(title)」" : "Deleted “\(title)” for good"
    }
}
