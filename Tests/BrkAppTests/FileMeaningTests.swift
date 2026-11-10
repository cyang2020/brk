import AppKit
@testable import BrkApp
import BrkBase
import BrkDomain
import XCTest

/// Files by meaning: which files the index reads, what it reads of them, and how the `file` mode's rows are shared
/// between Spotlight's name matches and the files found by meaning.
final class FileMeaningTests: XCTestCase {
    func testTheIndexReadsDocumentsAndSkipsBuiltHiddenAndHugeFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("brk-files-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func write(_ path: String, _ data: Data) throws {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        try write("notes/index.md", Data("---\ntitle: Grid\nslug: css/grid\n---\n\nThe   CSS grid\nlayout module divides a page into regions.".utf8))
        let rich = NSAttributedString(string: "Sourdough is a leavening agent.")
        try write("Document3.rtf", try rich.data(from: NSRange(location: 0, length: rich.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf]))
        try write("app/node_modules/lib/readme.md", Data("vendored".utf8))
        try write(".hidden/secret.txt", Data("hidden".utf8))
        try write("Library/Caches/cache.txt", Data("cache".utf8))
        try write("photo.jpg", Data([0xFF, 0xD8]))
        try write("huge.txt", Data(count: 2_000_001))

        let listed = FolderLister.walk(root).map { String($0.path.dropFirst(FolderLister.real(root).path.count + 1)) }.sorted()
        XCTAssertEqual(listed, ["Document3.rtf", "notes/index.md"])
        XCTAssertEqual(FileText.read(root.appendingPathComponent("notes/index.md")), "The CSS grid layout module divides a page into regions.", "no front matter, whitespace folded")
        XCTAssertEqual(FileText.read(root.appendingPathComponent("Document3.rtf")), "Sourdough is a leavening agent.")
        let long = root.appendingPathComponent("long.txt")
        try Data(String(repeating: "word ", count: 400).utf8).write(to: long)
        XCTAssertEqual(FileText.read(long)?.count, FileText.keep)
    }

    func testTheFileModeKeepsNamesFirstAndRoomForMeaning() {
        func hits(_ names: [String]) -> [LocalHit] { names.map { LocalHit(path: "/u/" + $0, name: $0) } }
        let names = hits(["a.txt", "b.txt", "c.txt", "d.txt", "e.txt"])
        XCTAssertEqual(LocalSources.merge(names: names, meaning: hits(["x.pdf", "b.txt", "y.md", "z.md"])).map(\.name),
                       ["a.txt", "b.txt", "c.txt", "x.pdf", "y.md"], "two rows by meaning kept, a name already listed not repeated")
        XCTAssertEqual(LocalSources.merge(names: [], meaning: hits(["x.pdf", "y.md", "z.md"])).map(\.name), ["x.pdf", "y.md", "z.md"], "no name matched: meaning fills")
        XCTAssertEqual(LocalSources.merge(names: names, meaning: []).map(\.name), names.map(\.name))
    }
}
