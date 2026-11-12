import AppKit

/// Favicons for command bar rows, Library rows, Boosts and the tab switcher, fetched once per URL. A URL whose fetch
/// failed is not fetched again this run: rows are rebuilt on every keystroke and re-rank.
@MainActor
public final class FaviconCache {
    public static let shared = FaviconCache()
    private var images: [URL: NSImage] = [:]
    private var waiting: [URL: [(NSImage) -> Void]] = [:]
    private var failed: Set<URL> = []
    private let fetch: @Sendable (URL) async -> Data?

    /// Every favicon fetch outside Chromium goes through this (this cache's and the sidebar's): no disk cache, no cookies.
    /// The URLs come from every profile and from incognito windows. Through URLSession.shared an incognito site's
    /// favicon stayed in the app's disk cache after the window was gone, and a cookie it set went out with later fetches.
    nonisolated public static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        return URLSession(configuration: configuration)
    }()

    init(fetch: @escaping @Sendable (URL) async -> Data? = { try? await FaviconCache.session.data(from: $0).0 }) { self.fetch = fetch }

    /// The cached image, or nil now and `then` once it arrives (never, if the fetch fails).
    public func image(for url: URL, then: @escaping (NSImage) -> Void) -> NSImage? {
        if let image = images[url] { return image }
        guard !failed.contains(url) else { return nil }
        if waiting[url] != nil {
            waiting[url]?.append(then)
            return nil
        }
        waiting[url] = [then]
        Task {
            let data = await fetch(url)
            let callbacks = waiting.removeValue(forKey: url) ?? []
            guard let data, let image = NSImage(data: data) else { failed.insert(url); return }
            images[url] = image
            for callback in callbacks { callback(image) }
        }
        return nil
    }
}
