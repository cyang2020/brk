import CCef
import Foundation
import Testing
@testable import CefKit

@MainActor struct BrowserBasicOwnershipTests {
    @MainActor final class Delegate: CefBrowserDelegate {
        var decision = CefPreKeyDecision.passThrough
        func browser(_ b: CefBrowser, preKeyEvent event: CefKeyEvent) -> CefPreKeyDecision { decision }
    }
    final class Native {
        var host: UnsafeMutablePointer<cef_browser_host_t>?
        var callback: UnsafeMutablePointer<cef_pdf_print_callback_t>?
        var path = ""
        var background = false
    }

    @Test func preKeyBridgePreservesHandledPassAndShortcutOutParameter() {
        let delegate = Delegate(), client = BrowserClient(), raw = client.makeClient()
        let browser = CefBrowser(raw: nil, client: client, delegate: delegate)
        client.attach(browser)
        let handler = raw.pointee.get_keyboard_handler!(raw)!
        var event = cef_key_event_t()
        event.type = KEYEVENT_RAWKEYDOWN
        for (decision, consumed, out) in [(CefPreKeyDecision.handled, Int32(1), Int32(0)), (.passThrough, 0, 0), (.shortcutAfterPage, 0, 1)] {
            delegate.decision = decision
            var shortcut: Int32 = -1
            #expect(handler.pointee.on_pre_key_event!(handler, nil, &event, nil, &shortcut) == consumed)
            #expect(shortcut == out)
        }
        cefRelease(UnsafeMutableRawPointer(handler)); cefRelease(UnsafeMutableRawPointer(raw)); client.releaseHandlers()
    }

    @Test func pdfOutgoingReferenceKeepsOwnerUntilNativeReleaseAndRepliesOnce() {
        let native = Native()
        let host = cefAllocate(cef_browser_host_t.self, owner: native)
        native.host = host
        host.pointee.print_to_pdf = { host, path, settings, callback in
            let owner = cefOwner(Native.self, host.map(UnsafeMutableRawPointer.init))!
            owner.path = CefStringUtil.string(from: path)
            owner.background = settings?.pointee.print_background == 1
            owner.callback = callback
        }
        let raw = cefAllocate(cef_browser_t.self, owner: native)
        raw.pointee.get_host = { raw in
            let host = cefOwner(Native.self, raw.map(UnsafeMutableRawPointer.init))!.host!
            cefAddRef(UnsafeMutableRawPointer(host)); return host
        }
        let browser = CefBrowser(raw: raw, client: nil, delegate: nil)
        var replies: [Bool] = []
        var output: CefPDFOutput? = browser.printPDF(to: URL(fileURLWithPath: "/tmp/owned-fixture.pdf")) { replies.append($0) }
        weak var retained = output
        output = nil
        #expect(retained != nil)
        #expect(native.path == "/tmp/owned-fixture.pdf" && native.background)
        let callback = native.callback!
        callback.pointee.on_pdf_print_finished!(callback, nil, 1)
        callback.pointee.on_pdf_print_finished!(callback, nil, 0)
        #expect(replies == [true])
        cefRelease(UnsafeMutableRawPointer(callback)); native.callback = nil
        #expect(retained == nil)
        browser.handleBeforeClose()
        native.host = nil; cefRelease(UnsafeMutableRawPointer(host))
    }
}
