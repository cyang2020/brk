import CCef
import Foundation
import PageEditorScript

/// The source frame is supplied by CEF, never by page JavaScript. No web-callable global is installed.
public struct CefRendererMessage: Sendable {
    public let frame: String
    public let document: String
    public let kind: String
    public let request: String
    public let payload: String
    static let channel = "brk.scoped-edit.v1"

    static func read(_ message: UnsafeMutablePointer<cef_process_message_t>, frame: UnsafeMutablePointer<cef_frame_t>) -> Self? {
        guard CefStringUtil.takingUserFree(message.pointee.get_name?(message)) == channel,
              let args = message.pointee.get_argument_list?(message) else { return nil }
        defer { cefRelease(UnsafeMutableRawPointer(args)) }
        guard args.pointee.get_size?(args) == 4,
              let id = CefStringUtil.takingUserFree(frame.pointee.get_identifier?(frame)) else { return nil }
        func string(_ i: Int) -> String { CefStringUtil.takingUserFree(args.pointee.get_string?(args, i)) ?? "" }
        return Self(frame: id, document: string(0), kind: string(1), request: string(2), payload: string(3))
    }

    static func send(frame: UnsafeMutablePointer<cef_frame_t>, process: cef_process_id_t,
                     document: String, kind: String, request: String = "", payload: String = "") {
        guard let message = CefStringUtil.withCefString(channel, { cef_process_message_create($0) }) else { return }
        guard let args = message.pointee.get_argument_list?(message) else { cefRelease(UnsafeMutableRawPointer(message)); return }
        for (i, string) in [document, kind, request, payload].enumerated() {
            _ = CefStringUtil.withCefString(string) { args.pointee.set_string?(args, i, $0) }
        }
        cefRelease(UnsafeMutableRawPointer(args))
        // send_process_message consumes the supplied +1. It invalidates the message's argument list.
        frame.pointee.send_process_message?(frame, process, message)
    }
}

extension CefBrowser {
    public struct FrameDocument: Equatable, Sendable {
        public let frame: String
        public let document: String
        public init(frame: String, document: String) { self.frame = frame; self.document = document }
    }

    public func focusedDocument() -> FrameDocument? {
        guard let raw = rawBrowserPointer, let frame = raw.pointee.get_focused_frame?(raw) else { return nil }
        defer { cefRelease(UnsafeMutableRawPointer(frame)) }
        guard frame.pointee.is_valid?(frame) != 0,
              let id = CefStringUtil.takingUserFree(frame.pointee.get_identifier?(frame)),
              let doc = rendererDocuments[id] else { return nil }
        return FrameDocument(frame: id, document: doc)
    }

    public func sendRenderer(to target: FrameDocument, request: String, payload: String) -> Bool {
        guard rendererDocuments[target.frame] == target.document, let raw = rawBrowserPointer,
              let frame = CefStringUtil.withCefString(target.frame, { raw.pointee.get_frame_by_identifier?(raw, $0) }) else { return false }
        defer { cefRelease(UnsafeMutableRawPointer(frame)) }
        guard frame.pointee.is_valid?(frame) != 0 else { return false }
        CefRendererMessage.send(frame: frame, process: PID_RENDERER, document: target.document,
                                kind: "request", request: request, payload: payload)
        return true
    }

    public var frameDocuments: [FrameDocument] { rendererDocuments.map { FrameDocument(frame: $0.key, document: $0.value) } }
    public func isCurrent(_ target: FrameDocument) -> Bool {
        guard rendererDocuments[target.frame] == target.document, let raw = rawBrowserPointer,
              let frame = CefStringUtil.withCefString(target.frame, { raw.pointee.get_frame_by_identifier?(raw, $0) }) else { return false }
        defer { cefRelease(UnsafeMutableRawPointer(frame)) }
        return frame.pointee.is_valid?(frame) != 0
    }
    func receiveRenderer(_ message: CefRendererMessage) {
        switch message.kind {
        case "created": rendererDocuments[message.frame] = message.document
        case "released":
            if rendererDocuments[message.frame] == message.document { rendererDocuments[message.frame] = nil }
        default:
            guard rendererDocuments[message.frame] == message.document else { return }
        }
        delegate?.browser(self, rendererMessage: message)
    }
}

/// Lives only in a renderer process. CEF serializes these callbacks on its renderer thread. Each saved function
/// is released at OnContextReleased; no V8 context reference survives that barrier.
final class ScopedEditRenderer: @unchecked Sendable {
    private struct Entry {
        let document: String
        let context: UnsafeMutablePointer<cef_v8_context_t>
        let function: UnsafeMutablePointer<cef_v8_value_t>
    }
    private var entries: [String: Entry] = [:]

