import BrkBase
import BrkDomain
import BrkLocalModels
import Foundation

/// Search by meaning for the command bar, the History page and the agent panel's @ list (docs/design/ai-native.md,
/// 基础 AI 功能 "按意思搜"), on the local search model's index (`LocalModelServices.search`). Debounced like the engine's
/// suggestions; a newer text for the same place cancels the older search. Without the search model nothing is sent and
/// the three places show what they showed before.
@MainActor
final class MeaningSearchService {
    private let models: LocalModelServices
    private let send: @MainActor (Input) -> Void
    private let state: @MainActor () -> AppState?
    private let debounce: Duration
    private var pending: [String: Task<Void, Never>] = [:]

    /// Rows found per place, at most: the bar shows two of them under its own rows, the page and the @ list more.
    static let limits: [MeaningScope: Int] = [.commandBar: 6, .history: 12]
    static let mentionLimit = 8

    init(models: LocalModelServices, debounce: Duration = .seconds(Metrics.commandBar.suggestionDebounce.value),
         send: @escaping @MainActor (Input) -> Void, state: @escaping @MainActor () -> AppState?) {
        self.models = models
        self.debounce = debounce
        self.send = send
        self.state = state
    }

    private static func key(_ window: WindowID, _ place: String) -> String { window.rawValue + "|" + place }

    func cancel(_ window: WindowID, _ scope: MeaningScope) { pending.removeValue(forKey: Self.key(window, scope.rawValue))?.cancel() }

    /// `Effect.searchByMeaning`: the answer is `SystemEvent.meaningResults`, also when nothing matched (the place then
    /// drops older matches).
    func search(_ window: WindowID, _ query: MeaningQuery) {
        let key = Self.key(window, query.scope.rawValue)
        pending.removeValue(forKey: key)?.cancel()
        let kinds: Set<IndexEntry.Kind> = query.scope == .history ? [.history] : Set(IndexEntry.Kind.allCases)
        let limit = Self.limits[query.scope] ?? 8
        pending[key] = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled, let self else { return }
            guard let hits = await models.search(query.text, profile: query.profile, limit: limit, kinds: kinds), !Task.isCancelled else { return }
            pending[key] = nil
            send(.system(.meaningResults(window, MeaningResults(text: query.text, scope: query.scope, hits: hits.map { MeaningHit(key: $0.key, score: Double($0.score)) }))))
        }
    }

    /// `Effect.aiMentionSearch`: the agent panel's @ text; matches go back as the tab tools' ids
    /// (`SystemEvent.aiMentionMatches`), after the panel's own title and address matches.
    func mention(_ window: WindowID, _ text: String) {
        let key = Self.key(window, "mention")
        pending.removeValue(forKey: key)?.cancel()
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= MeaningSearch.minimumLength, let profile = state()?.agentProfile(in: window) else { return }
        pending[key] = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled, let self else { return }
            guard let hits = await models.search(query, profile: profile, limit: Self.mentionLimit), !Task.isCancelled, let now = state() else { return }
            pending[key] = nil
            let ids = hits.compactMap { now.agentTabID(forIndexKey: $0.key, profile: profile) }
            guard !ids.isEmpty else { return }
            send(.system(.aiMentionMatches(window, query: text, ids)))
        }
    }

    /// Windows that went away, or whose bar closed, stop their searches.
    func reconcile(_ snapshot: AppSnapshot) {
        for key in Array(pending.keys) {
            let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { continue }
            let window = WindowID(parts[0])
            guard let shown = snapshot.windows[window] else { pending.removeValue(forKey: key)?.cancel(); continue }
            if parts[1] == MeaningScope.commandBar.rawValue, case .commandBar? = shown.overlay { continue }
            if parts[1] == MeaningScope.commandBar.rawValue { pending.removeValue(forKey: key)?.cancel() }
        }
    }
}
