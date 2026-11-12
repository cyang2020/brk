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

    init(fetch: @escaping @Sendable (URL) async -> Data? = { try? await URLSession.shared.data(from: $0).0 }) { self.fetch = fetch }

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
