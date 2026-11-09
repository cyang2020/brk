import BrkBase
import Foundation

// Saved conversations and the pages agents draw in their answers (docs/design/ai-conversations.md, ai-right-panel.md). A
// conversation is saved in `Doc.conversations` once its first message goes out. It lives only in the AI panel: it has no
// sidebar row (step 8), and it records its own Space (`StoredConversation.space`). `ConversationPage.url(id)` is only
// its name in links and tool results; a tab that ends up at such an address is taken out of the sidebar and the
// conversation shows in the panel (`Work.dropConversationRows`). A page an agent renders is a file written by the app
// (`AIPageRecord.html`) and an item in the transcript; kept as a tab, its row is a tab at `AIPageTab.url(id)` whose card
// shows the page in the page sandbox under a caption row that leads back to its conversation. Both live in files of
// their own beside state.json (BrkApp/ConversationFiles.swift), so a long transcript is not written again every time a
// tab title changes.

public enum AIPageTag {}
/// One page an agent rendered in a conversation.
public typealias AIPageID = ID<AIPageTag>

/// A conversation's address, `brk://conversation/<id>`: how the tools and the agent name it, and what a link to it opens
/// (in the panel). No tab shows it.
public enum ConversationPage {
    public static let host = "conversation"

    public static func url(_ id: AIRequestID) -> URL { URL(string: "brk://\(host)/" + (id.rawValue.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_"))) ?? id.rawValue))! }

    /// The conversation `url` shows, nil for any other address.
    public static func id(of url: URL?) -> AIRequestID? {
        guard let url, url.scheme?.lowercased() == "brk", url.host?.lowercased() == host else { return nil }
        let raw = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !raw.isEmpty, !raw.contains("/"), raw.count <= 100 else { return nil }
        return AIRequestID(raw.removingPercentEncoding ?? raw)
    }

    public static func shows(_ url: URL?) -> Bool { id(of: url) != nil }

    /// `[Title](brk://conversation/<id>)`: how the tools and the agent name a conversation; a click opens it in the panel.
    public static func markdown(_ id: AIRequestID, title: String) -> String {
        let shown = String(title.prefix(80)).replacingOccurrences(of: "[", with: "(").replacingOccurrences(of: "]", with: ")")
            .replacingOccurrences(of: "\n", with: " ")
        return "[\(shown.isEmpty ? untitled : shown)](\(url(id).absoluteString))"
    }

    public static let untitled = "New Conversation"

    /// A conversation's first title, from its first message: its first line, at most 60 characters.
    public static func title(from message: String) -> String {
        let line = message.split(whereSeparator: \.isNewline).first.map { $0.trimmingCharacters(in: .whitespaces) } ?? ""
        guard !line.isEmpty else { return untitled }
        return line.count > 60 ? String(line.prefix(59)) + "…" : line
    }

    /// Its icon in the command bar's rows: two speech bubbles in the Space's foreground grey (an SVG data URL).
    public static let favicon = URL(string: "data:image/svg+xml;base64," + Data((
        #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="32" height="32">"#
            + ##"<g fill="none" stroke="#5C5C66" stroke-width="1.4" stroke-linejoin="round">"##
            + #"<path d="M2 3.6c0-.9.7-1.6 1.6-1.6h6.3c.9 0 1.6.7 1.6 1.6v3.8c0 .9-.7 1.6-1.6 1.6H6.1L3.4 11V9H3.6C2.7 9 2 8.3 2 7.4z"/>"#
            + #"<path d="M13.2 6.2c.5.3.8.8.8 1.4v3.4c0 .9-.7 1.6-1.6 1.6h-.2v2l-2.6-2H7.8c-.6 0-1.1-.3-1.4-.8"/></g></svg>"#
    ).utf8).base64EncodedString())!
}

/// The address of a kept page's row. Its card shows the page in the page sandbox.
public enum AIPageTab {
    public static let host = "ai-page"

    public static func url(_ id: AIPageID) -> URL { URL(string: "brk://\(host)/" + (id.rawValue.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_"))) ?? id.rawValue))! }

    public static func id(of url: URL?) -> AIPageID? {
        guard let url, url.scheme?.lowercased() == "brk", url.host?.lowercased() == host else { return nil }
        let raw = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !raw.isEmpty, !raw.contains("/"), raw.count <= 100 else { return nil }
        return AIPageID(raw.removingPercentEncoding ?? raw)
    }

    public static func shows(_ url: URL?) -> Bool { id(of: url) != nil }

    /// A small bar chart in the Space's foreground grey.
    public static let favicon = URL(string: "data:image/svg+xml;base64," + Data((
        #"<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" width="32" height="32">"#
            + ##"<rect x="1.5" y="1.5" width="13" height="13" rx="3" fill="none" stroke="#5C5C66" stroke-width="1.3"/>"##
            + ##"<g fill="#5C5C66"><rect x="4" y="8" width="2" height="4" rx=".5"/><rect x="7" y="5" width="2" height="7" rx=".5"/><rect x="10" y="9.5" width="2" height="2.5" rx=".5"/></g></svg>"##
    ).utf8).base64EncodedString())!
}

/// Brk's own pages that a card draws natively, without a browser: History, Easels and kept pages. A conversation's
/// address is in the list too, so no browser ever loads it in the moment before its row is taken away.
public enum NativePages {
    public static func shows(_ url: URL?) -> Bool {
        HistoryPage.shows(url) || EaselPage.shows(url) || ConversationPage.shows(url) || AIPageTab.shows(url)
    }
}

/// A conversation as it is saved: what the user and the agent said, the pages the agent drew, and what is needed to
/// continue it another day.
public struct StoredConversation: Equatable, Sendable, Codable {
    public let id: AIRequestID
    public var profile: ProfileID
    public var title: String
    public let createdAt: Instant
    public var updatedAt: Instant
    public var agent: AIProviderKind?
    public var agentName: String?
    public var model: String?
    public var effort: String?
    /// A session with tools on in this folder (Work in a Folder…).
    public var folder: String?
    /// A browser session with Brk's tab tools.
    public var tabs: Bool
    /// The agent's own session this conversation continues: Claude's session id, Codex's thread id, an ACP session.
    /// Nil when the agent keeps none (read-only sessions keep nothing): the next message then carries the transcript.
    public var resume: String?
    /// Page text reached this conversation (a tab read, a search, titles in a message).
    public var readPages: Bool = false
    /// The injection check flagged a page this conversation read.
    public var flagged: Bool = false
    public var items: [AIConversationItem]
    /// The Space it belongs to: the one it was started in, or the one it was last moved to (docs/design/ai-right-panel.md).
    /// A Space that is gone gives way to the profile's first (`AppState.conversationSpaces`).
    public var space: SpaceID?
    /// The tabs it used, oldest first: those the user gave it (a drop, @, Ask AI, the right edge) and those its agent read,
    /// opened or showed with Brk's tab tools. By tab, not by address: a tab that went to another page still counts.
    /// Hovering its list row lights those still open in the window's Space.
    public var usedTabs: [ItemID]?
    /// When its last reply finished, and when it was last shown in the panel after one did: a reply finished later than it
    /// was seen is unread ("等你处理").
    public var repliedAt: Instant?
    public var seenAt: Instant?
    /// The small model named it (its title is that name), or the user did (never named again).
    public var aiNamed: Bool?
    public var userNamed: Bool?
    /// The agent and model chosen in the + menu, kept for its next messages.
    public var pick: AIAgentPick?
    /// A reply finished that nobody has seen yet.
    public var unread: Bool { repliedAt.map { $0 > (seenAt ?? Instant(milliseconds: 0)) } ?? false }

    public init(id: AIRequestID, profile: ProfileID, title: String, createdAt: Instant, tabs: Bool, folder: String? = nil, items: [AIConversationItem] = []) {
        self.id = id
        self.profile = profile
        self.title = title
        self.createdAt = createdAt
        updatedAt = createdAt
        self.tabs = tabs
        self.folder = folder
        self.items = items
    }

    /// What the user and the agent said, in order: the messages the read tool pages through.
    public var messages: [(position: Int, item: AIConversationItem)] {
        items.enumerated().compactMap { index, item in
            switch item {
            case .user, .assistant, .page: (index, item)
            case .step, .approval, .notice: nil
            }
        }
    }
}

/// A page in a transcript: the record's id, and the title and height it shows with.
public struct AIPageRef: Hashable, Sendable, Codable {
    public let id: AIPageID
    public var title: String
    public var height: Int
    public init(id: AIPageID, title: String, height: Int) { self.id = id; self.title = title; self.height = height }
}

/// One rendered page: its HTML (a file the app wrote), the data the agent gave with it and the conversation that made
/// it. A page kept as a tab keeps all three, so a later step can ask the same conversation to draw it again with new data.
public struct AIPageRecord: Hashable, Sendable, Codable {
    public let id: AIPageID
    public var title: String
    /// The complete HTML document, in the data folder's `AI Pages`.
    public var html: URL
    public var height: Int
    /// JSON text the agent passed with the page (the page reads it as `window.brk.data`), at most `AIPageLimits.data`.
    public var data: String?
    public let conversation: AIRequestID
    public let profile: ProfileID
    /// Stamped by the reducer when the page arrives.
    public var createdAt: Instant
    /// Page text had reached its conversation when the agent wrote it: an address this page opens that the profile has
    /// not visited asks first, as `brk_tab_open` does.
    public let readPages: Bool
    /// The shape of `data` the agent declared with the page (JSON Schema text, `AIPageShape`); a refresh's data must fit
    /// it. Nil: the shape of the first data (`dataShape`).
    public var schema: String?
    /// The shape of what the page saves itself (`window.brk.save`); nil: any JSON object.
    public var saveSchema: String?
    /// What the page saved itself (ticks, notes), as JSON text: the page reads it as `window.brk.saved`, and a refresh
    /// reads it but never writes it.
    public var saved: String?
    /// The addresses the page was made from, as the agent listed them: the only ones a refresh may load.
    public var sources: [URL]?
    public var live: AIPageLive?
    /// Goes up when the data or the HTML is replaced, so views showing the page load it again.
    public var revision: Int?

    public init(id: AIPageID, title: String, html: URL, height: Int, data: String?, conversation: AIRequestID, profile: ProfileID, createdAt: Instant, readPages: Bool,
                schema: String? = nil, saveSchema: String? = nil, sources: [URL]? = nil) {
        self.id = id; self.title = title; self.html = html; self.height = height; self.data = data
        self.conversation = conversation; self.profile = profile; self.createdAt = createdAt; self.readPages = readPages
        self.schema = schema; self.saveSchema = saveSchema; self.sources = sources
    }
}

public enum AIPageLimits {
    /// The HTML of one page, in UTF-8 bytes.
    public static let html = 400_000
    /// The page's data, as JSON text.
    public static let data = 100_000
    public static let titleMax = 120
    /// T3's bounds for a rendered page's height.
    public static let minHeight = 80, maxHeight = 2_000
    public static func height(_ value: Int) -> Int { min(maxHeight, max(minHeight, value)) }
}

/// A click on a link in an agent's page that asks first: the page was written after page text reached its
/// conversation, and the address is new to the profile. The address could carry what the agent read.
public struct AIPageLinkPrompt: Hashable, Sendable, Codable {
    public let page: AIPageID
    public let url: URL
    public init(page: AIPageID, url: URL) { self.page = page; self.url = url }
}

/// A rendered page as a view shows it: inline in a transcript, or filling a kept page's card.
public struct AIPageSnapshot: Hashable, Sendable, Codable {
    public let id: AIPageID
    public let title: String
    public let html: URL
    public let height: Int
    public let data: String?
    /// Already a sidebar tab: its Keep as Tab is done.
    public var kept: Bool
    /// The conversation that made it, while it is saved: a kept page's caption row leads back to it.
    public var conversation: AIRequestID? = nil
    /// The language of Brk's words on its caption row: its conversation's.
    public var language: AILanguage = .en
    /// What the page saved itself, read as `window.brk.saved`.
    public var saved: String? = nil
    /// The shape its saves must have (JSON Schema text); nil: any JSON object.
    public var saveSchema: String? = nil
    /// A view loads the page again when this changes (new data or HTML), never for the page's own saves.
    public var revision: Int = 0
    /// How often it updates itself; nil when it does not.
    public var schedule: AIPageSchedule? = nil
    public init(id: AIPageID, title: String, html: URL, height: Int, data: String?, kept: Bool) {
        self.id = id; self.title = title; self.html = html; self.height = height; self.data = data; self.kept = kept
    }
}

/// A card that shows a kept page (`PaneContent.aiPage`), under its caption row: the page's name and how often it refreshes,
/// and a button back to the conversation that made it.
public struct AIPageCard: Equatable, Sendable, Codable {
    public let page: PageID
    public let content: AIPageSnapshot?
    public init(page: PageID, content: AIPageSnapshot?) { self.page = page; self.content = content }
}

/// How a saved conversation's next session starts (`Effect.aiOpenConversation`): continuing the agent's own session
/// when it kept one, else with the transcript ahead of the next message.
public struct AIResume: Hashable, Sendable, Codable {
    /// The agent's own session id; nil when it kept none.
    public let session: String?
    /// The transcript as text: sent when the session cannot be continued.
    public let history: String
    public init(session: String?, history: String) { self.session = session; self.history = history }
}
