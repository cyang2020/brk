import BrkBase

/// Which incarnation of each page id is live and which are still closing, so a retired incarnation's close callback
/// never touches a newer one with the same id. Pure, shared by every engine; the CEF engine keys its browsers by the
/// `Incarnation` this hands out.
///
/// Life of an id: `create` makes it live with a fresh generation. `retire` (reconcile stopped listing it, or
/// shutdown) moves it to closing; the id may be created again at once. `closed` (OnBeforeClose) says what the
/// engine may do: report closure for the id only when no newer incarnation is live, treat a close of a still-live
/// incarnation as page-initiated, and ignore an incarnation it does not know.
public struct PageLedger: Sendable, Equatable {
    public typealias Incarnation = BrowserToken

    public enum CloseEffect: Hashable, Sendable {
        /// A retired incarnation finished closing. `idLiveAgain` is true when a newer incarnation of the id is live:
        /// then nothing about the id may be reported or removed.
        case retiredClosed(idLiveAgain: Bool)
        /// A live incarnation closed without being retired: the page closed itself. The engine drops it from the
        /// live set and reports `.closedByPage` then `.closed`.
        case liveClosedByPage
        /// Not a known incarnation (already handled, or never created). Ignore.
        case stale
    }

    private var live: [PageID: UInt64] = [:]
    private var closing: Set<Incarnation> = []
    private var nextGeneration: UInt64 = 1

    public init() {}

    public var liveCount: Int { live.count }
    public var closingCount: Int { closing.count }
    public var closingIncarnations: [Incarnation] { closing.sorted { ($0.page, $0.generation) < ($1.page, $1.generation) } }

    public func isLive(_ incarnation: Incarnation) -> Bool { live[incarnation.page] == incarnation.generation }
    public func liveGeneration(of page: PageID) -> UInt64? { live[page] }

    /// Makes `page` live with a new generation. A still-live incarnation of the same id is retired first.
    public mutating func create(_ page: PageID) -> Incarnation {
        if live[page] != nil { _ = retire(page) }
        let incarnation = Incarnation(page: page, generation: nextGeneration)
        nextGeneration += 1
        live[page] = incarnation.generation
        return incarnation
    }

    /// Moves the live incarnation of `page` to closing; nil when none is live.
    public mutating func retire(_ page: PageID) -> Incarnation? {
        guard let generation = live.removeValue(forKey: page) else { return nil }
        let incarnation = Incarnation(page: page, generation: generation)
        closing.insert(incarnation)
        return incarnation
    }

    /// OnBeforeClose for `incarnation`.
    public mutating func closed(_ incarnation: Incarnation) -> CloseEffect {
        if closing.remove(incarnation) != nil {
            return .retiredClosed(idLiveAgain: live[incarnation.page] != nil)
        }
        if live[incarnation.page] == incarnation.generation {
            live[incarnation.page] = nil
            return .liveClosedByPage
        }
        return .stale
    }
}
