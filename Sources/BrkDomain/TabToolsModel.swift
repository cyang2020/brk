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
    /// The × of the Little window's first-run tip ("Links Open in Little Arc").
    case dismissLittleTip
    /// The × on the empty favorites box (Arc's "Drag to add Favorites"): the box goes away for good.
    case dismissFavoritesHint
    /// ⌘Z while an undo toast shows: brings back what the cleared Today or the deleted space held.
    case undoToast
    /// BrkApp copied a link to the highlighted text (Shared Quotes): Arc's "Copied Link" / "With Quote".
    case quoteLinkCopied
    case preferences(includeFavorites: Bool, previews: Bool)
    /// A Favorite's or Pinned tab's per-site switch ("Show Unread Badge", "Show Time to Next Meeting", "Show Hover
    /// Preview"), kept by host like Arc's `topAppsBadgingDisabledHosts`.
    case siteDisplay(host: String, SiteDisplayOption, on: Bool)
    /// A tab group header's ×: archives the group's tabs as one unit.
    case closeGroup(ItemID)
    /// Group menu "Remove Group Header": the tabs stay, the header goes (⌘Z on the toast puts it back).
    case removeGroupHeader(ItemID)
    /// Command bar "Open <folder>": opens the folder and shows it in the sidebar.
    case openFolder(ItemID)
    /// "Replace Pinned Tab with the Current Site" / "Replace Pinned URL with Current".
    case replacePinned(ItemID)
    /// Command bar "Mute All Tabs" (true) / "Unmute All Tabs" (false).
    case muteAll(Bool)
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
    /// Off until turned on in settings, as Arc's Previews are.
    var hoverPreviews = false
    var archiveEducationDismissed = false
    /// An auto-archive has happened: Arc's banner says "We cleaned up!" and shows only then (its analytics event
    /// `autoArchiveEducationDisplayedWhenTabsAutoArchive`).
    var archiveEducationEarned = false
    var favoritesHintDismissed = false
    var littleTipDismissed = false
    /// Hosts whose Favorite hides its unread dot (Arc: `topAppsBadgingDisabledHosts`).
    var badgeHiddenHosts: Set<String> = []
    /// Hosts whose calendar Favorite hides the time to the next meeting (Arc: `topAppsSubtitleDisabledHosts`).
    var subtitleHiddenHosts: Set<String> = []
    /// Hosts whose hover card is off ("Show Hover Preview").
    var previewHiddenHosts: Set<String> = []

    private enum CodingKeys: String, CodingKey {
        case includeFavoritesInNumbers, hoverPreviews, archiveEducationDismissed, archiveEducationEarned, favoritesHintDismissed, littleTipDismissed, badgeHiddenHosts, subtitleHiddenHosts, previewHiddenHosts
    }

    init() {}

    /// Keys added later are absent from older state files.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        includeFavoritesInNumbers = try c.decodeIfPresent(Bool.self, forKey: .includeFavoritesInNumbers) ?? true
        hoverPreviews = try c.decodeIfPresent(Bool.self, forKey: .hoverPreviews) ?? false
        archiveEducationDismissed = try c.decodeIfPresent(Bool.self, forKey: .archiveEducationDismissed) ?? false
        archiveEducationEarned = try c.decodeIfPresent(Bool.self, forKey: .archiveEducationEarned) ?? false
        favoritesHintDismissed = try c.decodeIfPresent(Bool.self, forKey: .favoritesHintDismissed) ?? false
        littleTipDismissed = try c.decodeIfPresent(Bool.self, forKey: .littleTipDismissed) ?? false
        badgeHiddenHosts = try c.decodeIfPresent(Set<String>.self, forKey: .badgeHiddenHosts) ?? []
        subtitleHiddenHosts = try c.decodeIfPresent(Set<String>.self, forKey: .subtitleHiddenHosts) ?? []
        previewHiddenHosts = try c.decodeIfPresent(Set<String>.self, forKey: .previewHiddenHosts) ?? []
    }

    /// The newer key is written only once set, so an older file round-trips byte for byte.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(includeFavoritesInNumbers, forKey: .includeFavoritesInNumbers)
        try c.encode(hoverPreviews, forKey: .hoverPreviews)
        try c.encode(archiveEducationDismissed, forKey: .archiveEducationDismissed)
        // Only once earned: an older file reads back byte for byte until then.
        if archiveEducationEarned { try c.encode(archiveEducationEarned, forKey: .archiveEducationEarned) }
        if favoritesHintDismissed { try c.encode(true, forKey: .favoritesHintDismissed) }
        if littleTipDismissed { try c.encode(true, forKey: .littleTipDismissed) }
        if !badgeHiddenHosts.isEmpty { try c.encode(badgeHiddenHosts.sorted(), forKey: .badgeHiddenHosts) }
        if !subtitleHiddenHosts.isEmpty { try c.encode(subtitleHiddenHosts.sorted(), forKey: .subtitleHiddenHosts) }
        if !previewHiddenHosts.isEmpty { try c.encode(previewHiddenHosts.sorted(), forKey: .previewHiddenHosts) }
    }
}
struct TabSelection: Equatable, Sendable {
    var items: [ItemID] = []
    var anchor: ItemID?
}
public struct ToastSnapshot: Equatable, Sendable, Codable {
    public var text: String
    public var expiresAt: Instant
    /// A notice with a way out (Arc's "ChatGPT in the Command Bar not enabled" with "Arc Max Preferences ↗"): shown
    /// as Arc's notice banner instead of the plain toast.
    public var link: ToastLink? = nil
    /// Arc's undo toasts: "Cleared Tabs! Use", the key cap "⌘Z", then "to undo".
    public var keycap: String? = nil
    public var trailing: String? = nil
    /// One button on the toast (Arc: "Screenshot Copied to Clipboard" · Save; "Copied Current URL" · Share).
    public var action: ToastAction? = nil
    /// A second, smaller line under the text (Arc's sublabel: "Copied Link" / "With Quote").
    public var subtitle: String? = nil
    /// What a click on the strip does before it closes (Arc: "Tab moved! Click to go there.").
    public var click: Command? = nil
    /// Where Arc shows it (Q20). Absent in saved data: the window's corner.
    public var placement: ToastPlacement? = nil
}

