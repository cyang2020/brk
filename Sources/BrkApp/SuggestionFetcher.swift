import BrkBase
import BrkDomain
import Foundation
import os

/// Owner: F4. Fetches the default engine's OpenSearch suggestions for the command bar (`Effect.fetchSuggestions`),
/// debounced by Metrics.commandBar.suggestionDebounce so typing does not fire a request per key, and answers with
/// `SystemEvent.suggestions(window, query:, results)`. The answer format is the OpenSearch JSON every engine uses:
/// `["query", ["s1", "s2", ...]]`. A newer request for the same window cancels the older one.
@MainActor
public final class SuggestionFetcher {
    private let send: @MainActor (Input) -> Void
    private var pending: [WindowID: Task<Void, Never>] = [:]
    private let session: URLSession
    /// `LaunchOptions.suggestOverride`: the e2e fixture's endpoint instead of the engine's.
    private let override: URL?
    private let log = Logger(subsystem: "brk", category: "suggest")

    public init(send: @escaping @MainActor (Input) -> Void, session: URLSession = .shared, override: URL? = LaunchOptions().suggestOverride) {
        self.send = send
        self.session = session
        self.override = override
    }

    public func fetch(_ window: WindowID, query: String, url engineURL: URL) {
        pending[window]?.cancel()
        var url = engineURL
        if let override, var components = URLComponents(url: override, resolvingAgainstBaseURL: false) {
            components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "q", value: query)]
            url = components.url ?? engineURL
        }
        let session = session, send = send
        pending[window] = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Metrics.commandBar.suggestionDebounce.value))
            guard !Task.isCancelled else { return }
            do {
                let (data, _) = try await session.data(from: url)
                guard !Task.isCancelled else { return }
                let results = Self.parse(data)
                send(.system(.suggestions(window, query: query, results)))
            } catch {
                guard !Task.isCancelled else { return }
                self.log.notice("suggestions for \"\(query, privacy: .public)\" failed: \(error)")
            }
        }
    }

    /// `["q", ["a", "b"]]` -> ["a", "b"]; anything else -> [].
    public static func parse(_ data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [Any], json.count >= 2,
              let suggestions = json[1] as? [String] else { return [] }
        return suggestions
    }
}
