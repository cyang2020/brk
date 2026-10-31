import BrkBase

/// Native page construction can pump callbacks before its resource has been installed. Finish that pass before
/// replaying nested demand, including an identical replay caused by a newly ready browsing context.
@MainActor
public final class PageReconciliation {
    /// True while a demand pass runs; context disposal and shutdown drains wait for it.
    public private(set) var isApplying = false
    private var pending: [PageSpec]?
    public init() {}

    /// `invalidate` runs synchronously on every submit, nested ones included, while `isApplying` is true, so a
    /// reassigned page's old presentation is gone before the caller returns; only the outermost pass applies.
    public func submit(_ pages: [PageSpec], invalidate: () -> Void = {}, apply: ([PageSpec]) -> Void) {
        pending = pages
        let reentered = isApplying
        isApplying = true
        invalidate()
        guard !reentered else { return }
        defer { isApplying = false }
        while let next = pending {
            pending = nil
            apply(next)
        }
    }
}
