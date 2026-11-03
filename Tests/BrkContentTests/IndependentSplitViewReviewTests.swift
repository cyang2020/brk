import AppKit
import BrkBase
import BrkLayout
import BrkUIKit
import XCTest
@testable import BrkDomain
@testable import BrkContent
@testable import BrkSidebar

@MainActor
final class IndependentSplitViewReviewTests: XCTestCase {
    @MainActor
    final class Model {
        let context = Context(now: Instant(milliseconds: 1_790_000_000_000), newID: { UUID().uuidString })
        var state: AppState
        let window: WindowID
        let size = CGSize(width: 1280, height: 776)
        init() {
            state = StateCodec.restore(nil, seed: RestoreSeed(startURL: URL(string: "https://test.example/first"),contentSize:CGSize(width:1280,height:776)),ctx:context).state
            window = project(state, ProjectionContext(now:context.now,calendar:.current)).windows.keys.first!
        }
        var view: WindowSnapshot { project(state,ProjectionContext(now:context.now,calendar:.current)).windows[window]! }
        func send(_ command: Command) { state=reduce(state,.user(window,command),context).state }
        func commit() {
            let snapshot=project(state,ProjectionContext(now:context.now,calendar:.current))
            for page in snapshot.pages where page.initialURL != nil {
                let token=BrowserToken(page:page.id,generation:1)
                state=reduce(state,.system(.page(token,.browserCreated(page.context,.unavailable))),context).state
                state=reduce(state,.system(.page(token,.committed(page.initialURL!))),context).state
            }
        }
        func row(_ id: ItemID) -> TabRow? {
            for row in view.space.today.rows {
                if case .tab(let tab)=row,tab.id==id { return tab }
                if case .split(let split)=row,let pane=split.panes.first(where:{$0.id==id}) {return pane}
            }
            return nil
        }
    }
    func testBackgroundSplitCloseKeepsActivePageAndDoesNotLoadHiddenPanes() throws {
        let model=Model(); model.commit()
        for n in 2...3 { model.send(.split(.addPane));model.send(.commandBar(.submit("https://test.example/\(n)")));model.commit() }
        let panes=model.view.content.panes.map(\.tab), split=model.view.content.split!
        model.send(.commandBar(.open(.newTab)));model.send(.commandBar(.submit("https://test.example/foreground")));model.commit()
        let foreground=model.view.content.panes[0].tab
        model.state=StateCodec.restore(StateCodec.encode(model.state),seed:RestoreSeed(startURL:nil,contentSize:model.size),ctx:model.context).state
        let before=project(model.state,ProjectionContext(now:model.context.now,calendar:.current)).pages.map(\.id)
        let segment=SplitSegmentView(dispatch:{model.send($0)})
        segment.render(try XCTUnwrap(model.row(panes[1])),palette:Palette(model.view.theme))
        let close=try XCTUnwrap(segment.subviews.compactMap{$0 as? GlyphButton}.first{$0.accessibilityIdentifier()==ViewID.rowClose(panes[1]).identifier})
        close.action?([])
        let after=project(model.state,ProjectionContext(now:model.context.now,calendar:.current)).pages.map(\.id)
        print("BACKGROUND_CLOSE foreground=\(foreground) split=\(split) actualShown=\(String(describing:model.view.content.split)) beforeDemand=\(before) afterDemand=\(after)")
        XCTAssertEqual(model.view.content.panes.map(\.tab),[foreground],"Closing a background split pane must preserve the unrelated active page")
        XCTAssertEqual(after,before,"Closing an unloaded background pane must not load its hidden siblings")
    }
    func testAdmittedDropPreviewSurvivesUnrelatedPageTitleRender() throws {
        let model=Model(); model.commit(); let target=model.view.content.panes[0].tab
        model.send(.commandBar(.open(.newTab)));model.send(.commandBar(.submit("https://test.example/source")));model.commit()
        let source=model.view.content.panes[0].tab;model.send(.tab(.focus(target)))
        let content=ContentAreaView(dispatch:{model.send($0)})
        func render() { content.render(model.view.content,frames:WindowLayout.compute(model.view,contentSize:model.size),theme:model.view.theme,palette:Palette(model.view.theme),surface:{_ in nil}) }
        render();let capturedOffer=model.view.content.drop?.offers[source];content.beginDrop(source)
        let frames=WindowLayout.compute(model.view,contentSize:model.size)
        let point=CGPoint(x:frames.contentArea.maxX-12,y:frames.contentArea.midY)
        XCTAssertNotNil(content.dropCommand(source,at:point))
        let preview=try XCTUnwrap(content.subviews.first{$0.accessibilityIdentifier()==ViewID.splitDropPreview.identifier})
        XCTAssertFalse(preview.isHidden)
        let page=PageID(window:model.window,item:target),token=model.state.session.live[PageID(window:model.window,item:target)]!.browser!
        model.state=reduce(model.state,.system(.page(token,.titleChanged("Tick"))),model.context).state
        render()
        XCTAssertEqual(model.view.content.drop?.offers[source],capturedOffer)
        print("PREVIEW_RENDER page=\(page) offerStillValid=\(model.view.content.drop?.offers[source] != nil) previewHidden=\(preview.isHidden)")
        XCTAssertFalse(preview.isHidden,"A title update must not erase valid stationary drag feedback")
        XCTAssertNotNil(content.dropCommand(source,at:point),"Release is still admitted at the now invisible target")
    }
    func testBackgroundPinnedPaneCloseSeparatesWithoutLoadingOrChangingSelection() throws {
        let model=Model();model.commit()
        for n in 2...3 { model.send(.split(.addPane));model.send(.commandBar(.submit("https://test.example/pinned-\(n)")));model.commit() }
        let panes=model.view.content.panes.map(\.tab),split=model.view.content.split!
        model.send(.tab(.togglePin(.focused)))
        model.send(.commandBar(.open(.newTab)));model.send(.commandBar(.submit("https://test.example/foreground")));model.commit()
        let foreground=model.view.content.panes[0].tab
        model.state=StateCodec.restore(StateCodec.encode(model.state),seed:RestoreSeed(startURL:nil,contentSize:model.size),ctx:model.context).state
        let before=project(model.state,ProjectionContext(now:model.context.now,calendar:.current)).pages.map(\.id)
        guard case .split(let row)=try XCTUnwrap(model.view.space.pinned.rows.first),let pane=row.panes.first(where:{$0.id==panes[1]}) else {return XCTFail("missing pinned fixture")}
        let segment=SplitSegmentView(dispatch:{model.send($0)})
        segment.render(pane,palette:Palette(model.view.theme))
        try XCTUnwrap(segment.subviews.compactMap{$0 as? GlyphButton}.first{$0.accessibilityIdentifier()==ViewID.rowClose(panes[1]).identifier}).action?([])
        XCTAssertEqual(model.view.content.panes.map(\.tab),[foreground])
        XCTAssertEqual(model.view.space.pinned.rows.map(\.id),[split,panes[1]])
        XCTAssertEqual(project(model.state,ProjectionContext(now:model.context.now,calendar:.current)).pages.map(\.id),before)
        guard model.view.space.pinned.rows.count > 1, case .tab(let retained)=model.view.space.pinned.rows[1] else{return XCTFail("closed pinned pane was lost")}
        XCTAssertEqual(retained.url,pane.url)
    }
    func testCancelledDropPreviewDoesNotReappearOnRender() throws {
        let model=Model();model.commit();let target=model.view.content.panes[0].tab
        model.send(.commandBar(.open(.newTab)));model.send(.commandBar(.submit("https://test.example/source")));model.commit()
        let source=model.view.content.panes[0].tab;model.send(.tab(.focus(target)))
        let content=ContentAreaView(dispatch:{model.send($0)})
        func render(){content.render(model.view.content,frames:WindowLayout.compute(model.view,contentSize:model.size),theme:model.view.theme,palette:Palette(model.view.theme),surface:{_ in nil})}
        render();content.beginDrop(source)
        let area=WindowLayout.compute(model.view,contentSize:model.size).contentArea
        let point=CGPoint(x:area.maxX-12,y:area.midY)
        XCTAssertNotNil(content.dropCommand(source,at:point))
        let preview=try XCTUnwrap(content.subviews.first{$0.accessibilityIdentifier()==ViewID.splitDropPreview.identifier})
        XCTAssertFalse(preview.isHidden)
        content.endDrop();render()
        XCTAssertTrue(preview.isHidden)
        XCTAssertNil(content.dropCommand(source,at:point))
    }

}
