import BrkBase
import CoreGraphics
import Foundation

// The state file format: `{ "version": 1, "doc": { ... } }` in state.json. Only `Doc` is saved; `Session` is
// rebuilt fresh on every launch. This file is the only place that knows the format: the stored types are private
// DTOs, decoded and then validated into `Doc` (parse at the boundary, trust the types inside). BrkApp/StateFile
// knows bytes and paths only (atomic write, quarantine), never the shape.

/// What a fresh profile needs that the file cannot provide.
public struct RestoreSeed: Sendable {
    /// The single tab of a fresh profile; nil opens a fresh window with the command bar.
    public var startURL: URL?
    public var contentSize: CGSize
    public init(startURL: URL?, contentSize: CGSize) {
        self.startURL = startURL
        self.contentSize = contentSize
    }
}

public enum RestoreOutcome: Sendable, Equatable {
    /// No file: a fresh profile (one space, one window, one Today tab at `startURL` if given).
    case fresh
    /// Decoded; `repairs` lists what `SidebarTree.repair` and `normalize` fixed.
    case restored(repairs: [String])
    /// The file exists but is unusable (bad JSON, unknown version, no spaces). The caller moves it aside
    /// (quarantine) and starts with the fresh state returned alongside.
    case rejected(reason: String)
}

public struct Restored: Sendable {
    public let state: AppState
    public let outcome: RestoreOutcome
}

public enum StateCodec {
    public static let currentVersion = 1

    /// Doc only, deterministic key order (sorted keys) so identical state writes identical bytes.
    public static func encode(_ state: AppState) -> Data {
        // TODO(W1): StoredFile(version: 1, doc: StoredDocV1(state.doc)) with JSONEncoder(.sortedKeys).
        fatalError("not implemented")
    }

    /// Parse, migrate, validate, repair, normalize. Never throws: an unusable file is `.rejected` with a fresh state.
    /// Restored tabs keep their saved URL and title; only visible tabs are loaded (lazy restore).
    public static func restore(_ data: Data?, seed: RestoreSeed, ctx: Context) -> Restored {
        // TODO(W1): nil -> fresh(seed, ctx). Decode {version}; unknown -> rejected. migrate(version, json) -> V1;
        // V1.validated() -> Doc (drops items with unknown kinds, builds SidebarTree via repair); no spaces ->
        // rejected. Session: rev 0, windows with seed.contentSize, loaded = visible tabs.
        fatalError("not implemented")
    }
}

/// The v1 stored shape. Every field of `Doc` appears here, and `init(_ doc:)`/`validated()` construct fields
/// explicitly, so a field added to `Doc` but not here is a compile error in one of the two.
private struct StoredDocV1: Codable {
    var items: [ItemID: StoredItem]
    var spaces: [SpaceID: StoredSpace]
    var spaceOrder: [SpaceID]
    var favorites: [ProfileID: ItemID]
    var archive: [StoredArchived]
    var history: [StoredHistory]
    var windows: [WindowID: StoredWindow]
    var autoArchive: AutoArchiveThreshold

    struct StoredItem: Codable {
        var kind: String
        var parent: ItemID?
        var children: [ItemID]
        var createdAt: Instant
        var tab: StoredTab?
        var folder: StoredFolder?
        var split: StoredSplit?
        var section: StoredSection?
    }
    struct StoredTab: Codable {
        var url: URL?, title: String, customTitle: String?, favicon: URL?, pinnedURL: URL?, lastActiveAt: Instant
    }
    struct StoredFolder: Codable { var title: String, collapsed: Bool }
    struct StoredSplit: Codable { var widths: [ItemID: Double], focused: ItemID, lastActiveAt: Instant }
    struct StoredSection: Codable { var kind: SectionKind, space: SpaceID?, profile: ProfileID? }
    struct StoredSpace: Codable {
        var title: String, icon: SpaceIcon, theme: SpaceTheme, profile: ProfileID
        var pinnedRoot: ItemID, todayRoot: ItemID, pinnedCollapsed: Bool
    }
    struct StoredArchived: Codable {
        var id: ArchiveID, tabID: ItemID, tab: StoredTab, archivedAt: Instant, reason: ArchiveReason
        var fromSpace: SpaceID?, fromSection: SectionKind
    }
    struct StoredHistory: Codable { var url: URL, title: String, visitedAt: Instant }
    struct StoredWindow: Codable {
        var bounds: CGRect?, space: SpaceID, activeBySpace: [SpaceID: ItemID], sidebarVisible: Bool, sidebarWidth: Double
    }
}
