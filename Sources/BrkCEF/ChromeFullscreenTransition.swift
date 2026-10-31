/// Chrome runtime animates its own native host before Brk may transition the containing window.
struct ChromeFullscreenTransition {
    private var transitioning = false
    private var nativeFullscreen = false
    private var pending: Bool?
    var isTransitioning: Bool { transitioning || pending != nil }

    mutating func nativeChanged(fullscreen: Bool, completed: Bool) -> Bool? {
        nativeFullscreen = fullscreen
        transitioning = !completed
        guard completed, pending == fullscreen else { return nil }
        defer { pending = nil }
        return pending
    }
    mutating func pageChanged(_ fullscreen: Bool) -> Bool? {
        if transitioning || nativeFullscreen != fullscreen { pending = fullscreen; return nil }
        return fullscreen
    }
    mutating func cancelPending() { pending = nil }
}
