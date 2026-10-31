/// DOM requests may arrive while AppKit is animating a previous fullscreen transition.
struct PageFullscreenTransition {
    private var restoreNative: Bool?
    private var pending: Bool?
    private var transitionTarget: Bool?

    mutating func pageChanged(_ on: Bool, nativeFullscreen: Bool) {
        if on {
            if restoreNative == nil {
                // Chrome can begin native entry before its DOM callback; the transition is not a prior native session.
                restoreNative = pending ?? (transitionTarget == nil ? nativeFullscreen : false)
            }
            pending = true
        } else if let original = restoreNative {
            restoreNative = nil
            pending = original
        }
    }
    mutating func nativeWillChange(to fullscreen: Bool) { transitionTarget = fullscreen }
    mutating func nativeDidChange() { transitionTarget = nil }
    mutating func nativeExited() -> Bool {
        let exitDocument = nativeExitShouldExitDocument
        if exitDocument { restoreNative = false }
        transitionTarget = nil
        return exitDocument
    }
    mutating func needsToggle(nativeFullscreen: Bool) -> Bool {
        guard transitionTarget == nil, let target = pending else { return false }
        pending = nil
        return target != nativeFullscreen
    }
    var nativeExitShouldExitDocument: Bool { restoreNative != nil && pending != true }
}