    func makeHandler() -> UnsafeMutablePointer<cef_render_process_handler_t> {
        let handler = cefAllocate(cef_render_process_handler_t.self, owner: self)
        handler.pointee.on_context_created = { raw, browser, frame, context in
            defer {
                cefRelease(browser.map(UnsafeMutableRawPointer.init)); cefRelease(frame.map(UnsafeMutableRawPointer.init))
                cefRelease(context.map(UnsafeMutableRawPointer.init))
            }
            guard let owner = cefOwner(ScopedEditRenderer.self, raw.map(UnsafeMutableRawPointer.init)),
                  let context, let frame else { return }
            owner.created(context, frame)
        }
        handler.pointee.on_context_released = { raw, browser, frame, context in
            defer {
                cefRelease(browser.map(UnsafeMutableRawPointer.init)); cefRelease(frame.map(UnsafeMutableRawPointer.init))
                cefRelease(context.map(UnsafeMutableRawPointer.init))
            }
            guard let owner = cefOwner(ScopedEditRenderer.self, raw.map(UnsafeMutableRawPointer.init)), let context, let frame else { return }
            owner.released(context, frame)
        }
        handler.pointee.on_process_message_received = { raw, browser, frame, source, message in
            defer {
                cefRelease(browser.map(UnsafeMutableRawPointer.init)); cefRelease(frame.map(UnsafeMutableRawPointer.init))
                cefRelease(message.map(UnsafeMutableRawPointer.init))
            }
            guard source == PID_BROWSER, let owner = cefOwner(ScopedEditRenderer.self, raw.map(UnsafeMutableRawPointer.init)),
                  let frame, let message, let input = CefRendererMessage.read(message, frame: frame) else { return 0 }
            owner.receive(input, frame); return 1
        }
        return handler
    }

    private func created(_ context: UnsafeMutablePointer<cef_v8_context_t>, _ frame: UnsafeMutablePointer<cef_frame_t>) {
        var value: UnsafeMutablePointer<cef_v8_value_t>?
        var exception: UnsafeMutablePointer<cef_v8_exception_t>?
        let ok = CefStringUtil.withCefString(FindEditorScript.source) { code in
            CefStringUtil.withCefString("brk://scoped-edit") { context.pointee.eval?(context, code, $0, 1, &value, &exception) ?? 0 }
        }
        cefRelease(exception.map(UnsafeMutableRawPointer.init))
        guard ok != 0, let value, value.pointee.is_function?(value) != 0 else {
            cefRelease(value.map(UnsafeMutableRawPointer.init)); return
        }
        let doc = UUID().uuidString
        guard let id = CefStringUtil.takingUserFree(frame.pointee.get_identifier?(frame)) else { cefRelease(UnsafeMutableRawPointer(value)); return }
        if let old = entries.removeValue(forKey: id) { cefRelease(UnsafeMutableRawPointer(old.function)); cefRelease(UnsafeMutableRawPointer(old.context)) }
        cefAddRef(UnsafeMutableRawPointer(context))
        entries[id] = Entry(document: doc, context: context, function: value)
        CefRendererMessage.send(frame: frame, process: PID_BROWSER, document: doc, kind: "created")
    }
    private func released(_ context: UnsafeMutablePointer<cef_v8_context_t>, _ frame: UnsafeMutablePointer<cef_frame_t>) {
        guard let id = CefStringUtil.takingUserFree(frame.pointee.get_identifier?(frame)), let entry = entries[id] else { return }
        cefAddRef(UnsafeMutableRawPointer(context))
        guard entry.context.pointee.is_same?(entry.context, context) != 0 else { return }
        entries[id] = nil
        cefRelease(UnsafeMutableRawPointer(entry.context))
        cefRelease(UnsafeMutableRawPointer(entry.function))
        CefRendererMessage.send(frame: frame, process: PID_BROWSER, document: entry.document, kind: "released")
    }
    private func receive(_ input: CefRendererMessage, _ frame: UnsafeMutablePointer<cef_frame_t>) {
        guard let context = frame.pointee.get_v8_context?(frame) else { return }
        defer { cefRelease(UnsafeMutableRawPointer(context)) }
        guard let entry = entries[input.frame], entry.document == input.document,
              context.pointee.enter?(context) != 0 else { return }
        defer { _ = context.pointee.exit?(context) }
        var arg = CefStringUtil.withCefString(input.payload) { cef_v8_value_create_string($0) }
        // Incoming object arguments transfer a reference. Keep our context's own +1 until the defer above.
        cefAddRef(UnsafeMutableRawPointer(context))
        let value = withUnsafePointer(to: &arg) {
            entry.function.pointee.execute_function_with_context?(entry.function, context, nil, 1, $0)
        }
        defer { cefRelease(value.map(UnsafeMutableRawPointer.init)) }
        let result = value.flatMap { CefStringUtil.takingUserFree($0.pointee.get_string_value?($0)) }
            ?? "{\"status\":\"unconfirmed\"}"
        CefRendererMessage.send(frame: frame, process: PID_BROWSER, document: entry.document,
                                kind: "result", request: input.request, payload: result)
    }
}
