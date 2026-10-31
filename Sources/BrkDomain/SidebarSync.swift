import BrkBase
import Foundation

public struct SidebarSyncStamp: Hashable, Sendable, Codable, Comparable {
    public var counter: UInt64
    public var replica: String
    public init(counter: UInt64, replica: String) { self.counter = counter; self.replica = replica }
    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.counter == rhs.counter ? lhs.replica < rhs.replica : lhs.counter < rhs.counter
    }
}

/// This is the complete shared whitelist. No StateCodec DTO, browser context or filesystem path is accepted.
public enum SidebarSyncPayload: Hashable, Sendable, Codable {
    case space(title: String, icon: SpaceIcon, theme: SpaceTheme)
    case root(space: String?)
    case folder(title: String, icon: CustomIcon?)
    case tab(title: String, url: URL, icon: CustomIcon?)
    case split(orientation: SplitOrientation, icon: CustomIcon?)
}

public struct SidebarSyncValue: Hashable, Sendable, Codable {
    public var payload: SidebarSyncPayload
    public var parent: String?
    public var order: Int
    public init(payload: SidebarSyncPayload, parent: String?, order: Int) {
        self.payload = payload; self.parent = parent; self.order = order
    }
}

public struct SidebarSyncRecord: Hashable, Sendable, Codable {
    public var stamp: SidebarSyncStamp
    /// Nil is a permanent tombstone. Restoring an archived identity requires reenrollment with a new sync ID.
    public var value: SidebarSyncValue?
    public init(stamp: SidebarSyncStamp, value: SidebarSyncValue?) { self.stamp = stamp; self.value = value }
}

public struct SidebarSyncDocument: Hashable, Sendable, Codable {
    public var version: Int = 1
    public var records: [String: SidebarSyncRecord]
    public init(records: [String: SidebarSyncRecord] = [:]) { self.records = records }
}

public enum SidebarSync {
    public static func merge(_ left: SidebarSyncDocument, _ right: SidebarSyncDocument) throws -> SidebarSyncDocument {
        guard left.version == 1, right.version == 1 else { throw SidebarDataError.invalid("Unsupported sidebar sync version.") }
        var result = left
        for (id, incoming) in right.records {
            guard let old = result.records[id] else { result.records[id] = incoming; continue }
            if old.value == nil || incoming.value == nil {
                // Removal defeats every edit/move, including a disconnected stale device.
                let deletes = [old, incoming].filter { $0.value == nil }
                result.records[id] = deletes.max { $0.stamp < $1.stamp }
            } else if old.stamp == incoming.stamp {
                guard old == incoming else { throw SidebarDataError.invalid("Conflicting payloads have the same sync revision.") }
            } else if old.stamp < incoming.stamp { result.records[id] = incoming }
        }
        return result
    }

    public static func safeURL(_ url: URL) -> Bool {
        guard SidebarImport.publicURL(url), url.query == nil, url.fragment == nil,
              let host = url.host?.lowercased(), host != "localhost", !host.hasSuffix(".localhost"),
              !host.hasSuffix(".local"), !host.hasSuffix(".internal"),
              !host.hasPrefix("127."), !host.hasPrefix("0."), !host.hasPrefix("169.254."),
              !host.hasPrefix("192.168."), !host.hasPrefix("10."),
              !host.contains(":"), !host.contains("[") else { return false }
        let octets = host.split(separator: ".").compactMap { Int($0) }
        if octets.count == 4, octets[0] == 172, (16...31).contains(octets[1]) { return false }
        return true
    }
}

struct SidebarSyncLocal: Sendable, Equatable, Codable {
    var replica: String
    var counter: UInt64 = 0
    var profile: ProfileID
    var folder: String?
    var epoch: String
    var document = SidebarSyncDocument()
    var baseline: [String: SidebarSyncValue] = [:]
    /// Maps local identity to shared identity. A restored tombstoned local ID receives a fresh shared ID.
    var aliases: [String: String] = [:]
    var pending = true
}

struct SidebarDataSaved: Sendable, Equatable, Codable {
    /// Missing in existing v3 files means the existing installation already passed first run.
    var onboardingCompleted = true
    var sync: SidebarSyncLocal?
}

public struct SidebarDataSnapshot: Sendable, Equatable, Codable {
    public var needsOnboarding: Bool
    public var connected: Bool
    public var status: String
    public var profileName: String?
    public var excluded: Int
}

