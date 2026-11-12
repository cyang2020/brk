import AppKit
import BrkBase
import BrkDomain
import Foundation
import XCTest
@testable import BrkApp

@MainActor
final class ImportSyncIOTests: XCTestCase {
    func testTwoAppStoresExchangeActualFilesWithoutCopyingLocalSettingsOrDemand() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("brk-stores-" + UUID().uuidString)
        let shared = root.appendingPathComponent("shared")
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func make(_ name: String) throws -> (AppStore, StateFile, WindowID) {
            let clock = OffsetClock()
            let restored = StateCodec.restore(nil, seed: RestoreSeed(startURL: nil, contentSize: Metrics.window.defaultSize.value), ctx: Context(now: clock.now(), newID: { UUID().uuidString }))
            let window = try XCTUnwrap(project(restored.state, ProjectionContext(now: clock.now(), calendar: .current)).windows.keys.first)
            let file = StateFile(directory: root.appendingPathComponent(name))
            let store = AppStore(restored: restored, clock: clock, engine: FakeEngine(), stateFile: file)
            let target = try XCTUnwrap(restored.state.sidebarImportTarget(in: window))
            store.dispatch(.system(.sidebarData(.imported(window, target: target, SidebarImportPreview(entries: [.link(title: name, url: URL(string: "https://example.test/\(name)")!)]), favorites: false))))
            return (store, file, window)
        }
        let (a, fileA, windowA) = try make("StoreA"), (b, fileB, windowB) = try make("StoreB")
        defer {
            for (store, window) in [(a, windowA), (b, windowB)] {
                store.dispatch(.user(window, .sidebarData(.disconnect)))
                store.flush()
                store.windowController(window)?.window.orderOut(nil)
            }
        }
        a.dispatch(.user(windowA, .settings(.general(.warnBeforeQuitting(true)))))
        a.dispatch(.user(windowA, .settings(.profile(.default, .searchSuggestions(false)))))
        a.dispatch(.user(windowA, .commandBar(.open(.newTab))))
        let nativeWindow = try XCTUnwrap(a.windowController(windowA)?.window)
        let editor = try XCTUnwrap(ViewTree.find("command-bar-input", in: nativeWindow) as? NSTextField)
        try EventInjector().type("owned unsent draft", in: nativeWindow)
        XCTAssertEqual(editor.stringValue, "owned unsent draft")
        let panes = a.snapshot.windows[windowA]?.content.panes
        a.dispatch(.system(.sidebarData(.connected(windowA, folder: shared.path))))
        b.dispatch(.system(.sidebarData(.connected(windowB, folder: shared.path))))
        func documents() throws -> [SidebarSyncDocument] {
            try FileManager.default.contentsOfDirectory(at: shared, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.hasSuffix(".brksync.json") }
                .map { try SidebarDataCodec.decodeSync(Data(contentsOf: $0)) }
        }
        func hasBoth(_ doc: SidebarSyncDocument) -> Bool {
            let titles = doc.records.values.compactMap { record -> String? in
                if case .tab(let title, _, _)? = record.value?.payload { return title }; return nil
            }
            return titles.contains("StoreA") && titles.contains("StoreB")
        }
        var converged = false
        for _ in 0..<200 {
            a.dispatch(.system(.sidebarData(.syncPoll)))
            b.dispatch(.system(.sidebarData(.syncPoll)))
            let files = try documents()
            if files.count == 2, files.allSatisfy(hasBoth) { converged = true; break }
            try await Task.sleep(for: .milliseconds(25))
        }
        await a.stopSidebarData(); await b.stopSidebarData()
        for (store, file, window) in [(a, fileA, windowA), (b, fileB, windowB)] {
            XCTAssertTrue(store.flush())
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.url.path))
            store.windowController(window)?.window.orderOut(nil)
        }
        XCTAssertTrue(converged, "Both real transport files must contain both public links")
        XCTAssertTrue(a.snapshot.settings.general.warnBeforeQuitting)
        XCTAssertFalse(b.snapshot.settings.general.warnBeforeQuitting)
        XCTAssertEqual(a.snapshot.windows[windowA]?.content.panes, panes)
        if case .commandBar? = a.snapshot.windows[windowA]?.overlay {} else { XCTFail("Background sync dismissed the native editor") }
        XCTAssertEqual(editor.stringValue, "owned unsent draft")
        XCTAssertTrue(a.snapshot.pages.isEmpty); XCTAssertTrue(b.snapshot.pages.isEmpty)
        XCTAssertEqual(a.snapshot.windows.count, 1); XCTAssertEqual(b.snapshot.windows.count, 1)
        for file in try FileManager.default.contentsOfDirectory(at: shared, includingPropertiesForKeys: nil) {
            let text = try String(contentsOf: file, encoding: .utf8)
            XCTAssertFalse(text.contains("warnBeforeQuitting")); XCTAssertFalse(text.contains(root.path))
        }
    }

    func testAcceptedImportIsOnDiskBeforeItIsReported() throws {
        let h = Harness(); defer { h.cleanUp() }
        let window = try XCTUnwrap(h.store.snapshot.windows[h.window])
        // Read the opaque destination from this store's own saved checkpoint.
        XCTAssertTrue(h.store.flush())
        let saved = StateCodec.restore(try Data(contentsOf: h.stateFile.url), seed: RestoreSeed(startURL: nil, contentSize: Metrics.window.defaultSize.value), ctx: Context(now: OffsetClock().now(), newID: { UUID().uuidString }))
        let target = try XCTUnwrap(saved.state.sidebarImportTarget(in: window.id))
        h.store.dispatch(.system(.sidebarData(.imported(h.window, target: target, SidebarImportPreview(entries: [.link(title: "Durable", url: URL(string: "https://example.test/durable")!)]), favorites: false))))
        let disk = StateCodec.restore(try Data(contentsOf: h.stateFile.url), seed: RestoreSeed(startURL: nil, contentSize: Metrics.window.defaultSize.value), ctx: Context(now: OffsetClock().now(), newID: { UUID().uuidString }))
        XCTAssertEqual(project(disk.state, ProjectionContext(now: OffsetClock().now(), calendar: .current)).windows[h.window]?.space.pinned.rows.count, 1)
        XCTAssertTrue(h.store.snapshot.sidebarData.status.contains("Imported 1 bookmarks"))
        XCTAssertTrue(h.store.flush())
    }
    /// A sync poll with nothing new to publish (the minute's clock tick) only reads the folder: it does not encode and
    /// fsync the whole state file on the main thread first.
    func testAPollWithNothingToPublishWritesNoStateFile() async throws {
        let h = Harness(); defer { h.cleanUp() }
        let shared = h.directory.appendingPathComponent("shared", isDirectory: true)
        try FileManager.default.createDirectory(at: shared, withIntermediateDirectories: true)
        h.store.dispatch(.system(.sidebarData(.connected(h.window, folder: shared.path))))
        let deadline = Date().addingTimeInterval(5)
        while h.store.state.docNeedsSidebarPublication, Date() < deadline { try await Task.sleep(for: .milliseconds(25)) }
        XCTAssertFalse(h.store.state.docNeedsSidebarPublication, "the first exchange did not publish")
        // The debounced save that followed it lands first; then any write is the poll's own.
        try await Task.sleep(for: .seconds(Metrics.persistence.saveDebounce.value * 3))
        try? FileManager.default.removeItem(at: h.stateFile.url)
        h.store.dispatch(.system(.sidebarData(.syncPoll)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: h.stateFile.url.path), "an idle poll wrote state.json")
        await h.store.stopSidebarData()
    }

    func testInvalidPeerDoesNotOverwriteLastReplicaAndTemporaryFilesAreIgnored() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("brk-sync-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let io = SidebarSyncIO(), document = SidebarSyncDocument()
        _ = try await io.exchange(folder: root, replica: "owned", document: document)
        let output = root.appendingPathComponent("owned.brksync.json"), before = try Data(contentsOf: output)
        try Data("unfinished".utf8).write(to: root.appendingPathComponent(".brksync-crash.tmp"))
        _ = try await io.exchange(folder: root, replica: "owned", document: document)
        try Data("not JSON".utf8).write(to: root.appendingPathComponent("bad.brksync.json"))
        do { _ = try await io.exchange(folder: root, replica: "owned", document: document); XCTFail("Accepted malformed peer") } catch {}
        XCTAssertEqual(try Data(contentsOf: output), before)
    }
}
