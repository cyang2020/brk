import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

final class CaptureTests: XCTestCase {
    private func ready(_ d: Driver) throws -> DocumentToken {
        let tab = d.todayIDs[0], page = PageID(window: d.window, item: tab)
        let document = DocumentToken(browser: try XCTUnwrap(d.state.session.live[page]?.browser), sequence: 1)
        d.page(tab, .documentChanged(.loading(document))); d.page(tab, .documentChanged(.ready(document)))
        return document
    }
    func testSelectionCancellationAndNavigationRejectOldPixels() throws {
        let d = Driver(); let document = try ready(d)
        d.user(.capture(.begin(.area)))
        XCTAssertEqual(d.view.focus, .capture)
        let selected = d.user(.capture(.select(CaptureRegion(x:0.1,y:0.1,width:0.3,height:0.2))))
        guard case .capture(.render(let request))? = selected.effects.first else { return XCTFail("No capture") }
        d.user(.capture(.cancel))
        let image = CaptureImage(png: Data([1]), width: 10, height: 10, scale: 2)
        XCTAssertTrue(d.system(.capture(.rendered(request, image))).effects.isEmpty)
        d.user(.capture(.begin(.area)))
        let fragment = URL(string:"https://example.com/#capture-race")!
        d.page(document.browser.page.item,.navigationRequested(fragment))
        XCTAssertNil(d.view.capture,"A same-document navigation request must cancel capture before document replacement")
        d.page(document.browser.page.item,.committed(fragment))
        d.user(.capture(.begin(.fullPage)))
        let next = DocumentToken(browser: document.browser, sequence: 2)
        d.page(document.browser.page.item, .documentChanged(.loading(next)))
        XCTAssertNil(d.view.capture)
        XCTAssertTrue(d.system(.capture(.rendered(request, image))).effects.isEmpty)
        XCTAssertFalse(String(decoding:d.savedFile,as:UTF8.self).contains("capturePreview"))
    }
    func testAutomaticPiPSelectsPlayingVideoAndReattachesWithoutForgingActivation() throws {
        let d = Driver(); let document = try ready(d)
        let player = MediaPlayer(id:MediaPlayerID(document:"frame",frame:0,element:"video"),kind:.video,paused:false,ended:false)
        d.page(document.browser.page.item,.mediaChanged(document,[player],error:nil))
        d.user(.page(.pictureInPicture(.document)))
        d.page(document.browser.page.item,.documentPictureInPictureChanged(document,true,error:nil))
        d.user(.commandBar(.open(.newTab)))
        let left = d.user(.commandBar(.submit("https://example.com/next")))
        XCTAssertTrue(left.effects.contains(.page(document.browser.page,.media(MediaControl(document:document,player:player.id,operation:.enterPictureInPicture,userInitiated:false)))))
        let returned = d.user(.tab(.focus(document.browser.page.item)))
        XCTAssertTrue(returned.effects.contains(.page(document.browser.page,.media(MediaControl(document:document,player:player.id,operation:.exitPictureInPicture,userInitiated:false)))))
        var rule = SiteRule(); rule.pictureInPictureExempt = true
        if let target = d.state.siteTarget(in:d.window) { d.user(.site(.rule(target,rule))) }
        d.user(.commandBar(.open(.newTab)))
        let exempt = d.user(.commandBar(.submit("https://example.com/third")))
        XCTAssertFalse(exempt.effects.contains { if case .page(_, .media(let request)) = $0 { request.operation == .enterPictureInPicture } else { false } })
    }

