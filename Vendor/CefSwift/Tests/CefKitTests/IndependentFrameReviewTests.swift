import CCef
import Foundation
import Testing
@testable import CefKit

@MainActor struct IndependentFrameReviewTests {
    final class Observer: CefBrowserDelegate {
        var invalidations: [String] = []
        func browser(_ b: CefBrowser, willNavigateFrame identifier: String) { invalidations.append(identifier) }
    }
    final class FrameOwner { var identifierReads = 0 }
    @Test func subframeNavigationMustReachPermissionInvalidation() {
        let delegate = Observer()
        let client = BrowserClient()
        let browser = CefBrowser(raw: nil, client: nil, delegate: delegate)
        client.attach(browser)
        let rawClient = client.makeClient()
        let request = rawClient.pointee.get_request_handler!(rawClient)!
        let load = rawClient.pointee.get_load_handler!(rawClient)!
        let owner = FrameOwner()
        let frame = cefAllocate(cef_frame_t.self, owner: owner)
        frame.pointee.is_main = { _ in 0 }
        frame.pointee.get_identifier = { raw in
            cefOwner(FrameOwner.self, raw.map(UnsafeMutableRawPointer.init))!.identifierReads += 1
            return nil // A read is already sufficient to prove entry into invalidation; no CEF string allocation.
        }
        cefAddRef(UnsafeMutableRawPointer(frame))
        let allowed = request.pointee.on_before_browse!(request, nil, frame, nil, 1, 0)
        cefAddRef(UnsafeMutableRawPointer(frame))
        load.pointee.on_load_start!(load, nil, frame, TT_LINK)
        print("REPRO subframe navigation: allowed=\(allowed), identifierReads=\(owner.identifierReads), invalidations=\(delegate.invalidations.count)")
        #expect(owner.identifierReads > 0, "Successful subframe navigation must identify and cancel the old frame's permission callbacks before allowing another answer")
        cefRelease(UnsafeMutableRawPointer(frame))
        cefRelease(UnsafeMutableRawPointer(request)); cefRelease(UnsafeMutableRawPointer(load))
        cefRelease(UnsafeMutableRawPointer(rawClient)); client.releaseHandlers()
        withExtendedLifetime(browser) {}
    }
}
