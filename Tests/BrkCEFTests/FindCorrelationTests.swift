import BrkBase
import Foundation
import XCTest
@testable import BrkCEF

final class FindCorrelationTests: XCTestCase {
    func token(_ window: String, _ sequence: UInt64 = 1) -> SearchToken {
        SearchToken(id: SearchID("s-\(window)-\(sequence)"), document: DocumentToken(browser: BrowserToken(page: PageID(window: WindowID(window), item: ItemID("shared")), generation: 1), sequence: sequence))
    }
    func testGloballyGeneratedInterleavedIDsBindToIndependentBrowsers() {
        var a = FindCorrelation(), b = FindCorrelation()
        let sa = token("a"), sb = token("b")
        a.begin(FindRequestID("a1"), sa, FindQuery(text: "one")); b.begin(FindRequestID("b1"), sb, FindQuery(text: "two"))
        XCTAssertEqual(b.receive(id: 108, count: 3, ordinal: 2, final: true, document: sb.document)?.0,
                       .matches(FindRequestID("b1"), sb, count: 3, ordinal: 2, passComplete: true))
        XCTAssertEqual(a.receive(id: 104, count: 5, ordinal: 1, final: true, document: sa.document)?.0,
                       .matches(FindRequestID("a1"), sa, count: 5, ordinal: 1, passComplete: true))
        XCTAssertEqual(a.bindings.map(\.native), [104]); XCTAssertEqual(b.bindings.map(\.native), [108])
    }
    func testFinalDoesNotEndLifetimeAndZeroHasNoOrdinal() {
        var a = FindCorrelation(); let s = token("a"), r = FindRequestID("r")
        a.begin(r, s, FindQuery(text: "needle"))
        _ = a.receive(id: 20, count: 0, ordinal: 0, final: true, document: s.document)
        XCTAssertEqual(a.receive(id: 20, count: 4, ordinal: 0, final: false, document: s.document)?.0,
                       .matches(r, s, count: 4, ordinal: nil, passComplete: false))
        XCTAssertEqual(a.receive(id: 20, count: 0, ordinal: 4, final: true, document: s.document)?.0,
                       .matches(r, s, count: 0, ordinal: nil, passComplete: true))
    }
    func testStepsQueueAndKnownOlderIDsNeverBindPendingStep() {
        var a = FindCorrelation(); let s = token("a")
        a.begin(FindRequestID("initial"), s, FindQuery(text: "x"))
        XCTAssertNil(a.step(FindRequestID("next"), s, .next))
        XCTAssertNil(a.step(FindRequestID("previous"), s, .previous))
        let first = a.receive(id: 17, count: 4, ordinal: 1, final: true, document: s.document)
        XCTAssertEqual(first?.1?.request, FindRequestID("next"))
        XCTAssertNil(a.receive(id: 17, count: 99, ordinal: 1, final: true, document: s.document))
        let second = a.receive(id: 64, count: 4, ordinal: 2, final: true, document: s.document)
        XCTAssertEqual(second?.1?.direction, .previous)
        XCTAssertNil(a.receive(id: 17, count: 99, ordinal: 1, final: true, document: s.document))
        XCTAssertNil(a.receive(id: 64, count: 99, ordinal: 1, final: true, document: s.document))
        XCTAssertEqual(a.receive(id: 91, count: 4, ordinal: 1, final: true, document: s.document)?.0,
                       .matches(FindRequestID("previous"), s, count: 4, ordinal: 1, passComplete: true))
    }
    func testResetRejectsSynchronousCallbacksAndOldDocument() {
        var a = FindCorrelation(); let s = token("a"), new = token("a", 2)
        a.begin(FindRequestID("old"), s, FindQuery(text: "x"))
        _ = a.receive(id: 2, count: 4, ordinal: 1, final: true, document: s.document)
        a.reset()
        XCTAssertNil(a.receive(id: 2, count: 0, ordinal: 0, final: true, document: s.document))
        a.begin(FindRequestID("new"), new, FindQuery(text: "y"))
        XCTAssertNil(a.receive(id: 2, count: 4, ordinal: 1, final: true, document: new.document))
        XCTAssertNil(a.receive(id: 3, count: 4, ordinal: 1, final: true, document: s.document))
        XCTAssertNotNil(a.receive(id: 8, count: 1, ordinal: 1, final: true, document: new.document))
        a.reset(); XCTAssertNil(a.receive(id: 8, count: 1, ordinal: 1, final: false, document: new.document))
    }
    func testNewQuerySearchesEvenWhenDOMRevisionIsUnchanged() {
        var revisions=FindRevisions();revisions.beginQuery()
        XCTAssertTrue(revisions.observe(frameDocument:"doc",revision:4))
        revisions.started()
        XCTAssertFalse(revisions.observe(frameDocument:"doc",revision:4))
        revisions.beginQuery()
        XCTAssertTrue(revisions.observe(frameDocument:"doc",revision:4))
        revisions.started()
        XCTAssertTrue(revisions.observe(frameDocument:"doc",revision:5))
        XCTAssertTrue(revisions.observe(frameDocument:"subframe",revision:1))
    }
    func testDOMRefreshKeepsQueuedStepsAndRejectsResetReplies() {
        var a=FindCorrelation(); let s=token("a")
        a.begin(FindRequestID("first"),s,FindQuery(text:"x"))
        _=a.receive(id:1,count:3,ordinal:1,final:false,document:s.document)
        XCTAssertNil(a.step(FindRequestID("queued"),s,.previous))
        a.pauseForRefresh()
        XCTAssertNil(a.receive(id:1,count:0,ordinal:0,final:true,document:s.document))
        a.resumeAfterRefresh()
        XCTAssertNil(a.receive(id:1,count:3,ordinal:2,final:true,document:s.document))
        XCTAssertEqual(a.receive(id:8,count:4,ordinal:1,final:true,document:s.document)?.1?.request,FindRequestID("queued"))
        XCTAssertEqual(a.receive(id:11,count:4,ordinal:4,final:true,document:s.document)?.0,.matches(FindRequestID("queued"),s,count:4,ordinal:4,passComplete:true))
    }
    func testMutationTimeoutOrCloseDoesNotAllowDuplicateEdit() {
        var ledger = FindMutations()
        let ticket = SelectionTicket(id:SelectionID("t"),document:token("a").document), id = FindRequestID("edit")
        XCTAssertNil(ledger.begin(id,ticket:ticket))
        XCTAssertEqual(ledger.begin(id,ticket:ticket),.edited(id,ticket,.unconfirmed))
        XCTAssertEqual(ledger.complete(id,ticket:ticket,result:.partial(applied:2,reason:"changed")),.edited(id,ticket,.partial(applied:2,reason:"changed")))
        XCTAssertEqual(ledger.begin(id,ticket:ticket),.edited(id,ticket,.partial(applied:2,reason:"changed")))
        ledger.removeAll()
        XCTAssertNil(ledger.begin(id,ticket:SelectionTicket(id:ticket.id,document:token("a",2).document)))
    }
    @MainActor func testEditingAcknowledgementNeverInventsAppliedCount() {
        XCTAssertEqual(PageFind.editResult(["status":"edited","applied":3]), .replaced(3))
        XCTAssertEqual(PageFind.editResult(["status":"partial","applied":1,"message":"input handler changed text"]), .partial(applied: 1, reason: "input handler changed text"))
        XCTAssertEqual(PageFind.editResult(["status":"edited"]), .unconfirmed)
        XCTAssertEqual(PageFind.editResult(["status":"edited","applied":-1]), .unconfirmed)
        XCTAssertEqual(PageFind.editResult(["status":"unconfirmed"]), .unconfirmed)
    }
}
