import BrkBase
import Foundation

public enum AIFeature: String, CaseIterable, Hashable, Sendable, Codable {
    case commandBar, askPage, linkPreviews, downloadRename, instantLinks, browse, translation
    /// The switch's name where the person finds it: the Max pane's row titles (P38-max-list), More Settings' rows.
    public var title: String {
        switch self {
        case .commandBar: "Ask in Command Bar"
        case .askPage: "Ask on Page"
        case .linkPreviews: "5-Second Previews"
        case .downloadRename: "Tidy Downloads"
        case .instantLinks: "Instant Links"
        case .browse: "Browse for Me"
        case .translation: "Translate Pages"
        }
    }
    /// Brk's own three are switched in Advanced → More Settings…; Arc's are in the Max pane.
    public var inMoreSettings: Bool { [.askPage, .browse, .translation].contains(self) }
    /// Where the switch is, as a message says it, and the pane a link opens.
    public var place: String { inMoreSettings ? "Settings → Advanced → More Settings…" : "Settings → Max" }
    public var pane: SettingsPane { inMoreSettings ? .advanced : .max }
}
public enum AIMode: String, Hashable, Sendable, Codable {
    case question, page, instant, browse, translate
    /// The switch this bar's feature has; the question bar has its own notice (P43-a).
    var feature: AIFeature? {
        switch self {
        case .question: nil
        case .page: .askPage
        case .instant: .instantLinks
        case .browse: .browse
        case .translate: .translation
        }
    }
}
public enum AIIntent: Hashable, Sendable, Codable {
    case open(AIMode)
    case ask(String)
    /// `ask` with this agent, whatever Max's setting says (the `claude` and `gpt` prefixes). If it is not on this Mac the
    /// answer says so; another agent never answers in its place.
    case askAgent(String, agent: AIProviderChoice)
    case askPage(String)
    case browse(question: String, sources: [URL])
    case instant(String)
    case translate(String)
    case organizeToday, undoOrganize
    case renameDownload(DownloadID)
    case cancel, dismiss
    case neverTranslateSite, neverTranslateLanguage
    /// The translation popover's Use Original (P50-e): the page's own text comes back, "Translated back to French!
    /// Use ⌘Z to undo." shows, and ⌘Z puts the translation back.
    case useOriginal
    /// The translation popover's Options › Language Settings: Chromium's language settings page in a new tab (Arc's
    /// `chrome://settings/languages`).
    case languageSettings
    /// The pointer entered (true) or left (false) the 5-Second Preview card: while it is over the card the card stays
    /// although the link under it is no longer hovered.
    case previewHover(Bool)
    /// The card's share button: the previewed link's address on the pasteboard.
    case sharePreview
    /// The panel's input: the next message in the window's conversation.
    case followUp(String)
    /// The panel's Stop: the running turn ends and every process it started goes; the conversation stays.
    case stop
    /// The panel's Work in a Folder…: Brk asks for a folder. Only this starts a session with tools on.
    case chooseFolder
    /// The panel's approval buttons: the answer to a tool approval the agent asked for.
    case approve(approval: String, option: String)
    /// Tabs, a folder or a Space given to the panel's conversation (a drop on the panel, Ask AI, a pick after @): they
    /// show as chips in its input and go with the next message. With no conversation open, a new one starts.
    case attach([AIAttachmentSource])
    /// A chip's ×.
    case detach(String)
    /// The text after an @ in the panel's input, while the user types it; nil when the @ is gone.
    case mention(String?)
    /// A `brk://tab/<id>` link in an agent's answer: that tab is shown, or opened again from the archive or history.
    case openTabLink(String)
}

/// What the user gave the conversation, before Brk looks it up.
public enum AIAttachmentSource: Hashable, Sendable, Codable {
    /// A tab by its agent id (`AgentTabFacts.id`).
    case tab(String)
    case folder(ItemID)
    case space(SpaceID)
}

