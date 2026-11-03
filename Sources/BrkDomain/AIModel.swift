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
    case askPage(String)
    case browse(question: String, sources: [URL])
    case instant(String)
    case translate(String)
    case organizeToday, undoOrganize
    case renameDownload(DownloadID)
    case cancel, dismiss, searchFallback
    case neverTranslateSite, neverTranslateLanguage
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
    public var searchQuery: String?
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
}
enum AIPurpose: Equatable, Sendable {
    case answer, askPage(String), preview(URL), instant(String), browse(String), translate(String), organize
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
}
public struct AIGroupPlan: Hashable, Sendable, Codable {
    public let folder: String
    public let tabs: [String]
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
