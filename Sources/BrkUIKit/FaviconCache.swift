import AppKit

/// Brk's own favicon fetches, outside Chromium: the sidebar's (`FaviconStore`) and `FaviconCache`'s. None sends or keeps
/// a cookie: through URLSession.shared a cookie set on an incognito window's or one profile's favicon went into the
/// app's cookie store and out again with every later fetch, linking them. What a fetch keeps depends on the window the
/// favicon is drawn for (`NSView.fetchesKeepNothing`).
public enum FaviconFetch {
    /// An incognito window's favicons, and those of a view in no browser window: nothing kept, in memory or on disk.
    /// Through URLSession.shared the private site's favicon URL and response stayed in the app's Cache.db.
    public static let keepingNothing = session(cache: nil)

    /// Every other window's favicons: responses kept in Brk's own cache (`keep(in:)`), so a launch draws the restored
    /// rows' favicons from it at once, offline too while they are fresh, as URLSession.shared's disk cache did.
    public static var keeping: URLSession { kept.session }

    /// Where `keeping` keeps responses: BrkApp gives its data folder's Favicons folder at launch. Without one (tests,
    /// or nil) they are kept in memory only.
    public static func keep(in directory: URL?) { kept.move(to: directory) }

    public static func session(keepingNothing: Bool) -> URLSession { keepingNothing ? self.keepingNothing : keeping }

    private static let kept = Kept()

    private final class Kept: @unchecked Sendable {
        private let lock = NSLock()
        private var directory: URL?
        private var built: URLSession?

        var session: URLSession {
            lock.withLock {
                if let built { return built }
                if let directory { try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true) }
                let cache = URLCache(memoryCapacity: 1 << 20, diskCapacity: directory == nil ? 0 : 50 << 20, directory: directory)
                let made = FaviconFetch.session(cache: cache)
                built = made
                return made
            }
        }

        func move(to directory: URL?) {
            lock.withLock {
                self.directory = directory
                built?.finishTasksAndInvalidate()
                built = nil
            }
        }
    }

    /// `cache` nil: nothing is kept anywhere. The kept session starts from the default configuration (an ephemeral one
    /// keeps nothing on disk whatever its cache); neither has a cookie store or a credential store.
    private static func session(cache: URLCache?) -> URLSession {
        let configuration = cache == nil ? URLSessionConfiguration.ephemeral : .default
        configuration.urlCache = cache
        configuration.requestCachePolicy = .useProtocolCachePolicy
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        configuration.urlCredentialStorage = nil
        return URLSession(configuration: configuration)
    }
}

/// A browser window says whether what Brk fetches itself for its views (favicons) may be kept. Its controller says so
/// for every window but an incognito one, whose pages keep nothing after it closes.
@MainActor
public protocol FetchKeepingWindow: NSWindow {
    /// False until the controller sets it, and always in an incognito window.
    var keepsFetches: Bool { get set }
}

public extension NSView {
    /// Brk's own fetches for this view (favicons) keep nothing: it is in an incognito window, or in no browser window
    /// that says otherwise (not placed yet, a popover).
    @MainActor var fetchesKeepNothing: Bool { (window as? FetchKeepingWindow)?.keepsFetches != true }
}

/// Favicons for command bar rows, Library rows, Boosts and the tab switcher, fetched once per URL. A URL whose fetch
/// failed is not fetched again this run: rows are rebuilt on every keystroke and re-rank.
@MainActor
public final class FaviconCache {
    public static let shared = FaviconCache()
    private var images: [URL: NSImage] = [:]
    private var waiting: [URL: [(NSImage) -> Void]] = [:]
    private var failed: Set<URL> = []
    private let fetch: @Sendable (URL, _ keepingNothing: Bool) async -> Data?

    init(fetch: @escaping @Sendable (URL, _ keepingNothing: Bool) async -> Data? = { url, keepingNothing in
        try? await FaviconFetch.session(keepingNothing: keepingNothing).data(from: url).0
    }) { self.fetch = fetch }

    /// The cached image, or nil now and `then` once it arrives (never, if the fetch fails). `keepingNothing`: the
    /// favicon is drawn for an incognito window (`NSView.fetchesKeepNothing`); its fetch keeps nothing.
    public func image(for url: URL, keepingNothing: Bool, then: @escaping (NSImage) -> Void) -> NSImage? {
        if let image = images[url] { return image }
        guard !failed.contains(url) else { return nil }
        if waiting[url] != nil {
            waiting[url]?.append(then)
            return nil
        }
        waiting[url] = [then]
        Task {
            let data = await fetch(url, keepingNothing)
            let callbacks = waiting.removeValue(forKey: url) ?? []
            guard let data, let image = NSImage(data: data) else { failed.insert(url); return }
            images[url] = image
            for callback in callbacks { callback(image) }
        }
        return nil
    }
}
