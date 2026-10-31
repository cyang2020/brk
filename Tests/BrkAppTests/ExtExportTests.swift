import BrkDomain
import Foundation
import XCTest
@testable import BrkApp

@MainActor
final class ExtExportTests: XCTestCase {
    func test_selectedDestinationWritesReadableJSONAndHTML() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: directory) }
        let document = ExportDocument(title: "Selected link", entries: [.link(title: "A & B", url: URL(string: "https://example.test/page")!)])
        let json = directory.appendingPathComponent("link.json")
        XCTAssertEqual(ShareExport.writeSelected(document, to: json), .saved(json))
        XCTAssertEqual(try JSONDecoder().decode(ExportDocument.self, from: Data(contentsOf: json)), document)
        let html = directory.appendingPathComponent("link.html")
        XCTAssertEqual(ShareExport.writeSelected(document, to: html), .saved(html))
        let contents = try String(contentsOf: html, encoding: .utf8)
        XCTAssertTrue(contents.contains("A &amp; B"))
        XCTAssertTrue(contents.contains("https://example.test/page"))
    }

    func test_writeFailureReportsFailureWithoutSuccess() {
        let destination = URL(fileURLWithPath: "/unused/link.json")
        let result = ShareExport.writeSelected(ExportDocument(title: "Link", entries: []), to: destination) { _, _ in
            throw CocoaError(.fileWriteNoPermission)
        }
        guard case .failed(let reason) = result else { return XCTFail("A failed write reported success") }
        XCTAssertFalse(reason.isEmpty)
    }
}
