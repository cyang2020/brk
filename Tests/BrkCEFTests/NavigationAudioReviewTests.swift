import BrkBase
import Foundation
import XCTest
@testable import BrkCEF

// Only the event plumbing from ChromePage.emit/prepareNavigation is repeated here.
// AudioObservation and MainDocumentState themselves compile unchanged from final Git blobs.
final class NavigationAudioReviewTests: XCTestCase {
    let browser = BrowserToken(page: PageID(window: WindowID("window"), item: ItemID("playing")), generation: 1)
    let url = URL(string: "https://fixture.invalid/playing")!
    func deliver(_ events: [PageEvent], to audio: inout AudioObservation) {
        for event in events { if case .documentChanged(let document) = event { audio.document(document) } }
    }
    func testExplicitSameDocumentNavigationKeepsAudioObservable() throws {
        var doc = MainDocumentState(browser: browser)
        var audio = AudioObservation(browser: browser, context: .profile(.default))
        audio.bind("native-target")
        deliver(doc.started(url), to: &audio); deliver(doc.finished(url), to: &audio)
        XCTAssertTrue(audio.accept(true, tab: 9, for: try XCTUnwrap(audio.ticket)))
        let old = try XCTUnwrap(audio.ticket)
        // CEFEngine.perform(.navigate/.goBack/.goForward) calls ChromePage.prepareNavigation.
        audio.navigationRequested(); doc.prepareNavigation()
        // The pinned CEF header explicitly excludes same-page moves from OnLoadStart/OnLoadEnd.
        let fragment = URL(string: url.absoluteString + "#chapter")!
        let events = doc.addressChanged(fragment, loading: false)
        deliver(events, to: &audio); deliver(doc.loadingChanged(false), to: &audio)
        XCTAssertEqual(events.last, .committed(fragment))
        XCTAssertFalse(audio.accept(true, tab: 9, for: old), "Old reply must still be rejected")
        print("REPRO same-document: committed=true documentChanged=\(events.contains { if case .documentChanged = $0 { true } else { false } }) ticket=\(String(describing: audio.ticket)) audible=\(audio.audible)")
        XCTAssertNotNil(audio.ticket, "The same live document remains able to play; it needs a fresh audio ticket")
        // Control: an actual cross-document load is the only recovery path here.
        deliver(doc.started(url), to: &audio)
        XCTAssertNotNil(audio.ticket)
        print("CONTROL subsequent cross-document start restores ticket=true")
    }
    func testAttachmentAbortPreservesDocumentAndAudioObservation() throws {
        var doc = MainDocumentState(browser: browser)
        var audio = AudioObservation(browser: browser, context: .profile(.default))
        audio.bind("native-target")
        deliver(doc.started(url), to: &audio); deliver(doc.finished(url), to: &audio)
        XCTAssertTrue(audio.accept(true, tab: 9, for: try XCTUnwrap(audio.ticket)))
        audio.navigationRequested(); doc.prepareNavigation()
        let attachment = URL(string: "https://fixture.invalid/download")!
        deliver(doc.allowed(attachment, redirect: false), to: &audio)
        deliver(doc.addressChanged(attachment, loading: true), to: &audio)
        let aborted = doc.loadFailed(code: -3, description: "attachment", url: attachment.absoluteString)
        deliver(aborted, to: &audio); deliver(doc.loadingChanged(false), to: &audio)
        XCTAssertTrue(aborted.isEmpty)
        print("REPRO attachment-abort: documentPreserved=true ticket=\(String(describing: audio.ticket)) audible=\(audio.audible)")
        XCTAssertNotNil(audio.ticket, "The preserved original document still needs audio observations")
    }
}
