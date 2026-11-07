import BrkBase
import Foundation

public enum AIFeature: String, CaseIterable, Hashable, Sendable, Codable {
    case commandBar, askPage, linkPreviews, downloadRename, instantLinks, browse, translation
    public var title: String {
        switch self {
        case .commandBar: "Ask in Command Bar"
        case .askPage: "Ask on Page"
        case .linkPreviews: "5-Second Link Previews"
        case .downloadRename: "Tidy Download Names"
        case .instantLinks: "Instant Links"
        case .browse: "Browse for Me"
        case .translation: "Translate Pages"
        }
    }
}
public enum AIMode: String, Hashable, Sendable, Codable { case question, page, instant, browse, translate }
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
}
public struct AITranslationExclusions: Hashable, Sendable, Codable {
    public var languages: Set<String> = []
    public var sites: Set<String> = []
    public init() {}
}
extension MaxSettings {
    /// The user's switch, else "Automatically enable future … features" for a feature never switched.
    public func enabled(_ feature: AIFeature) -> Bool { features?[feature] ?? autoEnableFutureFeatures ?? false }
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
    var purpose: AIPurpose
    /// The agent named for this request; nil is Max's setting.
    var agent: AIProviderChoice? = nil
    /// Translation: the page being translated and the translated nodes sent to it.
    var page: PageID? = nil
    var translated: [AITextNode] = []
}
enum AIPurpose: Equatable, Sendable {
    case answer, askPage(String), preview(URL), instant(String), browse(String), translate(String), organize
    /// The `translate` prefix: the answer goes in the bar's row.
    case barTranslation
}
extension AIPurpose {
    /// Purposes that show in their own place (the preview card, the Today row, the URL pill and its popover, the
    /// Tidy button and a toast), not in the answer panel.
    var inPlace: Bool {
        switch self {
        case .preview, .instant, .translate, .organize, .barTranslation: true
        case .answer, .askPage, .browse: false
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
