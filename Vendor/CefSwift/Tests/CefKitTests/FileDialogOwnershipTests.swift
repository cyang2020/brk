import CCef
import Foundation
import Testing
@testable import CefKit

@MainActor struct FileDialogOwnershipTests {
    final class Counts { var releases = 0; var cancels = 0; var reenter: (() -> Void)? }
    final class Owner {
        let counts: Counts
        init(_ counts: Counts) { self.counts = counts }
        deinit { counts.releases += 1 }
    }
    @Test func cancelIsOneShotAcrossNativeReentry() {
        let counts = Counts()
        let raw = cefAllocate(cef_file_dialog_callback_t.self, owner: Owner(counts))
        raw.pointee.cancel = { pointer in
            let owner = cefOwner(Owner.self, pointer.map(UnsafeMutableRawPointer.init))!
            owner.counts.cancels += 1; owner.counts.reenter?()
        }
        let callback = CefFileDialogCallback(taking: raw)
        counts.reenter = { callback.cancel() }
        callback.cancel(); counts.reenter = nil
        #expect(counts.cancels == 1)
        #expect(counts.releases == 1)
    }
    @Test func decliningCustomHandlingKeepsTheNativeDefaultConnected() {
        let counts = Counts()
        let raw = cefAllocate(cef_file_dialog_callback_t.self, owner: Owner(counts))
        raw.pointee.cancel = { pointer in cefOwner(Owner.self, pointer.map(UnsafeMutableRawPointer.init))?.counts.cancels += 1 }
        let client = BrowserClient(), browser = CefBrowser(raw: nil, client: nil, delegate: nil)
        client.attach(browser)
        let rawClient = client.makeClient()
        let handler = rawClient.pointee.get_dialog_handler!(rawClient)!
        #expect(handler.pointee.on_file_dialog?(handler, nil, FILE_DIALOG_OPEN_FOLDER, nil, nil, nil, nil, nil, raw) == 0)
        #expect(counts.cancels == 0)
        #expect(counts.releases == 1)
        cefRelease(UnsafeMutableRawPointer(handler)); cefRelease(UnsafeMutableRawPointer(rawClient)); client.releaseHandlers()
    }
    @Test func abandonedIncomingReferenceIsReleased() {
        let counts = Counts()
        var callback: CefFileDialogCallback? = CefFileDialogCallback(taking: cefAllocate(cef_file_dialog_callback_t.self, owner: Owner(counts)))
        #expect(callback != nil); callback = nil
        #expect(counts.releases == 1)
    }
}
