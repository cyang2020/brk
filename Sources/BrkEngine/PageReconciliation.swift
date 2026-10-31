import BrkBase

/// Native page construction can pump callbacks before its resource has been installed. Finish that pass before
/// replaying nested demand, including an identical replay caused by a newly ready browsing context.
@MainActor
public final class PageReconciliation {
    /// True while a demand pass runs; context disposal and shutdown drains wait for it.
    public private(set) var isApplying = false
    private var pending: [PageSpec]?
    public init() {}

    public func submit(_ pages: [PageSpec], apply: ([PageSpec]) -> Void) {
        pending = pages
        guard !isApplying else { return }
        isApplying = true
        defer { isApplying = false }
        while let next = pending {
            pending = nil
            apply(next)
        }
    }
}
