import BrkDomain
import Foundation
import XCTest
@testable import BrkApp

@MainActor
final class FilePanelIOTests: XCTestCase {
    func testSelectedExportWritesActualJSONAndParseableHTMLAndReportsWriteFailure() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("brk-selected-export-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let document = ExportDocument(title: "Owned", entries: [.folder(title: "Folder", children: [.link(title: "Link", url: URL(string: "https://example.test/owned")!)])])
        for ext in ["json", "html"] {
            let file = root.appendingPathComponent("selected." + ext)
            XCTAssertEqual(ShareExport.writeSelected(document, to: file), .saved(file))
            let bytes = try Data(contentsOf: file)
            if ext == "json" { XCTAssertEqual(try SidebarDataCodec.decodeExport(bytes), document) }
            else {
                let imported = try SidebarImport.parse(bytes, format: .bookmarksHTML)
                XCTAssertEqual(imported.preview.bookmarkCount, 1)
                XCTAssertEqual(imported.preview.entries, document.entries)
            }
        }
        let blocker = root.appendingPathComponent("blocker")
        let bytes = Data("owned unchanged blocker".utf8)
        try bytes.write(to: blocker)
        if case .failed = ShareExport.writeSelected(document, to: blocker.appendingPathComponent("selected.json")) {} else { XCTFail("Write failure was not reported") }
        XCTAssertEqual(try Data(contentsOf: blocker), bytes)
    }
}