/// A chip in the panel's input and the tabs behind it.
public struct AIAttachment: Hashable, Sendable, Codable {
    public enum Kind: String, Hashable, Sendable, Codable { case tab, folder, space }
    public let kind: Kind
    /// The tab's agent id, the folder's item id or the Space's id.
    public let id: String
    public let title: String
    public let tabs: [AIAttachedTab]
    public init(kind: Kind, id: String, title: String, tabs: [AIAttachedTab]) { self.kind = kind; self.id = id; self.title = title; self.tabs = tabs }
}
public struct AIAttachedTab: Hashable, Sendable, Codable {
    public let id: String
    public let title: String
    public let url: URL?
    /// A tab of another profile than the conversation's: the user gave it, so the agent may read it, and nothing else of
    /// that profile.
    public let otherProfile: Bool
    public init(id: String, title: String, url: URL?, otherProfile: Bool) { self.id = id; self.title = title; self.url = url; self.otherProfile = otherProfile }
}
/// What @ offers while the user types after it: open tabs first, then archived ones, then history.
public struct AIMentionSnapshot: Hashable, Sendable, Codable {
    public let query: String
    public var matches: [AIAttachedTab]
    public init(query: String, matches: [AIAttachedTab]) { self.query = query; self.matches = matches }
}
public struct AITranslationExclusions: Hashable, Sendable, Codable {
    public var languages: Set<String> = []
    public var sites: Set<String> = []
    public init() {}
}
extension MaxSettings {
    /// Max on, and the user's switch, else "Automatically enable future … features" for a feature never switched.
    public func enabled(_ feature: AIFeature) -> Bool { isOn && switched(feature) }
    /// The switch alone, kept while Max is off.
    public func switched(_ feature: AIFeature) -> Bool { features?[feature] ?? autoEnableFutureFeatures ?? false }
}

/// Arc's 5-Second Preview card (P45-a): under the hovered link, the summary's title and two to four details, each an
/// SF Symbol, a bold label and a short line (Arc's `HoverCardViewModel` answer card: quickSummary, details with
/// label, icon and info).
public struct AIPreviewSnapshot: Equatable, Sendable, Codable {
    public var url: URL
    /// The page the hovered link is on, and the link's box in that page's surface (points, top-left origin); nil
    /// when the page could not say, and the card then sits at the top of the page.
    public var page: PageID
    public var link: CGRect?
    public var busy: Bool
    public var title: String
    public var details: [AIPreviewDetail] = []
    /// Arc's "No preview available" and Brk's actionable failures, in place of the details.
    public var failure: String? = nil
    /// The summary request while it runs.
    public var request: AIRequestID? = nil
}
public struct AIPreviewDetail: Hashable, Sendable, Codable {
    public let label: String
    public let icon: String
    public let info: String
    public init(label: String, icon: String, info: String) { self.label = label; self.icon = icon; self.info = info }
}
/// The summary the tool returns for a preview (Arc's `Response`): `blocked` when the page asks for JavaScript or a
/// security check, else a 3-8 word `quickSummary` and two to four `details`.
public struct AIPreviewReply: Hashable, Sendable, Codable {
    public var blocked: Bool?
    public var quickSummary: String?
    public var details: [AIPreviewDetail]?
}
/// The URL pill's second line (Arc: "Translation Available" on a page in a language other than the system's;
/// "Translated", underlined under the pointer, once translated). Nil: no second line.
public enum PillTranslation: Equatable, Sendable, Codable {
    case available
    case translating
    /// The popover's "Translated from French." names the page's own language.
    case translated(from: String)
}
/// A page translated in place (P50-b): which document, its own language and the one it was translated to, and
/// whether the translation or the original text shows now. Session only.
struct AIPageTranslation: Equatable, Sendable {
    let document: DocumentToken
    let source: String
    var target: String
    var showingTranslation: Bool
}
/// Arc's Instant Links row at the top of Today while Max looks ("Searching the web for you…", Max's flower), and
/// "Oops, something went wrong." when nothing could be opened. Session only; the row's × removes it.
struct AIInstantRow: Equatable, Sendable {
    let id: ItemID
    let request: AIRequestID
    var failed = false
    var opened: [ItemID] = []
}

public struct AISource: Hashable, Sendable, Codable {
    public let title: String
    public let url: URL
    public init(title: String, url: URL) { self.title = title; self.url = url }
}
public struct AIAnswerSnapshot: Equatable, Sendable, Codable {
    public var request: AIRequestID?
    public var title: String
    public var text: String
    public var busy: Bool
    public var sources: [AISource]
    public var isPreview: Bool = false
    public var canUndo: Bool = false
    public var language: String? = nil
    public var site: String? = nil
    /// The conversation shown in the panel; nil for a plain message (a feature that is off, a failure before asking).
    public var conversation: AIConversationSnapshot? = nil
}

