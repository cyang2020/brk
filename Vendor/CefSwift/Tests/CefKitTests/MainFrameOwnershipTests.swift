import CCef
import Foundation
import Testing
@testable import CefKit

@MainActor struct MainFrameOwnershipTests {
    final class Counts { var frameReleases=0; var browserReleases=0; var currentReads=0 }
    final class FrameOwner {
        let counts: Counts
        init(_ counts: Counts) { self.counts=counts }
        deinit { counts.frameReleases += 1 }
    }
    final class BrowserOwner {
        let counts: Counts
        let current: UnsafeMutablePointer<cef_frame_t>
        init(_ counts: Counts, current: UnsafeMutablePointer<cef_frame_t>) { self.counts=counts; self.current=current }
        deinit { cefRelease(UnsafeMutableRawPointer(current)); counts.browserReleases += 1 }
    }
    final class Delegate: CefBrowserDelegate {
        var finished=0
        func browser(_ b: CefBrowser, didFinishMainDocument url: URL?) { finished += 1 }
    }
    private func run(currentCallback: Bool) -> (finished:Int, frames:Int, browsers:Int) {
        let counts=Counts(),client=BrowserClient(),delegate=Delegate()
        let wrapper=CefBrowser(raw:nil,client:client,delegate:delegate);client.attach(wrapper)
        let rawClient=client.makeClient(),load=rawClient.pointee.get_load_handler!(rawClient)!
        let current=cefAllocate(cef_frame_t.self,owner:FrameOwner(counts))
        current.pointee.is_main = { _ in 1 }
        let callback: UnsafeMutablePointer<cef_frame_t>
        if currentCallback { cefAddRef(UnsafeMutableRawPointer(current)); callback=current }
        else { callback=cefAllocate(cef_frame_t.self,owner:FrameOwner(counts));callback.pointee.is_main = {_ in 1} }
        let browser=cefAllocate(cef_browser_t.self,owner:BrowserOwner(counts,current:current))
        browser.pointee.get_main_frame = { raw in
            guard let owner=cefOwner(BrowserOwner.self,raw.map(UnsafeMutableRawPointer.init)) else{return nil}
            owner.counts.currentReads += 1;cefAddRef(UnsafeMutableRawPointer(owner.current));return owner.current
        }
        load.pointee.on_load_end?(load,browser,callback,200)
        client.releaseHandlers();cefRelease(UnsafeMutableRawPointer(load));cefRelease(UnsafeMutableRawPointer(rawClient))
        return (delegate.finished,counts.frameReleases,counts.browserReleases)
    }
    @Test func equivalentFacadesRequireTheSameNonemptyNativeIdentifier() {
        #expect(MainFrameScope.matches("frame-a","frame-a"))
        #expect(!MainFrameScope.matches("frame-a","frame-b"))
        #expect(!MainFrameScope.matches(nil,nil))
        #expect(!MainFrameScope.matches("",""))
    }
    @Test func retiredMainFrameEndDoesNotCompleteItsReplacement() {
        let result=run(currentCallback:false)
        #expect(result.finished == 0)
        #expect(result.frames == 2)
        #expect(result.browsers == 1)
    }
    @Test func currentMainFrameEndCompletesAndReleasesEveryIncomingReference() {
        let result=run(currentCallback:true)
        #expect(result.finished == 1)
        #expect(result.frames == 1)
        #expect(result.browsers == 1)
    }
}