public struct OnboardingChoices: Hashable, Sendable, Codable {
    public var spaceName: String
    public var starterTabs: Bool
    public var favorites: Bool
    public var tour: Bool
    public var importAfter: Bool
    public var defaultBrowser: Bool
    public init(spaceName: String = "Personal", starterTabs: Bool = true, favorites: Bool = true, tour: Bool = true,
                importAfter: Bool = false, defaultBrowser: Bool = false) {
        self.spaceName = spaceName; self.starterTabs = starterTabs; self.favorites = favorites; self.tour = tour
        self.importAfter = importAfter; self.defaultBrowser = defaultBrowser
    }
}

public enum SidebarDataCommand: Hashable, Sendable, Codable {
    case welcome, tour, importFile, syncSettings, syncNow, disconnect
    case completeOnboarding(OnboardingChoices)
}

public enum SidebarPanel: Hashable, Sendable { case welcome, importFile, syncSettings }

public enum SidebarDataEvent: Sendable, Equatable {
    case syncPoll
    case imported(WindowID, target: SidebarImportTarget, SidebarImportPreview, favorites: Bool)
    case connected(WindowID, folder: String)
    case syncRead(epoch: String, SidebarSyncDocument)
    case syncWritten(epoch: String, revision: UInt64, published: SidebarSyncDocument)
    case failed(epoch: String?, String)
    case exportFinished(String)
}

public enum SidebarDataEffect: Hashable, Sendable {
    case panel(WindowID, SidebarPanel)
    case tour(WindowID)
    case exchange(epoch: String, folder: String, replica: String, revision: UInt64, SidebarSyncDocument)
}

extension AppState {
    public var docNeedsSidebarPublication: Bool { doc.sidebarData.sync?.folder != nil && doc.sidebarData.sync?.pending == true }
    public func sidebarImportTarget(in window: WindowID) -> SidebarImportTarget? {
        guard let w = doc.windows[window], w.kind == .standard, let space = doc.spaces[w.space] else { return nil }
        return SidebarImportTarget(space: space.id, profile: space.profile, title: displayTitle(of: space.id))
    }
    public var sidebarDataSnapshot: SidebarDataSnapshot {
        let sync = doc.sidebarData.sync
        return SidebarDataSnapshot(needsOnboarding: !doc.sidebarData.onboardingCompleted, connected: sync?.folder != nil,
                                   status: session.sidebarDataStatus, profileName: sync.flatMap { doc.profiles[$0.profile]?.name },
                                   excluded: sync.map { syncProjection(profile: $0.profile).excluded } ?? 0)
    }

    /// Only selected-profile Spaces, Pinned and Favorites. Observed titles, Today and live URLs are never used.
    func syncProjection(profile: ProfileID) -> (values: [String: SidebarSyncValue], excluded: Int) {
        var values: [String: SidebarSyncValue] = [:], excluded = 0
        let aliases = doc.sidebarData.sync?.aliases ?? [:]
        func key(_ raw: String) -> String { aliases[raw] ?? raw }
        func itemKey(_ id: ItemID) -> String { key("i-" + id.rawValue) }
        func walk(_ id: ItemID, parent: String?, order: Int) {
            guard let item = doc.tree[id] else { return }
            let payload: SidebarSyncPayload
            switch item.body {
            case .tab(let tab):
                guard let url = tab.pinnedURL, SidebarSync.safeURL(url) else { excluded += 1; return }
                payload = .tab(title: tab.customTitle ?? url.host ?? "Tab", url: url, icon: tab.icon)
            case .folder(let folder): payload = .folder(title: folder.title, icon: folder.icon)
            case .split(let split): payload = .split(orientation: split.orientation, icon: split.icon)
            case .section(let section):
                switch section.role {
                case .favorites: payload = .root(space: nil)
                case .pinned(let space): payload = .root(space: key("s-" + space.rawValue))
                default: return
                }
            }
            let idKey: String
            if case .section(let section) = item.body, case .favorites = section.role { idKey = "favorites" }
            else { idKey = itemKey(id) }
            values[idKey] = SidebarSyncValue(payload: payload, parent: parent, order: order)
            for (index, child) in item.children.enumerated() { walk(child, parent: idKey, order: index) }
        }
        if let root = doc.favorites[profile] { walk(root, parent: nil, order: 0) }
        for (index, id) in doc.spaceOrder.enumerated() {
            guard let space = doc.spaces[id], space.profile == profile else { continue }
            let spaceKey = key("s-" + id.rawValue)
            if let record = doc.sidebarData.sync?.document.records[spaceKey], record.value == nil { continue }
            values[spaceKey] = SidebarSyncValue(payload: .space(title: space.title, icon: space.icon, theme: space.theme), parent: nil, order: index)
            walk(space.pinnedRoot, parent: nil, order: 0)
        }
        return (values, excluded)
    }
}

public struct SidebarImportTarget: Sendable, Equatable, Hashable {
    public let space: SpaceID
    public let profile: ProfileID
    public let title: String
}
