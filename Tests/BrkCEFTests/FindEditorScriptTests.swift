import Foundation
import JavaScriptCore
import PageEditorScript
import XCTest

/// FindEditorScript in JavaScriptCore, over the few DOM calls it makes for a selection outside any field.
final class FindEditorScriptTests: XCTestCase {
    private static let page = #"""
    var listeners = {}, records = [];
    class MutationObserver { constructor(callback) {} observe() {} disconnect() {} takeRecords() { const r = records; records = []; return r; } }
    class HTMLInputElement {}
    class HTMLTextAreaElement {}
    var NodeFilter = {SHOW_TEXT: 4};
    var document = {documentElement: {}, addEventListener(type, f) { (listeners[type] = listeners[type] || []).push(f); }};
    var top = {document};
    var body = {tagName: 'BODY', nodeType: 1, isContentEditable: false, isConnected: true, parentElement: null, getRootNode() { return document; }, closest() { return null; }};
    document.activeElement = body;
    var word = {nodeType: 3, parentElement: body}, match = {nodeType: 3, parentElement: body};
    var selection = {anchorNode: word, anchorOffset: 0, focusNode: word, focusOffset: 5, rangeCount: 1, toString() { return 'apple'; },
        getRangeAt() { return {cloneRange() { return {startContainer: word, endContainer: word, commonAncestorContainer: word}; }}; }};
    function getSelection() { return selection; }
    function select(node, start, end) {
        selection.anchorNode = node; selection.anchorOffset = start; selection.focusNode = node; selection.focusOffset = end;
        selection.rangeCount = node ? 1 : 0;
        for (const f of listeners.selectionchange || []) f({});
    }
    function ask(request) { return JSON.parse(editor(JSON.stringify(request))); }
    """#

    private func page() throws -> JSContext {
        let context = try XCTUnwrap(JSContext())
        context.evaluateScript(Self.page)
        context.evaluateScript("var editor = " + FindEditorScript.source)
        XCTAssertNil(context.exception)
        return context
    }
    private func ask(_ context: JSContext, _ request: String) throws -> [String: Any] {
        let value = context.evaluateScript("ask(\(request))")
        XCTAssertNil(context.exception, "\(context.exception?.toString() ?? "")")
        return try XCTUnwrap(value?.toDictionary() as? [String: Any])
    }
    private func revision(_ context: JSContext) throws -> Int {
        try XCTUnwrap(try ask(context, #"{op:'revision'}"#)["revision"] as? Int)
    }

    /// After Use Selection for Find (Cmd+E) the page kept its selection ticket. Page find moves the selection itself: a
    /// recount stops Chromium's find keeping the active match as the selection, and the next search clears it. Each move
    /// counted as a page change, so the next poll started another recount, every 0.4 s for as long as the bar was open,
    /// with the match highlights flickering, even on a page that never changed.
    func testSelectionMovesAreNotPageChangesForFind() throws {
        let context = try page()
        XCTAssertEqual(try ask(context, #"{op:'capture',ticket:'t1'}"#)["status"] as? String, "selection")
        XCTAssertEqual(try ask(context, #"{op:'validate',ticket:'t1'}"#)["status"] as? String, "valid")
        let before = try revision(context)
        context.evaluateScript("select(match, 2, 7); select(null, 0, 0)")
        XCTAssertEqual(try revision(context), before, "a selection change started a recount")
        // The ticket still sees the change, even when the selection comes back to where it was.
        context.evaluateScript("select(word, 0, 5)")
        XCTAssertEqual(try ask(context, #"{op:'validate',ticket:'t1'}"#)["status"] as? String, "invalid")
        // A change of the page's nodes is still one.
        context.evaluateScript("records.push({})")
        XCTAssertEqual(try revision(context), before + 1)
    }
}
