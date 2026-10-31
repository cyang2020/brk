import BrkBase

/// Native page construction can pump callbacks before its resource has been installed. Finish that pass before
/// replaying nested demand, including an identical replay caused by a newly ready browsing context.
@MainActor
public final class PageReconciliation {
    private var applying = false
    private var pending: [PageSpec]?
    public init() {}

    public func submit(_ pages: [PageSpec], apply: ([PageSpec]) -> Void) {
        pending = pages
        guard !applying else { return }
        applying = true
        defer { applying = false }
        while let next = pending {
            pending = nil
            apply(next)
        }
    }
}
