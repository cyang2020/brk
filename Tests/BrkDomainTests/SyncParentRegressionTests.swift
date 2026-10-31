import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

final class SyncParentRegressionTests: XCTestCase {
    func testSidebarEntryPointsCaptureTheirOwnerAndSyncRequiresConnection() throws {
        let d = Driver(startURL: nil)
        XCTAssertEqual(d.user(.sidebarData(.welcome)).effects, [.sidebarData(.panel(d.window, .welcome))])
        XCTAssertEqual(d.user(.sidebarData(.tour)).effects, [.sidebarData(.tour(d.window))])
        XCTAssertEqual(d.user(.sidebarData(.importFile)).effects, [.sidebarData(.panel(d.window, .importFile))])
        XCTAssertEqual(d.user(.sidebarData(.syncSettings)).effects, [.sidebarData(.panel(d.window, .syncSettings))])
        XCTAssertTrue(d.user(.sidebarData(.syncNow)).effects.isEmpty)
        d.system(.sidebarData(.connected(d.window, folder: "/tmp/owned-sync-entry-points")))
        let connected = try XCTUnwrap(d.state.doc.sidebarData.sync)
        XCTAssertEqual(d.user(.sidebarData(.syncNow)).effects, [
            .sidebarData(.exchange(epoch: connected.epoch, folder: "/tmp/owned-sync-entry-points",
                                   replica: connected.replica, revision: connected.counter, connected.document)),
        ])
        d.user(.sidebarData(.disconnect))
        XCTAssertTrue(d.user(.sidebarData(.syncNow)).effects.isEmpty)
    }
    func testInvalidFolderPlacementRecoversInMappedProfile() throws {
        let d = Driver(startURL: nil)
        d.user(.profile(.create(name: "Mapped", icon: nil)))
        let mapped = try XCTUnwrap(d.state.doc.profiles.keys.first { $0 != .default })
        d.newSpace("Mapped space")
        d.user(.profile(.assign(.current, to: mapped)))
        d.system(.sidebarData(.connected(d.window, folder: "/tmp/owned-unused-placement-probe")))
        let local = try XCTUnwrap(d.state.doc.sidebarData.sync)
        var peer = local.document
        peer.records["i-peer-folder"] = SidebarSyncRecord(stamp: SidebarSyncStamp(counter: local.counter + 1, replica: "peer"), value: SidebarSyncValue(payload: .folder(title: "Peer folder", icon: nil), parent: "favorites", order: 0))
        peer.records["i-peer-tab"] = SidebarSyncRecord(stamp: SidebarSyncStamp(counter: local.counter + 2, replica: "peer"), value: SidebarSyncValue(payload: .tab(title: "Peer tab", url: url("https://example.test/owned-peer"), icon: nil), parent: "i-peer-folder", order: 0))
        XCTAssertNoThrow(try SidebarDataCodec.encodeSync(peer))
        d.system(.sidebarData(.syncRead(epoch: local.epoch, peer)))
        XCTAssertEqual(d.state.browsingContext(of: ItemID("peer-tab")), .profile(mapped))
        print("CONTROL invalid folder-under-Favorites stays in mapped profile; cross-profile suspicion disproved")
    }

    func testRejectsPeerRootReplacementAndKeepsExcludedLocalTab() throws {
        let d = Driver(startURL: nil)
        d.user(.profile(.create(name: "Mapped", icon: nil)))
        let mapped = try XCTUnwrap(d.state.doc.profiles.keys.first { $0 != .default })
        d.newSpace("Mapped space")
        d.user(.profile(.assign(.current, to: mapped)))
        let tab = d.open("https://example.test/?owned=local-only")
        d.user(.tab(.togglePin(.item(tab))))
        let pinned = d.view.space.pinned.root
        d.system(.sidebarData(.connected(d.window, folder: "/tmp/owned-unused-root-probe")))
        let local = try XCTUnwrap(d.state.doc.sidebarData.sync)
        var peer = local.document
        peer.records["i-" + pinned.rawValue] = SidebarSyncRecord(stamp: SidebarSyncStamp(counter: local.counter + 1, replica: "peer"), value: SidebarSyncValue(payload: .tab(title: "Replacement", url: url("https://example.test/replacement"), icon: nil), parent: "favorites", order: 0))
        XCTAssertNoThrow(try SidebarDataCodec.encodeSync(peer))
        d.system(.sidebarData(.syncRead(epoch: local.epoch, peer)))
        XCTAssertEqual(d.state.doc.tree[pinned]?.kind, .section)
        XCTAssertEqual(d.state.browsingContext(of: tab), .profile(mapped))
        XCTAssertEqual(d.state.doc.tree[tab]?.parent, pinned)
        XCTAssertEqual(d.state.doc.spaces[d.view.space.id]?.pinnedRoot, pinned)
    }

