import CCef
import Foundation
import Testing
@testable import CefKit

@MainActor private enum ReentryFixture {
    static var current: Counts?
    final class Counts {
        var control: CefDownloadControl?
        var destroyed = false
        var destroyedInsideCall = false
    }
    final class Owner {
        let counts: Counts
        init(_ counts: Counts) { self.counts = counts }
        deinit { counts.destroyed = true }
    }
}

@MainActor struct ControlReentryTests {
    @Test func cancelKeepsTheNativeObjectAliveIfItsOwnerReleasesDuringTheCall() {
        let counts = ReentryFixture.Counts()
        ReentryFixture.current = counts
        defer { ReentryFixture.current = nil; counts.control = nil }
        let raw = cefAllocate(cef_download_item_callback_t.self, owner: ReentryFixture.Owner(counts))
        raw.pointee.cancel = { _ in
            MainActor.assumeIsolated {
                let counts = ReentryFixture.current!
                counts.control?.release()
                counts.destroyedInsideCall = counts.destroyed
            }
        }
        counts.control = CefDownloadControl(taking: raw)
        counts.control?.cancel()
        #expect(!counts.destroyedInsideCall, "the native callback must survive until cancel returns")
        #expect(counts.destroyed)
    }
}