/// A conversation with a local agent in the Max panel. Session only, one per window. Its id is the first request's.
public struct AIConversationSnapshot: Equatable, Sendable, Codable {
    public let id: AIRequestID
    /// The agent as the app resolved it, its name for the header. Nil until the session started.
    public var agent: AIProviderKind? = nil
    public var agentName: String? = nil
    /// The model the agent says it runs, and the effort asked for. Nil: the agent's default, not told.
    public var model: String? = nil
    public var effort: String? = nil
    /// The folder the user chose for a session with tools on. Nil: tools off, the agent's strictest read-only mode.
    public var folder: String? = nil
    public var items: [AIConversationItem] = []
    /// The session ended for good (another agent chosen, Max off); no more messages.
    public var ended = false
    /// Brk's tab tools are on: the agent reads and changes this profile's tabs, and its own tools ask every time.
    public var tabs = false
    /// No message sent yet: the session starts with the first one.
    public var fresh = false
    /// The chips waiting in the input for the next message.
    public var attached: [AIAttachment] = []
    public var mention: AIMentionSnapshot? = nil
    public init(id: AIRequestID, folder: String? = nil, tabs: Bool = false) { self.id = id; self.folder = folder; self.tabs = tabs }
}
public enum AIConversationItem: Equatable, Sendable, Codable {
    case user(String)
    case assistant(String)
    case step(AIAgentStep)
    case approval(AIAgentApproval)
    case notice(String)
}
/// One thing the agent does (a command, a file edit, a search), as it reports it.
public struct AIAgentStep: Equatable, Sendable, Codable {
    public enum State: String, Equatable, Sendable, Codable { case running, done, failed }
    public let id: String
    public var title: String
    public var state: State
    public init(id: String, title: String, state: State) { self.id = id; self.title = title; self.state = state }
}
/// A tool the agent wants to run and may not without the user's answer. `options` come from the agent.
public struct AIAgentApproval: Equatable, Sendable, Codable {
    public struct Option: Equatable, Sendable, Codable {
        public enum Kind: String, Equatable, Sendable, Codable { case allowOnce, allowSession, deny }
        public let id: String
        public let title: String
        public let kind: Kind
        public init(id: String, title: String, kind: Kind) { self.id = id; self.title = title; self.kind = kind }
    }
    public let id: String
    public let title: String
    public let detail: String
    public let options: [Option]
    /// The option chosen; nil while the agent waits.
    public var answer: String? = nil
    public init(id: String, title: String, detail: String, options: [Option]) {
        self.id = id; self.title = title; self.detail = detail; self.options = options
    }
}
/// What a running session reports (`SystemEvent.aiConversation`). Text arrives as `aiPartial` and `aiResult`.
public enum AIConversationEvent: Equatable, Sendable, Codable {
    case started(agent: AIProviderKind, name: String, model: String?, effort: String?)
    case step(AIAgentStep, turn: AIRequestID)
    case approval(AIAgentApproval, turn: AIRequestID)
    /// The agent no longer waits for this approval (the turn ended, or it was answered elsewhere).
    case approvalClosed(String)
    case notice(String)
}

/// What an installed agent says about itself, read without sending the model anything (the Max pane, the panel).
public struct AIAgentStatus: Hashable, Sendable, Codable {
    public enum State: Hashable, Sendable, Codable {
        case missing, checking, ready, notSignedIn
        case failed(String)
    }
    public let kind: AIProviderKind
    public var state: State
    public var version: String? = nil
    public var models: [AIAgentModel] = []
    public init(kind: AIProviderKind, state: State, version: String? = nil, models: [AIAgentModel] = []) {
        self.kind = kind; self.state = state; self.version = version; self.models = models
    }
}
public struct AIAgentModel: Hashable, Sendable, Codable {
    public let id: String
    public let name: String
    public let efforts: [String]
    public let isDefault: Bool
    public init(id: String, name: String, efforts: [String] = [], isDefault: Bool = false) {
        self.id = id; self.name = name; self.efforts = efforts; self.isDefault = isDefault
    }
}