    func testLocalHostSpellingsStayLocal() throws {
        let d = Driver(startURL: nil)
        let addresses = ["http://localhost./owned-local-path", "http://printer.local./owned-local-path", "http://2130706433/owned-local-path", "http://0x7f000001/owned-local-path"]
        let target = try XCTUnwrap(d.state.sidebarImportTarget(in: d.window))
        let preview = SidebarImportPreview(entries: addresses.map { .link(title: "Owned fixture", url: URL(string: $0)!) })
        d.system(.sidebarData(.imported(d.window, target: target, preview, favorites: false)))
        d.system(.sidebarData(.connected(d.window, folder: "/tmp/owned-unused-host-probe")))
        let document = try XCTUnwrap(d.state.doc.sidebarData.sync?.document)
        let text = String(decoding: try SidebarDataCodec.encodeSync(document), as: UTF8.self)
        for address in addresses { XCTAssertFalse(text.contains(address)) }
        XCTAssertEqual(d.snapshot.sidebarData.excluded, addresses.count)
    }

    func testClockExhaustionKeepsValidOutboxAndFreshFolderRecovers() throws {
        let d = Driver(startURL: nil)
        d.system(.sidebarData(.connected(d.window, folder: "/tmp/owned-unused-clock-probe")))
        let local = try XCTUnwrap(d.state.doc.sidebarData.sync)
        let key = "s-" + d.view.space.id.rawValue
        var incoming = local.document
        incoming.records[key]?.stamp = SidebarSyncStamp(counter: UInt64.max - 10_001, replica: "peer")
        incoming.records[key]?.value?.payload = .space(title: "Peer", icon: .none, theme: .default)
        XCTAssertNoThrow(try SidebarDataCodec.encodeSync(incoming))
        d.system(.sidebarData(.syncRead(epoch: local.epoch, incoming)))
        d.user(.item(.newFolder))
        let after = try XCTUnwrap(d.state.doc.sidebarData.sync)
        XCTAssertEqual(after.counter, UInt64.max - 10_001)
        XCTAssertNoThrow(try SidebarDataCodec.encodeSync(after.document))
        XCTAssertEqual(after.document, incoming)
        XCTAssertTrue(d.snapshot.sidebarData.status.contains("exhausted"))
        d.user(.sidebarData(.disconnect))
        d.system(.sidebarData(.connected(d.window, folder: "/tmp/owned-unused-clock-reconnect")))
        let recovered = try XCTUnwrap(d.state.doc.sidebarData.sync)
        XCTAssertNoThrow(try SidebarDataCodec.encodeSync(recovered.document))
        XCTAssertNotEqual(recovered.replica, local.replica)
        XCTAssertLessThan(recovered.counter, 100)
        XCTAssertTrue(Driver(file: d.savedFile, startURL: nil).snapshot.sidebarData.connected)
    }

    func testRejectsPeerCollisionWithUnenrolledTodayTab() throws {
        let d = Driver()
        let today = try XCTUnwrap(d.todayIDs.first)
        d.system(.sidebarData(.connected(d.window, folder: "/tmp/owned-unused-today-probe")))
        let local = try XCTUnwrap(d.state.doc.sidebarData.sync)
        XCTAssertNil(local.document.records["i-" + today.rawValue])
        var peer = local.document
        peer.records["i-" + today.rawValue] = SidebarSyncRecord(stamp: SidebarSyncStamp(counter: local.counter + 1, replica: "peer"), value: SidebarSyncValue(payload: .tab(title: "Peer replacement", url: url("https://example.test/replaced"), icon: nil), parent: "favorites", order: 0))
        XCTAssertNoThrow(try SidebarDataCodec.encodeSync(peer))
        d.system(.sidebarData(.syncRead(epoch: local.epoch, peer)))
        XCTAssertTrue(d.todayIDs.contains(today))
        XCTAssertFalse(d.favoriteIDs.contains(today))
        XCTAssertNotEqual(d.state.tab(today)?.customTitle, "Peer replacement")
        XCTAssertEqual(d.state.doc.sidebarData.sync?.document, local.document)
    }

