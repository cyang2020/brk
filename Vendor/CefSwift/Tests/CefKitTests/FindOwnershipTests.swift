import CCef
import Foundation
import Testing
@testable import CefKit

@MainActor struct FindOwnershipTests {
    final class Delegate: CefBrowserDelegate {
        var results: [(Int,Int,Int,Bool)] = []
        func browser(_ b: CefBrowser, findResult identifier: Int, count: Int, ordinal: Int, final: Bool) {
            results.append((identifier,count,ordinal,final))
        }
        func browser(_ b: CefBrowser, preKeyEvent event: CefKeyEvent) -> CefKeyDisposition {
            CefKeyDisposition(handled:false,shortcut:true)
        }
    }
    final class Count { var released = 0 }
    final class Owner {
        let count: Count
        init(_ count: Count) {self.count=count}
        deinit {count.released += 1}
    }
    @Test func findHandlerReleasesIncomingBrowserAndAllInitialReferences() {
        let client=BrowserClient(), delegate=Delegate(), count=Count()
        let browser=CefBrowser(raw:nil,client:client,delegate:delegate);client.attach(browser)
        let raw=client.makeClient()
        let find=raw.pointee.get_find_handler?(raw)
        #expect(find != nil)
        let incoming=cefAllocate(cef_browser_t.self,owner:Owner(count))
        find?.pointee.on_find_result?(find,incoming,41,7,nil,3,1)
        #expect(count.released == 1)
        #expect(delegate.results.first?.0 == 41)
        #expect(delegate.results.first?.1 == 7)
        client.releaseHandlers()
        #expect(client.findPointer == nil)
        cefRelease(find.map(UnsafeMutableRawPointer.init));cefRelease(UnsafeMutableRawPointer(raw))
    }
    @Test func preKeyOutParameterPreservesRendererFirstDispatch() {
        let client=BrowserClient(),delegate=Delegate(),count=Count()
        let browser=CefBrowser(raw:nil,client:client,delegate:delegate);client.attach(browser)
        let raw=client.makeClient(), keyboard=client.keyboardPointer!
        let incoming=cefAllocate(cef_browser_t.self,owner:Owner(count))
        var event=cef_key_event_t(), shortcut:Int32=0
        event.type=KEYEVENT_RAWKEYDOWN
        let handled=keyboard.pointee.on_pre_key_event?(keyboard,incoming,&event,nil,&shortcut)
        #expect(handled == 0);#expect(shortcut == 1);#expect(count.released == 1)
        client.releaseHandlers();cefRelease(UnsafeMutableRawPointer(raw))
    }
}
