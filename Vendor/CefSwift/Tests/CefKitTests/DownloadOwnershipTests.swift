import CCef
import Foundation
import Testing
@testable import CefKit

@MainActor struct DownloadOwnershipTests {
    final class Counts {
        var releases = 0
        var calls = 0
    }
    final class Owner {
        let counts: Counts
        init(_ counts: Counts) { self.counts = counts }
        deinit { counts.releases += 1 }
    }
    @Test func decisionConsumesExactlyOneIncomingReference() {
        let counts = Counts()
        let raw = cefAllocate(cef_before_download_callback_t.self, owner: Owner(counts))
        raw.pointee.cont = { raw, _, _ in
            cefOwner(Owner.self, raw.map(UnsafeMutableRawPointer.init))?.counts.calls += 1
        }
        var callback: CefDownloadDecisionCallback? = CefDownloadDecisionCallback(taking: raw)
        callback?.resolve(URL(fileURLWithPath: "/tmp/fixture"))
        callback?.resolve(nil)
        #expect(counts.calls == 1)
        #expect(counts.releases == 1)
        callback = nil
        #expect(counts.releases == 1)
    }
    @Test func abandonedDecisionReleasesWithoutContinue() {
        let counts = Counts()
        var callback: CefDownloadDecisionCallback? = CefDownloadDecisionCallback(taking: cefAllocate(cef_before_download_callback_t.self, owner: Owner(counts)))
        #expect(callback != nil)
        callback = nil
        #expect(counts.releases == 1)
        #expect(counts.calls == 0)
    }
    @Test func controlCancelDoesNotConsumeTheReferenceAndReleaseIsIdempotent() {
        let counts = Counts()
        let raw = cefAllocate(cef_download_item_callback_t.self, owner: Owner(counts))
        raw.pointee.cancel = { raw in cefOwner(Owner.self, raw.map(UnsafeMutableRawPointer.init))?.counts.calls += 1 }
        var callback: CefDownloadControl? = CefDownloadControl(taking: raw)
        callback?.cancel()
        #expect(counts.calls == 1)
        #expect(counts.releases == 0)
        callback?.release(); callback?.release(); callback?.cancel(); callback = nil
        #expect(counts.releases == 1)
        #expect(counts.calls == 1)
    }
    @Test func missingBrowserBridgeReleasesItemDecisionAndControl() {
        let client = BrowserClient()
        let rawClient = client.makeClient()
        let handler = rawClient.pointee.get_download_handler!(rawClient)!
        let itemCounts = Counts(), controlCounts = Counts(), decisionCounts = Counts()
        let item = cefAllocate(cef_download_item_t.self, owner: Owner(itemCounts))
        let decision = cefAllocate(cef_before_download_callback_t.self, owner: Owner(decisionCounts))
        #expect(handler.pointee.on_before_download?(handler, nil, item, nil, decision) == 1)
        #expect(itemCounts.releases == 1)
        #expect(decisionCounts.releases == 1)
        let item2 = cefAllocate(cef_download_item_t.self, owner: Owner(itemCounts))
        item2.pointee.is_in_progress = { _ in 1 }
        let control = cefAllocate(cef_download_item_callback_t.self, owner: Owner(controlCounts))
        control.pointee.cancel = { raw in cefOwner(Owner.self, raw.map(UnsafeMutableRawPointer.init))?.counts.calls += 1 }
        handler.pointee.on_download_updated?(handler, nil, item2, control)
        #expect(itemCounts.releases == 2)
        #expect(controlCounts.releases == 1)
        #expect(controlCounts.calls == 1)
        cefRelease(UnsafeMutableRawPointer(handler))
        cefRelease(UnsafeMutableRawPointer(rawClient))
        client.releaseHandlers()
    }
}
