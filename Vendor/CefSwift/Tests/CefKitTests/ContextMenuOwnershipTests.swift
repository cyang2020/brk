import CCef
import Foundation
import Testing
@testable import CefKit

@MainActor struct ContextMenuOwnershipTests {
    final class Counts { var freed = 0; var selected = 0; var cancelled = 0; var callback: CefRunContextMenuCallback? }
    final class Owner {
        let counts: Counts
        init(_ counts: Counts) { self.counts = counts }
        deinit { counts.freed += 1 }
    }

    @Test func selectionIsOneShotEvenIfCompletionReentersCancellation() {
        let counts = Counts()
        let raw = cefAllocate(cef_run_context_menu_callback_t.self, owner: Owner(counts))
        raw.pointee.cont = { raw, _, _ in
            MainActor.assumeIsolated {
                let counts = cefOwner(Owner.self, raw.map(UnsafeMutableRawPointer.init))!.counts
                counts.selected += 1
                counts.callback?.cancel()
            }
        }
        raw.pointee.cancel = { raw in cefOwner(Owner.self, raw.map(UnsafeMutableRawPointer.init))?.counts.cancelled += 1 }
        counts.callback = CefRunContextMenuCallback(raw: raw)
        counts.callback?.select(commandID: 42)
        #expect(counts.selected == 1 && counts.cancelled == 0 && counts.freed == 1)
        counts.callback = nil
        #expect(counts.freed == 1)
    }

    @Test func decliningCustomPresentationReleasesWithoutDisconnectingDefault() {
        let counts = Counts()
        let raw = cefAllocate(cef_run_context_menu_callback_t.self, owner: Owner(counts))
        raw.pointee.cancel = { raw in cefOwner(Owner.self, raw.map(UnsafeMutableRawPointer.init))?.counts.cancelled += 1 }
        var callback: CefRunContextMenuCallback? = CefRunContextMenuCallback(raw: raw)
        callback?.discard(); callback = nil
        #expect(counts.freed == 1 && counts.cancelled == 0)
    }

    @Test func contextMenuBridgeReleasesBorrowedFacadeArgumentsAfterTheCallback() {
        let client = BrowserClient(), rawClient = client.makeClient()
        let handler = rawClient.pointee.get_context_menu_handler!(rawClient)!
        let paramsCount = Counts(), modelCount = Counts(), callbackCount = Counts()
        let params = cefAllocate(cef_context_menu_params_t.self, owner: Owner(paramsCount))
        let model = cefAllocate(cef_menu_model_t.self, owner: Owner(modelCount))
        let callback = cefAllocate(cef_run_context_menu_callback_t.self, owner: Owner(callbackCount))
        #expect(handler.pointee.run_context_menu!(handler, nil, nil, params, model, callback) == 0)
        #expect(paramsCount.freed == 1 && modelCount.freed == 1 && callbackCount.freed == 1)
        let p2 = cefAllocate(cef_context_menu_params_t.self, owner: Owner(paramsCount))
        let m2 = cefAllocate(cef_menu_model_t.self, owner: Owner(modelCount))
        handler.pointee.on_before_context_menu!(handler, nil, nil, p2, m2)
        #expect(paramsCount.freed == 2 && modelCount.freed == 2)
        let p3 = cefAllocate(cef_context_menu_params_t.self, owner: Owner(paramsCount))
        _ = handler.pointee.on_context_menu_command!(handler, nil, nil, p3, 1, cef_event_flags_t(rawValue: 0))
        #expect(paramsCount.freed == 3)
        cefRelease(UnsafeMutableRawPointer(handler)); cefRelease(UnsafeMutableRawPointer(rawClient))
        client.releaseHandlers()
    }
}
