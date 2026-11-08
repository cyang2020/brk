import BrkBase
import BrkDomain
import BrkLocalModels
import Foundation
import os

/// Owner: Brk's local models in the running app (docs/design/ai-native.md, 模型分工 and 分步计划 第 2 步). Runs the Max
/// pane's On This Mac actions, reports downloads to the domain as `SystemEvent.localModels`, and keeps each profile's
/// search index equal to what `AppState.searchCorpus()` lists. Every entry point answers nil or does nothing when a model
/// is absent: features call their fallback then.
///
/// When indexing runs: once the search model is on disk, a few seconds after the state changes (a debounce, so a page's
/// title updates and a burst of new tabs make one pass), and at launch. A pass first drops whatever the state no longer
/// has (cleared history, a removed visit, a deleted archive entry, a closed tab), writing the file at once, then embeds
/// what is new. A scenario's data folder is its own, so no model is there unless the scenario puts one there (or points
/// `BRK_LOCAL_MODELS_ROOT` at a folder that has them).
@MainActor
final class LocalModelServices {
    let models: LocalModels
    private let send: @MainActor (Input) -> Void
    private let log = Logger(subsystem: "Brk", category: "local-models")
    private var pending: Task<Void, Never>?
    private var running: Task<Void, Never>?
    private var again = false
    private var corpus: () -> [ProfileID: [SearchCorpusItem]] = { [:] }
    private var lastReported: LocalModelsSnapshot?
    private var indexed: [ProfileID: Int] = [:]
    let debounce: Duration

    init(models: LocalModels, debounce: Duration = .seconds(3), send: @escaping @MainActor (Input) -> Void) {
        self.models = models
        self.debounce = debounce
        self.send = send
        models.onChange = { [weak self] in self?.report(); self?.scheduleIndexing() }
    }

    static func live(send: @escaping @MainActor (Input) -> Void, options: LaunchOptions = LaunchOptions()) -> LocalModelServices {
        let environment = ProcessInfo.processInfo.environment
        let root = environment["BRK_LOCAL_MODELS_ROOT"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? Product.dataDirectory().appendingPathComponent("Local Models", isDirectory: true)
        return LocalModelServices(models: LocalModels(root: root), send: send)
    }

    // MARK: The card

    func perform(_ action: LocalModelAction) {
        switch action {
        case .download(let kind): models.download(role(kind))
        case .cancel(let kind): models.cancelDownload(role(kind))
        case .remove(let kind):
            models.remove(role(kind))
            if kind == .search { indexed = [:] }
        case .choose(_, let id):
            if let model = ModelCatalog.model(id: id) { models.choose(model) }
        }
        report()
    }

    /// Sends the card's state when it changed.
    func report() {
        let snapshot = Self.snapshot(models, indexed: indexed.isEmpty ? nil : indexed.values.reduce(0, +))
        guard snapshot != lastReported else { return }
        lastReported = snapshot
        send(.system(.localModels(snapshot)))
    }

    static func snapshot(_ models: LocalModels, indexed: Int?) -> LocalModelsSnapshot {
        LocalModelsSnapshot(rows: LocalModelKind.allCases.map { kind in
            let status = models.status(role(kind))
            let choices = ModelCatalog.all.filter { $0.role == role(kind) }
            return LocalModelRow(kind: kind, title: status.model.title, purpose: status.model.purpose, bytes: status.model.bytes,
                                 license: status.model.license, languages: status.model.languages, residentMB: status.model.residentMB,
                                 stage: stage(status.install), runtimeFound: status.runtimeFound,
                                 choices: choices.count > 1 ? choices.map { LocalModelFileChoice(id: $0.id, title: $0.title, bytes: $0.bytes) } : [],
                                 chosen: status.model.id)
        }, indexed: indexed)
    }

    static func stage(_ install: ModelInstall) -> LocalModelStage {
        switch install {
        case .absent: .absent
        case .downloading(let received, let total): .downloading(received: received, total: total)
        case .verifying: .verifying
        case .ready: .ready
        case .failed(let message): .failed(message)
        }
    }

    static func role(_ kind: LocalModelKind) -> LocalModelRole {
        switch kind {
        case .search: .search
        case .decision: .decision
        }
    }

    private func role(_ kind: LocalModelKind) -> LocalModelRole { Self.role(kind) }

    // MARK: The index

    /// The store calls this after every state change; the pass itself runs `debounce` later.
    func stateChanged(corpus: @escaping () -> [ProfileID: [SearchCorpusItem]]) {
        self.corpus = corpus
        scheduleIndexing()
    }

    private func scheduleIndexing() {
        guard models.status(.search).install.isReady || FileManager.default.fileExists(atPath: models.root.appendingPathComponent("Index").path) else { return }
        pending?.cancel()
        let wait = debounce
        pending = Task { [weak self] in
            try? await Task.sleep(for: wait)
            guard !Task.isCancelled else { return }
            self?.startPass()
        }
    }

    private func startPass() {
        guard running == nil else { again = true; return }
        guard models.status(.search).install.isReady else {
            // Vectors are useless without their model: none stay on disk once it is gone.
            models.removeIndexes()
            indexed = [:]
            report()
            return
        }
        let wanted = corpus()
        let embedder = models.embedder
        let indexes = wanted.keys.sorted().map { ($0, models.index(profile: $0.rawValue)) }
        models.removeIndexes(except: Set(wanted.keys.map(\.rawValue)))
        running = Task.detached(priority: .utility) { [weak self, log] in
            var counts: [ProfileID: Int] = [:]
            for (profile, index) in indexes {
                let entries = (wanted[profile] ?? []).map { IndexEntry(kind: Self.kind($0.kind), id: $0.id, title: $0.title, url: $0.url) }
                do {
                    try await index.reconcile(entries, embedder: embedder)
                } catch is CancellationError {
                    return
                } catch {
                    log.error("search index for \(profile.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
                }
                counts[profile] = await index.count
            }
            await self?.passFinished(counts)
        }
    }

    private func passFinished(_ counts: [ProfileID: Int]) {
        running = nil
        indexed = counts
        report()
        if again { again = false; startPass() }
    }

    nonisolated static func kind(_ kind: SearchCorpusItem.Kind) -> IndexEntry.Kind {
        switch kind {
        case .tab: .tab
        case .history: .history
        case .archive: .archive
        }
    }

    // MARK: For features (the command bar and Tidy call these once slice A's wiring lands)

    /// The best matches for `query` in a profile's index, best first, or nil when the search model is not usable.
    func search(_ query: String, profile: ProfileID, limit: Int = 8) async -> [SearchHit]? {
        guard let embedder = models.embedder else { return nil }
        let index = models.index(profile: profile.rawValue)
        guard let vector = try? await embedder.embed([.query(query)]).first else { return nil }
        return await index.search(vector, limit: limit, minimum: 0.5)
    }

    /// Tidy's first cut: groups of tab indices by meaning, biggest first, or nil without the search model. Titles are
    /// embedded alone at 768 dimensions, the form measured best for grouping.
    func clusters(titles: [String]) async -> [[Int]]? {
        guard var embedder = models.embedder, !titles.isEmpty else { return nil }
        embedder.dimensions = 768
        guard let vectors = try? await embedder.embed(titles.map { .document(title: nil, text: $0) }) else { return nil }
        return TabClustering.clusters(vectors)
    }

    /// The decider when the decision model is usable.
    var decider: LocalDecider? { models.decider }
}
