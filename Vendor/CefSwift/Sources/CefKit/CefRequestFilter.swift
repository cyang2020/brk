import CCef
import Foundation

/// UI writes and CEF IO reads only copied values under this lock. No synchronous hop to the UI thread.
public struct CefRequestRules: Sendable {
    public let enabled: Bool
    public let hosts: [String]
    public let paths: [String]
    public let urlPrefixes: [String]
    public init(enabled: Bool, hosts: [String], paths: [String], urlPrefixes: [String] = []) { self.enabled = enabled; self.hosts = hosts; self.paths = paths; self.urlPrefixes = urlPrefixes }
}

public final class CefRequestFilter: @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = false
    private var hosts: [String] = []
    private var paths: [String] = []
    private var urlPrefixes: [String] = []
    public init() {}
    public func configure(enabled: Bool, hosts: [String], paths: [String], urlPrefixes: [String] = []) {
        lock.lock(); defer { lock.unlock() }
        self.enabled = enabled; self.hosts = hosts; self.paths = paths; self.urlPrefixes = urlPrefixes
    }
    public func blocks(_ url: URL) -> Bool {
        guard ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return false }
        lock.lock(); defer { lock.unlock() }
        guard enabled else { return false }
        let host = (url.host?.lowercased() ?? "").trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return hosts.contains { host == $0 || host.hasSuffix("." + $0) } || paths.contains { url.path.hasPrefix($0) } || urlPrefixes.contains { prefix in
            guard let rule = URL(string: prefix), url.scheme == rule.scheme, url.host == rule.host, url.port == rule.port else { return false }
            return url.path.hasPrefix(rule.path)
        }
    }
    func makeHandler() -> UnsafeMutablePointer<cef_resource_request_handler_t> {
        let handler = cefAllocate(cef_resource_request_handler_t.self, owner: self)
        handler.pointee.on_before_resource_load = { pointer, browser, frame, request, callback in
            defer {
                cefRelease(browser.map(UnsafeMutableRawPointer.init)); cefRelease(frame.map(UnsafeMutableRawPointer.init))
                cefRelease(request.map(UnsafeMutableRawPointer.init)); cefRelease(callback.map(UnsafeMutableRawPointer.init))
            }
            guard let owner = cefOwner(CefRequestFilter.self, pointer.map(UnsafeMutableRawPointer.init)), let request,
                  let value = CefStringUtil.takingUserFree(request.pointee.get_url?(request)), let url = URL(string: value) else { return RV_CONTINUE }
            return owner.blocks(url) ? RV_CANCEL : RV_CONTINUE
        }
        handler.pointee.on_resource_redirect = { pointer, browser, frame, request, response, newURL in
            defer {
                cefRelease(browser.map(UnsafeMutableRawPointer.init)); cefRelease(frame.map(UnsafeMutableRawPointer.init))
                cefRelease(request.map(UnsafeMutableRawPointer.init)); cefRelease(response.map(UnsafeMutableRawPointer.init))
            }
            guard let owner = cefOwner(CefRequestFilter.self, pointer.map(UnsafeMutableRawPointer.init)), let newURL,
                  let url = URL(string: CefStringUtil.string(from: newURL)), owner.blocks(url) else { return }
            CefStringUtil.set("about:blank#brk-blocked", into: &newURL.pointee)
        }
        return handler
    }
}

extension CefBrowser {
    public var requestFilter: CefRequestFilter? { client?.requestFilter }
}
