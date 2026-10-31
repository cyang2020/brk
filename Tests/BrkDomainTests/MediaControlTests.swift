import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

final class MediaControlTests: XCTestCase {
    func testBackgroundControlFreezesDocumentAndSpecificPlayerWithoutChangingSelection() throws {
        let d = Driver()
        let tab = d.todayIDs[0]
        let page = PageID(window: d.window, item: tab)
        let browser = try XCTUnwrap(d.state.session.live[page]?.browser)
        let document = DocumentToken(browser: browser, sequence: 1)
        d.page(tab, .documentChanged(.loading(document)))
        d.page(tab, .documentChanged(.ready(document)))
        let player = MediaPlayer(id: MediaPlayerID(document: "frame-document", frame: 7, element: "player"), kind: .video, paused: false, ended: false)
        d.page(tab, .mediaChanged(document, [player], error: nil))
        d.user(.commandBar(.open(.newTab))); d.user(.commandBar(.submit("https://example.com/other")))
        let selected = d.paneIDs
        let result = d.user(.page(.media(.item(tab), player.id, .pause)))
        XCTAssertEqual(d.paneIDs, selected)
        XCTAssertEqual(result.effects, [.page(page, .media(MediaControl(document: document, player: player.id, operation: .pause)))])
        let replacement = DocumentToken(browser: document.browser, sequence: document.sequence + 1)
        d.page(tab, .documentChanged(.loading(replacement)))
        d.page(tab, .documentChanged(.ready(replacement)))
        d.page(tab, .mediaChanged(document, [player], error: nil))
        XCTAssertTrue(d.state.session.live[page]!.mediaPlayers.isEmpty)
        XCTAssertTrue(d.user(.page(.media(.item(tab), player.id, .play))).effects.isEmpty)
        XCTAssertFalse(String(decoding: d.savedFile, as: UTF8.self).contains("frame-document"))
    }
}