struct AIRequest: Equatable, Sendable {
    let window: WindowID
    let context: BrowsingContext
    var task: AITask
    var document: DocumentToken?
    var hidden: [PageSpec] = []
    var hiddenDocuments: [PageID: DocumentToken] = [:]
    var contents: [PageID: AIPageContent] = [:]
    var extracting: Set<PageID> = []
    /// Readers whose read failed once and were asked again.
    var readAgain: Set<PageID> = []
    var purpose: AIPurpose
    /// Translation: the page being translated and the translated nodes sent to it.
    var page: PageID? = nil
    var translated: [AITextNode] = []
}
enum AIPurpose: Equatable, Sendable {
    case answer, askPage(String), preview(URL), instant(String), browse(String), translate(String), organize, followUp
    /// The `translate` prefix: the answer goes in the bar's row.
    case barTranslation
    /// A page read for an agent's `brk_tab_read` call: the text goes back to the tool, not to the panel.
    case agentRead(String)
}
extension AIPurpose {
    /// Purposes that show in their own place (the preview card, the Today row, the URL pill and its popover, the
    /// Tidy button and a toast), not in the answer panel.
    var inPlace: Bool {
        switch self {
        case .preview, .instant, .translate, .organize, .barTranslation, .agentRead: true
        case .answer, .askPage, .browse, .followUp: false
        }
    }
}
struct AIOrganizeUndo: Equatable, Sendable {
    let space: SpaceID
    let original: [ItemID]
    let folders: [ItemID: [ItemID]]
}
struct AISession: Equatable, Sendable {
    var requests: [AIRequestID: AIRequest] = [:]
    var backgroundContexts: [AIRequestID: BrowsingContext] = [:]
    var answers: [WindowID: AIAnswerSnapshot] = [:]
    var answerContexts: [WindowID: BrowsingContext] = [:]
    var undo: [WindowID: AIOrganizeUndo] = [:]
    var hover: [WindowID: URL] = [:]
    var hoverDocuments: [WindowID: DocumentToken] = [:]
    var previews: [WindowID: AIPreviewSnapshot] = [:]
    /// The pointer is over the window's preview card.
    var previewHeld: Set<WindowID> = []
    var translations: [PageID: AIPageTranslation] = [:]
    var instantRows: [WindowID: [AIInstantRow]] = [:]
    /// The Today tidy in flight, by window: the Tidy button shows it is working.
    var tidying: Set<WindowID> = []
    /// What each agent said about itself last (`SystemEvent.aiAgents`); only for the Max pane and `.auto`.
    var agents: [AIProviderKind: AIAgentStatus] = [:]
    /// By conversation: how much of the running turn's text rows above its last step already show.
    var turnText: [AIRequestID: Int] = [:]
    /// A background request's window (Tidy Tab Titles, Tidy Downloads): where its result or failure is told.
    var backgroundWindows: [AIRequestID: WindowID] = [:]
    /// A download Max is renaming in the background, and the window that started it.
    var renamingDownloads: [DownloadID: WindowID] = [:]
}
public struct AIGroupPlan: Hashable, Sendable, Codable {
    public let folder: String
    public let tabs: [String]
}
/// Language codes and names for translation: a page's `lang` ("fr", "fr-CA"), the system's, the popover's
/// "Translated from French." and the Options menu's Choose Another Language list (Chromium's translate languages,
/// in the order and with the names of Arc's submenu, P50-f-languages).
/// Arc's words for the AI features' in-place surfaces (strings in Arc 1.170's binary).
public enum AICopy {
    /// "Title for an in progress web search item".
    public static let instantSearching = "Searching the web for you…"
    /// "Title for web search item that failed".
    public static let instantFailed = "Oops, something went wrong."
    /// The Tidy button and its tooltip on the Today divider ("Button Title; Tidy unpinned tabs in this space",
    /// "Tooltip; Use LLM to organize unpinned tabs in this space").
    public static let tidy = "Tidy"
    public static let tidyTooltip = "Organize Today Tabs"
    public static let translationAvailable = "Translation Available"
    /// "Title for the share quote affordance below the URL".
    public static let shareQuote = "Share Quote"
    public static let translated = "Translated"
    public static let translating = "Translating…"
    public static func translatedFrom(_ language: String) -> String { "Translated from \(language)." }
    public static let options = "Options"
    public static let useOriginal = "Use Original"
    /// P50-g: the popover of a page that can be translated, and its button.
    public static func translateOffer(_ language: String) -> String { "Translate this page to \(language)?" }
    public static let translate = "Translate"
    public static let chooseAnotherLanguage = "Choose Another Language"
    public static let neverTranslateSite = "Never Translate This Site"
    public static let languageSettings = "Language Settings"
    public static let noPreview = "No preview available"
}

