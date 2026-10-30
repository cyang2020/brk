import BrkBase
import BrkDomain
import CoreGraphics
import Foundation

// Every frame in a window, as data. `WindowLayout.compute` is the only code that turns a snapshot and the window's
// content size into positions; views apply these frames verbatim and never compute their own, the control socket
// returns them verbatim, and e2e compares them with the frames AppKit actually has (`ControlReply.frames`), so
// layout drift between "what we meant" and "what is on screen" is a test failure, not a screenshot argument.
//
// Coordinates: window content space, points, origin at the TOP-left, y grows down. Every BrkUI container is
// flipped (`isFlipped == true`), so a frame here is assigned to `NSView.frame` without conversion.

public struct WindowFrames: Sendable, Equatable, Codable {
    public var contentSize: CGSize
    /// Nil when the sidebar is hidden and not peeking.
    public var sidebar: SidebarFrames?
    /// True when `sidebar` is the floating (peeked) sidebar over the content.
    public var sidebarFloats: Bool
    public var resizeHandle: CGRect?
    /// The left-edge strip that reveals a hidden sidebar on hover.
    public var revealStrip: CGRect?
    /// The area the cards share (window minus sidebar, inset by Metrics.content.inset).
    public var contentArea: CGRect
    /// One per pane, left to right; panes separated by Metrics.content.splitGap.
    public var cards: [CardFrame]
    /// Drag handles in the gaps between cards.
    public var dividers: [CGRect]
    public var commandBar: CGRect?
    /// The archive page draws inside the content area, like Arc's archive in the content card.
    public var archive: CGRect?

    public init(contentSize: CGSize, sidebar: SidebarFrames?, sidebarFloats: Bool, resizeHandle: CGRect?,
                revealStrip: CGRect?, contentArea: CGRect, cards: [CardFrame], dividers: [CGRect],
                commandBar: CGRect?, archive: CGRect?) {
        self.contentSize = contentSize
        self.sidebar = sidebar
        self.sidebarFloats = sidebarFloats
        self.resizeHandle = resizeHandle
        self.revealStrip = revealStrip
        self.contentArea = contentArea
        self.cards = cards
        self.dividers = dividers
        self.commandBar = commandBar
        self.archive = archive
    }
}

public struct CardFrame: Sendable, Equatable, Codable {
    public var pane: Int
    public var content: PaneContent
    public var rect: CGRect
    public var cornerRadius: Double
}

public struct SidebarFrames: Sendable, Equatable, Codable {
    public var frame: CGRect
    /// Traffic lights and back/forward/reload (Metrics.sidebar.titleRowHeight).
    public var titleRow: CGRect
    /// Origin of the close button; the other two follow at size + spacing.
    public var trafficLightsOrigin: CGPoint
    public var urlPill: CGRect
    public var favoritesTray: CGRect
    public var favoriteTiles: [ItemID: CGRect]
    /// The scrolling tab list's visible rect; rows are in its document coordinates.
    public var tablistViewport: CGRect
    public var rows: [RowFrame]
    public var dock: CGRect
    public var dockSpaces: [SpaceID: CGRect]
    public var libraryButton: CGRect
    public var plusButton: CGRect
}

/// One line of the tab list, after flattening folders.
public struct RowFrame: Sendable, Equatable, Codable {
    public enum Kind: Sendable, Equatable, Codable {
        case topSpacer
        case item(ItemID)
        /// The Pinned/Today divider (Arc: `exploreSectionDivider`), with Today's Clear button.
        case divider
        /// Today's "New Tab" row (Arc: `newTabButton`).
        case newTab
    }
    public var kind: Kind
    /// Document coordinates of the tab list.
    public var rect: CGRect
    /// Folder nesting level (indent = depth x Metrics.tablist.folderIndent).
    public var depth: Int
}

/// Every view the harness can address. `identifier` is the view's NSAccessibility identifier (set by BrkUI from
/// this enum, never typed by hand), and `WindowFrames.frame(of:)` is its computed frame when layout owns it.
public enum ViewID: Hashable, Sendable, Codable {
    case sidebar, floatingSidebar, titleRow, urlPill, favoritesTray
    case favorite(ItemID)
    case section(SectionKind)
    case row(ItemID)
    case rowClose(ItemID)
    case todayNewTab, todayClear, renameField
    case dock, dockSpace(SpaceID), dockLibrary, dockPlus
    case resizeHandle, revealStrip
    case card(Int), divider(Int)
    case commandBar, commandBarInput, commandBarResult(Int)
    case archive, archiveGroup(ArchiveBucket), archiveEntry(ArchiveID), archiveRestore(ArchiveID), archiveClear, archiveThreshold
    case spaceDialog
    case themeBackground

    public var identifier: String {
        switch self {
        case .sidebar: "sidebar"
        case .floatingSidebar: "floating-sidebar"
        case .titleRow: "title-row"
        case .urlPill: "url-pill"
        case .favoritesTray: "favorites"
        case .favorite(let id): "favorite-\(id)"
        case .section(let kind): "section-\(kind.rawValue)"
        case .row(let id): "row-\(id)"
        case .rowClose(let id): "row-\(id)-close"
        case .todayNewTab: "today-new-tab"
        case .todayClear: "today-clear"
        case .renameField: "rename-field"
        case .dock: "dock"
        case .dockSpace(let id): "dock-space-\(id)"
        case .dockLibrary: "dock-library"
        case .dockPlus: "dock-plus"
        case .resizeHandle: "sidebar-resize"
        case .revealStrip: "reveal-strip"
        case .card(let i): "card-\(i)"
        case .divider(let i): "split-divider-\(i)"
        case .commandBar: "command-bar"
        case .commandBarInput: "command-bar-input"
        case .commandBarResult(let i): "command-bar-result-\(i)"
        case .archive: "archive"
        case .archiveGroup(let bucket): "archive-group-\(bucket.rawValue)"
        case .archiveEntry(let id): "archive-entry-\(id)"
        case .archiveRestore(let id): "archive-restore-\(id)"
        case .archiveClear: "archive-clear"
        case .archiveThreshold: "archive-threshold"
        case .spaceDialog: "space-dialog"
        case .themeBackground: "theme-background"
        }
    }
}

extension WindowFrames {
    /// The computed frame of a view, in window coordinates, when layout owns it (rows are converted out of the
    /// tab list's document space using its current scroll offset of zero; scrolled rows are reported by `actual`).
    public func frame(of view: ViewID) -> CGRect? {
        // TODO(W2): switch over the cases layout owns; nil for view-owned frames (command bar results, archive rows).
        fatalError("not implemented")
    }
}
