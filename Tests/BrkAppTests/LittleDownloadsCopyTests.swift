import XCTest
@testable import BrkApp

/// A finished pill's subtitle is Arc's word for the file's kind ("Sidebar download cell file type copy",
/// bin:0x100828ad4): the first matching type in Arc's order, else "Download". Arc showed Archive for a .bin, Download
/// for .txt and .csv, Image for a .png and PDF for a .pdf.
final class LittleDownloadsCopyTests: XCTestCase {
    func test_kindsFollowArcsOrder() {
        let kinds = ["a.bin", "a.txt", "a.csv", "a.png", "a.pdf", "a.zip", "a.dmg", "a.mov", "a.mp3", "a"].map(LittleDownloadsCopy.kind(of:))
        XCTAssertEqual(kinds, ["Archive", "Download", "Download", "Image", "PDF", "Zip Archive", "Disk Image", "Movie", "Audio", "Download"])
    }
}
