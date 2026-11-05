import BrkBase

/// Edges are in content coordinates. Left/right lay panes side by side; top/bottom stack them.
public enum SplitEdge: String, Hashable, Sendable, Codable, CaseIterable {
    case left, right, top, bottom

    public var orientation: SplitOrientation {
        switch self { case .left, .right: .horizontal; case .top, .bottom: .vertical }
    }

    public var isLeading: Bool { self == .left || self == .top }
}

/// Read-only input for local pointer hit testing. The reducer repeats admission checks on release.
public struct SplitDropSnapshot: Sendable, Equatable, Codable {
    public var target: ItemID
    public var offers: [ItemID: SplitDropOffer]
    public var sources: Set<ItemID> { Set(offers.keys) }
}

public struct SplitDropOffer: Hashable, Sendable, Codable {
    public let window: WindowID
    public let source: ItemID
    public let target: ItemID
    let sourceParent: ItemID
    let targetParent: ItemID
    let panes: [ItemID]
    let orientation: SplitOrientation
    let context: BrowsingContext
}

extension AppState {
    func canUseSplit(_ split: ItemID, in window: WindowID) -> Bool {
        units(in: window).contains(split) && tree(of: window)?[split]?.kind == .split
    }

    func presentedPanes(in window: WindowID) -> [ItemID] {
        guard let shown = shownItem(in: window) else { return [] }
        if session.windows[window]?.expandedSplit == shown { return focusedPane(in: window).map { [$0] } ?? [] }
        return panes(of: shown)
    }

    func splitDrop(in window: WindowID) -> SplitDropSnapshot? {
        guard doc.windows[window]?.kind != .little, session.windows[window]?.overlay == nil,
              session.windows[window]?.find == nil,
              session.windows[window]?.dialog == nil, session.windows[window]?.profileDialog == nil,
              session.windows[window]?.expandedSplit == nil,
              let target = shownItem(in: window), let role = role(of: target), role.kind != .favorites,
              panes(of: target).count < Metrics.content.maxPanes.value else { return nil }
        guard let tree = tree(of: window) else { return nil }
        // A Favorite dragged over the page offers the same slots (Arc, Q13-e); the drop moves it out first.
        let sources = Set(tree.allTabs().filter { tab in
            tab != target && tree.splitContaining(tab) == nil && (self.role(of: tab)?.joinsSplit(in: role) == true || self.role(of: tab)?.kind == .favorites)
        })
        guard let parent = tree[target]?.parent else { return nil }
        let orientation: SplitOrientation = if case .split(let split)? = tree[target]?.body { split.orientation } else { .horizontal }
        return SplitDropSnapshot(target: target, offers: Dictionary(uniqueKeysWithValues: sources.compactMap { source in
            tree[source]?.parent.map { (source, SplitDropOffer(window: window, source: source, target: target,
                sourceParent: $0, targetParent: parent, panes: panes(of: target), orientation: orientation,
                context: browsingContext(of: source))) }
        }))
    }
}
