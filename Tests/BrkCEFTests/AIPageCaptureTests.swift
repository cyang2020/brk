import Foundation
import JavaScriptCore
import XCTest
@testable import BrkCEF

/// The AI page read (Translate, Ask on Page, previews, Browse for Me) in JavaScriptCore, over a page whose main text is
/// a list of visible text nodes. BrkCore's copy (CoreAIPage.swift) is the same script.
final class AIPageCaptureTests: XCTestCase {
    private static let page = #"""
    var element = {isContentEditable: false, closest() { return null; }, getClientRects() { return [{}]; }};
    var texts = pieces.map(t => ({nodeValue: t, parentElement: element}));
    var document = {title: 'Article', documentElement: {lang: 'fr'}, body: element, querySelector() { return element; },
        createTreeWalker() { let i = 0; return {nextNode() { return i < texts.length ? texts[i++] : null; }}; }};
    var NodeFilter = {SHOW_TEXT: 4};
    var location = {href: 'https://example.com/article'};
    function getComputedStyle() { return {display: 'block', visibility: 'visible'}; }
    """#

    private struct Read { let text: String; let nodes: [String]; let partial: Bool }
    private func capture(_ pieces: [String]) throws -> Read {
        let context = try XCTUnwrap(JSContext())
        context.setObject(pieces, forKeyedSubscript: "pieces" as NSString)
        context.evaluateScript(Self.page)
        let value = context.evaluateScript(AIPageScripts.capture)
        XCTAssertNil(context.exception, "\(context.exception?.toString() ?? "")")
        let object = try XCTUnwrap(value?.toDictionary() as? [String: Any])
        let nodes = try XCTUnwrap(object["nodes"] as? [[String: Any]]).compactMap { $0["text"] as? String }
        return Read(text: try XCTUnwrap(object["text"] as? String), nodes: nodes, partial: object["partial"] as? Bool == true)
    }

    /// Every paragraph over 1,000 characters was left out of translation, so a long article stayed in its own language
    /// while the pill said Translated. Paragraphs of up to 3,000 characters are translated.
    func testParagraphsOfUpTo3000CharactersAreTranslated() throws {
        let paragraphs = (0..<5).map { String(repeating: "\($0)", count: 2500) }
        let read = try capture(paragraphs)
        XCTAssertEqual(read.nodes, paragraphs)
        XCTAssertFalse(read.partial, "the whole page was read")
    }

    /// A piece too long to translate as one is still read for the text, but takes nothing from the 24,000 characters
    /// that go to translation: the headings and captions after it are translated as before.
    func testATooLongPieceIsReadWithoutCrowdingOutTranslation() throws {
        let long = String(repeating: "x", count: 5000)
        let paragraphs = (0..<10).map { String(repeating: "\($0)", count: 2000) }
        let headings = (0..<30).map { "Heading \($0)" }
        let read = try capture(paragraphs + [long] + headings)
        XCTAssertEqual(read.nodes, paragraphs + headings)
        XCTAssertTrue(read.text.contains(long), "Ask on Page gets the long piece")
        XCTAssertTrue(read.partial, "the long piece is not translated")
    }

    /// The text stays within what the readers accept (100,000 UTF-8 bytes): 24,000 characters of translated pieces and
    /// 8,000 of pieces too long to translate.
    func testTheTextStaysBounded() throws {
        let read = try capture((0..<20).map { _ in String(repeating: "长", count: 3001) } + (0..<20).map { _ in String(repeating: "文", count: 2000) })
        XCTAssertEqual(read.nodes.count, 12)
        XCTAssertLessThanOrEqual(read.text.utf8.count, 100_000)
        XCTAssertTrue(read.partial)
    }
}
