import BrkBase
import BrkEngine
import CCef
import Foundation
import os

/// Owner: F2. Deleting a profile's Chromium data. A persistent profile lives in `<rootCachePath>/Profile-<name>`
/// (CefSwift's layout, `CefProfile.persistent`: the Chrome runtime only loads a profile directly under its root),
/// and Chromium holds that directory while the runtime runs, so `CEFEngine.disposeContext` marks it after draining: the directory's
/// name goes into `<data dir>/profiles-to-delete`, one per line. The next launch deletes every marked directory
/// before CEF starts, then the marker.
///
/// Every step converges whatever the previous run left: marking a name twice lists it once; the marker is replaced
/// atomically; a sweep that crashed half way finds the deleted directories gone and deletes the rest; a directory
/// that could not be deleted stays listed for the next launch.
struct ProfileDirectories {
    /// CEF's root cache path (`<data dir>/Chromium`, real path).
    let root: URL
    private let log = Logger(subsystem: "brk", category: "profiles")

    init(root: URL) { self.root = root }

    var marker: URL { root.deletingLastPathComponent().appendingPathComponent("profiles-to-delete") }

    /// The directory name CefSwift gives a profile (`CefProfile.cachePath` and `sanitize`, internal to CefKit,
    /// repeated here; W2-2 proves the two agree on disk): "Profile-" and the name with path separators as "_" and
    /// leading dots dropped, "Profile" for an empty result.
    static func directoryName(_ id: ProfileID) -> String {
        let cleaned = id.rawValue.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
        let trimmed = cleaned.drop { $0 == "." }
        return prefix + (trimmed.isEmpty ? "Profile" : String(trimmed))
    }

    static let prefix = "Profile-"

    /// The marker's names that can only name a profile directory directly inside the root: one path component
    /// with CefSwift's prefix (never "Default" or Chromium's own folders). Anything else in the file is ignored:
    /// the file is outside input at launch.
    static func names(in text: String) -> [String] {
        var out: [String] = []
        for line in text.split(whereSeparator: \.isNewline).map(String.init)
        where line.hasPrefix(prefix) && line.count > prefix.count && !line.contains("/") && !line.contains("\\") && !out.contains(line) {
            out.append(line)
        }
        return out
    }

    /// Adds the profile's directory to the marker.
    func mark(_ id: ProfileID) throws {
        var names = Self.names(in: readMarker())
        let name = Self.directoryName(id)
        guard !names.contains(name) else { return }
        names.append(name)
        try write(names)
        log.notice("profile \(id.rawValue, privacy: .public): directory \(name, privacy: .public) marked for deletion at the next launch")
    }

    /// Deletes every marked directory; keeps listed only the ones still on disk. Call before CEF starts.
    func deleteMarked() {
        guard FileManager.default.fileExists(atPath: marker.path) else { return }
        let names = Self.names(in: readMarker())
        var left: [String] = []
        for name in names {
            let directory = root.appendingPathComponent(name, isDirectory: true)
            guard FileManager.default.fileExists(atPath: directory.path) else { continue }
            do {
                try FileManager.default.removeItem(at: directory)
                log.notice("deleted the data of removed profile directory \(name, privacy: .public)")
            } catch {
                log.error("could not delete profile directory \(name, privacy: .public): \(error.localizedDescription, privacy: .public)")
                left.append(name)
            }
        }
        if left.isEmpty { try? FileManager.default.removeItem(at: marker) } else { try? write(left) }
    }

