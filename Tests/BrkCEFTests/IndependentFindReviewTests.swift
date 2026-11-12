import BrkBase
import CCef
import Foundation
import XCTest
@testable import CefKit
@testable import BrkCEF
@testable import BrkEngine

@MainActor final class IndependentFindReviewTests: XCTestCase {
    final class Native {
        var focused = "a"
        var frames: [String: UnsafeMutablePointer<cef_frame_t>] = [:]
        var host: UnsafeMutablePointer<cef_browser_host_t>!
        var browser: CefBrowser!
        var calls: [(String,Int32,Int32)] = []
        var stops: [Int32] = []
        var sent: [(String,String)] = []
        var updates: [FindUpdate] = []
        let doc = DocumentToken(browser:BrowserToken(page:PageID(window:WindowID("w"),item:ItemID("p")),generation:1),sequence:1)
        var adapter: PageFind!
        static func string(_ s: String) -> cef_string_userfree_t {
            let p=malloc(MemoryLayout<cef_string_t>.stride)!.assumingMemoryBound(to:cef_string_t.self)
            p.initialize(to:cef_string_t());CefStringUtil.set(s,into:&p.pointee);return p
        }
        @MainActor func setup() throws {
            if ccef_is_framework_loaded()==0 {
                let root=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                let path=root.appendingPathComponent("dist/Brk.app/Contents/Frameworks/Chromium Embedded Framework.framework/Chromium Embedded Framework").path
                guard FileManager.default.fileExists(atPath:path) else { throw XCTSkip("Build the CEF bundle before running raw adapter fixtures") }
                guard ccef_load_framework(path)==1 else { throw NSError(domain:"FindFixture",code:1,userInfo:[NSLocalizedDescriptionKey:String(cString:ccef_loader_error())]) }
                _=cef_api_hash(14800,0)
            }
            for id in ["a","b"] {
                let frame=cefAllocate(cef_frame_t.self,owner:FrameOwner(self,id));frames[id]=frame
                frame.pointee.is_valid={_ in 1}
                frame.pointee.get_identifier={ raw in Native.string(cefOwner(FrameOwner.self,raw.map(UnsafeMutableRawPointer.init))!.id) }
                frame.pointee.send_process_message={raw,_,msg in
                    let owner=cefOwner(FrameOwner.self,raw.map(UnsafeMutableRawPointer.init))!
                    if let msg,let input=CefRendererMessage.read(msg,frame:raw!) {owner.native.sent.append((owner.id,input.request))}
                    cefRelease(msg.map(UnsafeMutableRawPointer.init))
                }
            }
            host=cefAllocate(cef_browser_host_t.self,owner:self)
            host.pointee.find={raw,text,forward,_,next in
                let n=cefOwner(Native.self,raw.map(UnsafeMutableRawPointer.init))!
                n.calls.append((CefStringUtil.string(from:text),forward,next))
            }
            host.pointee.stop_finding={raw,clear in cefOwner(Native.self,raw.map(UnsafeMutableRawPointer.init))!.stops.append(clear)}
            let raw=cefAllocate(cef_browser_t.self,owner:self)
            raw.pointee.get_host={raw in let h=cefOwner(Native.self,raw.map(UnsafeMutableRawPointer.init))!.host!;cefAddRef(UnsafeMutableRawPointer(h));return h}
            raw.pointee.get_focused_frame={raw in
                let n=cefOwner(Native.self,raw.map(UnsafeMutableRawPointer.init))!;let f=n.frames[n.focused]!;cefAddRef(UnsafeMutableRawPointer(f));return f
            }
            raw.pointee.get_frame_by_identifier={raw,id in
                let n=cefOwner(Native.self,raw.map(UnsafeMutableRawPointer.init))!;guard let f=n.frames[CefStringUtil.string(from:id)] else{return nil};cefAddRef(UnsafeMutableRawPointer(f));return f
            }
            browser=CefBrowser(raw:raw,client:nil,delegate:nil)
            browser.receiveRenderer(CefRendererMessage(frame:"a",document:"doc-a",kind:"created",request:"",payload:""))
            browser.receiveRenderer(CefRendererMessage(frame:"b",document:"doc-b",kind:"created",request:"",payload:""))
            adapter=PageFind(browser:browser) {[weak self] in self?.updates.append($0)}
            adapter.observe(.documentChanged(.ready(doc)))
        }
        @MainActor func reply(_ request: String,frame: String="a",payload: String) {
            adapter.receive(CefRendererMessage(frame:frame,document:"doc-"+frame,kind:"result",request:request,payload:payload))
        }
        @MainActor func capture(_ id:String="capture") -> SelectionTicket {
            adapter.perform(.captureSelection(FindRequestID(id),doc))
            reply(id,payload:#"{"status":"selection","text":"apple","editable":"input"}"#)
            guard case .selection(_,let ticket,_,_)=updates.last! else {fatalError("no ticket")};return ticket
        }
        @MainActor func cleanup() {
            adapter.invalidate();adapter=nil;browser.handleBeforeClose();browser=nil
            for f in frames.values {cefRelease(UnsafeMutableRawPointer(f))};frames.removeAll()
            cefRelease(UnsafeMutableRawPointer(host));host=nil
        }
    }
    final class FrameOwner {
        let native: Native;let id: String
        init(_ native:Native,_ id:String){self.native=native;self.id=id}
    }
    func testCaptureReplyAfterFocusMovesMustNotPublishOldFrameSelection() throws {
        let n=Native();try n.setup();defer{n.cleanup()}
        n.adapter.perform(.captureSelection(FindRequestID("capture"),n.doc))
        n.focused="b"
        n.reply("capture",payload:#"{"status":"selection","text":"old frame text","editable":"input"}"#)
        print("REPRO late capture after focus changed:",n.updates)
        XCTAssertFalse(n.updates.contains{if case .selection = $0 {true}else{false}},"old focused frame selection reached UI")
    }
    func testOutOfOrderCapturesMustNotOverwriteNewerSelection() throws {
        let n=Native();try n.setup();defer{n.cleanup()}
        n.adapter.perform(.captureSelection(FindRequestID("old"),n.doc))
        n.focused="b"
        n.adapter.perform(.captureSelection(FindRequestID("new"),n.doc))
        n.reply("new",frame:"b",payload:#"{"status":"selection","text":"new","editable":"input"}"#)
        guard case .selection(_,let ticket,_,_)=n.updates.last! else{return XCTFail("no new ticket")}
        n.reply("old",payload:#"{"status":"selection","text":"old","editable":"input"}"#)
        let s=SearchToken(id:SearchID("search"),document:n.doc)
        n.adapter.perform(.search(FindRequestID("scoped"),s,FindQuery(text:"new"),.editable(ticket)))
        print("REPRO newer selection after old reply:",n.updates.last!)
        XCTAssertFalse(n.updates.contains{if case .failed(FindRequestID("scoped"),.staleSelection) = $0 {true}else{false}},"late capture overwrote newest adapter ticket")
    }
    func testFrameRetirementMustSettleItsPendingMutation() throws {
        let n=Native();try n.setup();defer{n.cleanup()}
        let ticket=n.capture()
        n.adapter.perform(.replace(FindRequestID("edit"),ticket,FindQuery(text:"apple"),replacement:"pear",all:true))
        n.browser.receiveRenderer(CefRendererMessage(frame:"a",document:"doc-a",kind:"released",request:"",payload:""))
        n.adapter.receive(CefRendererMessage(frame:"a",document:"doc-a",kind:"released",request:"",payload:""))
        print("REPRO pending edit after frame retirement:",n.updates)
        XCTAssertTrue(n.updates.contains{switch $0 {case .edited(FindRequestID("edit"),_,_),.failed(FindRequestID("edit"),_):true;default:false}},"pending mutation silently discarded and timeout cancelled")
    }
    func testNativeRefreshMustPreservePendingPreviousDirection() async throws {
        let n=Native();try n.setup();defer{n.cleanup()}
        let search=SearchToken(id:SearchID("page-search"),document:n.doc)
        n.adapter.perform(.search(FindRequestID("first"),search,FindQuery(text:"apple"),.page))
        try? await Task.sleep(for:.milliseconds(30))
        for (frame,id) in n.sent {n.reply(id,frame:frame,payload:#"{"status":"revision","revision":0}"#)}
        try? await Task.sleep(for:.milliseconds(120))
        XCTAssertEqual(n.calls.count,1)
        n.adapter.nativeResult(id:17,count:3,ordinal:1,final:true)
        n.adapter.perform(.step(FindRequestID("previous"),search,.previous))
        XCTAssertEqual(n.calls.last?.1,0)
        // A subframe document changes before the generated ID for Previous arrives.
        let changed=CefRendererMessage(frame:"b",document:"doc-b-2",kind:"created",request:"",payload:"")
        n.browser.receiveRenderer(changed);n.adapter.receive(changed)
        try? await Task.sleep(for:.milliseconds(120))
        n.adapter.nativeResult(id:18,count:4,ordinal:1,final:true)
        print("REPRO native directions through Previous/refresh:",n.calls,"last update:",n.updates.last!)
        XCTAssertEqual(n.calls.last?.1,0,"the pending Previous request was restarted as forward Find")
    }
    func testCaptureStopsPageFindWithoutClearingDOMSelection() throws {
        let n=Native();try n.setup();defer{n.cleanup()}
        let search=SearchToken(id:SearchID("page"),document:n.doc)
        n.adapter.perform(.search(FindRequestID("page-search"),search,FindQuery(text:"apple"),.page))
        n.stops.removeAll()
        n.adapter.perform(.captureSelection(FindRequestID("captured"),n.doc))
        XCTAssertEqual(n.stops,[0],"capturing must cancel native Find while preserving the user's selected text")
    }

}
