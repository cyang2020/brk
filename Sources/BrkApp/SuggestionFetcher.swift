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
    private struct Eligibility: Equatable {
        let profileRoot: ItemID
        let opening: Int
        let engine: SearchEngineCandidate
    }
    private struct Pending {
        let id: UUID
        let query: String
        let endpoint: URL
        let eligibility: Eligibility?
        let task: Task<Void, Never>
    }
    private var pending: [WindowID: Pending] = [:]
    private var eligible: [WindowID: Eligibility] = [:]
    private let session: URLSession
    /// `LaunchOptions.suggestOverride`: the e2e fixture's endpoint instead of the engine's.
    private let override: URL?
    private let log = Logger(subsystem: "brk", category: "suggest")

    public init(send: @escaping @MainActor (Input) -> Void, session: URLSession = .shared, override: URL? = LaunchOptions().suggestOverride) {
        self.send = send
        self.session = session
        self.override = override
    }

    public func cancel(_ window: WindowID) { pending.removeValue(forKey: window)?.task.cancel() }

    public func reconcile(_ snapshot: AppSnapshot) {
        eligible = snapshot.windows.compactMapValues { window in
            guard case .commandBar(let bar)? = window.overlay, bar.suggestionsEnabled else { return nil }
            return Eligibility(profileRoot: window.favorites.root, opening: bar.openID, engine: bar.engine)
        }
        for window in Array(pending.keys) {
            guard let request = pending[window], let current = eligible[window] else { cancel(window); continue }
            if let captured = request.eligibility {
                if captured != current { cancel(window) }
            } else if SearchEngine.builtIn(current.engine.id)?.suggestURL(request.query) != request.endpoint {
                cancel(window)
            }
        }
    }

    public func fetch(_ window: WindowID, query: String, url engineURL: URL) {
        cancel(window)
        let id = UUID(), eligibility = eligible[window]
        var url = engineURL
        if let override, var components = URLComponents(url: override, resolvingAgainstBaseURL: false) {
            components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: "q", value: query)]
            url = components.url ?? engineURL
        }
        let session = session, send = send
        let task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Metrics.commandBar.suggestionDebounce.value))
            guard !Task.isCancelled, self.pending[window]?.id == id else { return }
            do {
                let (data, _) = try await session.data(from: url)
                guard !Task.isCancelled, self.pending[window]?.id == id,
                      eligibility == nil || self.eligible[window] == eligibility else { return }
                let results = Self.parse(data)
                self.pending[window] = nil
                send(.system(.suggestions(window, query: query, results)))
            } catch {
                guard !Task.isCancelled, self.pending[window]?.id == id else { return }
                self.pending[window] = nil
                self.log.notice("suggestions failed: \(error)")
            }
        }
        pending[window] = Pending(id: id, query: query, endpoint: engineURL, eligibility: eligibility, task: task)
    }

    /// `["q", ["a", "b"]]` -> ["a", "b"]; anything else -> [].
    public static func parse(_ data: Data) -> [String] {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [Any], json.count >= 2,
              let suggestions = json[1] as? [String] else { return [] }
        return suggestions
    }
}
