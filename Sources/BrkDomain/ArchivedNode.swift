import BrkBase
import Foundation

/// A detached value tree. It contains no live page, browser, context or window identity.
indirect enum ArchivedNode: Equatable, Sendable, Codable {
    case tab(ItemID, Tab)
    case folder(ItemID, title: String, icon: CustomIcon?, group: Bool, repository: String?, children: [ArchivedNode])
    case split(ItemID, title: String?, icon: CustomIcon?, orientation: SplitOrientation, fractions: [Double], children: [ArchivedNode])

    var id: ItemID {
        switch self { case .tab(let id, _), .folder(let id, _, _, _, _, _), .split(let id, _, _, _, _, _): id }
    }
    var allIDs: [ItemID] {
        switch self {
        case .tab(let id, _): [id]
        case .folder(let id, _, _, _, _, let children), .split(let id, _, _, _, _, let children): [id] + children.flatMap(\.allIDs)
        }
    }
    var tabs: [(ItemID, Tab)] {
        switch self {
        case .tab(let id, let tab): [(id, tab)]
        case .folder(_, _, _, _, _, let children), .split(_, _, _, _, _, let children): children.flatMap(\.tabs)
        }
    }
    var title: String {
        switch self {
        case .tab(_, let tab): tab.displayTitle
        case .folder(_, let title, _, _, _, _): title
        case .split(_, let title, _, _, _, let children): title ?? children.map(\.title).joined(separator: " / ")
        }
    }
    /// Restored files are external input. Reject excessive depth, duplicate IDs and unsafe URLs as a unit.
    func isValid(depth: Int = 0) -> Bool {
        guard depth < 32 else { return false }
        if depth == 0 { let ids = allIDs; guard ids.count <= 5_000, Set(ids).count == ids.count else { return false } }
        switch self {
        case .tab(_, let tab):
            // Brk's own pages (History, Easels, kept AI pages) keep their brk:// address, as a saved tab may (StateCodec).
            func opens(_ url: URL) -> Bool { isOpenableURL(url) || NativePages.shows(url) }
            return (tab.url.map(opens) ?? true) && (tab.pinnedURL.map(opens) ?? true)
        case .folder(_, _, _, _, _, let children):
            return children.count <= 1_000 && children.allSatisfy { $0.isValid(depth: depth + 1) }
        case .split(_, _, _, _, let fractions, let children):
            return (2...Metrics.content.maxPanes.value).contains(children.count)
                && children.allSatisfy { if case .tab = $0 { return $0.isValid(depth: depth + 1) }; return false }
                && fractions.count == children.count && fractions.allSatisfy { $0.isFinite && $0 > 0 }
        }
    }
}

extension AppState {
    func detached(_ id: ItemID, in window: WindowID?) -> ArchivedNode? {
        guard let scope = locate(id), let tree = tree(scope), let item = tree[id] else { return nil }
        switch item.body {
        case .tab(let original):
            var tab = original
            if let window, owns(PageID(window: window, item: id)) { tab = displayedTab(id, in: window, for: .savedDocument) ?? tab }
            else { tab.url = address(of: id, in: nil, for: .savedDocument) }
            return .tab(id, tab)
        case .folder(let f):
            return .folder(id, title: f.title, icon: f.icon, group: f.isGroup, repository: f.liveRepository, children: item.children.compactMap { detached($0, in: window) })
        case .split(let s):
            return .split(id, title: s.title, icon: s.icon, orientation: s.orientation,
                          fractions: clampFractions(s.panes.ids.map { s.widths[$0] ?? 1 }), children: item.children.compactMap { detached($0, in: window) })
        case .section: return nil
        }
    }
}
