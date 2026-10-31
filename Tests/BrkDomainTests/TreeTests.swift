import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

/// The hierarchy invariants `SidebarTree` keeps by construction. These run now: the tree is the contract every rule
/// writes through, so its guarantees are not waiting on W1.
final class TreeTests: XCTestCase {
    let t0 = Instant(milliseconds: 1_000)
    let space = SpaceID("s1")
    let pinned = ItemID("pinned"), today = ItemID("today"), favorites = ItemID("favorites")

    func makeTree() -> SidebarTree {
        var tree = SidebarTree(scope: .global)
        tree.makeRoot(favorites, .favorites(.default), createdAt: t0)
        tree.makeRoot(pinned, .pinned(space), createdAt: t0)
        tree.makeRoot(today, .today(space), createdAt: t0)
        return tree
    }

    func tab(_ path: String) -> Tab {
        Tab(url: URL(string: "https://example.com/\(path)"), title: path, lastActiveAt: t0)
    }

    // MARK: Pane membership

    func testSplitPanesHoldTwoToMaxDistinctIDs() {
        let ids = (0..<6).map { ItemID("p\($0)") }
        XCTAssertNil(SplitPanes([ids[0]]))
        XCTAssertNotNil(SplitPanes(Array(ids[0..<2])))
        XCTAssertNotNil(SplitPanes(Array(ids[0..<Metrics.content.maxPanes.value])))
        XCTAssertNil(SplitPanes(Array(ids[0...Metrics.content.maxPanes.value])))
        XCTAssertNil(SplitPanes([ids[0], ids[0]]))
        XCTAssertNil(SplitPanes(Array(ids[0..<2]))?.removing(ids[0]))
    }

    func testSplitInPlaceThenAddPaneUpToTheCap() throws {
        var tree = makeTree()
        try tree.insert(ItemID("a"), .tab(tab("a")), at: .into(parent: today, index: 0), createdAt: t0)
        try tree.splitInPlace(ItemID("a"), splitID: ItemID("sp"), newPane: ItemID("b"), tab("b"), createdAt: t0)
        XCTAssertEqual(tree[today]?.children, [ItemID("sp")])
        XCTAssertEqual(tree[ItemID("sp")]?.children, [ItemID("a"), ItemID("b")])
        XCTAssertEqual(tree[ItemID("a")]?.parent, ItemID("sp"))
        guard case .split(let split)? = tree[ItemID("sp")]?.body else { return XCTFail("no split") }
        XCTAssertEqual(split.orientation, .horizontal)

        try tree.addPane(to: ItemID("sp"), newPane: ItemID("c"), tab("c"), after: ItemID("a"), createdAt: t0)
        XCTAssertEqual(tree[ItemID("sp")]?.children, [ItemID("a"), ItemID("c"), ItemID("b")])
        try tree.addPane(to: ItemID("sp"), newPane: ItemID("d"), tab("d"), after: ItemID("b"), createdAt: t0)
        var thrown: TreeError?
        do { try tree.addPane(to: ItemID("sp"), newPane: ItemID("e"), tab("e"), after: ItemID("d"), createdAt: t0) } catch { thrown = error }
        XCTAssertEqual(thrown, .splitFull)
        XCTAssertEqual(tree[ItemID("sp")]?.children.count, Metrics.content.maxPanes.value)
    }

    /// Removing or moving a pane out of a two-pane split dissolves the split in the same mutation: the public
    /// state never shows a one-pane split.
    func testDissolveIsAtomicOnRemoveAndOnMove() throws {
        var tree = makeTree()
        try tree.insert(ItemID("x"), .tab(tab("x")), at: .into(parent: today, index: 0), createdAt: t0)
        try tree.insert(ItemID("a"), .tab(tab("a")), at: .into(parent: today, index: 1), createdAt: t0)
        try tree.splitInPlace(ItemID("a"), splitID: ItemID("sp"), newPane: ItemID("b"), tab("b"), createdAt: t0)
        XCTAssertEqual(tree[today]?.children, [ItemID("x"), ItemID("sp")])

        let removed = tree.removeSubtree(ItemID("b"))
        XCTAssertEqual(removed.tabs.map(\.0), [ItemID("b")])
        XCTAssertNil(tree[ItemID("sp")], "the split is gone")
        XCTAssertEqual(tree[today]?.children, [ItemID("x"), ItemID("a")], "the remaining pane took the split's place")
        XCTAssertEqual(tree[ItemID("a")]?.parent, today)

        try tree.splitInPlace(ItemID("a"), splitID: ItemID("sp2"), newPane: ItemID("c"), tab("c"), createdAt: t0)
        try tree.move(ItemID("c"), to: .into(parent: pinned, index: 0))
        XCTAssertNil(tree[ItemID("sp2")])
        XCTAssertEqual(tree[today]?.children, [ItemID("x"), ItemID("a")])
        XCTAssertEqual(tree[pinned]?.children, [ItemID("c")])
        for (id, item) in tree.items { XCTAssertEqual(item.id, id) }
    }

    // MARK: Kinds, roots, placement

