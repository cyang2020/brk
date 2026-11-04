import BrkBase
import BrkDomain
import XCTest
@testable import BrkSettings

/// R4-11 (A142): the Max pane's cards say what Arc's say (P38-max-list), with the local tool's name where Arc names
/// ChatGPT, in Arc's order.
final class MaxCopyTests: XCTestCase {
    private func words(_ feature: MaxFeature, _ provider: String? = "Claude") -> String {
        MaxCopy.description(feature, provider: provider).map { part -> String in
            switch part {
            case .text(let text): text
            case .broom: "🧹"
            case .link(let text, _): text
            }
        }.joined()
    }

    func testArcsSixCardsInArcsOrderWithArcsWords() {
        XCTAssertEqual(MaxFeature.arcs, [.tidyTabs, .instantLinks, .linkPreviews, .tidyTitles, .tidyDownloads, .askInCommandBar])
        XCTAssertEqual(words(.tidyTabs), "Press the 🧹 icon to let your Sidebar organize itself whenever you have more than six Today Tabs.")
        XCTAssertEqual(words(.instantLinks), "Press Shift + Enter for any web search to instantly open the top result. You can also search multiple queries!")
        XCTAssertEqual(words(.linkPreviews), "Instant summaries appear when you hover over links on certain websites. Or hold Shift while hovering to preview any link.")
        XCTAssertEqual(words(.tidyTitles), "Have your tabs automatically renamed with tidier, shorter titles when you Pin them.")
        XCTAssertEqual(words(.askInCommandBar), "Add Claude to your Search suggestions, or start typing “Claude”, hit Tab, to ask any question instantly.")
        XCTAssertEqual(MaxCopy.title(.askInCommandBar, provider: "Codex"), "Codex in the Command Bar")
        XCTAssertEqual(MaxCopy.title(.linkPreviews, provider: nil), "5-Second Previews")
    }

    func testTheBlueWordsAreLinksToNotes() {
        XCTAssertTrue(MaxCopy.description(.instantLinks, provider: nil).contains(.link("You can also search multiple queries!", .multipleQueries)))
        XCTAssertTrue(MaxCopy.description(.linkPreviews, provider: nil).contains(.link("certain websites.", .previewSites)))
        XCTAssertTrue(MaxCopy.description(.tidyTabs, provider: nil).contains(.broom))
    }
}