    private func readMarker() -> String {
        (try? Data(contentsOf: marker)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    private func write(_ names: [String]) throws {
        try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data((names.joined(separator: "\n") + "\n").utf8).write(to: marker, options: .atomic)
    }

}

/// Owner: F2. Starts Chromium loading a persistent profile and says when it is ready. The Chrome runtime creates a
/// disk profile asynchronously, and a browser created in a request context that is still initializing never
/// appears (W2-2 on CEF 154: the first page in a fresh profile kept browser id -1 and never closed; a page created
/// after the profile had loaded worked). So the engine creates no page in a persistent profile until its loader
/// reports `on_request_context_initialized`. The loader's context shares the profile's browser context with the
/// `CefProfile` the pages use (CEF shares a browser context between request contexts with one cache path), and is
/// held until the profile is forgotten, which keeps the profile loaded.
@MainActor
final class ProfileLoader {
    private(set) var context: UnsafeMutablePointer<cef_request_context_t>?
    private var onReady: (@MainActor () -> Void)?

    init(cachePath: URL, onReady: @escaping @MainActor () -> Void) {
        self.onReady = onReady
        var settings = cef_request_context_settings_t()
        settings.size = MemoryLayout<cef_request_context_settings_t>.stride
        let path = Array(cachePath.path.utf16)
        _ = path.withUnsafeBufferPointer { ccef_string_set_utf16($0.baseAddress, $0.count, &settings.cache_path) }
        defer { ccef_string_clear(&settings.cache_path) }
        // The handler's +1 goes to CEF with the call; the returned context's +1 is ours.
        context = cef_request_context_create_context(&settings, Self.makeHandler(owner: self))
    }

    /// Releases the loader's reference (the profile can unload once its pages are gone too). Idempotent.
    func release() {
        onReady = nil
        if let context {
            releaseRef(context)
            self.context = nil
        }
    }

    private func initialized() {
        let ready = onReady
        onReady = nil
        ready?()
    }

    private static let releaseOwner: @convention(c) (UnsafeMutableRawPointer?) -> Void = { opaque in
        guard let opaque else { return }
        Unmanaged<AnyObject>.fromOpaque(opaque).release()
    }

    /// A `cef_request_context_handler_t` allocated the CefSwift way (`ccef_object_alloc`: a hidden header holds the
    /// refcount and a retained box with the loader, released when CEF drops the last reference).
    private static func makeHandler(owner: ProfileLoader) -> UnsafeMutablePointer<cef_request_context_handler_t> {
        let box = Unmanaged.passRetained(WeakLoader(owner) as AnyObject).toOpaque()
        guard let raw = ccef_object_alloc(MemoryLayout<cef_request_context_handler_t>.stride, box, releaseOwner) else {
            fatalError("Brk: out of memory allocating a request context handler")
        }
        let handler = raw.assumingMemoryBound(to: cef_request_context_handler_t.self)
        handler.pointee.on_request_context_initialized = { handlerSelf, requestContext in
            // CEF passes the context with a reference for the callee.
            if let requestContext { releaseRef(requestContext) }
            guard let handlerSelf, let opaque = ccef_object_get_swift(handlerSelf),
                  let box = Unmanaged<AnyObject>.fromOpaque(opaque).takeUnretainedValue() as? WeakLoader else { return }
            MainActor.assumeIsolated { box.loader?.initialized() }   // CEF's UI thread is the main thread
        }
        return handler
    }

    private final class WeakLoader {
        weak var loader: ProfileLoader?
        init(_ loader: ProfileLoader) { self.loader = loader }
    }
}

/// Drops one reference of a CEF object (its first member is `cef_base_ref_counted_t`).
private func releaseRef<T>(_ object: UnsafeMutablePointer<T>) {
    let base = UnsafeMutableRawPointer(object).assumingMemoryBound(to: cef_base_ref_counted_t.self)
    _ = base.pointee.release?(base)
}

/// Owns the native request context through each acknowledged cookie/cache operation.
/// No profile directory or origin index is involved in clearing these two classes.
@MainActor
final class ProfileDataStore {
    static func inspect(browser id: Int) -> (path: String?, global: Bool)? {
        guard id > 0, let browser = cef_browser_host_get_browser_by_identifier(Int32(id)) else { return nil }
        defer { releaseRef(browser) }
        guard let host = browser.pointee.get_host?(browser) else { return nil }
        defer { releaseRef(host) }
        guard let context = host.pointee.get_request_context?(host) else { return nil }
        defer { releaseRef(context) }
        let path = context.pointee.get_cache_path?(context)
        defer { if let path { cef_string_userfree_utf16_free(path) } }
        return (path.flatMap { text in text.pointee.str.map { String(utf16CodeUnits: $0, count: text.pointee.length) } },
                context.pointee.is_global?(context) == 1)
    }

    let context: UnsafeMutablePointer<cef_request_context_t>
    init(context: UnsafeMutablePointer<cef_request_context_t>) { self.context = context }
    func release() { releaseRef(context) }

    func clearCookies(deleted: () -> Void) async throws {
        try await completion { callback in
            guard let get = context.pointee.get_cookie_manager else { releaseRef(callback); return false }
            guard let manager = get(context, callback) else { return false }
            releaseRef(manager)
            return true
        }
        guard let manager = context.pointee.get_cookie_manager?(context, nil) else { throw CocoaError(.featureUnsupported) }
        defer { releaseRef(manager) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            let owner = Completion(continuation)
            let callback = Self.allocate(cef_delete_cookies_callback_t.self, owner: owner)
            callback.pointee.on_complete = { object, count in
                guard let object else { return }
                MainActor.assumeIsolated { ProfileDataStore.owner(object)?.finish(count >= 0) }
            }
            guard let remove = manager.pointee.delete_cookies else {
                releaseRef(callback); owner.finish(false); return
            }
            if remove(manager, nil, nil, callback) == 0 { owner.finish(false) }
        }
        deleted()
        do {
            try await completion { callback in
                guard let flush = manager.pointee.flush_store else { releaseRef(callback); return false }
                return flush(manager, callback) != 0
            }
        } catch {
            throw NSError(domain: "Brk.SiteData", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cookies were deleted, but their disk flush failed. Restart durability is unconfirmed"])
        }
    }

    func clearCache() async throws {
        try await completion { callback in
            guard let clear = context.pointee.clear_http_cache else { releaseRef(callback); return false }
            clear(context, callback)
            return true
        }
    }

    func completion(_ start: (UnsafeMutablePointer<cef_completion_callback_t>) -> Bool) async throws {
        try await withCheckedThrowingContinuation { continuation in
            let owner = Completion(continuation)
            let callback = Self.allocate(cef_completion_callback_t.self, owner: owner)
            callback.pointee.on_complete = { object in
                guard let object else { return }
                MainActor.assumeIsolated { ProfileDataStore.owner(object)?.finish(true) }
            }
            if !start(callback) { owner.finish(false) }
        }
    }

    private final class Completion {
        private var continuation: CheckedContinuation<Void, any Error>?
        init(_ continuation: CheckedContinuation<Void, any Error>) { self.continuation = continuation }
        func finish(_ success: Bool) {
            guard let continuation else { return }
            self.continuation = nil
            if success { continuation.resume() } else { continuation.resume(throwing: CocoaError(.fileWriteUnknown)) }
        }
    }
    private static func owner<T>(_ object: UnsafeMutablePointer<T>) -> Completion? {
        guard let opaque = ccef_object_get_swift(object) else { return nil }
        return Unmanaged<AnyObject>.fromOpaque(opaque).takeUnretainedValue() as? Completion
    }
    private static func allocate<T>(_ type: T.Type, owner: Completion) -> UnsafeMutablePointer<T> {
        let box = Unmanaged.passRetained(owner as AnyObject).toOpaque()
        let raw = ccef_object_alloc(MemoryLayout<T>.stride, box, { opaque in
            if let opaque { Unmanaged<AnyObject>.fromOpaque(opaque).release() }
        })
        guard let raw else {
            Unmanaged<AnyObject>.fromOpaque(box).release()
            fatalError("Brk: out of memory allocating a data-removal callback")
        }
        return raw.assumingMemoryBound(to: T.self)
    }
}

/// Import from another browser: cookies set through the profile's own cookie manager (CEF's supported way in; the
/// store is Chromium's), then flushed to disk.
extension ProfileDataStore {
    func setCookies(_ cookies: [ImportedCookie]) async throws -> Int {
        try await completion { callback in
            guard let get = context.pointee.get_cookie_manager else { releaseRef(callback); return false }
            guard let manager = get(context, callback) else { return false }
            releaseRef(manager)
            return true
        }
        guard let manager = context.pointee.get_cookie_manager?(context, nil), let set = manager.pointee.set_cookie else {
            throw CocoaError(.featureUnsupported)
        }
        defer { releaseRef(manager) }
        var accepted = 0
        var start = 0
        while start < cookies.count {
            let batch = Array(cookies[start..<min(cookies.count, start + 200)])
            start += batch.count
            accepted += await withCheckedContinuation { (continuation: CheckedContinuation<Int, Never>) in
                let counter = CookieBatch(expected: batch.count, continuation)
                for cookie in batch {
                    let box = Unmanaged.passRetained(counter as AnyObject).toOpaque()
                    guard let raw = ccef_object_alloc(MemoryLayout<cef_set_cookie_callback_t>.stride, box, { opaque in
                        if let opaque { Unmanaged<AnyObject>.fromOpaque(opaque).release() }
                    }) else { Unmanaged<AnyObject>.fromOpaque(box).release(); counter.done(false); continue }
                    let callback = raw.assumingMemoryBound(to: cef_set_cookie_callback_t.self)
                    callback.pointee.on_complete = { object, success in
                        guard let object, let opaque = ccef_object_get_swift(object),
                              let batch = Unmanaged<AnyObject>.fromOpaque(opaque).takeUnretainedValue() as? CookieBatch else { return }
                        MainActor.assumeIsolated { batch.done(success != 0) }
                    }
                    let host = cookie.domain.hasPrefix(".") ? String(cookie.domain.dropFirst()) : cookie.domain
                    let address = (cookie.secure ? "https://" : "http://") + host + (cookie.path.hasPrefix("/") ? cookie.path : "/")
                    var value = cef_cookie_t()
                    value.size = MemoryLayout<cef_cookie_t>.stride
                    func assign(_ text: String, _ target: inout cef_string_t) {
                        let units = Array(text.utf16)
                        _ = units.withUnsafeBufferPointer { ccef_string_set_utf16($0.baseAddress, $0.count, &target) }
                    }
                    assign(cookie.name, &value.name); assign(cookie.value, &value.value)
                    assign(cookie.domain.hasPrefix(".") ? cookie.domain : "", &value.domain); assign(cookie.path, &value.path)
                    value.secure = cookie.secure ? 1 : 0
                    value.httponly = cookie.httpOnly ? 1 : 0
                    // base::Time: microseconds since 1601-01-01 UTC.
                    func time(_ instant: Instant?) -> cef_basetime_t { cef_basetime_t(val: instant.map { ($0.milliseconds + 11_644_473_600_000) * 1000 } ?? 0) }
                    value.creation = time(cookie.creation); value.last_access = time(cookie.lastAccess)
                    value.has_expires = cookie.expires == nil ? 0 : 1
                    value.expires = time(cookie.expires)
                    value.same_site = cef_cookie_same_site_t(rawValue: UInt32(max(0, min(3, cookie.sameSite + 1))))
                    value.priority = cef_cookie_priority_t(rawValue: Int32(max(-1, min(1, cookie.priority - 1))))
                    var url = cef_string_t()
                    assign(address, &url)
                    if set(manager, &url, &value, callback) == 0 { counter.done(false) }
                    ccef_string_clear(&url)
                    ccef_string_clear(&value.name); ccef_string_clear(&value.value); ccef_string_clear(&value.domain); ccef_string_clear(&value.path)
                }
            }
        }
        try? await completion { callback in
            guard let flush = manager.pointee.flush_store else { releaseRef(callback); return false }
            return flush(manager, callback) != 0
        }
        return accepted
    }

    private final class CookieBatch {
        private var remaining: Int
        private var accepted = 0
        private var continuation: CheckedContinuation<Int, Never>?
        init(expected: Int, _ continuation: CheckedContinuation<Int, Never>) {
            remaining = expected; self.continuation = continuation
            if expected == 0 { finish() }
        }
        func done(_ success: Bool) {
            guard remaining > 0 else { return }
            remaining -= 1
            if success { accepted += 1 }
            if remaining == 0 { finish() }
        }
        private func finish() {
            continuation?.resume(returning: accepted); continuation = nil
        }
    }
}
