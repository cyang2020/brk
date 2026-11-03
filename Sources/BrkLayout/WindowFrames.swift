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
    public var toolbar: CGRect? = nil
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
    /// The Library host draws inside the content area (the archive is one of its pages), like Arc's archive in the
    /// content card. Nil unless the Library is open.
    public var library: LibraryFrames?
    /// The Peek card over the content area (Metrics.peek), nil unless a Peek is open.
    public var find: FindFrames? = nil
    public var peek: CGRect?

    public init(contentSize: CGSize, sidebar: SidebarFrames?, sidebarFloats: Bool, resizeHandle: CGRect?,
                revealStrip: CGRect?, contentArea: CGRect, cards: [CardFrame], dividers: [CGRect],
                commandBar: CGRect?, library: LibraryFrames?, peek: CGRect?) {
        self.contentSize = contentSize
        self.sidebar = sidebar
        self.sidebarFloats = sidebarFloats
        self.resizeHandle = resizeHandle
        self.revealStrip = revealStrip
        self.contentArea = contentArea
        self.cards = cards
        self.dividers = dividers
        self.commandBar = commandBar
        self.library = library
        self.peek = peek
    }
}

/// The Library panel (Arc: `HomeButton`), in the sidebar's place: `strip` (and `frame`) is the whole panel, `nav` its
/// navigation column with one cell per `LibraryPage` (`pageCells`, in `LibraryPage.allCases` order), and `page` the
/// open page's column beside it. The content area keeps showing the window's page. Owner: F5 (`LibraryLayout`).
public struct LibraryFrames: Sendable, Equatable, Codable {
    public var frame: CGRect
    public var strip: CGRect
    public var nav: CGRect
    public var pageCells: [LibraryPage: CGRect]
    public var page: CGRect

    public init(frame: CGRect, strip: CGRect, nav: CGRect, pageCells: [LibraryPage: CGRect], page: CGRect) {
        self.frame = frame
        self.strip = strip
        self.nav = nav
        self.pageCells = pageCells
        self.page = page
    }
}

public struct CardFrame: Sendable, Equatable, Codable {
    public var pane: Int
    public var content: PaneContent
    public var rect: CGRect
    public var cornerRadius: Double
    /// A split pane's own header strip along the top of its card (Arc: each pane has back, forward, reload, its
    /// host and close; Metrics.content.paneHeaderHeight), nil outside a split.
    public var header: CGRect? = nil

    /// Where the page draws: the card under its header and the header's hairline, else the whole card.
    public var page: CGRect {
        guard let header else { return rect }
        let top = header.height + Metrics.content.paneHeaderSeparator.value
        return CGRect(x: rect.minX, y: rect.minY + top, width: rect.width, height: max(0, rect.height - top))
    }
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
    /// The space title strip (Arc: `pinnedTabsHeader`, Metrics.tablist.spaceHeaderHeight) between the favorites
    /// tray and the tab list; W3 draws the space's icon and name there and a click collapses Pinned.
    public var spaceHeader: CGRect
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
    case toolbar, toolbarAddress, toolbarButton(String), spaceToolsControl(String), boostControl(String)
    /// The page loading bar above the content card (Arc P06-a).
    case loadingBar
    case siteInfo, paneSiteInfo
    case sidebar, floatingSidebar, titleRow, urlPill, favoritesTray
    case favorite(ItemID)
    case section(SectionKind)
    case row(ItemID)
    case rowClose(ItemID)
    case todayNewTab, todayClear, renameField
    case dock, dockSpace(SpaceID), dockLibrary, dockPlus
    case resizeHandle, revealStrip
    case card(Int), divider(Int)
    case findBar, findQuery, findReplacement, findStatus, findNext, findPrevious, findClose, findReplace, findReplaceAll, findCapture
    case splitTool(ActionID), splitSegment(ItemID), splitDropPreview
    case commandBar, commandBarInput, commandBarResult(Int)
    case archive, archiveGroup(ArchiveBucket), archiveEntry(ArchiveID), archiveRestore(ArchiveID), archiveClear, archiveThreshold
    case spaceDialog
    case themeBackground
    case tabTool(String)
    // Wave 2
    /// The Library host, its navigation cells, its close button; the Downloads rows; the History page in its card
    /// and its visits (F5).
    case library, libraryPage(LibraryPage), libraryClose, downloadEntry(DownloadID), historyPage, historyEntry(Int)
    /// The Peek card and its round buttons: close, open as a tab, open in a split (F3).
    case peek, peekClose, peekOpenIn, peekSplit
    /// The scratch section of an ephemeral window's sidebar and the Little Arc hint strip (F3).
    case littleHint
    /// The profile badge in the URL pill and the profile dialog (F2).
    case profileBadge, profileDialog
    /// The settings window: its pane toolbar buttons and one id per field, by the setting's name (F1).
    case settingsWindow, settingsPane(SettingsPane), settingsField(String)
    /// An Easel's board in its card, one of its controls by name (the tools, the title box, the font-size buttons,
    /// the person button), one element by id, and a card of the Library's Easels page.
    case easelBoard, easelControl(String), easelElement(String), easelCard(EaselID)

