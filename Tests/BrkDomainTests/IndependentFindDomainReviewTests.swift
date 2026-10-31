import BrkBase
import XCTest
@testable import BrkDomain

final class IndependentFindDomainReviewTests: XCTestCase {
    func testPendingMutationCannotBeOrphanedByRecapture() throws {
        let d = Driver(), page = PageID(window: d.window, item: d.paneIDs[0])
        let doc = DocumentToken(browser: d.state.session.live[page]!.browser!, sequence: 1)
        d.page(page.item, .documentChanged(.loading(doc)))
        d.page(page.item, .documentChanged(.ready(doc)))
        d.user(.find(.open(replace: true)))
        let ticket = SelectionTicket(id: SelectionID("pending"), document: doc)
        d.system(.find(.selection(try XCTUnwrap(d.state.session.windows[d.window]?.find?.capture?.id), ticket, text: "apple", editable: .input)))
        d.user(.find(.replaceAll("pear")))
        let pending = try XCTUnwrap(d.state.session.windows[d.window]?.find?.operation)
        d.user(.find(.captureScope))
        XCTAssertEqual(d.state.session.windows[d.window]?.find?.operation, pending)
        XCTAssertEqual(d.state.session.windows[d.window]?.find?.ticket, ticket)
        XCTAssertNil(d.state.session.windows[d.window]?.find?.capture)
        d.system(.find(.edited(pending, ticket, .replaced(2))))
        XCTAssertNil(d.state.session.windows[d.window]?.find?.operation)
    }

    func testNewCaptureAfterFrameRetirementMustNotKeepOldOperationLocked() throws {
        let d=Driver(),tab=d.paneIDs[0],page=PageID(window:d.window,item:d.paneIDs[0])
        let doc=DocumentToken(browser:d.state.session.live[page]!.browser!,sequence:1)
        d.page(tab,.documentChanged(.loading(doc)));d.page(tab,.documentChanged(.ready(doc)))
        d.user(.find(.open(replace:true)))
        let old=SelectionTicket(id:SelectionID("old-frame"),document:doc)
        d.system(.find(.selection(try XCTUnwrap(d.state.session.windows[d.window]?.find?.capture?.id),old,text:"apple",editable:.input)))
        d.user(.find(.replaceAll("pear")))
        let pending=try XCTUnwrap(d.state.session.windows[d.window]?.find?.operation)
        d.system(.find(.invalidated(old)))
        // The corrected adapter also settles the retired frame's outstanding mutation.
        d.system(.find(.failed(pending,.failed("Replacement was not confirmed because its frame changed. Select and capture the field again."))))
        d.user(.find(.captureScope))
        let fresh=SelectionTicket(id:SelectionID("new-frame"),document:doc)
        d.system(.find(.selection(try XCTUnwrap(d.state.session.windows[d.window]?.find?.capture?.id),fresh,text:"apple",editable:.input)))
        print("REPRO fresh capture canReplace",d.view.find!.canReplace,"old pending operation",pending,"current operation",String(describing:d.state.session.windows[d.window]?.find?.operation))
        XCTAssertTrue(d.view.find!.canReplace,"fresh valid scope is still locked by a retired frame's operation")
    }
}
