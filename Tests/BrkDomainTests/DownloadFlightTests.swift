import BrkBase
import CoreGraphics
import Foundation
import XCTest
@testable import BrkDomain

/// A download's flight into the Library button (Arc's `DownloadToLibrary`; docs/arc-anatomy/library-flyout.md, "The
/// download flight"). The numbers checked here are the ones read off Arc's screen in the r1 and r2 recordings.
final class DownloadFlightTests: XCTestCase {
    /// Arc's r1: a click at (772, 379) from the top left of a 1280 x 776 window, the sidebar showing. The icon rises to
    /// y 184 from the top (592 up from the bottom), 0.40 s after it starts, moves 12 points left per frame, and falls
    /// into the Library button about 1.05 s after it starts, shrinking to nothing.
    func test_throwIntoTheLibraryButtonFollowsArcsArc() throws {
        let window = CGSize(width: 1280, height: 776)
        let path = try XCTUnwrap(DownloadFlightPath.plan(pointer: CGPoint(x: 772, y: 776 - 379), window: window, bin: false))
        XCTAssertEqual(path.frames[0].position.x, 787, accuracy: 0.001, "15 points right of the pointer")
        XCTAssertEqual(path.frames[0].position.y, 382, accuracy: 0.001, "15 points below it")
        XCTAssertEqual(path.frames[0].scale.width, 0.8, accuracy: 0.001)
        XCTAssertEqual(path.frames[0].scale.height, 1.2, accuracy: 0.001, "taller than wide as it leaves")
        XCTAssertEqual(path.apexTime, 0.400, accuracy: 0.005)
        XCTAssertEqual(path.duration, 1.046, accuracy: 0.005)
        let top = try XCTUnwrap(path.frames.max { $0.position.y < $1.position.y })
        XCTAssertEqual(top.position.y, 592, accuracy: 2.5, "Arc's icon peaks at y 184 from the top")
        XCTAssertEqual(top.scale.width, 1.6, accuracy: 0.02)
        XCTAssertEqual(path.frames[1].position.x - path.frames[0].position.x, -12, accuracy: 0.2, "12 points left per frame")
        let landing = path.frames[Int((path.duration * 60).rounded())]
        XCTAssertEqual(landing.position.x, 32, accuracy: 13, "over the Library button")
        XCTAssertEqual(landing.position.y, 40, accuracy: 13)
        XCTAssertEqual(landing.scale.width, 0.3, accuracy: 0.05)
        XCTAssertEqual(path.frames.count, Int(ceil((path.duration + 8.0 / 60) * 60)), "eight frames past the button")
        XCTAssertLessThan(try XCTUnwrap(path.frames.last).scale.width, 0.06, "it has shrunk to nothing")
    }

    /// Arc's r2, the sidebar hidden: the icon lands 8 points short of the bin's corner (70, 70), drops 58 points below
    /// it on the spring (response 0.48, damping ratio 0.72) and settles on the corner, keeping the landing scale (about 0.7).
    func test_bounceIntoTheBin() throws {
        let window = CGSize(width: 1280, height: 776)
        let path = try XCTUnwrap(DownloadFlightPath.plan(pointer: CGPoint(x: 652, y: 776 - 379), window: window, bin: true))
        let thrown = Int(ceil(path.duration * 60))
        let bounce = path.frames[thrown...]
        XCTAssertLessThan(hypot(bounce.first!.position.x - 62, bounce.first!.position.y - 70), 30, "the bounce starts at the landing, 8 short of the corner")
        let low = try XCTUnwrap(bounce.min { $0.position.y < $1.position.y })
        XCTAssertEqual(70 - low.position.y, 57.5, accuracy: 3, "Arc's icon dropped 58 points below the corner")
        XCTAssertEqual(try XCTUnwrap(path.frames.last).position, CGPoint(x: 70, y: 70), "it rests on the corner")
        let landing = path.frames[thrown - 1].scale
        XCTAssertEqual(landing.width, 0.7, accuracy: 0.03)
        XCTAssertTrue(bounce.allSatisfy { $0.scale == landing }, "the bounce keeps the last thrown frame's scale (Arc appends it to every bounce frame)")
        XCTAssertLessThan(path.length - path.duration, 1.6, "the spring settles within the overlay's hold")
    }

    /// Every download that starts in a standard window flies once, several at a time; a Little Arc window has no
    /// Library button and throws nothing (Arc's Little Arc shows its own download pill).
    func test_flightsStartInStandardWindowsOnly() throws {
        let d = Driver()
        let tab = d.todayIDs[0]
        d.download(tab, DownloadID("a"), .receiving(TransferProgress(received: 0, total: 100)),
                   details: DownloadDetails(url: URL(string: "https://example.com/a.txt")!, suggestedName: "a.txt"))
        d.download(tab, DownloadID("a"), .receiving(TransferProgress(received: 50, total: 100)))
        d.advance(.milliseconds(300))
        d.download(tab, DownloadID("b"), .receiving(TransferProgress(received: 0, total: 100)),
                   details: DownloadDetails(url: URL(string: "https://example.com/b.txt")!, suggestedName: "b.txt"))
        d.download(tab, DownloadID("a"), .terminal(.completed(FileReceipt(url: URL(fileURLWithPath: "/tmp/a.txt"), bytes: 100))))
        XCTAssertEqual(try XCTUnwrap(d.view.libraryFlyout).flights.map(\.id), [DownloadID("a"), DownloadID("b")],
                       "one flight per download, not one per progress report or for finishing")
        d.advance(.seconds(11))
        d.download(tab, DownloadID("c"), .receiving(TransferProgress(received: 0, total: 100)),
                   details: DownloadDetails(url: URL(string: "https://example.com/c.txt")!, suggestedName: "c.txt"))
        XCTAssertEqual(try XCTUnwrap(d.view.libraryFlyout).flights.map(\.id), [DownloadID("c")], "old flights are dropped")

        d.user(.window(.newLittle(URL(string: "https://example.com/")!)))
        let little = try XCTUnwrap(d.snapshot.windows.first { $0.value.kind == .little }?.key)
        let littleTab = try XCTUnwrap(d.view(of: little).content.panes.first?.tab)
        d.download(littleTab, DownloadID("l"), .receiving(TransferProgress(received: 0, total: 100)),
                   details: DownloadDetails(url: URL(string: "https://example.com/l.txt")!, suggestedName: "l.txt"), in: little)
        XCTAssertNil(d.view(of: little).libraryFlyout, "no Library button, no flight")
        XCTAssertEqual(try XCTUnwrap(d.view.libraryFlyout).flights.map(\.id), [DownloadID("c")], "nor one in the other window")
        XCTAssertTrue(d.state.doc.downloads.contains { $0.id == DownloadID("l") }, "the download itself is listed")
    }
}
