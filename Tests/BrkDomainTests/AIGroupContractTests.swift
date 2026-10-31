import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

final class AIGroupContractTests: XCTestCase {
    private func grouped(pinned: Bool = false) throws -> (Driver, ItemID, [ItemID]) {
        let d = Driver()
        d.user(.settings(.max(.tidyTabs(true))))
        _ = d.open("https://example.com/reading")
        let children = d.todayIDs
        let transition = d.user(.assist(.organizeToday))
        let request = try XCTUnwrap(transition.effects.compactMap { if case .ai(let id, _, _) = $0 { id } else { nil } }.first)
        let ids = children.map { "\"\($0.rawValue)\"" }.joined(separator: ",")
        d.system(.aiResult(request, .text("[{\"folder\":\"Reading\",\"tabs\":[\(ids)]}]")))
        guard case .folder(let group)? = d.view.space.today.rows.first else { throw MissingGroup() }
        if pinned { d.user(.item(.move(group.id, to: .into(parent: d.view.space.pinned.root, index: 0)))) }
        return (d, group.id, children)
    }
    private struct MissingGroup: Error {}
    private func folder(_ d: Driver, _ id: ItemID, in window: WindowID? = nil) throws -> FolderRow {
        let view = window.map(d.view(of:)) ?? d.view
        return try XCTUnwrap((view.space.today.rows + view.space.pinned.rows).compactMap { row in
            if case .folder(let f) = row, f.id == id { return f }; return nil
        }.first)
    }

    func testSavedTodayGroupRestoresInPlaceWithOrderedChildrenAndMetadata() throws {
        let (d, group, children) = try grouped()
        let outside = d.open("https://example.com/outside")
        d.user(.item(.rename(children[1], title: "Kept title")))
        d.user(.item(.toggleFolder(group)))
        let saved = d.savedFile
        let r = Driver(file: saved)
        XCTAssertEqual(r.outcome, .restored(repairs: []))
        XCTAssertEqual(r.todayIDs, [outside, group])
        XCTAssertEqual(r.pinnedIDs, [])
        let restored = try folder(r, group)
        XCTAssertEqual(restored.children.map(\.id), children)
        XCTAssertEqual(restored.title, "Reading")
        XCTAssertTrue(restored.collapsed)
        XCTAssertEqual(r.row(children[1])?.title, "Kept title")
        XCTAssertEqual(children.compactMap { r.state.tab($0)?.url }, children.compactMap { d.state.tab($0)?.url })
        XCTAssertTrue(children.allSatisfy { r.state.doc.tree[$0]?.parent == group && r.state.role(of: $0)?.kind == .today })
        guard case .folder(let stored)? = r.state.doc.tree[group]?.body else { return XCTFail("folder payload lost") }
        XCTAssertTrue(stored.isGroup)
        XCTAssertEqual(r.savedFile, saved)
    }

    func testFrozenPreGroupV3FileRestoresUnchanged() throws {
        let path = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ai-state-v3-before-groups.json")
        let file = try Data(contentsOf: path)
        let r = Driver(file: file)
        XCTAssertEqual(r.outcome, .restored(repairs: []))
        XCTAssertEqual(r.todayIDs.count, 2)
        XCTAssertEqual(r.view.space.today.rows.compactMap { if case .tab(let t) = $0 { t.url } else { nil } },
                       [url("https://legacy.example/third"), url("https://legacy.example/second")])
        let legacy = try folder(r, XCTUnwrap(r.pinnedIDs.first))
        XCTAssertEqual(legacy.title, "Legacy Reading")
        XCTAssertTrue(legacy.collapsed)
        XCTAssertEqual(legacy.children.count, 1)
        XCTAssertEqual(r.row(legacy.children[0].id)?.url, url("https://legacy.example/start"))
        XCTAssertNil(r.state.doc.settings.max.features)
        XCTAssertNil(r.state.doc.settings.max.translationExclusions)
        XCTAssertEqual(r.savedFile, file, "legacy v3 state must not be relocated or rewritten by the hierarchy extension")
    }

