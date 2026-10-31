/// Chrome runtime animates its own native host before Brk may transition the containing window.
struct ChromeFullscreenTransition {
    private var transitioning = false
    private var pending: Bool?

    mutating func nativeChanged(completed: Bool) -> Bool? {
        transitioning = !completed
        guard completed else { return nil }
        defer { pending = nil }
        return pending
    }
    mutating func pageChanged(_ fullscreen: Bool) -> Bool? {
        if transitioning { pending = fullscreen; return nil }
        return fullscreen
    }
    mutating func cancelPending() { pending = nil }
}
