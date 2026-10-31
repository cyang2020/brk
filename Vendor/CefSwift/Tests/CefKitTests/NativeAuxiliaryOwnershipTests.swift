import CCef
import Foundation
import Testing
@testable import CefKit

@MainActor struct NativeAuxiliaryOwnershipTests {
    @MainActor final class Delegate: CefBrowserDelegate {
        var counts: [Int] = []
        var closed: [(CefBrowser, CefAuxiliaryKind)] = []
        func browser(_ b: CefBrowser, didCloseAuxiliary auxiliary: CefBrowser, kind: CefAuxiliaryKind) { closed.append((auxiliary, kind)) }
        func browser(_ b: CefBrowser, auxiliaryCountChanged count: Int) { counts.append(count) }
    }
    @Test func closeNotifiesTheRootWithTheActualAuxiliaryAndKindExactlyOnce() {
        let owner = BrowserClient(), delegate = Delegate(), raw = owner.makeClient()
        let browser = CefBrowser(raw: nil, client: owner, delegate: delegate)
        owner.attach(browser)
        var request = CefWindowOpenRequest(targetURL: nil, frameName: "adapter-owned", disposition: .newPopup,
            userGesture: true, features: CefPopupFeatures(), isSourceOffscreen: false)
        request.popupID = 78
        var pointer: UnsafeMutablePointer<cef_client_t>?
        owner.installNativeAuxiliary(.popup(request), replacing: &pointer)
        let child = owner.nativeAuxiliaries.values.first!
        let auxiliary = child.pendingOSRBrowser!
        child.attach(auxiliary)
        child.pendingOSRBrowser = nil
        child.didCloseNativeAuxiliary()
        child.didCloseNativeAuxiliary()
        #expect(delegate.closed.count == 1)
        #expect(delegate.closed.first?.0 === auxiliary)
        #expect(delegate.closed.first?.1 == .popup(request))
        #expect(owner.auxiliaryCount == 0)
        #expect(delegate.counts == [1, 0])
        child.releaseHandlers(); cefRelease(pointer.map(UnsafeMutableRawPointer.init))
        owner.releaseHandlers(); cefRelease(UnsafeMutableRawPointer(raw))
    }
    @Test func abortedPopupReleasesPendingWrapperAndKeepsRawRequestIdentity() {
        let owner = BrowserClient(), delegate = Delegate(), raw = owner.makeClient()
        let browser = CefBrowser(raw: nil, client: owner, delegate: delegate)
        owner.attach(browser)
        var request = CefWindowOpenRequest(targetURL: nil, frameName: "empty", disposition: .newPopup, userGesture: true,
            features: CefPopupFeatures(), isSourceOffscreen: false)
        request.popupID = 77; request.sourceFrame = "frame-7"; request.rawDisposition = 5
        var childPointer: UnsafeMutablePointer<cef_client_t>?
        owner.installNativeAuxiliary(.popup(request), replacing: &childPointer)
        weak var child = owner.nativeAuxiliaries.values.first
        #expect(owner.auxiliaryCount == 1)
        #expect(child?.auxiliaryKind == .popup(request))
        #expect(child?.pendingOSRBrowser != nil)
        owner.abortNativePopup(77)
        #expect(owner.auxiliaryCount == 0)
        #expect(delegate.counts == [1, 0])
        cefRelease(childPointer.map(UnsafeMutableRawPointer.init))
        #expect(child == nil)
        owner.releaseHandlers(); cefRelease(UnsafeMutableRawPointer(raw))
    }
}