    func testRenameCollapseAndDragBehaveLikePinnedFolders() throws {
        for pinned in [false, true] {
            let (d, group, children) = try grouped(pinned: pinned)
            let root = pinned ? d.view.space.pinned.root : d.view.space.today.root
            d.user(.window(.new))
            let other = try XCTUnwrap(d.snapshot.windows.keys.first { $0 != d.window })
            d.user(.item(.rename(group, title: "  Renamed  ")))
            XCTAssertEqual(try folder(d, group).title, "Renamed")
            XCTAssertEqual(try folder(d, group, in: other).title, "Renamed")
            d.user(.item(.toggleFolder(group)))
            XCTAssertTrue(try folder(d, group).collapsed)
            XCTAssertFalse(try folder(d, group, in: other).collapsed, "collapse belongs to its window in both sections")
            d.user(.item(.move(children[0], to: .into(parent: root, index: 0))))
            XCTAssertEqual(try folder(d, group).children.map(\.id), [children[1]])
            XCTAssertEqual(d.state.doc.tree[children[0]]?.parent, root)
            d.user(.item(.move(children[0], to: .into(parent: group, index: 0))))
            XCTAssertEqual(try folder(d, group).children.map(\.id), children)
            XCTAssertEqual(d.state.role(of: children[0])?.kind, pinned ? .pinned : .today)
        }
    }

    func testMovingBetweenTodayAndPinnedChangesPinnedHomeOnly() throws {
        let (d, group, children) = try grouped()
        let child = children[0], address = d.row(child)?.url
        XCTAssertNil(d.state.tab(child)?.pinnedURL)
        d.user(.item(.move(child, to: .into(parent: d.view.space.pinned.root, index: 0))))
        XCTAssertEqual(d.state.tab(child)?.pinnedURL, address)
        d.user(.item(.move(child, to: .into(parent: group, index: 0))))
        XCTAssertNil(d.state.tab(child)?.pinnedURL)
        XCTAssertEqual(d.row(child)?.url, address)
    }

    func testCommandWArchivesTodayChildButKeepsPinnedChild() throws {
        for pinned in [false, true] {
            let (d, group, children) = try grouped(pinned: pinned)
            let child = children[0]
            d.user(.tab(.focus(child)))
            d.user(ActionID.archiveTab.spec.command) // The single Cmd+W action table entry.
            XCTAssertNotNil(d.state.doc.tree[group])
            XCTAssertEqual(try folder(d, group).children.map(\.id), pinned ? children : [children[1]])
            XCTAssertEqual(d.state.doc.archive.map(\.tabID), pinned ? [] : [child])
            XCTAssertFalse(d.loadedIDs.contains(child))
            if !pinned {
                d.user(.archive(.restoreLast))
                XCTAssertNotNil(d.state.tab(child))
                XCTAssertEqual(d.state.doc.tree[child]?.parent, d.view.space.today.root, "individual-tab restore retains the existing top-of-Today behavior")
            }
        }
    }

    func testSweepProtectsVisibleGroupDescendantsThenUsesNewestActivity() throws {
        let (d, group, children) = try grouped()
        d.user(.settings(.autoArchive(.oneHour)))
        d.advance(.seconds(7200))
        d.system(.clockTick)
        XCTAssertNotNil(d.state.doc.tree[group], "an on-screen descendant protects the whole group")
        XCTAssertTrue(d.state.doc.archive.isEmpty)
        _ = d.open("https://example.com/outside") // Leaving the group stamps its newest child now.
        d.system(.clockTick)
        XCTAssertNotNil(d.state.doc.tree[group], "old siblings must not override the recent child")
        d.advance(hour)
        d.system(.clockTick)
        XCTAssertNil(d.state.doc.tree[group])
        let entry = try XCTUnwrap(d.state.doc.archive.first)
        XCTAssertEqual(entry.tabID, group)
        XCTAssertEqual(entry.reason, .auto)
        XCTAssertEqual(entry.structure?.tabs.map(\.0), children)
        d.user(.archive(.restore(entry.id)))
        XCTAssertEqual(try folder(d, group).children.map(\.id), children)
        XCTAssertEqual(d.state.role(of: group)?.kind, .today)
        let (p, pinned, _) = try grouped(pinned: true)
        p.advance(.seconds(86400)); p.system(.clockTick)
        XCTAssertNotNil(p.state.doc.tree[pinned], "Pinned is excluded from auto-archive")
    }

    func testClearTodayProtectsVisibleGroupAndRestoreKeepsTodayAfterSourceRemoval() throws {
        let (d, group, children) = try grouped()
        d.user(.tab(.clearToday))
        XCTAssertNotNil(d.state.doc.tree[group])
        _ = d.open("https://example.com/outside")
        d.user(.tab(.clearToday))
        let entry = try XCTUnwrap(d.state.doc.archive.first { $0.tabID == group })
        XCTAssertNil(d.state.doc.tree[group])
        let origin = d.view.space.id
        _ = d.newSpace("Destination")
        d.user(.space(.delete(origin)))
        d.user(.archive(.restore(entry.id)))
        XCTAssertEqual(d.state.role(of: group)?.kind, .today)
        XCTAssertEqual(try folder(d, group).children.map(\.id), children)
    }
}
