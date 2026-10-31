import CCef
import Foundation

/// A per-call callback owner. CEF retains it until the PDF writer has actually answered.
@MainActor public final class CefPDFOutput {
    private var completion: ((Bool) -> Void)?
    fileprivate init(completion: @escaping (Bool) -> Void) { self.completion = completion }
    fileprivate func finish(_ ok: Bool) { let reply = completion; completion = nil; reply?(ok) }
}

/// One DevTools observer registration, scoped to a single capture message. No global callback sink.
@MainActor public final class CefSnapshotOutput {
    private var registration: UnsafeMutablePointer<cef_registration_t>?
    private let messageID: Int
    private var completion: ((Result<Data, Error>) -> Void)?

    fileprivate init(completion: @escaping (Result<Data, Error>) -> Void) {
        messageID = CefDevToolsRequestIDs.next(); self.completion = completion
    }

    fileprivate func receive(_ data: Data) -> Bool {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], json["id"] as? Int == messageID else { return false }
        if let result = json["result"] as? [String: Any], let archive = result["data"] as? String {
            finish(.success(Data(archive.utf8)))
        } else { finish(.failure(CocoaError(.fileReadCorruptFile))) }
        return true
    }

    private func finish(_ result: Result<Data, Error>) {
        let reply = completion; completion = nil
        cancelRegistration()
        reply?(result)
    }

    /// Cancels only the observer. Capturing an MHTML string has no file writer to outlive this barrier.
    public func cancel() { completion = nil; cancelRegistration() }
    private func cancelRegistration() {
        let raw = registration; registration = nil
        cefRelease(raw.map(UnsafeMutableRawPointer.init))
    }

    fileprivate func start(_ browser: CefBrowser) {
        var started = false
        browser.withHostInternal { host in
            guard let add = host.pointee.add_dev_tools_message_observer, let send = host.pointee.send_dev_tools_message else { return }
            let observer = cefAllocate(cef_dev_tools_message_observer_t.self, owner: self)
            observer.pointee.on_dev_tools_message = { owner, rawBrowser, message, size in
                cefRelease(rawBrowser.map(UnsafeMutableRawPointer.init))
                guard let message else { return 0 }
                let data = Data(bytes: message, count: size)
                return MainActor.assumeIsolated {
                    cefOwner(CefSnapshotOutput.self, owner.map(UnsafeMutableRawPointer.init))?.receive(data) == true ? 1 : 0
                }
            }
            // The outgoing observer +1 transfers into CEF. The returned registration +1 belongs to this owner.
            registration = add(host, observer)
            guard registration != nil else { return }
            let bytes = try! JSONSerialization.data(withJSONObject: ["id": messageID, "method": "Page.captureSnapshot", "params": ["format": "mhtml"]])
            started = bytes.withUnsafeBytes { send(host, $0.baseAddress, bytes.count) != 0 }
        }
        if !started { finish(.failure(CocoaError(.featureUnsupported))) }
    }
}

extension CefBrowser {
    @discardableResult public func captureMHTML(completion: @escaping (Result<Data, Error>) -> Void) -> CefSnapshotOutput {
        let output = CefSnapshotOutput(completion: completion)
        output.start(self)
        return output
    }

    @discardableResult public func printPDF(to path: URL, completion: @escaping (Bool) -> Void) -> CefPDFOutput {
        let output = CefPDFOutput(completion: completion)
        var started = false
        withHostInternal { host in
            guard let print = host.pointee.print_to_pdf else { return }
            let callback = cefAllocate(cef_pdf_print_callback_t.self, owner: output)
            callback.pointee.on_pdf_print_finished = { owner, _, success in
                MainActor.assumeIsolated {
                    cefOwner(CefPDFOutput.self, owner.map(UnsafeMutableRawPointer.init))?.finish(success != 0)
                }
            }
            var settings = cef_pdf_print_settings_t()
            settings.size = MemoryLayout<cef_pdf_print_settings_t>.stride
            settings.print_background = 1
            started = true
            CefStringUtil.withCefString(path.path) { print(host, $0, &settings, callback) }
            // CEF consumes the callback +1. Releasing it here would double-release the native bridge.
        }
        if !started { output.finish(false) }
        return output
    }
}
