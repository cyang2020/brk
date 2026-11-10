import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

/// Little Arc's download pills (Arc: `LittleBrowserDownloadsTrayViewController`; docs/arc-anatomy/little-arc-downloads.md),
/// as seen on Arc 1.170 on 2026-11-10.
final class LittleDownloadsTests: XCTestCase {
    /// Every download a Little Arc window's page starts gets a pill, oldest on the left; downloads of other windows do
    /// not. The × removes a finished pill and leaves the file; on a running download it also cancels it. A click opens a
    /// finished file and does nothing while the download runs.
    func test_pillsCloseAndOpen() throws {
        let d = Driver()
        d.user(.window(.newLittle(URL(string: "https://example.com/")!)))
        let little = try XCTUnwrap(d.snapshot.windows.first { $0.value.kind == .little }?.key)
        let tab = try XCTUnwrap(d.view(of: little).content.panes.first?.tab)
        func start(_ name: String, in window: WindowID, tab: ItemID) {
            d.download(tab, DownloadID(name), .receiving(TransferProgress(received: 0, total: 100)),
                       details: DownloadDetails(url: URL(string: "https://example.com/" + name)!, suggestedName: name), in: window)
        }
        start("a.txt", in: little, tab: tab)
        start("b.png", in: little, tab: tab)
        start("other.txt", in: d.window, tab: d.todayIDs[0])
        d.download(tab, DownloadID("a.txt"), .terminal(.completed(FileReceipt(url: URL(fileURLWithPath: "/tmp/a.txt"), bytes: 100))), in: little)
        XCTAssertEqual(d.view(of: little).littleDownloads.map(\.filename), ["a.txt", "b.png"], "oldest first, finished ones stay")
        XCTAssertEqual(d.view.littleDownloads, [], "a standard window has no pills")

        XCTAssertEqual(d.user(.library(.littleDownload(.open(DownloadID("b.png")))), in: little).effects, [], "a running pill opens nothing")
        XCTAssertEqual(d.user(.library(.littleDownload(.open(DownloadID("a.txt")))), in: little).effects, [.openLocalFile("/tmp/a.txt")])

        let running = d.user(.library(.littleDownload(.dismiss(DownloadID("b.png")))), in: little)
        XCTAssertEqual(running.effects, [.cancelDownload(DownloadID("b.png"))], "the × cancels a running download")
        d.user(.library(.littleDownload(.dismiss(DownloadID("a.txt")))), in: little)
        XCTAssertEqual(d.view(of: little).littleDownloads, [])
        XCTAssertEqual(d.state.doc.downloads.first { $0.id == DownloadID("a.txt") }?.state, .finished, "the file and its Library entry stay")
    }

    /// Arc's subtitles: "671 KB/8.4 MB · 23s", "2.2/8.4 MB · 11s", "4.5/8.4 MB · 6s", "1/1 KB" for a 900-byte file,
    /// "294 KB/1.0 MB · 12s"; "Cancelled" and "Failed to Download" once it stopped.
    func test_progressTextReadsLikeArcs() {
        let mb = 1_048_576.0
        XCTAssertEqual(DownloadText.progress(received: 671_000, total: Int64(8 * mb), remaining: 23), "671 KB/8.4 MB · 23s")
        XCTAssertEqual(DownloadText.progress(received: 2_200_000, total: Int64(8 * mb), remaining: 11.4), "2.2/8.4 MB · 11s")
        XCTAssertEqual(DownloadText.progress(received: 900, total: 900, remaining: nil), "1/1 KB")
        XCTAssertEqual(DownloadText.progress(received: 294_000, total: Int64(mb), remaining: 12), "294 KB/1.0 MB · 12s")
        XCTAssertEqual(DownloadText.ended(.cancelled), "Cancelled")
        XCTAssertEqual(DownloadText.ended(.interrupted), "Failed to Download")
        XCTAssertNil(DownloadText.ended(.finished))
    }
}
