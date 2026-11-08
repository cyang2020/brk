import BrkBase
import Foundation

/// What the Max pane shows for one role: the model, where its download is, and whether Brk can run it.
public struct LocalModelStatus: Hashable, Sendable {
    public var role: LocalModelRole
    public var model: LocalModel
    public var install: ModelInstall
    /// This copy of Brk has the runtime (llama-server) to run it.
    public var runtimeFound: Bool
    /// The helper process is up with the model loaded.
    public var running: Bool

    /// Downloaded and runnable: features use it. Anything else, they use their fallback.
    public var usable: Bool { install.isReady && runtimeFound }
}

/// Brk's local models: the downloads, one helper process per role, the search index per profile. Every feature that
/// calls in here keeps working when a model is absent (the plan's rule: local models make features faster and cheaper,
/// they never decide whether a feature works), so every accessor can answer nil.
@MainActor
public final class LocalModels {
    public let root: URL
    public let store: ModelStore
    private let runtime: URL?
    private var helpers: [LocalModelRole: ModelHelper] = [:]
    private var indexes: [String: SemanticIndex] = [:]
    private var choice: [LocalModelRole: LocalModel]
    /// Called when a status changes (download progress included), on the main actor.
    public var onChange: (@MainActor () -> Void)?

    public init(root: URL = Product.dataDirectory().appendingPathComponent("Local Models", isDirectory: true),
                runtime: URL? = LlamaRuntime.executable(), models: [LocalModel] = ModelCatalog.all) {
        self.root = root
        self.runtime = runtime
        store = ModelStore(root: root, models: models)
        choice = Dictionary(uniqueKeysWithValues: LocalModelRole.allCases.map { ($0, ModelCatalog.standard($0)) })
        // A role uses whichever of its models is already on disk, the standard one first.
        for role in LocalModelRole.allCases {
            if let present = ([ModelCatalog.standard(role)] + models.filter { $0.role == role }).first(where: { store.state($0).isReady }) {
                choice[role] = present
            }
        }
        store.onChange = { [weak self] id, state in self?.changed(id, state) }
    }

    public func model(for role: LocalModelRole) -> LocalModel { choice[role] ?? ModelCatalog.standard(role) }

    public func status(_ role: LocalModelRole) -> LocalModelStatus {
        let model = model(for: role)
        return LocalModelStatus(role: role, model: model, install: store.state(model), runtimeFound: runtime != nil, running: false)
    }

    public var statuses: [LocalModelStatus] { LocalModelRole.allCases.map(status) }

    /// Picks which model a role downloads and uses (JevK5's 4-bit or 8-bit file).
    public func choose(_ model: LocalModel) {
        guard choice[model.role] != model else { return }
        if let helper = helpers.removeValue(forKey: model.role) { Task { await helper.stop() } }
        choice[model.role] = model
        onChange?()
    }

    public func download(_ role: LocalModelRole) { store.download(model(for: role)) }
    public func cancelDownload(_ role: LocalModelRole) { store.cancel(model(for: role)) }

    /// Deletes the role's model; removing the search model deletes every profile's index with it.
    public func remove(_ role: LocalModelRole) {
        if let helper = helpers.removeValue(forKey: role) { Task { await helper.stop() } }
        for model in ModelCatalog.all where model.role == role { store.remove(model) }
        if role == .search { removeIndexes() }
    }

    /// The embedder when the search model is downloaded and the runtime is present.
    public var embedder: LocalEmbedder? { helper(.search).map { LocalEmbedder(helper: $0) } }

    /// The decider when the decision model is downloaded and the runtime is present.
    public var decider: LocalDecider? { helper(.decision).map { LocalDecider(helper: $0) } }

    private func helper(_ role: LocalModelRole) -> ModelHelper? {
        let model = model(for: role)
        guard let runtime, let file = store.file(model) else { return nil }
        if let helper = helpers[role], helper.model == model { return helper }
        let helper = ModelHelper(model: model, modelFile: file, executable: runtime, runFolder: runFolder,
                                 idleTimeout: role == .search ? .seconds(600) : .seconds(300))
        helpers[role] = helper
        return helper
    }

    /// The socket and log folder. Short on purpose: a Unix socket path has at most 103 bytes.
    var runFolder: URL {
        let candidate = root.appendingPathComponent("run", isDirectory: true)
        if candidate.path.utf8.count + 16 < 100 { return candidate }
        return URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true).appendingPathComponent("brk-models-\(getuid())", isDirectory: true)
    }

    /// The search index of a profile (created empty; filled by `SemanticIndex.reconcile`).
    public func index(profile: String) -> SemanticIndex {
        if let index = indexes[profile] { return index }
        let index = SemanticIndex(file: root.appendingPathComponent("Index", isDirectory: true).appendingPathComponent(indexFileName(profile)))
        indexes[profile] = index
        return index
    }

    /// Deletes a profile's index (the profile was deleted).
    public func removeIndex(profile: String) {
        let index = self.index(profile: profile)
        indexes[profile] = nil
        Task { await index.removeAll() }
    }

    public func removeIndexes() {
        for index in indexes.values { Task { await index.removeAll() } }
        indexes = [:]
        try? FileManager.default.removeItem(at: root.appendingPathComponent("Index", isDirectory: true))
    }

    /// Deletes the index of every profile not in `profiles` (a deleted profile, or one with nothing left to find).
    public func removeIndexes(except profiles: Set<String>) {
        for profile in indexes.keys where !profiles.contains(profile) { removeIndex(profile: profile) }
        let folder = root.appendingPathComponent("Index", isDirectory: true)
        let keep = Set(profiles.map { indexFileName($0) })
        for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] where !keep.contains(name) {
            try? FileManager.default.removeItem(at: folder.appendingPathComponent(name))
        }
    }

    func indexFileName(_ profile: String) -> String {
        String(profile.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" }) + ".vectors"
    }

    /// Ends the helpers (Brk is quitting).
    public func shutdown() async {
        for helper in helpers.values { await helper.stop() }
        helpers = [:]
    }

    private func changed(_ id: String, _ state: ModelInstall) {
        if state.isReady, let model = ModelCatalog.model(id: id) { choice[model.role] = model }
        onChange?()
    }
}
