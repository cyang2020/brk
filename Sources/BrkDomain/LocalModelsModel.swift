import BrkBase
import Foundation

// Brk's local models as the domain sees them (docs/design/ai-native.md, 模型分工): what the Max pane's "On This Mac"
// card shows and the user's three actions. BrkApp owns the files and the helper processes (BrkLocalModels) and reports
// their state with `SystemEvent.localModels`; nothing here is saved: the files on disk are the record.

/// The two roles a local model can fill.
public enum LocalModelKind: String, CaseIterable, Hashable, Sendable, Codable {
    /// Search by meaning, the closest groups for a new tab, near duplicates.
    case search
    /// Yes/no and pick-one questions with probabilities.
    case decision
}

public enum LocalModelAction: Hashable, Sendable, Codable {
    /// The user pressed Download on the card: the only way a model file arrives.
    case download(LocalModelKind)
    case cancel(LocalModelKind)
    /// Deletes the model's files (and, for search, every profile's search index).
    case remove(LocalModelKind)
    /// Which file a role downloads and uses (JevK5's 4-bit or 8-bit build).
    case choose(LocalModelKind, file: String)
}

public enum LocalModelStage: Hashable, Sendable, Codable {
    case absent
    case downloading(received: Int64, total: Int64)
    case verifying
    case ready
    case failed(String)
}

public struct LocalModelFileChoice: Hashable, Sendable, Codable {
    public var id: String
    public var title: String
    public var bytes: Int64
    public init(id: String, title: String, bytes: Int64) { self.id = id; self.title = title; self.bytes = bytes }
}

public struct LocalModelRow: Hashable, Sendable, Codable {
    public var kind: LocalModelKind
    public var title: String
    public var purpose: String
    public var bytes: Int64
    public var license: String
    /// "English only", "100+ languages, Chinese included".
    public var languages: String
    /// Memory while loaded, as measured on an M1 with 16 GB.
    public var residentMB: Int
    public var stage: LocalModelStage
    /// This copy of Brk can run local models (has the runtime).
    public var runtimeFound: Bool
    public var choices: [LocalModelFileChoice]
    public var chosen: String

    public init(kind: LocalModelKind, title: String, purpose: String, bytes: Int64, license: String, languages: String, residentMB: Int,
                stage: LocalModelStage, runtimeFound: Bool, choices: [LocalModelFileChoice] = [], chosen: String = "") {
        self.kind = kind
        self.title = title
        self.purpose = purpose
        self.bytes = bytes
        self.license = license
        self.languages = languages
        self.residentMB = residentMB
        self.stage = stage
        self.runtimeFound = runtimeFound
        self.choices = choices
        self.chosen = chosen
    }
}

public struct LocalModelsSnapshot: Hashable, Sendable, Codable {
    public var rows: [LocalModelRow] = []
    /// Entries in the current profiles' search indexes; nil while there is no index.
    public var indexed: Int? = nil
    public init(rows: [LocalModelRow] = [], indexed: Int? = nil) { self.rows = rows; self.indexed = indexed }

    public func row(_ kind: LocalModelKind) -> LocalModelRow? { rows.first { $0.kind == kind } }
}
