import BrkBase

/// Native browser creation can pump the main run loop. Finish that creation before applying newer demand.
@MainActor final class PageReconciliation {
    private var pending: [PageSpec]?
    private(set) var isApplying = false

    func submit(_ pages: [PageSpec], invalidate: () -> Void = {}, apply: ([PageSpec]) -> Void) {
        pending = pages
        let reentered = isApplying
        isApplying = true
        invalidate()
        guard !reentered else { return }
        defer { isApplying = false }
        while let pages = pending {
            pending = nil
            apply(pages)
        }
    }
}
