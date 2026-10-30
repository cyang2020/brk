import BrkBase

/// Revocation fences both synchronous demand and asynchronous context readiness.
public struct ContextLifetimes: Sendable {
    private var revoked: Set<BrowsingContext> = []
    private var loading: Set<BrowsingContext> = []
    private var ready: Set<BrowsingContext> = []
    private var epochs: [BrowsingContext: ContextEpoch] = [:]
    private var generation: UInt64 = 0
    private var running = true
    public init() {}
    public func permitsWork(_ context: BrowsingContext) -> Bool { running && !revoked.contains(context) }
    public mutating func revoke(_ context: BrowsingContext) { revoked.insert(context) }
    public mutating func stop() { running = false }
    public mutating func epoch(for context: BrowsingContext) -> ContextEpoch {
        if let epoch = epochs[context] { return epoch }
        generation += 1
        let epoch = ContextEpoch(context: context, generation: generation)
        epochs[context] = epoch
        return epoch
    }
    public func isReady(_ context: BrowsingContext) -> Bool {
        guard permitsWork(context) else { return false }
        if case .profile(let id) = context, id != .default { return ready.contains(context) }
        return true
    }
    public mutating func beginLoading(_ context: BrowsingContext) -> Bool {
        guard permitsWork(context), !ready.contains(context) else { return false }
        return loading.insert(context).inserted
    }
    @discardableResult public mutating func initialized(_ context: BrowsingContext) -> Bool {
        guard loading.remove(context) != nil else { return false }
        ready.insert(context)
        return permitsWork(context)
    }
    public func isDrained(_ context: BrowsingContext) -> Bool { !loading.contains(context) }
    public var readinessDrained: Bool { loading.isEmpty }
}
