import BrkBase
import Foundation

/// Brk's conservative defaults, independent of Arc's unrecovered tuning values.
struct PageResourcePolicy {
    struct Configuration {
        var freezeAfter: TimeInterval = 300
        var discardAfter: TimeInterval = 1800
        var minimumPressureAge: TimeInterval = 60
        var protectedRecentCount = 3
    }
    enum Pressure { case normal, warning, critical }
    enum Action: Equatable { case active, freeze, discard }
    struct Page {
        let id: BrowserToken
        let lastUsed: TimeInterval
        let hiddenSince: TimeInterval?
        let protected: Bool
        let discarded: Bool
    }

    var configuration = Configuration()

    func actions(for pages: [Page], now: TimeInterval, pressure: Pressure = .normal) -> [BrowserToken: Action] {
        let newest = pages.sorted { $0.lastUsed == $1.lastUsed ? $0.id.page < $1.id.page : $0.lastUsed > $1.lastUsed }
        let keepCount = pressure == .critical ? 1 : configuration.protectedRecentCount
        let recent = Set(newest.prefix(keepCount).map(\.id))
        var result: [BrowserToken: Action] = [:]
        for page in newest.reversed() {
            guard !page.discarded else { continue }
            guard let hidden = page.hiddenSince, !page.protected, !recent.contains(page.id) else {
                result[page.id] = .active
                continue
            }
            let age = max(0, now - hidden)
            let underPressure = pressure != .normal && age >= configuration.minimumPressureAge
            if underPressure || age >= configuration.discardAfter {
                result[page.id] = .discard
            } else {
                result[page.id] = age >= configuration.freezeAfter ? .freeze : .active
            }
        }
        return result
    }
}