    private func rendered(_ d: Driver, _ mode: CaptureMode) throws -> (CaptureRequest, CaptureImage) {
        d.user(.capture(.begin(mode)))
        if mode != .fullPage { d.user(.capture(.select(CaptureRegion(x:0.2,y:0.2,width:0.3,height:0.3)))) }
        let request = try XCTUnwrap(d.view.capture?.request)
        if mode == .fullPage { XCTAssertEqual(d.view.tabTools.toast?.text,"Capture in Progress…") }
        let image = CaptureImage(png:Data([7]),width:300,height:200,scale:2)
        d.system(.capture(.rendered(request,image)))
        return (request,image)
    }
    func testReleasingASelectionOpensTheMenuAndEachRowActs() throws {
        let d = Driver(); _ = try ready(d)
        var (request,image) = try rendered(d,.area)
        XCTAssertEqual(d.view.capture?.image,image,"the menu card opens with the pixels in memory")
        XCTAssertNil(d.view.overlay,"Arc stays on the page")
        XCTAssertEqual(d.user(.capture(.act(.copy))).effects,[.capture(.copy(image))])
        XCTAssertNil(d.view.capture)
        XCTAssertEqual(d.view.tabTools.toast?.text,"Screenshot Copied to Clipboard")
        (request,image) = try rendered(d,.area)
        XCTAssertEqual(d.user(.capture(.act(.file))).effects,[.capture(.saveFile(request,image,d.window))])
        XCTAssertNil(d.view.capture)
        (request,image) = try rendered(d,.area)
        d.user(.capture(.act(.retake)))
        XCTAssertNil(d.view.capture?.image); XCTAssertNil(d.view.capture?.request.region)
        XCTAssertFalse(d.user(.capture(.select(CaptureRegion(x:0,y:0,width:0.5,height:0.5)))).effects.isEmpty,"Retake drags again")
        let again = try XCTUnwrap(d.view.capture?.request)
        d.system(.capture(.rendered(again,image)))
        XCTAssertEqual(d.user(.capture(.act(.library))).effects,[.capture(.store(again,image))])
        XCTAssertTrue(d.state.captureAwaitsStore(again))
        XCTAssertTrue(d.user(.capture(.act(.copy))).effects.isEmpty,"the menu is closed while its row runs")
        let record = CaptureRecord(request:again,profile:.default,image:image)
        d.system(.capture(.stored(again,record,URL(fileURLWithPath:"/tmp/saved.png"))))
        XCTAssertNil(d.view.capture); XCTAssertNil(d.view.overlay)
        XCTAssertEqual(d.view.tabTools.toast?.text,"Saved to Library")
        (request,image) = try rendered(d,.area)
        d.user(.capture(.act(.edit)))
        d.system(.capture(.stored(request,CaptureRecord(request:request,profile:.default,image:image),URL(fileURLWithPath:"/tmp/edit.png"))))
        guard case .library(let library)? = d.view.overlay else { return XCTFail("Edit opens the capture in Media") }
        XCTAssertEqual(library.capturePreview,request.id)
    }
    func testFullPageCopiesAndTheToastSaveStoresItInTheLibrary() throws {
        let d = Driver(); _ = try ready(d)
        d.user(.capture(.begin(.fullPage)))
        let request = try XCTUnwrap(d.view.capture?.request)
        let image = CaptureImage(png:Data([9]),width:1200,height:6000,scale:2)
        XCTAssertTrue(d.system(.capture(.rendered(request,image))).effects.contains(.capture(.copy(image))))
        XCTAssertNil(d.view.capture,"no overlay and no Library after a full-page capture")
        XCTAssertNil(d.view.overlay)
        let toast = try XCTUnwrap(d.view.tabTools.toast)
        XCTAssertEqual(toast.text,"Screenshot Copied to Clipboard")
        XCTAssertEqual(toast.action,ToastAction(title:"Save",command:.capture(.act(.library))))
        XCTAssertEqual(d.user(.capture(.act(.library))).effects,[.capture(.store(request,image))])
        XCTAssertTrue(d.state.captureAwaitsStore(request))
        d.user(.tabTools(.dismissToast))
        XCTAssertTrue(d.state.captureAwaitsStore(request),"dismissing the toast does not drop a write in flight")
        d.system(.capture(.stored(request,CaptureRecord(request:request,profile:.default,image:image),URL(fileURLWithPath:"/tmp/full.png"))))
        XCTAssertFalse(d.state.captureAwaitsStore(request))
        XCTAssertEqual(d.view.tabTools.toast?.text,"Saved to Library")
        d.user(.capture(.begin(.fullPage)))
        let next = try XCTUnwrap(d.view.capture?.request)
        d.system(.capture(.rendered(next,image)))
        d.user(.tabTools(.dismissToast))
        XCTAssertFalse(d.state.captureAwaitsStore(next),"an unsaved copy is forgotten with its toast")
        XCTAssertTrue(d.user(.capture(.act(.library))).effects.isEmpty)
    }
    func testPrivateCapturesOfferCopyAndSaveButNeverTheLibrary() throws {
        let d = Driver(); _ = try ready(d)
        d.user(.window(.newIncognito))
        let window = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .incognito }?.id)
        d.user(.commandBar(.submit("https://example.com/private")), in: window)
        let tab = try XCTUnwrap(d.state.resolveTab(.focused, in: window)), page = PageID(window: window, item: tab)
        let document = DocumentToken(browser: try XCTUnwrap(d.state.session.live[page]?.browser), sequence: 1)
        d.page(tab, .documentChanged(.loading(document)), in: window)
        d.page(tab, .committed(URL(string: "https://example.com/private")!), in: window)
        d.page(tab, .documentChanged(.ready(document)), in: window)
        d.user(.capture(.begin(.area)), in: window)
        d.user(.capture(.select(CaptureRegion(x:0,y:0,width:0.5,height:0.5))), in: window)
        let request = try XCTUnwrap(d.view(of: window).capture?.request)
        let image = CaptureImage(png:Data([3]),width:10,height:10,scale:2)
        d.system(.capture(.rendered(request,image)))
        XCTAssertEqual(d.view(of: window).capture?.canSaveToLibrary, false)
        XCTAssertTrue(d.user(.capture(.act(.library)), in: window).effects.isEmpty)
        XCTAssertTrue(d.user(.capture(.act(.edit)), in: window).effects.isEmpty)
        XCTAssertEqual(d.user(.capture(.act(.copy)), in: window).effects,[.capture(.copy(image))])
        XCTAssertEqual(d.user(.capture(.act(.library)), in: window).effects,[.capture(.saveFile(request,image,window))],"the toast's Save asks for a file in a private window")
    }
}
