import BrkBase
import BrkDomain
import Foundation
import XCTest
@testable import BrkOverlays

/// R3-6 (A068): the type-travel rows that are not menu items rank like the others, by title and trigger.
final class TypeTravelSuggestTests: XCTestCase {
    func testTravelCandidatesAreSearchableByTitleAndTrigger() {
        var bar = fixtureBar
        bar.travel = [
            TravelCandidate(title: "Mute All Tabs", triggers: ["Silence", "Audio"], symbol: "speaker.slash", command: .tabTools(.muteAll(true))),
            TravelCandidate(title: "Open Research", triggers: [], symbol: "folder", command: .tabTools(.openFolder(ItemID("f")))),
            TravelCandidate(title: "Fixture Action", triggers: ["Extension"], symbol: "puzzlepiece.extension", command: .site(.invokeExtension("abc"))),
        ]
        func first(_ query: String) -> Suggestion? { suggest(query, bar).first { $0.kind == .action } }
        XCTAssertEqual(first("mute all")?.command, .tabTools(.muteAll(true)))
        XCTAssertEqual(first("silence")?.command, .tabTools(.muteAll(true)), "a trigger word finds it")
        XCTAssertEqual(first("open research")?.command, .tabTools(.openFolder(ItemID("f"))))
        XCTAssertEqual(first("fixture action")?.command, .site(.invokeExtension("abc")))
        XCTAssertEqual(first("fixture action")?.symbol, "puzzlepiece.extension")
    }
}
