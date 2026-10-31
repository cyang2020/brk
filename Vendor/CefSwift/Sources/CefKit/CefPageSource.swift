import CCef
import Foundation

@MainActor private final class SourceVisitor {
    var completion: ((String?) -> Void)?
    init(_ completion: @escaping (String?) -> Void) { self.completion = completion }
    func finish(_ text: String?) { let done = completion; completion = nil; done?(text) }
}

extension CefBrowser {
    public func readSource(_ completion: @escaping (String?) -> Void) {
        guard let raw = rawBrowserPointer, let frame = raw.pointee.get_main_frame?(raw) else { completion(nil); return }
        defer { cefRelease(UnsafeMutableRawPointer(frame)) }
        guard let get = frame.pointee.get_source else { completion(nil); return }
        let visitor = cefAllocate(cef_string_visitor_t.self, owner: SourceVisitor(completion))
        visitor.pointee.visit = { raw, text in
            guard let owner = cefOwner(SourceVisitor.self, raw.map(UnsafeMutableRawPointer.init)) else { return }
            let value = CefStringUtil.string(from: text)
            MainActor.assumeIsolated { owner.finish(value) }
        }
        get(frame, visitor)
    }
}
