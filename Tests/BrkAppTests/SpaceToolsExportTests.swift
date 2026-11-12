import AppKit
import BrkBase
import BrkDomain
import Foundation
import XCTest
@testable import BrkApp

final class SpaceToolsExportTests: XCTestCase {
    func testExportPublishesBothBookmarkFilesAndNeverOverwrites() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("brk-space-export-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = ExportDocument(title: "../Work:One", entries: [.folder(title: "Pinned", children: [.link(title: "Fixture & one", url: URL(string: "https://example.org/one")!)])])
        let first = try SpaceFolderWriter.write(document, into: directory)
        let second = try SpaceFolderWriter.write(document, into: directory)
        XCTAssertEqual(first.deletingLastPathComponent().standardizedFileURL.path, directory.standardizedFileURL.path)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try JSONDecoder().decode(ExportDocument.self, from: Data(contentsOf: first.appendingPathComponent("bookmarks.json"))), document)
        XCTAssertTrue(try String(contentsOf: first.appendingPathComponent("bookmarks.html"), encoding: .utf8).contains("Fixture &amp; one"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 2)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: first.path).sorted(), ["bookmarks.html", "bookmarks.json"])
    }

    /// Export Here writes the folder off the main thread (a slow network share must not stop the window) and reports
    /// through the same completion
    @MainActor
    func testExportHereWritesOffTheMainThread() async throws {
        _ = NSApplication.shared
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("brk-space-export-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let window = NSWindow(contentRect: CGRect(x: 200, y: 200, width: 700, height: 500), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        final class Seen: @unchecked Sendable { var onMain: Bool?; var outcome: SpaceExportOutcome? }
        let seen = Seen()
        let panels = SpaceToolsPanels()
        panels.write = { document, folder in
            seen.onMain = Thread.isMainThread
            return try SpaceFolderWriter.write(document, into: folder)
        }
        let document = ExportDocument(title: "Work", entries: [.link(title: "One", url: URL(string: "https://example.org/one")!)])
        panels.export(document, owner: WindowID("owner"), token: "t", window: window) { seen.outcome = $0 }
        let sheet = try XCTUnwrap(window.attachedSheet)
        let path = try XCTUnwrap(ViewTree.find("space-tools-folder-export-path", in: sheet) as? NSTextField)
        path.stringValue = directory.path
        let confirm = try XCTUnwrap(ViewTree.find("space-tools-folder-export-confirm", in: sheet) as? NSButton)
        confirm.performClick(nil)
        let deadline = Date().addingTimeInterval(5)
        while seen.outcome == nil, Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertEqual(seen.outcome, .saved)
        XCTAssertEqual(seen.onMain, false)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["Work"])
    }
}
