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
    func testStoredCaptureProjectsOnlyItsProfileAndOffersTypedOperations() throws {
        let d = Driver(); _ = try ready(d)
        d.user(.capture(.begin(.portrait)))
        d.user(.capture(.select(CaptureRegion(x:0,y:0,width:0.3,height:0.5))))
        let request = try XCTUnwrap(d.view.capture?.request)
        let image = CaptureImage(png:Data([1]),width:720,height:1280,scale:2)
        let record = CaptureRecord(request:request,profile:.default,image:image)
        let file = URL(fileURLWithPath:"/tmp/owned.png")
        d.system(.capture(.stored(request,record,file)))
        d.system(.capture(.loaded(.default,[record],[record.id:file],error:nil)))
        XCTAssertEqual(d.user(.capture(.open(record.id))).effects,[.capture(.open(record,d.window))])
        d.user(.capture(.preview(record.id)))
        guard case .library(let library)? = d.view.overlay else { return XCTFail("Media closed on preview") }
        XCTAssertEqual(library.captures,[record]); XCTAssertEqual(library.captureFiles[record.id],file)
        XCTAssertEqual(d.user(.capture(.export(record.id))).effects,[.capture(.export(record,d.window))])
        XCTAssertEqual(d.user(.capture(.insertInEasel(record.id))).effects,[.capture(.insertInEasel(record,d.window))])
        XCTAssertEqual(d.user(.capture(.remove(record.id))).effects,[.capture(.remove(record))])
        d.system(.capture(.removed(.default,record.id)))
        d.system(.capture(.exported(d.window,"Exported")))
        XCTAssertEqual(try StateCodec.decodeCaptures(StateCodec.encodeCaptures([record])),[record])
    }
    func testLateObservationStartsAutoPiPOnceAndDisablingClosesIt() throws {
        let d = Driver(); let document = try ready(d)
        d.user(.commandBar(.open(.newTab))); d.user(.commandBar(.submit("https://example.com/background")))
        let player = MediaPlayer(id:MediaPlayerID(document:"late",frame:0,element:"video"),kind:.video,paused:false,ended:false)
        let observed = d.page(document.browser.page.item,.mediaChanged(document,[player],error:nil))
        XCTAssertTrue(observed.effects.contains(.page(document.browser.page,.media(MediaControl(document:document,player:player.id,operation:.enterPictureInPicture,userInitiated:false)))))
        XCTAssertTrue(d.page(document.browser.page.item,.mediaChanged(document,[player],error:nil)).effects.isEmpty)
        let disabled = d.user(.settings(.advanced(.autoPictureInPicture(false))))
        XCTAssertTrue(disabled.effects.contains(.page(document.browser.page,.media(MediaControl(document:document,player:player.id,operation:.exitPictureInPicture,userInitiated:false)))))
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
}