public enum AILanguages {
    public static func base(_ code: String) -> String {
        String(code.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first ?? "")
    }
    /// The system's first language as Translate to … names it ("English").
    public static var systemTarget: String { name(Locale.preferredLanguages.first ?? "en") }
    public static func name(_ code: String) -> String {
        let base = base(code)
        guard !base.isEmpty else { return "another language" }
        return Locale(identifier: "en_US").localizedString(forLanguageCode: base) ?? base
    }
    public static let targets: [String] = [
        "Afrikaans", "Akan", "Albanian", "Amharic", "Arabic", "Armenian", "Assamese", "Aymara", "Azerbaijani", "Bambara", "Bangla",
        "Basque", "Belarusian", "Bhojpuri", "Bosnian", "Bulgarian", "Burmese", "Catalan", "Cebuano", "Central Kurdish",
        "Chinese (Simplified)", "Chinese (Traditional)", "Corsican", "Croatian", "Czech", "Danish", "Divehi", "Dogri", "Dutch",
        "English", "Esperanto", "Estonian", "Ewe", "Filipino", "Finnish", "French", "Galician", "Ganda", "Georgian", "German",
        "Goan Konkani", "Greek", "Guarani", "Gujarati", "Haitian Creole", "Hausa", "Hawaiian", "Hebrew", "Hindi", "Hmong",
        "Hungarian", "Icelandic", "Igbo", "Iloko", "Indonesian", "Irish", "Italian", "Japanese", "Javanese", "Kannada", "Kazakh",
        "Khmer", "Kinyarwanda", "Korean", "Krio", "Kurdish", "Kyrgyz", "Lao", "Latin", "Latvian", "Lingala", "Lithuanian",
        "Luxembourgish", "Macedonian", "Maithili", "Malagasy", "Malay", "Malayalam", "Maltese", "Manipuri (Meitei Mayek)", "Māori",
        "Marathi", "Mizo", "Mongolian", "Nepali", "Northern Sotho", "Norwegian", "Nyanja", "Odia", "Oromo", "Pashto", "Persian",
        "Polish", "Portuguese", "Punjabi", "Quechua", "Romanian", "Russian", "Samoan", "Sanskrit", "Scottish Gaelic", "Serbian",
        "Shona", "Sindhi", "Sinhala", "Slovak", "Slovenian", "Somali", "Southern Sotho", "Spanish", "Sundanese", "Swahili",
        "Swedish", "Tajik", "Tamil", "Tatar", "Telugu", "Thai", "Tigrinya", "Tsonga", "Turkish", "Turkmen", "Ukrainian", "Urdu",
        "Uyghur", "Uzbek", "Vietnamese", "Welsh", "Western Frisian", "Xhosa", "Yiddish", "Yoruba", "Zulu",
    ]
}

