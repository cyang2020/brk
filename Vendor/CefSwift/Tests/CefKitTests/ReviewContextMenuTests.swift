import CCef
import Foundation
import Testing
@testable import CefKit

@MainActor struct ReviewContextMenuTests {
    @Test func windowedMenuMustAllowTheExistingNativeDefault() {
        let client = BrowserClient()
        let rawClient = client.makeClient()
        let browser = CefBrowser(raw: nil, client: client, delegate: nil)
        client.attach(browser)
        let handler = rawClient.pointee.get_context_menu_handler!(rawClient)!
        let model = cefAllocate(cef_menu_model_t.self, owner: client)
        let callback = cefAllocate(cef_run_context_menu_callback_t.self, owner: client)
        let handled = handler.pointee.run_context_menu!(handler, nil, nil, nil, model, callback)
        print("REPRO windowed run_context_menu handled =", handled)
        #expect(handled == 0, "Windowed Brk must fall through to CEF's native menu")
        cefRelease(UnsafeMutableRawPointer(handler))
        cefRelease(UnsafeMutableRawPointer(rawClient))
        client.releaseHandlers()
        withExtendedLifetime(browser) {}
    }
}
