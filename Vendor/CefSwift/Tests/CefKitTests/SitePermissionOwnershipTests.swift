import CCef
import Foundation
import Testing
@testable import CefKit

@MainActor struct SitePermissionOwnershipTests {
    final class Counts { var releases = 0; var answers = 0; var mask: UInt32 = 0; var reenter: (() -> Void)? }
    final class Owner {
        let counts: Counts
        init(_ counts: Counts) { self.counts = counts }
        deinit { counts.releases += 1 }
    }
    @Test func permissionAnswerIsOneShotEvenWhenContinuationReenters() {
        let counts = Counts()
        let raw = cefAllocate(cef_permission_prompt_callback_t.self, owner: Owner(counts))
        raw.pointee.cont = { pointer, _ in
            let owner = cefOwner(Owner.self, pointer.map(UnsafeMutableRawPointer.init))!
            owner.counts.answers += 1; owner.counts.reenter?()
        }
        let callback = CefPermissionCallback(prompt: raw)
        counts.reenter = { callback.resolve(.deny); callback.invalidate() }
        callback.resolve(.allow)
        counts.reenter = nil
        #expect(counts.answers == 1)
        #expect(counts.releases == 1)
    }
    @Test func nativeDismissalOnlyReleasesAndNeverContinuesAgain() {
        let counts = Counts()
        let raw = cefAllocate(cef_permission_prompt_callback_t.self, owner: Owner(counts))
        raw.pointee.cont = { pointer, _ in cefOwner(Owner.self, pointer.map(UnsafeMutableRawPointer.init))?.counts.answers += 1 }
        let callback = CefPermissionCallback(prompt: raw)
        callback.invalidate(); callback.resolve(.allow); callback.invalidate()
        #expect(counts.answers == 0)
        #expect(counts.releases == 1)
    }
    @Test func mediaAnswerReturnsTheExactRequestedMaskAndReleasesOnce() {
        let counts = Counts()
        let raw = cefAllocate(cef_media_access_callback_t.self, owner: Owner(counts))
        raw.pointee.cont = { pointer, mask in
            let owner = cefOwner(Owner.self, pointer.map(UnsafeMutableRawPointer.init))!
            owner.counts.answers += 1; owner.counts.mask = mask
        }
        let callback = CefPermissionCallback(media: raw, mask: 3)
        callback.resolve(.allow); callback.resolve(.allow)
        #expect(counts.answers == 1)
        #expect(counts.mask == 3)
        #expect(counts.releases == 1)
    }
    @Test func droppedCallbackReleasesItsIncomingReference() {
        let counts = Counts()
        var callback: CefPermissionCallback? = CefPermissionCallback(prompt: cefAllocate(cef_permission_prompt_callback_t.self, owner: Owner(counts)))
        #expect(callback != nil); callback = nil
        #expect(counts.releases == 1)
        #expect(counts.answers == 0)
    }
    @Test func unknownMediaBitsCannotBecomeAnUnshownCameraGrant() {
        let kinds = CefPermissionKind.fromMediaTypes(0x8000_0003)
        #expect(kinds.contains(.other))
        #expect(kinds.contains(.camera))
        #expect(kinds.contains(.microphone))
    }

    @Test func resourceFilterUsesExactHostBoundariesAndIndependentEnablement() {
        let filter = CefRequestFilter()
        filter.configure(enabled: true, hosts: ["tracker.example"], paths: ["/brk-blocked-tracker/"])
        #expect(filter.blocks(URL(string: "https://sub.tracker.example/script.js")!))
        #expect(!filter.blocks(URL(string: "https://tracker.example.evil/script.js")!))
        #expect(filter.blocks(URL(string: "https://normal.example/brk-blocked-tracker/script.js")!))
        #expect(!filter.blocks(URL(string: "https://normal.example/news")!))
        filter.configure(enabled: false, hosts: ["tracker.example"], paths: [])
        #expect(!filter.blocks(URL(string: "https://tracker.example/script.js")!))
    }
}
