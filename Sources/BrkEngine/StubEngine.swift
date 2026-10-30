import AppKit
import BrkBase

/// An engine without Chromium. Each page is a flat view showing its URL; `reconcile` emits `committed` and
/// `titleChanged` (the URL's host) so the sidebar fills in like a real load. Key presses never reach it (no page
/// view takes first responder), so app shortcuts go through the menu path, which is enough for UI work.
@MainActor
public final class StubEngine: WebEngine {
    public weak var delegate: (any WebEngineDelegate)?
    private var pages: [PageID: StubSurface] = [:]

    public init() {}

    public func reconcile(_ specs: [PageSpec]) {
        // TODO(W2): create StubSurface for new specs with a URL (emit .committed, .titleChanged(host), .loadingChanged
        // false); drop surfaces not listed (emit .closed).
        fatalError("not implemented")
    }

    public func surface(for page: PageID) -> PageSurfaceView? { pages[page] }

    public func perform(_ action: PageAction, on page: PageID) {
        // TODO(W2): .navigate -> update the label and emit .committed/.titleChanged; others are no-ops.
        fatalError("not implemented")
    }

    public func focus(_ page: PageID?) {}

    public func facts(for page: PageID) -> PageFacts? {
        guard let surface = pages[page] else { return nil }
        return PageFacts(surfaceFrame: surface.window == nil ? nil : surface.convert(surface.bounds, to: nil),
                         embeddedViews: [], browserID: nil, hostWindowNumber: nil, hasKeyboardFocus: false)
    }

    public func shutdown() async { pages.removeAll() }
}

@MainActor
final class StubSurface: PageSurfaceView {
    let label = NSTextField(labelWithString: "")
}