    func testRejectsOversizedMergeAfterConcurrentLocalEdit() throws {
        let d = Driver(startURL: nil)
        d.system(.sidebarData(.connected(d.window, folder: "/tmp/owned-unused-limit-probe")))
        let local = try XCTUnwrap(d.state.doc.sidebarData.sync)
        let peer = SidebarSyncDocument(records: Dictionary(uniqueKeysWithValues: (0..<(10_000 - local.document.records.count)).map { ("i-peer-\($0)", SidebarSyncRecord(stamp: SidebarSyncStamp(counter: 1, replica: "peer"), value: nil)) }))
        // The real IO actor merges the captured outbound document with its peer files. A user edit can
        // happen while AppStore awaits that actor, before the valid transport result reaches the reducer.
        let received = try SidebarSync.merge(local.document, peer)
        XCTAssertEqual(received.records.count, 10_000)
        XCTAssertNoThrow(try SidebarDataCodec.encodeSync(received))
        d.user(.item(.newFolder))
        d.system(.sidebarData(.syncRead(epoch: local.epoch, received)))
        let after = try XCTUnwrap(d.state.doc.sidebarData.sync)
        XCTAssertLessThanOrEqual(after.document.records.count, 10_000)
        XCTAssertNoThrow(try SidebarDataCodec.encodeSync(after.document))
        XCTAssertNotNil(d.pinnedIDs.first)
        XCTAssertTrue(d.snapshot.sidebarData.status.contains("Sync failed"))
        let restored = Driver(file: d.savedFile, startURL: nil)
        XCTAssertTrue(restored.snapshot.sidebarData.connected)
    }
    func testBrowserAddressSpellingsAndPublicControls() throws {
        let local = ["localhost.", "sub.localhost.", "printer.local.", "service.internal.", "printer", "127.1", "0177.0.0.1", "0x7f.1", "2130706433", "0x7f000001", "10.1", "0x0a000001", "0300.0250.1.1", "192.168.1.1.", "172.31.65535", "169.254.1", "100.64.1.1", "0", "4294967296", "127.0.0.1..", "[::1]", "%31%32%37.0.0.1"]
        for host in local { XCTAssertFalse(SidebarSync.safeURL(try XCTUnwrap(URL(string: "http://" + host + "/owned"))), host) }
        for host in ["example.com", "example.com.", "8.8.8.8", "134744072", "0x08080808", "193.1.2.3", "172.32.0.1"] {
            XCTAssertTrue(SidebarSync.safeURL(try XCTUnwrap(URL(string: "https://" + host + "/public"))), host)
        }
    }

    func testOutgoingCapacityKeepsLastValidMetadataAndLocalEdit() throws {
        let d = Driver(startURL: nil)
        d.system(.sidebarData(.connected(d.window, folder: "/tmp/owned-outgoing-limit")))
        let local = try XCTUnwrap(d.state.doc.sidebarData.sync)
        let remote = SidebarSyncDocument(records: Dictionary(uniqueKeysWithValues: (0..<(10_000 - local.document.records.count)).map {
            ("i-peer-\($0)", SidebarSyncRecord(stamp: SidebarSyncStamp(counter: 1, replica: "peer"), value: nil))
        }))
        d.system(.sidebarData(.syncRead(epoch: local.epoch, try SidebarSync.merge(local.document, remote))))
        let accepted = try XCTUnwrap(d.state.doc.sidebarData.sync)
        XCTAssertEqual(accepted.document.records.count, 10_000)
        d.user(.item(.newFolder))
        XCTAssertNotNil(d.pinnedIDs.first)
        XCTAssertEqual(d.state.doc.sidebarData.sync, accepted)
        XCTAssertNoThrow(try SidebarDataCodec.encodeSync(XCTUnwrap(d.state.doc.sidebarData.sync).document))
        XCTAssertTrue(d.snapshot.sidebarData.status.contains("Local edits were kept"))
        XCTAssertTrue(Driver(file: d.savedFile, startURL: nil).snapshot.sidebarData.connected)
    }

    func testEnrolledFolderKindCannotChange() throws {
        let d = Driver(startURL: nil)
        d.user(.item(.newFolder))
        let folder = try XCTUnwrap(d.pinnedIDs.first)
        d.system(.sidebarData(.connected(d.window, folder: "/tmp/owned-enrolled-kind")))
        let local = try XCTUnwrap(d.state.doc.sidebarData.sync)
        let key = "i-" + folder.rawValue
        var peer = local.document
        peer.records[key]?.stamp = SidebarSyncStamp(counter: local.counter + 1, replica: "peer")
        peer.records[key]?.value?.payload = .tab(title: "Changed", url: url("https://example.test/"), icon: nil)
        d.system(.sidebarData(.syncRead(epoch: local.epoch, peer)))
        XCTAssertEqual(d.state.doc.tree[folder]?.kind, .folder)
        XCTAssertEqual(d.state.doc.sidebarData.sync?.document, local.document)
    }

}
