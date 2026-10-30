import BrkBase
import CCef
import Foundation
import os

/// Owner: F2. Deleting a profile's Chromium data. A persistent profile lives in `<rootCachePath>/Profile-<name>`
/// (CefSwift's layout, `CefProfile.persistent`: the Chrome runtime only loads a profile directly under its root),
/// and Chromium holds that directory while the runtime runs, so `CEFEngine.forget` only marks it: the directory's
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
    func mark(_ id: ProfileID) {
        var names = Self.names(in: readMarker())
        let name = Self.directoryName(id)
        guard !names.contains(name) else { return }
        names.append(name)
        write(names)
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
        if left.isEmpty { try? FileManager.default.removeItem(at: marker) } else { write(left) }
    }

    private func readMarker() -> String {
        (try? Data(contentsOf: marker)).map { String(decoding: $0, as: UTF8.self) } ?? ""
    }

    private func write(_ names: [String]) {
        do {
            try FileManager.default.createDirectory(at: marker.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data((names.joined(separator: "\n") + "\n").utf8).write(to: marker, options: .atomic)
        } catch {
            log.error("could not write \(marker.path, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
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
