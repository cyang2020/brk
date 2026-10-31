import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

final class ImportSyncTests: XCTestCase {
    func testUnpinningCreatesSharedTombstoneButIncomingMergeKeepsLocalTodayAndWindowAddress() throws {
        let d = Driver()
        let tab = d.open("https://example.test/unpin"); d.user(.tab(.togglePin(.item(tab))))
        d.system(.sidebarData(.connected(d.window, folder: "/tmp/owned-unpin")))
        let old = try XCTUnwrap(d.state.doc.sidebarData.sync)
        d.user(.tab(.togglePin(.item(tab))))
        let window = d.state.doc.windows[d.window], today = d.todayIDs
        var peer = old.document
        peer.records["peer-folder"] = SidebarSyncRecord(stamp: SidebarSyncStamp(counter: old.counter + 5, replica: "peer"),
            value: SidebarSyncValue(payload: .folder(title: "Peer folder", icon: nil), parent: "i-" + d.view.space.pinned.root.rawValue, order: 0))
        d.system(.sidebarData(.syncRead(epoch: old.epoch, peer)))
        XCTAssertEqual(d.todayIDs, today)
        XCTAssertNotNil(d.state.doc.tree[tab])
        XCTAssertEqual(d.state.doc.windows[d.window], window)
        XCTAssertNil(d.state.doc.sidebarData.sync?.document.records["i-" + tab.rawValue]?.value)
    }
    func testSyncLeavesAnotherLocalProfileAndItsSidebarUntouched() throws {
        let d = Driver(), home = d.view.space.id
        d.user(.profile(.create(name: "Device only", icon: nil)))
        let profile = try XCTUnwrap(d.state.doc.profiles.keys.first { $0 != .default })
        d.newSpace("Local profile Space"); d.user(.profile(.assign(.current, to: profile)))
        let foreign = d.open("https://example.test/local-only"); d.user(.tab(.togglePin(.item(foreign))))
        d.user(.settings(.profile(profile, .downloadsDirectory("/tmp/device-only-setting"))))
        d.user(.space(.focus(home)))
        d.system(.sidebarData(.connected(d.window, folder: "/tmp/owned-profile-test")))
        let local = try XCTUnwrap(d.state.doc.sidebarData.sync)
        var peer = local.document
        peer.records["s-" + home.rawValue]?.value?.payload = .space(title: "Remote rename", icon: .none, theme: .default)
        peer.records["s-" + home.rawValue]?.stamp = SidebarSyncStamp(counter: local.counter + 1, replica: "peer")
        let before = d.state.doc.tree[foreign], settings = d.state.doc.settings.profiles[profile], profiles = d.state.doc.profiles
        d.system(.sidebarData(.syncRead(epoch: local.epoch, peer)))
        XCTAssertEqual(d.state.doc.tree[foreign], before)
        XCTAssertEqual(d.state.doc.settings.profiles[profile], settings)
        XCTAssertEqual(d.state.doc.profiles, profiles)
        XCTAssertEqual(d.view.space.title, "Remote rename")
        XCTAssertFalse(String(decoding: try SidebarDataCodec.encodeSync(local.document), as: UTF8.self).contains("local-only"))
    }