public enum AIValidation {
    public static func destination(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count <= 2048, !trimmed.contains(where: \.isWhitespace),
              let c = URLComponents(string: trimmed), ["https", "http"].contains(c.scheme?.lowercased()),
              let host = c.host, !host.isEmpty, c.user == nil, c.password == nil,
              let url = c.url else { return nil }
        return url
    }
    /// Instant Links: the tool's addresses, one per line (or separated by spaces), the safe ones, at most six, each once.
    public static func destinations(_ text: String) -> [URL] {
        var out: [URL] = []
        for part in text.split(whereSeparator: \.isWhitespace) {
            var token = String(part).trimmingCharacters(in: CharacterSet(charactersIn: "<>[],;\"'"))
            // A closing parenthesis ends the address only when it opened none (Arc_(web_browser) keeps its own).
            while token.hasSuffix(")"), token.filter({ $0 == ")" }).count > token.filter({ $0 == "(" }).count { token.removeLast() }
            if token.hasPrefix("("), token.filter({ $0 == "(" }).count > token.filter({ $0 == ")" }).count { token.removeFirst() }
            guard out.count < 6, let url = destination(token), !out.contains(url) else { continue }
            out.append(url)
        }
        return out
    }
    /// The preview card's reply: Arc's JSON (`AIPreviewReply`, inside a code block or not), else plain lines, the
    /// first the title and each "Label: info" after it a detail. Details with an unknown symbol get a dot.
    public static func preview(_ text: String) -> AIPreviewReply? {
        var body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasPrefix("```") {
            body = body.split(separator: "\n", omittingEmptySubsequences: false).dropFirst().filter { !$0.hasPrefix("```") }.joined(separator: "\n")
        }
        func clean(_ details: [AIPreviewDetail]) -> [AIPreviewDetail] {
            Array(details.filter { !$0.info.trimmingCharacters(in: .whitespaces).isEmpty }.prefix(4)).map {
                AIPreviewDetail(label: String($0.label.prefix(40)), icon: $0.icon.isEmpty || $0.icon.count > 60 ? "circle.fill" : $0.icon, info: String($0.info.prefix(160)))
            }
        }
        if var reply = AIReplyCodec.preview(body) {
            reply.quickSummary = reply.quickSummary.map { String($0.prefix(120)) }
            reply.details = clean(reply.details ?? [])
            return reply.blocked == true || reply.quickSummary?.isEmpty == false || reply.details?.isEmpty == false ? reply : nil
        }
        let lines = body.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        guard let first = lines.first, first.count <= 200 else { return nil }
        let details = lines.dropFirst().compactMap { line -> AIPreviewDetail? in
            let parts = line.split(separator: ":", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
            return parts.count == 2 ? AIPreviewDetail(label: parts[0] + ":", icon: "circle.fill", info: parts[1]) : nil
        }
        return AIPreviewReply(blocked: false, quickSummary: first, details: clean(details))
    }
    public static func citations(_ text: String, sourceCount: Int) -> Bool {
        guard sourceCount > 0, let pattern = try? NSRegularExpression(pattern: #"\[(\d+)\]"#) else { return false }
        let matches = pattern.matches(in: text, range: NSRange(text.startIndex..., in: text))
        return !matches.isEmpty && matches.allSatisfy { match in
            guard let range = Range(match.range(at: 1), in: text), let number = Int(text[range]) else { return false }
            return (1...sourceCount).contains(number)
        }
    }
    public static func plan(_ text: String, eligible: [AITab]) -> [AIGroupPlan]? {
        guard text.utf8.count <= 32_768, let groups = AIReplyCodec.groups(text),
              (1...12).contains(groups.count),
              groups.allSatisfy({ !$0.folder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.folder.count <= 60 && !$0.tabs.isEmpty }) else { return nil }
        let ids = groups.flatMap(\.tabs)
        guard Set(ids).count == ids.count, Set(ids) == Set(eligible.map { $0.id.rawValue }) else { return nil }
        return groups
    }
    /// Why this folder cannot be a session's working folder, nil when it can. Home and every folder above it hold
    /// everything the user has; a coding session gets one project.
    public static func workingFolderRefusal(_ folder: String, home: String) -> String? {
        let standard = (folder as NSString).standardizingPath
        guard standard.hasPrefix("/") else { return "Choose a folder on this Mac." }
        let home = (home as NSString).standardizingPath
        if standard == "/" || standard == home || home.hasPrefix(standard + "/") { return "Choose a project folder, not your home folder or a folder above it." }
        return nil
    }
    /// Keep the original extension; replies may suggest only a filename stem, never a path.
    public static func filename(_ text: String, original: String) -> String? {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, !line.contains(where: { $0.isNewline || $0.isASCII && $0.asciiValue! < 32 }),
              !line.contains("/"), !line.contains("\\"), !line.contains(":"), !line.hasPrefix("."), line != ".." else { return nil }
        let ext = (original as NSString).pathExtension
        let raw = !ext.isEmpty && line.lowercased().hasSuffix("." + ext.lowercased()) ? String(line.dropLast(ext.count + 1)) : line
        let stem = String(raw.trimmingCharacters(in: CharacterSet(charactersIn: " .\"'")).prefix(100))
        guard !stem.isEmpty, !stem.hasPrefix(".") else { return nil }
        return ext.isEmpty ? stem : stem + "." + ext
    }
}
