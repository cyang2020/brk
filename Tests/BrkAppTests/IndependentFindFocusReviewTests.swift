import AppKit
import BrkBase
import BrkDomain
import XCTest
@testable import BrkApp

@MainActor final class IndependentFindFocusReviewTests: XCTestCase {
    func testRepeatedFindReclaimsQueryFocusAfterClickingThePage() throws {
        _=NSApplication.shared
        let now=Instant(milliseconds:1790000000000)
        let ctx=Context(now:now,newID:{UUID().uuidString})
        var state=StateCodec.restore(nil,seed:RestoreSeed(startURL:URL(string:"https://example.test/"),contentSize:CGSize(width:1280,height:776)),ctx:ctx).state
        let pc=ProjectionContext(now:now,calendar:Calendar(identifier:.gregorian))
        let initial=project(state,pc),window=initial.windows.keys.first!,page=initial.pages[0].id
        let token=BrowserToken(page:page,generation:1),doc=DocumentToken(browser:token,sequence:1)
        state=reduce(state,.system(.page(token,.browserCreated(.profile(.default),.ready(doc)))),ctx).state
        state=reduce(state,.user(window,.find(.open(replace:false))),ctx).state
        let controller=WindowController(id:window,engine:FakeEngine(),send:{_ in})
        defer{controller.window.orderOut(nil)}
        controller.root.frame=CGRect(x:0,y:0,width:1280,height:776)
        controller.render(project(state,pc).windows[window]!)
        let initialResponder=try XCTUnwrap(controller.window.firstResponder)
        XCTAssertTrue((initialResponder as? NSTextView)?.isFieldEditor == true,"initial Find must focus a real query field editor")
        XCTAssertNotNil(project(state,pc).windows[window]!.find)
        XCTAssertFalse(controller.window.isVisible,"test window must never be shown")
        let pageEditor=NSTextView(frame:CGRect(x:300,y:200,width:100,height:50))
        controller.root.addSubview(pageEditor)
        XCTAssertTrue(controller.window.makeFirstResponder(pageEditor)) // same native responder change as a page click
        state=reduce(state,.user(window,.find(.open(replace:false))),ctx).state
        controller.render(project(state,pc).windows[window]!)
        print("REPRO repeated Find first responder remains page:",controller.window.firstResponder === pageEditor,"snapshot focus:",project(state,pc).windows[window]!.focus,"visible:",controller.window.isVisible)
        XCTAssertFalse(controller.window.firstResponder === pageEditor,"Find did not focus the already-open query")
        XCTAssertTrue(controller.window.firstResponder === initialResponder,"Find did not restore its query field editor")
    }
}