    func testPayloadUpdatesPreserveKindAndIgnoreOtherKinds() throws {
        var tree = makeTree()
        try tree.insert(ItemID("a"), .tab(tab("a")), at: .into(parent: today, index: 0), createdAt: t0)
        tree.updateFolder(ItemID("a")) { $0.title = "nope" }
        tree.updateTab(favorites) { $0.title = "nope" }
        XCTAssertEqual(tree[ItemID("a")]?.kind, .tab)
        XCTAssertEqual(tree[favorites]?.kind, .section)
        XCTAssertNil(tree[favorites]?.parent)
        tree.updateTab(ItemID("a")) { $0.customTitle = "renamed" }
        guard case .tab(let tab)? = tree[ItemID("a")]?.body else { return XCTFail("kind changed") }
        XCTAssertEqual(tab.customTitle, "renamed")
    }

    func testRootsNeverMoveAndScopesAreEnforced() throws {
        var tree = makeTree()
        var thrown: TreeError?
        do { try tree.move(pinned, to: .into(parent: today, index: 0)) } catch { thrown = error }
        XCTAssertEqual(thrown, .invalidHierarchy)
        XCTAssertTrue(tree.removeSubtree(today).tabs.isEmpty)
        XCTAssertNotNil(tree[today])
        XCTAssertFalse(tree.makeRoot(ItemID("scratch"), .scratch(WindowID("w")), createdAt: t0), "a saved tree holds no scratch root")
        var scratch = SidebarTree(scope: .window(WindowID("w")))
        XCTAssertFalse(scratch.makeRoot(ItemID("p"), .pinned(space), createdAt: t0))
        XCTAssertTrue(scratch.makeRoot(ItemID("s"), .scratch(WindowID("w")), createdAt: t0))
    }

    func testPlacementIsTheOneRuleTable() throws {
        var tree = makeTree()
        let folder = ItemBody.folder(Folder(title: "F", collapsed: false))
        var thrown: TreeError?
        try tree.insert(ItemID("today-group"), folder, at: .into(parent: today, index: 0), createdAt: t0)
        XCTAssertEqual(tree[ItemID("today-group")]?.parent, today, "Today supports organized groups")
        thrown = nil
        do { try tree.insert(ItemID("f"), folder, at: .into(parent: favorites, index: 0), createdAt: t0) } catch { thrown = error }
        XCTAssertEqual(thrown, .forbiddenPlacement, "Favorites is flat")
        try tree.insert(ItemID("f"), folder, at: .into(parent: pinned, index: 0), createdAt: t0)
        try tree.insert(ItemID("g"), folder, at: .into(parent: ItemID("f"), index: 0), createdAt: t0)
        thrown = nil
        do { try tree.move(ItemID("f"), to: .into(parent: ItemID("g"), index: 0)) } catch { thrown = error }
        XCTAssertEqual(thrown, .wouldCreateCycle)

        try tree.insert(ItemID("a"), .tab(tab("a")), at: .into(parent: today, index: 0), createdAt: t0)
        try tree.splitInPlace(ItemID("a"), splitID: ItemID("sp"), newPane: ItemID("b"), tab("b"), createdAt: t0)
        try tree.insert(ItemID("c"), .tab(tab("c")), at: .into(parent: today, index: 0), createdAt: t0)
        thrown = nil
        do { try tree.move(ItemID("c"), to: .into(parent: ItemID("sp"), index: 0)) } catch { thrown = error }
        XCTAssertEqual(thrown, .forbiddenPlacement, "panes enter only through split rules")
        XCTAssertFalse(Placement.canPlace(.tab, inSection: .today, parentKind: .split))
        XCTAssertTrue(Placement.canPlace(.split, inSection: .pinned, parentKind: .folder))
        XCTAssertTrue(Placement.canPlace(.tab, inSection: .scratch, parentKind: .section))
        XCTAssertFalse(Placement.canPlace(.folder, inSection: .scratch, parentKind: .section))
    }

    func testMoveMaintainsPinnedURLAndCountsIndexAfterDetach() throws {
        var tree = makeTree()
        try tree.insert(ItemID("a"), .tab(tab("a")), at: .into(parent: today, index: 0), createdAt: t0)
        try tree.insert(ItemID("b"), .tab(tab("b")), at: .into(parent: today, index: 1), createdAt: t0)
        try tree.move(ItemID("a"), to: .into(parent: pinned, index: 0))
        guard case .tab(let pinnedA)? = tree[ItemID("a")]?.body else { return XCTFail() }
        XCTAssertEqual(pinnedA.pinnedURL, pinnedA.url)
        try tree.move(ItemID("a"), to: .into(parent: today, index: 1))
        guard case .tab(let todayA)? = tree[ItemID("a")]?.body else { return XCTFail() }
        XCTAssertNil(todayA.pinnedURL)
        XCTAssertEqual(tree[today]?.children, [ItemID("b"), ItemID("a")])
        try tree.move(ItemID("a"), to: .into(parent: today, index: 1))
        XCTAssertEqual(tree[today]?.children, [ItemID("b"), ItemID("a")], "the same move twice is a no-op")
        XCTAssertEqual(tree.role(of: ItemID("a")), .today(space))
        XCTAssertEqual(tree.sidebarOrder(today), [ItemID("b"), ItemID("a")])
    }
}
