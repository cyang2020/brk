import CCef
import Foundation

public struct CefProtocolError: Error, LocalizedError {
    public let message: String
    public init(message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// One in-process protocol channel. No remote debugging port or DevTools window is required.
@MainActor
public final class CefDevToolsSession {
    private weak var browser: CefBrowser?
    private var registration: UnsafeMutablePointer<cef_registration_t>?
    private var observer: UnsafeMutablePointer<cef_dev_tools_message_observer_t>?
    private var pending: [Int: (Result<Data, Error>) -> Void] = [:]
    private var nextID = 0
    private var closed = false

    init(browser: CefBrowser) {
        self.browser = browser
        guard let raw = browser.rawBrowserPointer, let host = raw.pointee.get_host?(raw) else { return }
        defer { cefRelease(UnsafeMutableRawPointer(host)) }
        let observer = cefAllocate(cef_dev_tools_message_observer_t.self, owner: self)
        observer.pointee.on_dev_tools_method_result = { pointer, browser, id, success, result, size in
            cefRelease(browser.map(UnsafeMutableRawPointer.init))
            guard let owner = cefOwner(CefDevToolsSession.self, pointer.map(UnsafeMutableRawPointer.init)) else { return }
            let data = result.map { Data(bytes: $0, count: size) } ?? Data("{}".utf8)
            MainActor.assumeIsolated { owner.received(Int(id), success: success != 0, data: data) }
        }
        observer.pointee.on_dev_tools_agent_attached = { _, browser in cefRelease(browser.map(UnsafeMutableRawPointer.init)) }
        observer.pointee.on_dev_tools_agent_detached = { pointer, browser in
            cefRelease(browser.map(UnsafeMutableRawPointer.init))
            guard let owner = cefOwner(CefDevToolsSession.self, pointer.map(UnsafeMutableRawPointer.init)) else { return }
            MainActor.assumeIsolated { owner.failPending("Browser protocol agent detached") }
        }
        self.observer = observer
        cefAddRef(UnsafeMutableRawPointer(observer)) // CEF consumes the argument reference; retain our initial reference.
        registration = host.pointee.add_dev_tools_message_observer?(host, observer)
    }

    public func call(_ method: String, _ parameters: [String: Any] = [:], timeout: Double = 10) async throws -> [String: Any] {
        let data: Data = try await withCheckedThrowingContinuation { continuation in
            submit(method, parameters, timeout: timeout) { continuation.resume(with: $0) }
        }
        return try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
    }

    private func submit(_ method: String, _ parameters: [String: Any], timeout: Double,
                        completion: @escaping (Result<Data, Error>) -> Void) {
        guard !closed, registration != nil, let raw = browser?.rawBrowserPointer,
              let host = raw.pointee.get_host?(raw) else {
            completion(.failure(CefProtocolError(message: "Browser protocol channel is unavailable"))); return
        }
        defer { cefRelease(UnsafeMutableRawPointer(host)) }
        nextID += 1
        let id = nextID
        do {
            let message = try JSONSerialization.data(withJSONObject: ["id": id, "method": method, "params": parameters])
            pending[id] = completion
            let sent = message.withUnsafeBytes { host.pointee.send_dev_tools_message?(host, $0.baseAddress, $0.count) ?? 0 }
            if sent == 0 { pending.removeValue(forKey: id)?(.failure(CefProtocolError(message: "Protocol command was rejected"))) }
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.pending.removeValue(forKey: id)?(.failure(CefProtocolError(message: "Protocol command timed out: " + method)))
            }
        } catch { completion(.failure(error)) }
    }

    private func received(_ id: Int, success: Bool, data: Data) {
        guard let completion = pending.removeValue(forKey: id) else { return }
        do {
            let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            completion(success ? .success(data) : .failure(CefProtocolError(message: value["message"] as? String ?? "Protocol command failed")))
        } catch { completion(.failure(error)) }
    }

    private func failPending(_ message: String) {
        let callbacks = pending.values
        pending.removeAll()
        for callback in callbacks { callback(.failure(CefProtocolError(message: message))) }
    }

    public func close() {
        guard !closed else { return }
        closed = true
        if let registration { self.registration = nil; cefRelease(UnsafeMutableRawPointer(registration)) }
        if let observer { self.observer = nil; cefRelease(UnsafeMutableRawPointer(observer)) }
        failPending("Browser closed")
    }
}

extension CefBrowser {
    public var protocolSession: CefDevToolsSession {
        if let toolsSession { return toolsSession }
        let session = CefDevToolsSession(browser: self)
        toolsSession = session
        return session
    }
}
