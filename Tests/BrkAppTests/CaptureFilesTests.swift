import BrkBase
import Foundation
import XCTest
@testable import BrkApp

final class CaptureFilesTests: XCTestCase {
    func testActualIndexAndPNGSurviveNewOwnerExportAndRemovalWithPrivateRejection() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("brk-capture-files-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at:root) }
        let files = CaptureFiles(root:root)
        let document = DocumentToken(browser:BrowserToken(page:PageID(window:WindowID("w"),item:ItemID("t")),generation:1),sequence:1)
        let request = CaptureRequest(id:"capture-1",document:document,context:.profile(.default),mode:.fullPage,title:"Fixture",url:URL(string:"https://example.com")!,createdAt:Instant(milliseconds:1))
        let bytes = Data([137,80,78,71])
        let (record,url) = try await files.store(request,image:CaptureImage(png:bytes,width:320,height:180,scale:1))
        XCTAssertEqual(try Data(contentsOf:url),bytes)
        let reopened = CaptureFiles(root:root)
        let (rows,_) = try await reopened.load(.default)
        XCTAssertEqual(rows,[record])
        let exported = try await reopened.bytes(record); XCTAssertEqual(exported,bytes)
        let (other,_) = try await reopened.load(ProfileID("other")); XCTAssertTrue(other.isEmpty)
        let privateRequest = CaptureRequest(id:"private",document:document,context:.incognito(PrivateSessionID("private")),mode:.area,title:"Secret",url:request.url,createdAt:request.createdAt)
        do { _ = try await files.store(privateRequest,image:CaptureImage(png:bytes,width:1,height:1,scale:1)); XCTFail("Private capture persisted") } catch {}
        try await reopened.remove(record)
        XCTAssertFalse(FileManager.default.fileExists(atPath:url.path))
        let (removed,_) = try await files.load(.default); XCTAssertTrue(removed.isEmpty)
    }
}
