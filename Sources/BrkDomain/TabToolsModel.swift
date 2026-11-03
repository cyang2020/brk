import BrkBase
import Foundation

public enum SelectionGesture: String, Hashable, Sendable, Codable { case replace, toggle, range }
public enum TabTargets: Hashable, Sendable, Codable {
    case selected
    case items([ItemID])
    case other(ItemID)
    case below(ItemID)
}
public enum BulkTabAction: Hashable, Sendable, Codable {
    case close, archive
    /// Nil duplicates immediately after each source in its own parent.
    case duplicate(Destination?)
    case move(Destination)
    case newFolder(group: Bool)
}
public enum TabToolsCommand: Hashable, Sendable, Codable {
    case site(SiteToolsCommand)
    case resetPinned
    case cycleLinear(Step)
    case jumpItem(Int)
    case jumpSpace(Int)
    case select(ItemID, SelectionGesture)
    case bulk(TabTargets, BulkTabAction)
    case reveal
    case sidebarStep(Step)
    case leaveSidebar
    case folders(expanded: Bool)
    case cancelRecent
    case chooseIcon(ItemID)
    case iconPickerClosed
    case mute(ItemRef)
    case dismissToast
    case dismissArchiveEducation
    case preferences(includeFavorites: Bool, previews: Bool)
    /// Context menu "Copy Link", "Copy All Links" (a folder) and "Copy Links" (several rows): every address under
    /// the targets, one per line, on the pasteboard.
    case copyLinks(TabTargets)
    /// Context menu "Open in Split View": the first target joins what the window shows in a split (or, when it
    /// cannot, shows with a new empty pane); further targets join that split.
    case openInSplit(TabTargets)
    /// Folder menu "New Nested Folder…": a folder at the top of the folder, in rename mode.
    case newNestedFolder(ItemID)
    /// Folder menu "Turn “X” into Space": a new space named after the folder whose Pinned holds its contents.
    case folderToSpace(ItemID)
    /// Tab menu "Customize Page…": shows the tab and opens its site's Boost (a new one when there is none).
    case customize(ItemID)
    /// Split menu "Add Tab…": shows the split and adds an empty pane with the command bar.
    case addToSplit(ItemID)
    /// Space menu "Export “X” into Folder" > a space: the space's Pinned and Today move into a new folder at the
    /// top of that space's Pinned and the emptied space is deleted (Arc's "Space turned into folder").
    case spaceIntoFolder(SpaceID, into: SpaceID)
}

struct TabPreferences: Equatable, Sendable, Codable {
    var includeFavoritesInNumbers = true
    var hoverPreviews = true
    var archiveEducationDismissed = false
}
struct TabSelection: Equatable, Sendable {
    var items: [ItemID] = []
    var anchor: ItemID?
}
public struct ToastSnapshot: Equatable, Sendable, Codable {
    public var text: String
    public var expiresAt: Instant
    /// A notice with a way out (Arc's "ChatGPT in the Command Bar not enabled" with "Arc Max Preferences ↗"): shown
    /// as a banner at the window's top right instead of the bottom toast.
    public var link: ToastLink? = nil
}
public struct ToastLink: Equatable, Sendable, Codable {
    public var title: String
    public var command: Command
}
public struct RecentTabsSnapshot: Equatable, Sendable, Codable {
    public var items: [RecentTabRow]
    public var selected: ItemID
}
public struct RecentTabRow: Equatable, Sendable, Codable {
    public var id: ItemID
    public var title: String
    public var url: URL?
    /// The tab's favicon, drawn before its title under the switcher's thumbnail.
    public var favicon: URL? = nil
}
public struct TabToolsSnapshot: Equatable, Sendable, Codable {
    public var pendingSiteRequest: String? = nil
    public var selected: [ItemID] = []
    public var reveal: ItemID?
    public var revealGeneration: UInt64 = 0
    public var recent: RecentTabsSnapshot?
    public var toast: ToastSnapshot?
    public var archiveEducation: String?
    public var hoverPreviews = true
    public var includeFavoritesInNumbers = true
}

extension AutoArchiveThreshold {
    public var tabToolsLabel: String {
        switch self {
        case .oneHour: "1 hour"
        case .sixHours: "6 hours"
        case .twelveHours: "12 hours"
        case .twentyFourHours: "24 hours"
        case .sevenDays: "7 days"
        case .thirtyDays: "30 days"
        case .never: "Never"
        }
    }
}

/// Row kind determines hover metadata. Today can contain folders as well as tabs and splits.
extension Row {
    public var hoverPreviewText: String {
        switch self {
        case .tab(let tab): tab.title + "\n" + (tab.url?.absoluteString ?? "")
        case .folder(let folder): folder.title + "\n" + String(folder.children.count) + " items"
        case .split(let split): split.panes.map(\.title).joined(separator: "\n")
        }
    }
}