    func testInvalidSavedSyncMetadataDisconnectsWithoutDiscardingSidebar() throws {
        let d = Driver()
        let tab = d.open("https://example.test/keep"); d.user(.tab(.togglePin(.item(tab))))
        d.system(.sidebarData(.connected(d.window, folder: "/tmp/owned-invalid")))
        var envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: d.savedFile) as? [String: Any])
        var doc = try XCTUnwrap(envelope["doc"] as? [String: Any]), data = try XCTUnwrap(doc["sidebarData"] as? [String: Any])
        var sync = try XCTUnwrap(data["sync"] as? [String: Any]); sync["replica"] = "../unsafe"
        data["sync"] = sync; doc["sidebarData"] = data; envelope["doc"] = doc
        let restored = Driver(file: try JSONSerialization.data(withJSONObject: envelope))
        XCTAssertFalse(restored.snapshot.sidebarData.connected)
        XCTAssertNotNil(restored.state.doc.tree[tab])
        guard case .restored(let repairs) = restored.outcome else { return XCTFail("Discarded entire file") }
        XCTAssertTrue(repairs.contains { $0.contains("Disconnected invalid sidebar") })
    }

    func testOptionalDefaultBrowserChoiceOnlyEmitsAnExplicitRequest() {
        let empty = Driver(startURL: nil)
        let noRequest = empty.user(.sidebarData(.completeOnboarding(OnboardingChoices(starterTabs: false, favorites: false, tour: false))))
        XCTAssertFalse(noRequest.effects.contains(.app(.registerAsDefaultBrowser)))
        let optedIn = Driver(startURL: nil)
        let request = optedIn.user(.sidebarData(.completeOnboarding(OnboardingChoices(starterTabs: false, favorites: false, tour: false, defaultBrowser: true))))
        XCTAssertEqual(request.effects, [.app(.registerAsDefaultBrowser)])
    }
    func testTwoReducerReplicasConvergeAndRepairConcurrentMoveCycleWithoutUsingToday() throws {
        let a = Driver(), b = Driver()
        a.user(.item(.newFolder)); let first = try XCTUnwrap(a.pinnedIDs.first)
        a.user(.item(.rename(first, title: "First")))
        a.user(.item(.newFolder)); let second = try XCTUnwrap(a.pinnedIDs.first)
        a.user(.item(.rename(second, title: "Second")))
        a.system(.sidebarData(.connected(a.window, folder: "/tmp/owned-pair")))
        b.system(.sidebarData(.connected(b.window, folder: "/tmp/owned-pair")))
        let left = try XCTUnwrap(a.state.doc.sidebarData.sync), right = try XCTUnwrap(b.state.doc.sidebarData.sync)
        let merged = try SidebarSync.merge(left.document, right.document)
        a.system(.sidebarData(.syncRead(epoch: left.epoch, merged)))
        b.system(.sidebarData(.syncRead(epoch: right.epoch, merged)))
        XCTAssertEqual(a.state.doc.sidebarData.sync?.document, b.state.doc.sidebarData.sync?.document)
        let windowsA = a.state.doc.windows, windowsB = b.state.doc.windows
        var cycle = merged
        let f = "i-" + first.rawValue, s = "i-" + second.rawValue
        cycle.records[f]?.value?.parent = s
        cycle.records[f]?.stamp = SidebarSyncStamp(counter: 100, replica: "move-a")
        cycle.records[s]?.value?.parent = f
        cycle.records[s]?.stamp = SidebarSyncStamp(counter: 100, replica: "move-b")
        a.system(.sidebarData(.syncRead(epoch: left.epoch, cycle)))
        b.system(.sidebarData(.syncRead(epoch: right.epoch, cycle)))
        XCTAssertEqual(a.state.doc.tree[first]?.parent, b.state.doc.tree[first]?.parent)
        XCTAssertEqual(a.state.doc.tree[second]?.parent, b.state.doc.tree[second]?.parent)
        XCTAssertEqual(a.state.doc.tree.role(of: first)?.kind, .pinned)
        XCTAssertEqual(b.state.doc.tree.role(of: first)?.kind, .pinned)
        XCTAssertEqual(a.state.doc.windows, windowsA); XCTAssertEqual(b.state.doc.windows, windowsB)
        XCTAssertEqual(a.state.doc.sidebarData.sync?.document, b.state.doc.sidebarData.sync?.document)
    }

    func testArchiveRestoreKeepsTombstoneAndReenrollsWithNewSharedIdentity() throws {
        let d = Driver()
        let tab = d.open("https://example.test/restore"); d.user(.tab(.togglePin(.item(tab))))
        d.system(.sidebarData(.connected(d.window, folder: "/tmp/owned-restore")))
        let oldKey = "i-" + tab.rawValue
        d.user(.tab(.archive(.item(tab))))
        XCTAssertNil(d.state.doc.sidebarData.sync?.document.records[oldKey]?.value)
        d.user(.archive(.restoreLast))
        let sync = try XCTUnwrap(d.state.doc.sidebarData.sync)
        XCTAssertNil(sync.document.records[oldKey]?.value)
        let alias = try XCTUnwrap(sync.aliases[oldKey])
        XCTAssertNotEqual(alias, oldKey)
        XCTAssertNotNil(sync.document.records[alias]?.value)
        let restored = Driver(file: d.savedFile)
        XCTAssertEqual(restored.state.doc.sidebarData.sync?.aliases, sync.aliases)
    }
    func testOnboardingSeedsOnceAndExistingV3DefaultsToCompleted() throws {
        let fresh = Driver(startURL: nil)
        XCTAssertTrue(fresh.snapshot.sidebarData.needsOnboarding)
        let choices = OnboardingChoices(spaceName: "Study", tour: false)
        fresh.user(.sidebarData(.completeOnboarding(choices)))
        XCTAssertEqual(fresh.view.space.title, "Study")
        XCTAssertEqual(fresh.allTabRows.count, 3)
        XCTAssertEqual(fresh.favoriteIDs.count, 1)
        let saved = fresh.savedFile
        fresh.user(.sidebarData(.completeOnboarding(choices)))
        XCTAssertEqual(fresh.savedFile, saved)
        let restored = Driver(file: saved, startURL: nil)
        XCTAssertFalse(restored.snapshot.sidebarData.needsOnboarding)
        XCTAssertEqual(restored.allTabRows.count, 3)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: saved) as? [String: Any])
        var doc = try XCTUnwrap(object["doc"] as? [String: Any]); doc.removeValue(forKey: "sidebarData"); object["doc"] = doc
        let old = Driver(file: try JSONSerialization.data(withJSONObject: object), startURL: nil)
        XCTAssertFalse(old.snapshot.sidebarData.needsOnboarding)
        XCTAssertEqual(StateCodec.currentVersion, 3)
    }

    func testStartEmptyAndPrivateCommandsDoNotSeedOrRequestPanels() throws {
        let d = Driver(startURL: nil)
        d.user(.sidebarData(.completeOnboarding(OnboardingChoices(starterTabs: false, favorites: false, tour: false))))
        XCTAssertEqual(d.allTabRows.count, 0)
        d.user(.window(.newIncognito))
        let privateID = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .incognito }?.id)
        XCTAssertTrue(d.user(.sidebarData(.importFile), in: privateID).effects.isEmpty)
        XCTAssertTrue(d.user(.sidebarData(.syncSettings), in: privateID).effects.isEmpty)
    }

    func testHTMLAndJSONRoundTripFoldersAndRejectExecutableLinks() throws {
        let document = ExportDocument(title: "Reading", entries: [.folder(title: "Swift & Co", children: [
            .link(title: "Docs <A>", url: url("https://example.test/docs?a=1&b=2")),
            .link(title: "Unsafe", url: url("javascript:alert(1)"))])])
        for format in [ExportFormat.html, .json] {
            let parsed = try SidebarImport.parse(ExportCodec.encode(document, as: format), format: format == .html ? .bookmarksHTML : .bookmarksJSON)
            XCTAssertEqual(parsed.preview.bookmarkCount, 1)
            XCTAssertEqual(parsed.preview.rejected, 1)
            XCTAssertEqual(parsed.preview.entries, [.folder(title: "Swift & Co", children: [.link(title: "Docs <A>", url: url("https://example.test/docs?a=1&b=2"))])])
            XCTAssertTrue(parsed.passwords.isEmpty)
        }
        let chromium = Data(#"{"roots":{"bookmark_bar":{"name":"Bar","children":[{"name":"One","url":"https://example.test/one"}]}}}"#.utf8)
        XCTAssertEqual(try SidebarImport.parse(chromium, format: .bookmarksJSON).preview.bookmarkCount, 1)
        XCTAssertThrowsError(try SidebarImport.parse(Data("{}".utf8), format: .bookmarksJSON))
    }

    func testPasswordCSVEscapesStayOutOfPreviewAndMalformedSourceIsRejected() throws {
        let csv = "name,url,username,password\r\nSite,https://example.test/,alice,\"s,e\"\"cret\"\r\nBad,javascript:alert(1),bob,pw\r\n"
        let parsed = try SidebarImport.parse(Data(csv.utf8), format: .passwordsCSV)
        XCTAssertEqual(parsed.passwords.count, 1)
        XCTAssertEqual(parsed.passwords[0].password, "s,e\"cret")
        XCTAssertEqual(parsed.preview.passwords, 1)
        XCTAssertEqual(parsed.preview.rejected, 1)
        let encoded = String(decoding: try JSONEncoder().encode(parsed.preview), as: UTF8.self)
        XCTAssertFalse(encoded.contains("alice")); XCTAssertFalse(encoded.contains("cret"))
        XCTAssertThrowsError(try SidebarImport.parse(Data("url,username,password\nhttps://example.test/,a,\"unfinished".utf8), format: .passwordsCSV))
    }

    func testImportDeduplicatesAndStaleDestinationCannotApply() throws {
        let d = Driver()
        let target = try XCTUnwrap(d.state.sidebarImportTarget(in: d.window))
        let preview = SidebarImportPreview(entries: [.folder(title: "Imported", children: [.link(title: "One", url: url("https://example.test/"))])],
            visits: [ImportedVisit(url: url("https://example.test/"), title: "One", visitedAt: T0)])
        d.system(.sidebarData(.imported(d.window, target: target, preview, favorites: false)))
        let file = d.savedFile
        XCTAssertEqual(d.pinnedIDs.count, 1)
        XCTAssertEqual(d.state.doc.history.filter { $0.url == url("https://example.test/") }.count, 1)
        d.system(.sidebarData(.imported(d.window, target: target, preview, favorites: false)))
        XCTAssertEqual(d.savedFile, file)
        XCTAssertTrue(d.snapshot.sidebarData.status.contains("0 bookmarks"))
        d.newSpace("Changed")
        let before = d.savedFile
        d.system(.sidebarData(.imported(d.window, target: target, preview, favorites: false)))
        XCTAssertEqual(d.savedFile, before)
    }

    func testHistoryTakeoutFormatAndValidation() throws {
        let data = Data(#"{"Browser History":[{"url":"https://example.test/","title":"Owned visit","time_usec":1790000000000000},{"url":"file:///private/profile","time_usec":1790000000000000}]}"#.utf8)
        let source = try SidebarImport.parse(data, format: .historyJSON)
        XCTAssertEqual(source.preview.visits.count, 1)
        XCTAssertEqual(source.preview.visits.first?.visitedAt, T0)
        XCTAssertEqual(source.preview.rejected, 1)
    }

    func testSyncMergeLawsAndDeleteDefeatsConcurrentMoveEditAndStaleDevice() throws {
        func record(_ replica: String, _ n: UInt64, _ title: String, _ parent: String) -> SidebarSyncRecord {
            SidebarSyncRecord(stamp: SidebarSyncStamp(counter: n, replica: replica), value: SidebarSyncValue(payload: .tab(title: title, url: url("https://example.test/"), icon: nil), parent: parent, order: 0))
        }
        let a = SidebarSyncDocument(records: ["i-tab": record("a", 2, "Renamed", "i-folder")])
        let b = SidebarSyncDocument(records: ["i-tab": record("b", 2, "Moved", "favorites")])
        let c = SidebarSyncDocument(records: ["i-tab": SidebarSyncRecord(stamp: SidebarSyncStamp(counter: 1, replica: "c"), value: nil)])
        XCTAssertEqual(try SidebarSync.merge(a, b), try SidebarSync.merge(b, a))
        XCTAssertEqual(try SidebarSync.merge(a, a), a)
        XCTAssertEqual(try SidebarSync.merge(SidebarSync.merge(a, b), c), try SidebarSync.merge(a, SidebarSync.merge(b, c)))
        XCTAssertNil(try SidebarSync.merge(c, a).records["i-tab"]?.value)
        XCTAssertEqual(try SidebarSync.merge(a, b).records["i-tab"]?.value?.parent, "favorites")
        var corrupt = a; corrupt.records["i-tab"]?.value?.order = 1
        XCTAssertThrowsError(try SidebarSync.merge(a, corrupt))
    }

    func testSyncWhitelistNeverCopiesPrivateTodayHistoryPathsOrSettings() throws {
        let d = Driver()
        let publicTab = d.open("https://example.test/public")
        d.user(.tab(.togglePin(.item(publicTab))))
        d.user(.item(.rename(publicTab, title: "Approved name")))
        let query = d.open("https://example.test/?token=SECRETQUERY"); d.user(.tab(.togglePin(.item(query))))
        d.open("https://example.test/SECRET-TODAY")
        d.user(.settings(.profile(.default, .downloadsDirectory("/tmp/SECRET-PATH"))))
        d.user(.window(.newIncognito))
        d.system(.sidebarData(.connected(d.window, folder: "/tmp/owned-sync")))
        let document = try XCTUnwrap(d.state.doc.sidebarData.sync?.document)
        let bytes = try SidebarDataCodec.encodeSync(document)
        let text = String(decoding: bytes, as: UTF8.self)
        XCTAssertTrue(text.contains("Approved name")); XCTAssertTrue(text.contains("https://example.test/public"))
        for secret in ["SECRETQUERY", "SECRET-TODAY", "SECRET-PATH", "windows", "history", "downloadsDirectory", "privateSession", "observedTitle", "lastActiveAt"] {
            XCTAssertFalse(text.contains(secret), secret)
        }
        XCTAssertGreaterThan(d.snapshot.sidebarData.excluded, 0)
        XCTAssertEqual(try SidebarDataCodec.decodeSync(bytes), document)
    }

    func testIncomingSyncPreservesSettingsWindowsLiveAddressesAndOtherProfiles() throws {
        let d = Driver()
        let tab = d.open("https://example.test/home"); d.user(.tab(.togglePin(.item(tab))))
        d.system(.sidebarData(.connected(d.window, folder: "/tmp/owned-sync")))
        let local = try XCTUnwrap(d.state.doc.sidebarData.sync)
        var incoming = local.document
        let key = "i-" + tab.rawValue
        incoming.records[key] = SidebarSyncRecord(stamp: SidebarSyncStamp(counter: local.counter + 5, replica: "peer"),
            value: SidebarSyncValue(payload: .tab(title: "Peer name", url: url("https://example.test/new-home"), icon: nil), parent: incoming.records[key]?.value?.parent, order: 0))
        d.page(tab, .committed(url("https://example.test/local-document")))
        let windows = d.state.doc.windows, settings = d.state.doc.settings, demand = d.snapshot.pages
        d.system(.sidebarData(.syncRead(epoch: local.epoch, incoming)))
        XCTAssertEqual(d.state.doc.windows, windows)
        XCTAssertEqual(d.state.doc.settings, settings)
        XCTAssertEqual(d.snapshot.pages, demand)
        XCTAssertEqual(d.state.tab(tab)?.pinnedURL, url("https://example.test/new-home"))
        XCTAssertEqual(d.state.tab(tab)?.customTitle, "Peer name")
        d.user(.sidebarData(.disconnect))
        let before = d.savedFile
        d.system(.sidebarData(.syncRead(epoch: local.epoch, SidebarSyncDocument())))
        XCTAssertEqual(before, d.savedFile)
    }

    func testExportCapturesInitiatingWindowAndFolderSelection() throws {
        let d = Driver(); d.user(.item(.newFolder)); let folder = try XCTUnwrap(d.pinnedIDs.first)
        d.user(.item(.rename(folder, title: "Exports")))
        let tab = d.open("https://example.test/export")
        d.user(.item(.move(tab, to: .into(parent: folder, index: 0))))
        let transition = d.user(.app(.export(.items([folder]))))
        guard case .export(let document, let owner)? = transition.effects.first else { return XCTFail("Missing export") }
        XCTAssertEqual(owner, d.window)
        XCTAssertEqual(document.entries, [.folder(title: "Exports", children: [.link(title: "example.test/export", url: url("https://example.test/export"))])])
    }
}