/// Arc has two toast spots (measured on Arc 1.170, 2026-11-05, Q20): a toast about the page being shown ("Copied
/// Current URL", "Translated back to French!") sits inside the page card, 8.5 pt from its top and right edges; every
/// other one ("Cleared Tabs!", "Space deleted!", "Screenshot Copied to Clipboard", the Max notice) sits at the
/// window's corner, 4.5 pt from the top, above the card's edge.
public enum ToastPlacement: String, Sendable, Equatable, Codable { case window, page }
/// Arc's toast copy (the strings in its binary beside "Letting user know…", `ToastController`), for the toasts two rules
/// or a rule and a test share.
public enum ToastCopy {
    public static let copiedCurrentURL = "Copied Current URL"
    public static let share = "Share"
    public static let copiedItemLinks = "Copied item links"
    public static let copiedLink = "Copied Link"
    public static let withQuote = "With Quote"
    public static let tabMoved = "Tab moved! Click to go there."
    public static let newSpaceCreated = "New Space Created"
    public static let archiveCleared = "Archive Cleared"
    public static func deletedForGood(_ title: String) -> String { "Deleted “\(title.count > 40 ? String(title.prefix(39)) + "…" : title)”" }
    public static let folderDeleted = "Folder deleted"
    public static let cannotAddPane = "Cannot Add New Pane"
    public static let newTabCreated = "New Tab Created"
    public static let captureInProgress = "Capture in Progress…"
    public static let exitFullScreen = "To exit full screen, press"
    public static let escapeKey = "esc"
    public static let downloadRenamed = "Download renamed to:"
    public static let boostInstalled = "Boost installed!"
    public static let importSucceeded = "Success! We imported all of your stuff"
    public static let importPartly = "Only some of your data imported. Please try again!"
    public static func pinned(to space: String) -> String { "Pinned Tab to “\(space)”" }
    public static func unpinned(from space: String) -> String { "Un-Pinned Tab from “\(space)”" }
    public static func newTabCreated(in space: String) -> String { "New Tab Created in \(space)" }
    public static func restored(folder: Bool, to space: String) -> String { "\(folder ? "Folder" : "Tab") restored to \(space)" }
    public static func restoredClickToView(folder: Bool, to space: String) -> String { restored(folder: folder, to: space) + ". Click to view." }
    public static func autoArchived(_ count: Int) -> String { "Auto archived \(count) tabs" }
}
public struct ToastAction: Equatable, Sendable, Codable {
    public var title: String
    /// An icon in place of the title (Q11-b's Share button).
    public var symbol: String? = nil
    public var command: Command
}
public struct ToastLink: Equatable, Sendable, Codable {
    public var title: String
    public var command: Command
}

/// What ⌘Z undoes while an undo toast shows (session only).
enum ToastUndo: Sendable, Equatable {
    /// Clear Today: the archive entries it made, in sidebar order.
    case restore([ArchiveID])
    /// Delete Space: the space, its dock position and the archive entries of its tabs.
    case space(Space, index: Int, entries: [ArchiveID])
    /// Remove Group Header: the header and the tabs it held.
    case regroup(id: ItemID, folder: Folder, parent: ItemID, children: [ItemID])
    /// Use Original on a translated page (P50-e "Translated back to French! Use ⌘Z to undo."): the translation again.
    case translation(PageID)
    /// Tidy on the Today divider: the Today order before the tab groups.
    case tidy
    /// Place New Tabs moved a new tab into a group: back to where it was in Today.
    case placement(ItemID, parent: ItemID, index: Int)
    /// Name with AI renamed a folder: its name before.
    case folderName(ItemID, String)
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
extension TabToolsSnapshot {
    /// No tools at work: what a page that only shows a Space's rows passes (`SpaceSidePageView`).
    public static let idle = TabToolsSnapshot()
}

public struct TabToolsSnapshot: Equatable, Sendable, Codable {
    public var pendingSiteRequest: String? = nil
    public var selected: [ItemID] = []
    public var reveal: ItemID?
    public var revealGeneration: UInt64 = 0
    public var recent: RecentTabsSnapshot?
    public var toast: ToastSnapshot?
    /// The auto-archive banner at the bottom of a fresh profile's first space after the first auto-archive: the
    /// profile's threshold ("12 hours") for Arc's "Arc archives tabs that you haven’t used in the past 12 hours. You can
    /// adjust this in Settings."
    public var archiveEducation: String?
    /// A Little window's first-run tip is still to be dismissed.
    public var littleTip = false
    public var hoverPreviews = false
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
