import CCef
import Foundation
import Testing
@testable import CefKit

@MainActor struct RequestIDCollisionTests {
    final class State {
        var host: UnsafeMutablePointer<cef_browser_host_t>!
        var raw: UnsafeMutablePointer<cef_browser_t>!
        var observers: [UnsafeMutablePointer<cef_dev_tools_message_observer_t>] = []
        var messages: [[String: Any]] = []
        var snapshot: Result<Data, Error>?
        var releases = 0
    }
    final class RegistrationOwner {
        let state: State
        let observer: UnsafeMutablePointer<cef_dev_tools_message_observer_t>
        init(_ state: State, _ observer: UnsafeMutablePointer<cef_dev_tools_message_observer_t>) { self.state = state; self.observer = observer }
        deinit {
            state.observers.removeAll { $0 == observer }
            state.releases += 1
            cefRelease(UnsafeMutableRawPointer(observer))
        }
    }
    @Test func independentCountersMustNotCrossCompleteOnOneCEFConnection() async throws {
        let s = State()
        s.raw = cefAllocate(cef_browser_t.self, owner: s)
        s.host = cefAllocate(cef_browser_host_t.self, owner: s)
        s.raw.pointee.get_identifier = { _ in 7 }
        s.raw.pointee.is_same = { a,b in
            let same: Int32 = a == b ? 1 : 0
            cefRelease(b.map(UnsafeMutableRawPointer.init)); return same
        }
        s.raw.pointee.get_host = { raw in
            let s = cefOwner(State.self, raw.map(UnsafeMutableRawPointer.init))!
            cefAddRef(UnsafeMutableRawPointer(s.host)); return s.host
        }
        s.host.pointee.add_dev_tools_message_observer = { host, observer in
            let s = cefOwner(State.self, host.map(UnsafeMutableRawPointer.init))!
            s.observers.append(observer!)
            return cefAllocate(cef_registration_t.self, owner: RegistrationOwner(s, observer!))
        }
        s.host.pointee.send_dev_tools_message = { host, bytes, count in
            let s = cefOwner(State.self, host.map(UnsafeMutableRawPointer.init))!
            s.messages.append(try! JSONSerialization.jsonObject(with: Data(bytes: bytes!, count: count)) as! [String: Any])
            return 1
        }
        let browser = CefBrowser(raw: s.raw, client: nil, delegate: nil)
        let transport = try #require(CefDevTools(browser: browser))
        // Start the asynchronous snapshot before the first audio target lookup.
        // This does not assume that the browser-side Target.getTargetInfo handler is asynchronous.
        let snapshot = browser.captureMHTML { s.snapshot = $0 }
        #expect(s.messages.count == 1)
        let audio = Task { try await transport.call("Target.getTargetInfo") }
        for _ in 0..<100 where s.messages.count < 2 { await Task.yield() }
        #expect(s.messages.count == 2)
        let outputID = try #require(s.messages[0]["id"] as? Int)
        let audioID = try #require(s.messages[1]["id"] as? Int)
        print("REPRO request IDs: Target.getTargetInfo=\(audioID), Page.captureSnapshot=\(outputID), browser=7")
        // Simulate the pinned CefDevToolsController::DispatchProtocolMessage observer loop.
        // Every observer sees the envelope; returning handled skips only that observer's parsed callback.
        let result: [String: Any] = ["targetInfo": ["targetId": "native-page", "type": "page"]]
        let envelope = try JSONSerialization.data(withJSONObject: ["id": audioID, "result": result])
        let body = try JSONSerialization.data(withJSONObject: result)
        let observers = s.observers
        for observer in observers { cefAddRef(UnsafeMutableRawPointer(observer)) }
        for observer in observers {
            var handled: Int32 = 0
            if let callback = observer.pointee.on_dev_tools_message {
                cefAddRef(UnsafeMutableRawPointer(s.raw))
                handled = envelope.withUnsafeBytes { callback(observer, s.raw, $0.baseAddress, $0.count) }
            }
            if handled == 0, let callback = observer.pointee.on_dev_tools_method_result {
                cefAddRef(UnsafeMutableRawPointer(s.raw))
                body.withUnsafeBytes { callback(observer, s.raw, Int32(audioID), 1, $0.baseAddress, $0.count) }
            }
            cefRelease(UnsafeMutableRawPointer(observer))
        }
        _ = try await audio.value
        if case .failure(let error) = s.snapshot { print("REPRO snapshot completed on audio reply: failure=\(error)") }
        else { print("REPRO snapshot state: \(String(describing: s.snapshot))") }
        #expect(audioID != outputID, "One native connection needs noncolliding request IDs")
        #expect(s.snapshot == nil, "A target-info reply must not complete MHTML output")
        let archive = "MIME-Version: 1.0\r\nContent-Type: text/html\r\n\r\nOwned snapshot"
        let snapshotBody = try JSONSerialization.data(withJSONObject: ["data": archive])
        let snapshotEnvelope = try JSONSerialization.data(withJSONObject: ["id": outputID, "result": ["data": archive]])
        let remaining = s.observers
        for observer in remaining { cefAddRef(UnsafeMutableRawPointer(observer)) }
        for observer in remaining {
            var handled: Int32 = 0
            if let callback = observer.pointee.on_dev_tools_message {
                cefAddRef(UnsafeMutableRawPointer(s.raw))
                handled = snapshotEnvelope.withUnsafeBytes { callback(observer, s.raw, $0.baseAddress, $0.count) }
            }
            if handled == 0, let callback = observer.pointee.on_dev_tools_method_result {
                cefAddRef(UnsafeMutableRawPointer(s.raw))
                snapshotBody.withUnsafeBytes { callback(observer, s.raw, Int32(outputID), 1, $0.baseAddress, $0.count) }
            }
            cefRelease(UnsafeMutableRawPointer(observer))
        }
        if case .success(let data) = s.snapshot { #expect(data == Data(archive.utf8)) }
        else { Issue.record("The snapshot's own reply must finish with its exact MHTML bytes") }
        snapshot.cancel(); transport.invalidate()
        #expect(s.releases == 2)
        browser.handleBeforeClose(); cefRelease(UnsafeMutableRawPointer(s.host))
        #expect(!CefRuntime.shared.isInitialized, "No Chromium runtime was loaded")
    }
}
