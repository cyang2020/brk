import CCef
import Foundation
import Testing
@testable import CefKit

@MainActor struct DevToolsOwnershipTests {
    final class State {
        var observer: UnsafeMutablePointer<cef_dev_tools_message_observer_t>?
        var host: UnsafeMutablePointer<cef_browser_host_t>!
        var raw: UnsafeMutablePointer<cef_browser_t>!
        var foreign: UnsafeMutablePointer<cef_browser_t>!
        var browser: CefBrowser!
        var released = 0
        var lastID = 0
        var replyImmediately = true
        var acceptSend = true
    }
    final class RegistrationOwner {
        let state: State
        let observer: UnsafeMutablePointer<cef_dev_tools_message_observer_t>
        init(_ state: State, _ observer: UnsafeMutablePointer<cef_dev_tools_message_observer_t>) { self.state = state; self.observer = observer }
        deinit { state.released += 1; cefRelease(UnsafeMutableRawPointer(observer)) }
    }
    private func fixture() -> State {
        let state = State()
        state.raw = cefAllocate(cef_browser_t.self, owner: state)
        state.foreign = cefAllocate(cef_browser_t.self, owner: state)
        state.host = cefAllocate(cef_browser_host_t.self, owner: state)
        state.raw.pointee.get_identifier = { _ in 19 }
        state.raw.pointee.is_same = { a, b in
            let same: Int32 = a == b ? 1 : 0
            cefRelease(b.map(UnsafeMutableRawPointer.init)); return same
        }
        state.foreign.pointee.is_same = state.raw.pointee.is_same
        state.raw.pointee.get_host = { raw in
            let state = cefOwner(State.self, raw.map(UnsafeMutableRawPointer.init))!
            cefAddRef(UnsafeMutableRawPointer(state.host)); return state.host
        }
        state.host.pointee.add_dev_tools_message_observer = { raw, observer in
            let state = cefOwner(State.self, raw.map(UnsafeMutableRawPointer.init))!
            state.observer = observer
            return cefAllocate(cef_registration_t.self, owner: RegistrationOwner(state, observer!))
        }
        state.host.pointee.send_dev_tools_message = { raw, bytes, count in
            MainActor.assumeIsolated {
                let state = cefOwner(State.self, raw.map(UnsafeMutableRawPointer.init))!
                let message = try! JSONSerialization.jsonObject(with: Data(bytes: bytes!, count: count)) as! [String: Any]
                state.lastID = message["id"] as! Int
                if state.replyImmediately {
                    // Neither a valid ID from another browser nor another ID from the same browser may settle it.
                    Self.deliver(state, source: state.foreign, id: state.lastID, value: "foreign")
                    Self.deliver(state, source: state.raw, id: state.lastID + 1, value: "wrong request")
                    Self.deliver(state, source: state.raw, id: state.lastID, value: "correct")
                }
                return state.acceptSend ? 1 : 0
            }
        }
        state.browser = CefBrowser(raw: state.raw, client: nil, delegate: nil)
        return state
    }
    private static func deliver(_ state: State, source: UnsafeMutablePointer<cef_browser_t>, id: Int, value: String) {
        let data = Data("{\"value\":\"\(value)\"}".utf8)
        cefAddRef(UnsafeMutableRawPointer(source))
        data.withUnsafeBytes { bytes in
            state.observer!.pointee.on_dev_tools_method_result!(state.observer, source, Int32(id), 1, bytes.baseAddress, bytes.count)
        }
    }
    private func clean(_ state: State) {
        state.browser.handleBeforeClose(); state.browser = nil
        cefRelease(UnsafeMutableRawPointer(state.foreign)); cefRelease(UnsafeMutableRawPointer(state.host))
    }
    @Test func onlyExactBrowserAndRequestCanCompleteAndRegistrationReleasesOnce() async throws {
        let state = fixture()
        let session = try #require(CefDevTools(browser: state.browser))
        // Guard references keep a broken implementation measurable instead of dereferencing freed memory.
        for _ in 0..<4 { cefAddRef(UnsafeMutableRawPointer(state.raw)) }
        let result = try await session.call("Target.getTargetInfo")
        #expect(ccef_object_ref_count(state.raw) == 5, "IsSame must receive its own +1, not consume the browser owner")
        while ccef_object_ref_count(state.raw) > 1 { cefRelease(UnsafeMutableRawPointer(state.raw)) }
        #expect(String(decoding: result, as: UTF8.self) == "{\"value\":\"correct\"}")
        session.invalidate(); session.invalidate()
        #expect(state.released == 1)
        clean(state)
    }
    @Test func invalidateSettlesPendingAndRejectsLateReply() async throws {
        let state = fixture(); state.replyImmediately = false
        let session = try #require(CefDevTools(browser: state.browser))
        let task = Task { try await session.call("Runtime.evaluate") }
        for _ in 0..<100 where state.lastID == 0 { await Task.yield() }
        #expect(state.lastID > 0)
        // Keep CEF's in-flight callback alive past registration release.
        cefAddRef(UnsafeMutableRawPointer(state.observer!))
        session.invalidate()
        Self.deliver(state, source: state.raw, id: state.lastID, value: "late")
        cefRelease(UnsafeMutableRawPointer(state.observer!))
        do { _ = try await task.value; Issue.record("retired request completed") }
        catch CefDevTools.Failure.detached {}
        #expect(state.released == 1)
        clean(state)
    }
    @Test func rejectedSendSettlesWithoutWaitingForTimeout() async throws {
        let state = fixture(); state.replyImmediately = false; state.acceptSend = false
        let session = try #require(CefDevTools(browser: state.browser))
        do { _ = try await session.call("Target.getTargetInfo"); Issue.record("rejected send completed") }
        catch CefDevTools.Failure.unavailable {}
        session.invalidate(); clean(state)
    }
}
