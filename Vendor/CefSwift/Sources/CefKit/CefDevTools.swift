import CCef
import Foundation

/// In-process CEF DevTools transport. It opens no debugging socket and installs no JavaScript bridge.
/// The owner must invalidate this registration before closing its browser or unloading CEF.
@MainActor
public final class CefDevTools {
    public enum Failure: Error { case unavailable, detached, timeout, protocolError(String) }
    private weak var browser: CefBrowser?
    private var registration: UnsafeMutablePointer<cef_registration_t>?
    private var pending: [Int: (CheckedContinuation<Data, any Error>, Task<Void, Never>)] = [:]
    private static var nextID = 1

    private final class Owner {
        weak var session: CefDevTools?
        init(_ session: CefDevTools) { self.session = session }
    }

    public init?(browser: CefBrowser) {
        self.browser = browser
        let observer = cefAllocate(cef_dev_tools_message_observer_t.self, owner: Owner(self))
        observer.pointee.on_dev_tools_method_result = { raw, source, id, success, bytes, count in
            defer { cefRelease(source.map(UnsafeMutableRawPointer.init)) }
            guard let owner = cefOwner(Owner.self, raw.map(UnsafeMutableRawPointer.init)), let source else { return }
            let data = bytes.map { Data(bytes: $0, count: count) } ?? Data("{}".utf8)
            MainActor.assumeIsolated {
                guard let session = owner.session, let expected = session.browser?.rawBrowserPointer,
                      let isSame = source.pointee.is_same else { return }
                // CEF consumes ref-counted arguments. The browser still owns its original reference.
                cefAddRef(UnsafeMutableRawPointer(expected))
                guard isSame(source, expected) == 1 else { return }
                session.complete(Int(id), success == 1 ? .success(data) : .failure(Failure.protocolError(String(decoding: data, as: UTF8.self))))
            }
        }
        observer.pointee.on_dev_tools_agent_detached = { raw, source in
            defer { cefRelease(source.map(UnsafeMutableRawPointer.init)) }
            guard let owner = cefOwner(Owner.self, raw.map(UnsafeMutableRawPointer.init)) else { return }
            MainActor.assumeIsolated { owner.session?.failPending() }
        }
        var handedOff = false
        browser.withHostInternal { host in
            if let add = host.pointee.add_dev_tools_message_observer {
                handedOff = true
                registration = add(host, observer)
            }
        }
        if !handedOff { cefRelease(UnsafeMutableRawPointer(observer)) }
        // The call consumes the observer's +1 even though the returned registration has a separate lifetime.
        guard registration != nil else { return nil }
    }

    public func call(_ method: String, parameters: [String: Any] = [:]) async throws -> Data {
        guard registration != nil, let browser else { throw Failure.unavailable }
        let id = Self.nextID
        precondition(id < Int(Int32.max))
        Self.nextID += 1
        let message = try JSONSerialization.data(withJSONObject: ["id": id, "method": method, "params": parameters])
        return try await withCheckedThrowingContinuation { continuation in
            let timeout = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
                self?.complete(id, .failure(Failure.timeout))
            }
            pending[id] = (continuation, timeout)
            var sent = false
            browser.withHostInternal { host in
                sent = message.withUnsafeBytes { bytes in
                    host.pointee.send_dev_tools_message?(host, bytes.baseAddress, bytes.count) == 1
                }
            }
            if !sent { complete(id, .failure(Failure.unavailable)) }
        }
    }

    public func invalidate() {
        failPending()
        if let registration { self.registration = nil; cefRelease(UnsafeMutableRawPointer(registration)) }
        browser = nil
    }

    private func failPending() { for id in Array(pending.keys) { complete(id, .failure(Failure.detached)) } }
    private func complete(_ id: Int, _ result: Result<Data, any Error>) {
        guard let (continuation, timeout) = pending.removeValue(forKey: id) else { return }
        timeout.cancel()
        continuation.resume(with: result)
    }
}
