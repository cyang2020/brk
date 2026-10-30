import BrkBase
import Foundation

// The sidebar as Arc stores it (anatomy 1.4): one flat map of items keyed by id. Hierarchy is `parent` on every
// non-root item plus ordered `children` on containers. What an item is lives in `body`.
//
// Single writer, by construction: `parent` and `children` are `fileprivate(set)` and `SidebarTree.items` is
// `private(set)`, so only code in this file can create, move or delete items or change the hierarchy. Rules
// elsewhere change an item's payload through `update(_:_:)`, which cannot touch `parent` or `children`.
//
// Dominant reads and how this structure serves them:
// - render a section: walk `children` from its root (ordered).                                 O(rows)
// - which section and space is this tab in (Cmd+D, auto-archive, focus): walk `parent` up.     depth <= 4
// - what a window shows: WindowDoc.activeBySpace[space] -> tab or split -> split.children.      O(1)
// - recent-tab order (Ctrl+Tab): sort the space's tabs by `lastActiveAt`; no MRU list to keep in sync.

struct Item: Sendable, Equatable {
    let id: ItemID
    let createdAt: Instant
    /// Nil exactly for section roots.
    fileprivate(set) var parent: ItemID?
    /// Ordered. Empty for tabs. A split has 2 or more (normalize dissolves a split left with one pane).
    fileprivate(set) var children: [ItemID]
    var body: ItemBody
}

enum ItemBody: Sendable, Equatable {
    case tab(Tab)
    case folder(Folder)
    case split(Split)
    case section(Section)
}

/// Arc: `SidebarTab`.
struct Tab: Sendable, Equatable {
    /// Current location: set by the user (submit, reset) and by committed navigations. Nil only for an empty split
    /// pane waiting for the command bar. A failed load never changes it.
    var url: URL?
    /// As last reported by the page.
    var title: String
    /// Set by rename; shown instead of `title`. Separate so page title events never clobber it.
    var customTitle: String?
    var favicon: URL?
    /// URL when the tab entered Pinned or Favorites (Arc: `savedURL`); the target of "Reset Tab". Nil exactly
    /// while the tab is in Today. Maintained only by `SidebarTree.move`.
    var pinnedURL: URL?
    /// Last time the tab started or stopped being on screen. Drives auto-archive and recent-tab order.
    var lastActiveAt: Instant
}

/// Arc: `SidebarList`. Lives in Pinned (and Favorites later). `collapsed` is global; Arc keeps it per window.
struct Folder: Sendable, Equatable {
    var title: String
    var collapsed: Bool
    // Later: `live: LiveFolderSource?` (Arc: `automaticLiveFolderData`), filled by `SystemEvent.liveFolder`.
}

/// Arc: `SidebarSplitViewData`. The panes are the item's children, left to right.
struct Split: Sendable, Equatable {
    /// Relative widths keyed by pane (Arc: `itemWidthFactors`), so removing a pane cannot misalign an array.
    /// A missing key counts as 1. Normalized on read.
    var widths: [ItemID: Double]
    var focused: ItemID
    var lastActiveAt: Instant
    // Later: `orientation` (Arc: `layoutOrientation` horizontal | vertical).
}

/// A section root. Never moves, never archived. Arc: `SidebarItemContainer.ContainerType`.
enum Section: Sendable, Equatable, Hashable {
    /// One per profile, shared by every space of that profile (Arc: `topApps(Profile)`).
    case favorites(ProfileID)
    case pinned(SpaceID)
    /// Arc's unpinned container, called "Today" in the UI.
    case today(SpaceID)

    var kind: SectionKind {
        switch self {
        case .favorites: .favorites
        case .pinned: .pinned
        case .today: .today
        }
    }
}

public enum SectionKind: String, Hashable, Sendable, Codable, CaseIterable {
    case favorites, pinned, today
}

public enum ItemKind: String, Hashable, Sendable, Codable { case tab, folder, split, section }

/// Where an item may be placed. The one rule table: the reducer refuses a move it forbids, and the sidebar's drag
/// feedback calls the same function with the row kinds from its snapshot instead of re-deriving the rules.
public enum Placement {
    /// v1: tabs anywhere; folders in Pinned (nested folders allowed, no cycles); splits in Pinned and Today; nothing
    /// inside a split except tabs placed there by split rules.
    public static func canPlace(_ kind: ItemKind, inSection section: SectionKind, parentKind: ItemKind) -> Bool {
        // TODO(W1): the table above; parentKind == .split -> only via SplitRules (return false here).
        fatalError("not implemented")
    }
}

/// Where an insert or move lands. Arc: `SidebarInsertionStrategy`.
enum TreePosition: Sendable, Equatable {
    /// `index` counts the parent's children after the moved item is detached, so applying a move twice is a no-op.
    case into(parent: ItemID, index: Int)
    case after(ItemID)
    case before(ItemID)
}

enum TreeError: Error, Equatable {
    case itemNotFound, invalidHierarchy, forbiddenPlacement, wouldCreateCycle
}

struct SidebarTree: Sendable, Equatable {
    private(set) var items: [ItemID: Item]

    init() { items = [:] }

    subscript(id: ItemID) -> Item? { items[id] }

    /// Creates a section root. Used by space creation and fresh-profile setup only.
    mutating func makeRoot(_ id: ItemID, _ section: Section, createdAt: Instant) {
        items[id] = Item(id: id, createdAt: createdAt, parent: nil, children: [], body: .section(section))
    }

    /// Inserts a new item. Throws if the position is invalid or `Placement` forbids it.
    mutating func insert(_ id: ItemID, _ body: ItemBody, at position: TreePosition, createdAt: Instant) throws(TreeError) {
        // TODO(W1): resolve position to (parent, index); check Placement; set parent; splice into children;
        // if the destination section is pinned or favorites and body is a tab, set pinnedURL = url.
        fatalError("not implemented")
    }

    /// The only way an item changes place. Keeps `parent`/`children` in agreement and maintains `pinnedURL`
    /// (set on entering Pinned or Favorites, cleared on entering Today), so Cmd+D, drag and drop and
    /// "move to space" cannot disagree about it.
    mutating func move(_ id: ItemID, to position: TreePosition) throws(TreeError) {
        // TODO(W1): refuse section roots, cycles (position inside id's own subtree), forbidden placement;
        // detach from old parent's children; resolve index after detach; attach; update pinnedURL for every tab
        // in the moved subtree whose section changed.
        fatalError("not implemented")
    }

    /// Removes the item and its subtree, returning the removed tabs (callers archive them).
    mutating func removeSubtree(_ id: ItemID) -> [(ItemID, Tab)] {
        fatalError("not implemented")
    }

    /// Changes an item's payload. Cannot change hierarchy (`parent`/`children` are not settable outside this file).
    mutating func update(_ id: ItemID, _ change: (inout ItemBody) -> Void) {
        guard var item = items[id] else { return }
        change(&item.body)
        items[id] = item
    }

    /// Fixes orphan references, missing roots, wrong placements after decoding a file. Reports what it changed.
    mutating func repair() -> [String] {
        fatalError("not implemented")
    }

    // MARK: Reads

    func section(of id: ItemID) -> Section? {
        // TODO(W1): walk parent until a .section body.
        fatalError("not implemented")
    }

    /// Tabs under `id` (inclusive), depth first in sidebar order.
    func tabs(under id: ItemID) -> [ItemID] {
        fatalError("not implemented")
    }

    /// Items in visual order for one section, flattening open folders; a split counts as one stop.
    func sidebarOrder(_ root: ItemID) -> [ItemID] {
        fatalError("not implemented")
    }
}
