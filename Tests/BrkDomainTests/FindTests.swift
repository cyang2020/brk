import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

final class FindTests: XCTestCase {
    private func ready(_ d: Driver) {
        let tab=d.paneIDs[0], page=PageID(window:d.window,item:d.paneIDs[0])
        let token=DocumentToken(browser:d.state.session.live[page]!.browser!,sequence:1)
        d.page(tab,.documentChanged(.loading(token)));d.page(tab,.documentChanged(.ready(token)))
    }
    func testPageFirstIntentAndNativeMenuUseSameRemappedDecision() {
        let d = Driver(), chord = KeyChord(.command, .f)
        let pre = d.key(chord, stage: .beforePage, pressID: 1)
        XCTAssertFalse(pre.keyHandled); XCTAssertTrue(pre.keyShortcut); XCTAssertNil(d.view.find)
        XCTAssertTrue(d.key(chord, stage: .afterPage, pressID: 1).keyHandled)
        XCTAssertNotNil(d.view.find)
        d.user(.find(.close))
        d.user(.settings(.shortcuts(.setChord(.find, KeyChord([.command,.option], .e)))))
        XCTAssertFalse(d.key(chord, stage: .beforePage, pressID: 2).keyShortcut)
        let remap = d.key(KeyChord([.command,.option], .e), stage: .beforePage, pressID: 3)
        XCTAssertFalse(remap.keyHandled); XCTAssertTrue(remap.keyShortcut)
        XCTAssertTrue(d.key(KeyChord([.command,.option], .e), stage: .afterPage, pressID: 3).keyHandled)
    }
    func testNavigationKeepsQueryButRejectsOldMatchesAndNeverResurrectsToken() throws {
        let d = Driver(), tab = try XCTUnwrap(d.current?.id); ready(d)
        d.user(.find(.open(replace: false))); d.user(.find(.query(FindQuery(text:"secret-query"))))
        let old = try XCTUnwrap(d.state.session.windows[d.window]?.find)
        let doc = try XCTUnwrap(old.document), search = try XCTUnwrap(old.search), request = try XCTUnwrap(old.request)
        d.system(.find(.matches(request, search, count: 4, ordinal: 2, passComplete: true)))
        XCTAssertEqual(d.view.find?.count, 4)
        let new = DocumentToken(browser: doc.browser, sequence: doc.sequence + 1)
        d.page(tab, .documentChanged(.loading(new)))
        XCTAssertEqual(d.view.find?.query.text,"secret-query"); XCTAssertNil(d.view.find?.count)
        d.system(.find(.matches(request, search, count: 99, ordinal: 1, passComplete: true)))
        XCTAssertNil(d.view.find?.count)
        d.page(tab,.documentChanged(.ready(doc))); XCTAssertNil(d.state.session.windows[d.window]?.find?.document)
        d.page(tab,.documentChanged(.ready(new)))
        XCTAssertEqual(d.state.session.windows[d.window]?.find?.search?.document,new)
        XCTAssertFalse(String(decoding:d.savedFile,as:UTF8.self).contains("secret-query"))
    }
    func testInvalidatingSelectionTicketDoesNotErasePageScopedFind() throws {
        let d=Driver();ready(d);d.user(.find(.useSelection))
        let f=try XCTUnwrap(d.state.session.windows[d.window]?.find)
        let ticket=SelectionTicket(id:SelectionID("selected"),document:try XCTUnwrap(f.document))
        d.system(.find(.selection(try XCTUnwrap(f.capture?.id),ticket,text:"apple",editable:.input)))
        let search=try XCTUnwrap(d.state.session.windows[d.window]?.find?.search)
        let request=try XCTUnwrap(d.state.session.windows[d.window]?.find?.request)
        d.system(.find(.matches(request,search,count:6,ordinal:1,passComplete:true)))
        d.system(.find(.invalidated(ticket)))
        XCTAssertEqual(d.view.find?.count,6)
        d.system(.find(.matches(request,search,count:7,ordinal:2,passComplete:true)))
        XCTAssertEqual(d.view.find?.count,7)
    }
    func testNextAfterSearchFailureStartsANewRequestInsteadOfSteppingAnAbsentNativeSession() throws {
        let d=Driver();ready(d);d.user(.find(.open(replace:false)))
        d.user(.find(.query(FindQuery(text:"unsupported"))))
        let request=try XCTUnwrap(d.state.session.windows[d.window]?.find?.request)
        d.system(.find(.failed(request,.unsupported("Unsupported query"))))
        let t=d.user(.find(.step(.next)))
        XCTAssertTrue(t.effects.contains { if case .find(.search) = $0 { true } else { false } })
        XCTAssertFalse(t.effects.contains { if case .find(.step) = $0 { true } else { false } })
    }
    func testPeekEscAndConflictingOverlayRules() throws {
        let d=Driver(); d.user(.peek(.open(url("https://example.com/peek"))))
        let page=try XCTUnwrap(d.view.overlay)
        d.user(.find(.open(replace:false)))
        XCTAssertEqual(d.view.overlay,page); XCTAssertNotNil(d.view.find)
        d.user(.app(.exit)); XCTAssertEqual(d.view.overlay,page); XCTAssertNil(d.view.find)
        d.user(.app(.exit)); XCTAssertNil(d.view.overlay)
        d.user(.find(.open(replace:false))); d.user(.commandBar(.open(.newTab)))
        XCTAssertNil(d.view.find)
        d.user(.find(.open(replace:false))); XCTAssertNil(d.view.overlay)
        d.user(.library(.open(.history))); XCTAssertNil(d.view.find)
    }
    func testSelectionAndMutationRequestsRequireCurrentScopeAndUnconfirmedStaysPending() throws {
        let d=Driver(); ready(d); d.user(.find(.open(replace:true)))
        let f=try XCTUnwrap(d.state.session.windows[d.window]?.find)
        let ticket=SelectionTicket(id:SelectionID("s"),document:try XCTUnwrap(f.document))
        d.system(.find(.selection(try XCTUnwrap(f.capture?.id),ticket,text:"needle",editable:.input)))
        XCTAssertTrue(d.view.find?.canReplace == true)
        let t=d.user(.find(.replaceCurrent("replacement")))
        guard case .find(.replace(let id,_,_,_,_))?=t.effects.first else {return XCTFail("no replacement")}
        d.system(.find(.edited(id,ticket,.unconfirmed)))
        XCTAssertFalse(d.view.find?.canReplace ?? true)
        XCTAssertTrue(d.user(.find(.replaceAll("again"))).effects.isEmpty)
        d.system(.find(.edited(id,ticket,.partial(applied:1,reason:"Page changed"))))
        XCTAssertTrue(d.view.find?.message.contains("Replaced 1") == true)
        d.user(.find(.captureScope)); XCTAssertNotNil(d.state.session.windows[d.window]?.find?.capture)
        d.user(.find(.useSelection)); XCTAssertEqual(d.state.session.windows[d.window]?.find?.capture?.purpose,.selection)
        d.user(.find(.jumpToSelection)); XCTAssertEqual(d.state.session.windows[d.window]?.find?.capture?.purpose,.jump)
    }
    func testClosedBarNextUsesOnlyThatWindowsContextAndTabChangeClosesSession() throws {
        let d=Driver(); d.user(.find(.open(replace:false))); d.user(.find(.query(FindQuery(text:"private-data"))))
        d.user(.find(.close)); d.user(.find(.step(.next)))
        XCTAssertEqual(d.view.find?.query.text,"private-data")
        d.user(.window(.newIncognito))
        let privateID=try XCTUnwrap(d.snapshot.windows.first{ $0.value.kind == .incognito }?.key)
        d.user(.commandBar(.submit("https://example.com/private")),in:privateID)
        d.user(.find(.step(.previous)),in:privateID)
        XCTAssertEqual(d.view(of:privateID).find?.query.text, "")
        d.user(.commandBar(.open(.newTab)));d.user(.commandBar(.submit("https://example.com/new")))
        XCTAssertNil(d.view.find)
    }
}
