import BrkBase
import BrkDomain
import Foundation
import os

/// Saved conversations and rendered pages on disk, beside state.json:
///
///     <data directory>/Conversations/<conversation id>.json
///     <data directory>/AI Pages/<page id>.html     the page's document, written once when the agent renders it
///     <data directory>/AI Pages/<page id>.json     its record (title, height, data, the conversation that made it)
///
/// One file each, so a long transcript is written only when it changes and a damaged file loses one conversation.
/// Folders are 0700, files atomic. Never reads application state; `AppStore` hands it what changed.
final class ConversationFiles: @unchecked Sendable {
    let conversations: URL
    let pages: URL
    private let queue = DispatchQueue(label: "brk.conversation-files", qos: .utility)
    private let log = Logger(subsystem: "brk", category: "conversation-files")
    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    init(root: URL) {
        conversations = root.appendingPathComponent("Conversations", isDirectory: true)
        pages = root.appendingPathComponent("AI Pages", isDirectory: true)
    }

    /// Ids are Brk's own UUIDs; anything else is never turned into a path.
    static func valid(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 100 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }

    func htmlFile(_ page: AIPageID) -> URL { pages.appendingPathComponent(page.rawValue + ".html") }

    /// Everything saved, read once at launch. A file that does not decode is left where it is and skipped. A page's
    /// record always points at its own HTML file in `AI Pages`, whatever its file says.
    func load() -> ([StoredConversation], [AIPageRecord]) {
        let decoder = JSONDecoder()
        func files(_ folder: URL, _ ext: String) -> [URL] {
            ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []).filter { $0.pathExtension == ext }
        }
        var loaded: [StoredConversation] = []
        for file in files(conversations, "json") {
            guard let data = try? Data(contentsOf: file), let value = try? decoder.decode(StoredConversation.self, from: data),
                  Self.valid(value.id.rawValue), file.deletingPathExtension().lastPathComponent == value.id.rawValue else {
                log.error("skipped conversation file \(file.lastPathComponent, privacy: .public)")
                continue
            }
            loaded.append(value)
        }
        var records: [AIPageRecord] = []
        for file in files(pages, "json") {
            guard let data = try? Data(contentsOf: file), let value = try? decoder.decode(AIPageRecord.self, from: data),
                  Self.valid(value.id.rawValue), file.deletingPathExtension().lastPathComponent == value.id.rawValue else {
                log.error("skipped page file \(file.lastPathComponent, privacy: .public)")
                continue
            }
            var record = value
            record.html = htmlFile(value.id)
            guard FileManager.default.fileExists(atPath: record.html.path) else { continue }
            records.append(record)
        }
        return (loaded, records)
    }

    /// The page's HTML, written before the reducer hears of the page. Refuses an id that is not Brk's.
    func writeHTML(_ html: String, page: AIPageID) throws -> URL {
        guard Self.valid(page.rawValue) else { throw CocoaError(.fileWriteInvalidFileName) }
        try Self.folder(pages)
        let file = htmlFile(page)
        try Data(html.utf8).write(to: file, options: .atomic)
        return file
    }

    /// Writes what changed and removes what went, in order, off the main thread.
    func save(conversations changed: [StoredConversation], removed: [AIRequestID], pages: [AIPageRecord], removedPages: [AIPageID]) {
        guard !changed.isEmpty || !removed.isEmpty || !pages.isEmpty || !removedPages.isEmpty else { return }
        let conversationsFolder = conversations, pagesFolder = self.pages, log = log
        queue.async {
            do {
                if !changed.isEmpty { try Self.folder(conversationsFolder) }
                for conversation in changed where Self.valid(conversation.id.rawValue) {
                    try Self.encoder.encode(conversation).write(to: conversationsFolder.appendingPathComponent(conversation.id.rawValue + ".json"), options: .atomic)
                }
                for id in removed where Self.valid(id.rawValue) { try? FileManager.default.removeItem(at: conversationsFolder.appendingPathComponent(id.rawValue + ".json")) }
                if !pages.isEmpty { try Self.folder(pagesFolder) }
                for page in pages where Self.valid(page.id.rawValue) {
                    try Self.encoder.encode(page).write(to: pagesFolder.appendingPathComponent(page.id.rawValue + ".json"), options: .atomic)
                }
                for id in removedPages where Self.valid(id.rawValue) {
                    try? FileManager.default.removeItem(at: pagesFolder.appendingPathComponent(id.rawValue + ".json"))
                    try? FileManager.default.removeItem(at: pagesFolder.appendingPathComponent(id.rawValue + ".html"))
                }
            } catch {
                log.error("conversation write failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Returns once every write asked for so far is on disk (quit).
    func flush() { queue.sync {} }

    private static func folder(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
    }
}

/// What of the saved conversations and pages changed between two states.
struct ConversationChanges {
    var conversations: [StoredConversation] = []
    var removed: [AIRequestID] = []
    var pages: [AIPageRecord] = []
    var removedPages: [AIPageID] = []

    init(from old: (conversations: [AIRequestID: StoredConversation], pages: [AIPageID: AIPageRecord]),
         to new: (conversations: [AIRequestID: StoredConversation], pages: [AIPageID: AIPageRecord])) {
        for (id, value) in new.conversations where old.conversations[id] != value { conversations.append(value) }
        removed = old.conversations.keys.filter { new.conversations[$0] == nil }
        for (id, value) in new.pages where old.pages[id] != value { pages.append(value) }
        removedPages = old.pages.keys.filter { new.pages[$0] == nil }
    }
}