    public var identifier: String {
        switch self {
        case .toolbar: "address-toolbar"
        case .toolbarAddress: "toolbar-address"
        case .loadingBar: "loading-bar"
        case .toolbarButton(let name): "toolbar-\(name)"
        case .boostControl(let name): "boost-\(name)"
        case .spaceToolsControl(let name): "space-tools-\(name)"
        case .sidebar: "sidebar"
        case .floatingSidebar: "floating-sidebar"
        case .titleRow: "title-row"
        case .siteInfo: "site-info"
        case .paneSiteInfo: "pane-site-info"
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
        case .findBar: "find-bar"
        case .findQuery: "find-query"
        case .findReplacement: "find-replacement"
        case .findStatus: "find-status"
        case .findNext: "find-next"
        case .findPrevious: "find-previous"
        case .findClose: "find-close"
        case .findReplace: "find-replace"
        case .findReplaceAll: "find-replace-all"
        case .findCapture: "find-capture"
        case .splitTool(let action): "split-tool-\(action.rawValue)"
        case .splitSegment(let item): "split-segment-\(item)"
        case .splitDropPreview: "split-drop-preview"
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
        case .tabTool(let name): "tab-tools-\(name)"
        case .themeBackground: "theme-background"
        case .library: "library"
        case .libraryPage(let page): "library-page-\(page.rawValue)"
        case .libraryClose: "library-close"
        case .downloadEntry(let id): "download-\(id)"
        case .historyPage: "history-page"
        case .historyEntry(let i): "history-\(i)"
        case .peek: "peek"
        case .peekClose: "peek-close"
        case .peekOpenIn: "peek-open-in"
        case .peekSplit: "peek-split"
        case .littleHint: "little-hint"
        case .profileBadge: "profile-badge"
        case .profileDialog: "profile-dialog"
        case .settingsWindow: "settings"
        case .settingsPane(let pane): "settings-pane-\(pane.rawValue)"
        case .settingsField(let name): "settings-field-\(name)"
        case .easelBoard: "easel-board"
        case .easelControl(let name): "easel-\(name)"
        case .easelElement(let id): "easel-element-\(id)"
        case .easelCard(let id): "easel-card-\(id)"
        }
    }
}

extension WindowFrames {
    /// The computed frame of a view, in window coordinates, when layout owns it (rows are converted out of the
    /// tab list's document space using its current scroll offset of zero; scrolled rows are reported by `actual`).
    public func frame(of view: ViewID) -> CGRect? {
        switch view {
        case .toolbar: return toolbar
        case .toolbarAddress: return toolbar.map(AddressToolbarLayout.address(in:))
        case .toolbarButton, .spaceToolsControl, .boostControl: return nil
        case .sidebar: return sidebarFloats ? nil : sidebar?.frame
        case .floatingSidebar: return sidebarFloats ? sidebar?.frame : nil
        case .titleRow: return sidebar?.titleRow
        case .urlPill: return sidebar.flatMap { $0.urlPill.height > 0 ? $0.urlPill : nil }   // empty while the toolbar has the address
        case .favoritesTray: return sidebar?.favoritesTray
        case .favorite(let id): return sidebar?.favoriteTiles[id]
        case .row(let id):
            guard let s = sidebar, let row = s.rows.first(where: { $0.kind == .item(id) }) else { return nil }
            return row.rect.offsetBy(dx: s.tablistViewport.minX, dy: s.tablistViewport.minY)
        case .todayNewTab:
            guard let s = sidebar, let row = s.rows.first(where: { $0.kind == .newTab }) else { return nil }
            return row.rect.offsetBy(dx: s.tablistViewport.minX, dy: s.tablistViewport.minY)
        case .dock: return sidebar?.dock
        case .dockSpace(let id): return sidebar?.dockSpaces[id]
        case .dockLibrary: return sidebar?.libraryButton
        case .dockPlus: return sidebar?.plusButton
        case .resizeHandle: return resizeHandle
        case .revealStrip: return revealStrip
        case .card(let i): return cards.first { $0.pane == i }?.rect
        case .divider(let i): return i < dividers.count ? dividers[i] : nil
        case .findBar: return find?.bar
        case .findQuery, .findReplacement, .findStatus, .findNext, .findPrevious, .findClose, .findReplace, .findReplaceAll, .findCapture: return nil
        case .commandBar: return commandBar
        case .library: return library?.frame
        case .libraryPage(let page): return library?.pageCells[page]
        case .archive: return library?.page   // the archive page fills the Library's page column while it is the open page
        case .historyPage: return cards.first { if case .history = $0.content { true } else { false } }?.rect
        case .easelBoard: return cards.first { if case .easel = $0.content { true } else { false } }?.rect
        case .peek: return peek
        case .siteInfo, .paneSiteInfo, .loadingBar, .section, .rowClose, .todayClear, .renameField, .commandBarInput, .commandBarResult, .archiveGroup, .archiveEntry,
             .archiveRestore, .archiveClear, .archiveThreshold, .spaceDialog, .themeBackground, .libraryClose, .downloadEntry,
             .historyEntry, .peekClose, .peekOpenIn, .peekSplit, .littleHint, .profileBadge, .profileDialog, .settingsWindow, .settingsPane,
             .settingsField, .splitTool, .splitSegment, .splitDropPreview, .tabTool, .easelControl, .easelElement, .easelCard:
            return nil   // view-owned: reported by `actual` only
        }
    }
}
