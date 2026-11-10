import BrkBase
@testable import BrkDomain
import XCTest

/// Brk's own AI words follow the language the user writes in a conversation (docs/design/ai-panel.md, "文字的语言"), and
/// the panel's New Conversation puts the current one away for a fresh one.
final class AIPanelWordsTests: XCTestCase {
    func testTheLanguageIsTheLatestMessageThatTellsElseTheSystems() {
        XCTAssertEqual(AILanguage.of(text: "盯着这三个商品页的价格"), .zh)
        XCTAssertEqual(AILanguage.of(text: "帮我看 github 的 PR"), .zh, "any Han character is Chinese")
        XCTAssertEqual(AILanguage.of(text: "Summarize these"), .en)
        XCTAssertNil(AILanguage.of(text: "https://x.example/ 42 👍"), "no letters say nothing")
        XCTAssertEqual(AILanguage.of([], system: "en-US"), .en)
        XCTAssertEqual(AILanguage.of([], system: "zh-Hans-CN"), .zh)
        XCTAssertEqual(AILanguage.of([.user("你好"), .assistant("Hello"), .user("42")], system: "en-US"), .zh, "a message without letters does not change it")
        XCTAssertEqual(AILanguage.of([.user("你好"), .user("Now in English")], system: "zh-Hans"), .en, "the latest message wins")
    }

    private func enabled() -> Driver {
        let d = Driver()
        for feature in AIFeature.allCases { d.user(.settings(.max(.feature(feature, !AIFeature.basicLayer.contains(feature))))) }
        d.system(.aiProvidersDetected([.claude, .codex]))
        d.system(.aiAgents([AIAgentStatus(kind: .claude, state: .ready), AIAgentStatus(kind: .codex, state: .ready)]))
        return d
    }

    func testNewConversationPutsTheShownOneAwayAndStartsAFreshOne() throws {
        let d = enabled()
        let a = d.open("https://a.example/")
        d.user(.assist(.attach([.tab(a.rawValue)])))
        d.user(.assist(.followUp("What is this?")))
        let first = try XCTUnwrap(d.view.ai?.conversation?.id)
        d.system(.aiResult(first, .text("A page.")))
        XCTAssertEqual(d.view.ai?.name, "What is this?", "a conversation is called by its first message until it has a name")
        d.user(.assist(.newConversation))
        let fresh = try XCTUnwrap(d.view.ai?.conversation)
        XCTAssertNotEqual(fresh.id, first)
        XCTAssertTrue(fresh.fresh && fresh.tabs)
        XCTAssertEqual(fresh.items, [])
        XCTAssertNotNil(d.state.savedConversations[first], "the first one is kept, its tab shows it")
    }

}
