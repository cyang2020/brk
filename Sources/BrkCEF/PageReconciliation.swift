import BrkBase

/// Native browser creation can pump the main run loop. Finish that creation before applying newer demand.
@MainActor final class PageReconciliation {
    private var pending: [PageSpec]?
    private(set) var isApplying = false

    func submit(_ pages: [PageSpec], apply: ([PageSpec]) -> Void) {
        pending = pages
        guard !isApplying else { return }
        isApplying = true
        defer { isApplying = false }
        while let pages = pending {
            pending = nil
            apply(pages)
        }
    }
}
