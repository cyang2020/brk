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
    private var corpus: @Sendable () -> [ProfileID: [SearchCorpusItem]] = { [:] }
    private var duplicateScopes: () -> [DuplicateScope] = { [] }
    private var lastReported: LocalModelsSnapshot?
    private var indexed: [ProfileID: Int] = [:]
    /// Candidate pairs already posted this session (each tab and its address), so a "no" is not asked again.
    private var askedPairs: Set<String> = []
    private var lastDecisionUsable: Bool?
    let debounce: Duration
    /// Called when JevK5 becomes usable or stops being usable (the decision route reads it).
    var onDecisionAvailability: (@MainActor () -> Void)?

    init(models: LocalModels, debounce: Duration = .seconds(3), send: @escaping @MainActor (Input) -> Void) {
        self.models = models
        self.debounce = debounce
        self.send = send
        models.onChange = { [weak self] in self?.report(); self?.scheduleIndexing() }
    }

    /// The models under `<data folder>/Local Models` (`BRK_LOCAL_MODELS_ROOT` replaces that folder).
    static func live(root dataFolder: URL, send: @escaping @MainActor (Input) -> Void) -> LocalModelServices {
        let root = ProcessInfo.processInfo.environment["BRK_LOCAL_MODELS_ROOT"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? dataFolder.appendingPathComponent("Local Models", isDirectory: true)
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

    /// The card's state at launch, for the store to apply before its first render; later changes go through `report`.
    func initialSnapshot() -> LocalModelsSnapshot {
        let snapshot = Self.snapshot(models, indexed: nil)
        lastReported = snapshot
        return snapshot
    }

    /// Sends the card's state when it changed.
    func report() {
        let usable = models.status(.decision).usable
        if usable != lastDecisionUsable { lastDecisionUsable = usable; onDecisionAvailability?() }
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

    /// The store calls this after every state change; the pass itself runs `debounce` later, and the near-duplicate
    /// search after it.
    func stateChanged(corpus: @escaping @Sendable () -> [ProfileID: [SearchCorpusItem]], duplicates: @escaping () -> [DuplicateScope] = { [] }) {
        self.corpus = corpus
        self.duplicateScopes = duplicates
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
        let corpus = corpus
        let embedder = models.embedder
        running = Task.detached(priority: .utility) { [weak self, log] in
            // Listing a long history takes a while: off the main thread, from the state value the store handed over.
            let wanted = corpus()
            guard let indexes = await self?.indexes(for: Array(wanted.keys)) else { return }
            var counts: [ProfileID: Int] = [:]
            for (profile, index) in indexes {
                let entries = (wanted[profile] ?? []).map { IndexEntry(kind: Self.kind($0.kind), id: $0.id, title: $0.title, url: $0.url) }
                do {
                    try await index.reconcile(entries, embedder: embedder)
                } catch is CancellationError {
                    break
                } catch {
                    log.error("search index for \(profile.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
                }
                counts[profile] = await index.count
            }
            await self?.passFinished(counts)
        }
    }

    /// The profiles' indexes, and every other profile's deleted (a deleted profile, or one with nothing left to find).
    private func indexes(for profiles: [ProfileID]) -> [(ProfileID, SemanticIndex)] {
        models.removeIndexes(except: Set(profiles.map(\.rawValue)))
        return profiles.sorted().map { ($0, models.index(profile: $0.rawValue)) }
    }

    private func passFinished(_ counts: [ProfileID: Int]) {
        running = nil
        indexed = counts
        log.notice("index pass done: \(counts.values.reduce(0, +)) entries, again \(self.again)")
        report()
        if again { again = false; startPass() } else { Task { await postDuplicateCandidates() } }
    }

    nonisolated static func kind(_ kind: SearchCorpusItem.Kind) -> IndexEntry.Kind {
        switch kind {
        case .tab: .tab
        case .history: .history
        case .archive: .archive
        case .conversation: .conversation
        }
    }

    // MARK: For features

    /// The best matches for `query` in a profile's index, best first, at least `minimum` similar; nil when the search
    /// model is not usable.
    func search(_ query: String, profile: ProfileID, limit: Int = 8, kinds: Set<IndexEntry.Kind> = Set(IndexEntry.Kind.allCases),
                minimum: Float = Float(MeaningSearch.minimumScore)) async -> [SearchHit]? {
        guard let embedder = models.embedder else { return nil }
        let index = models.index(profile: profile.rawValue)
        guard let vector = try? await embedder.embed([.query(query)]).first else { return nil }
        return await index.search(vector, limit: limit, kinds: kinds, minimum: minimum)
    }

    /// Tidy's first cut: groups of tab indices by meaning, biggest first, or nil without the search model. Titles are
    /// embedded alone at 768 dimensions, the form measured best for grouping.
    func clusters(titles: [String]) async -> [[Int]]? {
        guard let found = try? await embedClusters(titles) else { return nil }
        return found.groups
    }

    private func embedClusters(_ titles: [String]) async throws -> (vectors: [[Float]], groups: [[Int]])? {
        guard var embedder = models.embedder, !titles.isEmpty else { return nil }
        embedder.dimensions = 768
        let vectors = try await embedder.embed(titles.map { .document(title: nil, text: $0) })
        return (vectors, EmbeddingGroups.clusters(vectors))
    }

    /// The decider when the decision model is usable.
    var decider: LocalDecider? { models.decider }

    /// JevK5 behind slice A's `DecisionBackend`: the basic channel's `localDecisions`.
    lazy var decisionBackend = LocalDecisionBackend(models: models)

    // MARK: Near duplicates

    /// After an index pass: pairs of one Space's tabs at 0.92 or more by meaning whose addresses the address rule does
    /// not already call the same (that rule lists those by itself), posted for the yes/no question. The Today tab is
    /// the copy offered for closing beside a pinned one, else the one shown less recently. Each pair once a session.
    func postDuplicateCandidates() async {
        guard models.status(.search).usable else { return }
        let scopes = duplicateScopes()
        var vectors: [ItemID: [Float]] = [:]
        for scope in scopes {
            let index = models.index(profile: scope.profile.rawValue)
            for entry in scope.entries { vectors[entry.id] = await index.vector(for: "tab:" + entry.id.rawValue) }
        }
        let pairs = Self.duplicatePairs(scopes, vectors: vectors, asked: &askedPairs)
        log.notice("near duplicates: \(scopes.count) spaces, \(vectors.values.count) tabs with vectors, \(pairs.count) new pairs")
        var start = 0
        while start < pairs.count {
            send(.system(.aiDuplicateCandidates(Array(pairs[start..<min(start + 8, pairs.count)]))))
            start += 8
        }
    }
}

extension LocalModelServices {
    /// The candidate pairs of `postDuplicateCandidates` from each tab's vector (tabs without one are left out).
    nonisolated static func duplicatePairs(_ scopes: [DuplicateScope], vectors: [ItemID: [Float]], asked: inout Set<String>) -> [AIDuplicatePair] {
        var pairs: [AIDuplicatePair] = []
        for scope in scopes {
            let entries = scope.entries.filter { vectors[$0.id] != nil }
            for (i, j, similarity) in EmbeddingGroups.duplicateCandidates(entries.map { vectors[$0.id]! }) {
                let x = entries[i], y = entries[j]
                guard !(x.pinned && y.pinned), AICleanup.addressKey(x.url) != AICleanup.addressKey(y.url) else { continue }
                let (copy, keep) = x.pinned ? (y, x) : y.pinned ? (x, y) : x.lastActiveAt <= y.lastActiveAt ? (x, y) : (y, x)
                let key = [x.id.rawValue + "|" + x.url.absoluteString, y.id.rawValue + "|" + y.url.absoluteString].sorted().joined(separator: "\u{1F}")
                guard asked.insert(key).inserted else { continue }
                pairs.append(AIDuplicatePair(a: copy.id, b: keep.id, similarity: Double(similarity)))
            }
        }
        return pairs
    }
}

// MARK: Tidy without a text model

extension LocalModelServices: TabClustering {
    var isAvailable: Bool { models.status(.search).usable }

    /// The clusters of two tabs or more, biggest first, each led by the tab closest to its centre (its name comes from
    /// that tab, `AIBasicChannel.groupName`). Tabs like no other stay out.
    func clusters(_ tabs: [AITab]) async throws -> [[ItemID]] {
        guard let found = try await embedClusters(tabs.map(\.title)) else { throw AIRouteError.message(AICopy.noBasicRoute) }
        return found.groups.filter { $0.count >= 2 }.map { members in
            let center = VectorMath.centroid(members.map { found.vectors[$0] })
            let lead = members.max { VectorMath.dot(found.vectors[$0], center) < VectorMath.dot(found.vectors[$1], center) } ?? members[0]
            return [tabs[lead].id] + members.filter { $0 != lead }.map { tabs[$0].id }
        }
    }
}

// MARK: Place New Tabs on JevK5

extension LocalModelServices: LocalDecisionPreparing {
    /// Slice B's measured placement (112 of 121 tabs with JevK5 Q4): the five groups whose tabs are nearest the new tab
    /// by meaning, worded as the benchmark asked (bench/run.py `placement`), "none of these" kept; `JevNoneRule` then
    /// answers none only at 0.95 or more. Without the search model every group is kept.
    static let placementShortlist = 5
    static let placementInstructions = "A new tab was opened in the user's browser. Which of the user's existing tab groups does it belong in? Choose none when no group is about the same topic."
    static let placementNone = "None of these groups: the tab's topic is not one of them."

    func prepare(_ request: DecisionRequest, hint: AIDecisionHint) async -> DecisionRequest {
        guard case .placement(let key, let subject, let members, let profile) = hint,
              case .choice(_, let options, let none)? = request.questions[key] else { return request }
        var names = options.map(\.name)
        if names.count > Self.placementShortlist, let nearest = await nearestGroups(subject, members: members, among: names, profile: profile) {
            names = nearest
        }
        var asked = request
        asked.state = .string("New tab\nTitle: \(subject.title)\nAddress: \(subject.url.absoluteString.prefix(120))")
        let listed = names.map { name in
            DecisionOption(name, "Group “\(name)”, which holds tabs like: " + (members[name] ?? []).prefix(3).map(\.title).joined(separator: "; "))
        }
        asked.questions[key] = .choice(Self.placementInstructions, options: listed, none: none == nil ? nil : Self.placementNone)
        return asked
    }

    /// The groups closest to the new tab, closest first: the centroid of each group's tabs, read from the index where
    /// it has them (the title and host) and embedded the same way where it does not yet.
    private func nearestGroups(_ subject: AITab, members: [String: [AITab]], among names: [String], profile: ProfileID) async -> [String]? {
        guard let embedder = models.embedder else { return nil }
        let index = models.index(profile: profile.rawValue)
        var vectors: [String: [[Float]]] = [:]
        var missing: [(name: String, tab: AITab)] = []
        for name in names {
            for tab in members[name] ?? [] {
                if let vector = await index.vector(for: "tab:" + tab.id.rawValue) { vectors[name, default: []].append(vector) }
                else { missing.append((name, tab)) }
            }
        }
        func text(_ tab: AITab) -> EmbeddingText { IndexEntry(kind: .tab, id: tab.id.rawValue, title: tab.title, url: tab.url.absoluteString).text }
        guard let embedded = try? await embedder.embed([text(subject)] + missing.map { text($0.tab) }), let target = embedded.first else { return nil }
        for (offset, item) in missing.enumerated() { vectors[item.name, default: []].append(embedded[offset + 1]) }
        let ranked = EmbeddingGroups.nearest(target, groups: names.map { (id: $0, vectors: vectors[$0] ?? []) }, limit: Self.placementShortlist)
        return ranked.isEmpty ? nil : ranked.map(\.id)
    }
}
