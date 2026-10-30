import AppKit
import BrkBase

/// An engine without Chromium, complete. Each page is a flat white view showing its URL; `reconcile` and
/// `navigate` emit `loadingChanged`, `committed`, `titleChanged` (the URL's host) and `loadingChanged` again, so
/// the sidebar fills in like a real load. Events are delivered synchronously inside the call (`AppStore` queues
/// re-entrant inputs, so this is safe) and in the order a real page would send them. Key presses never reach it
/// unless a stub surface is first responder; app shortcuts go through the menu path, which is enough for UI work.
///
/// `BRK_ENGINE=stub swift run Brk` runs the whole shell on this engine so sidebar, command bar and theme work can be
/// run and screenshotted without downloading CEF.
@MainActor
public final class StubEngine: WebEngine {
    public weak var delegate: (any WebEngineDelegate)?
    private var pages: [PageID: StubSurface] = [:]
    private var ledger = PageLedger()
    public private(set) var pageLog: [PageLogEntry] = []
    private var shutdownOutcome: ShutdownOutcome?

    public init() {}

    public func reconcile(_ specs: [PageSpec]) {
        guard shutdownOutcome == nil else { return }
        let wanted = Dictionary(specs.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        for (id, surface) in pages where wanted[id] == nil {
            pages[id] = nil
            if let incarnation = ledger.retire(id) {
                log(.closeRequested, incarnation)
                finishClosing(surface, incarnation)
            }
        }
        for spec in specs where pages[spec.id] == nil {
            guard let url = spec.initialURL else { continue }
            let incarnation = ledger.create(spec.id)
            let surface = StubSurface(page: spec.id, incarnation: incarnation)
            pages[spec.id] = surface
            log(.created, incarnation)
            load(url, in: surface)
        }
    }

    public func surface(for page: PageID) -> PageSurfaceView? { pages[page] }

    public func perform(_ action: PageAction, on page: PageID) {
        guard let surface = pages[page] else { return }
        switch action {
        case .navigate(let url): load(url, in: surface)
        case .reload, .recover: if let url = surface.url { load(url, in: surface) }
        case .goBack, .goForward, .stop, .zoom, .toggleDevTools: break
        }
    }

    public func focus(_ page: PageID?, in window: NSWindow) {
        guard let page, let surface = pages[page] else {
            for surface in pages.values where surface.window === window && window.firstResponder === surface {
                window.makeFirstResponder(nil)
            }
            return
        }
        guard surface.window === window else { return }
        window.makeFirstResponder(surface)
    }

    public func evaluate(_ script: String, in page: PageID) {
        // No JavaScript engine: recorded on the surface so a test can see the call reached the page.
        pages[page]?.evaluated.append(script)
    }

    /// The stub has no request contexts; nothing to forget.
    public func forget(_ context: BrowsingContext) {}

    public func facts(for page: PageID) -> PageFacts? {
        guard let surface = pages[page] else { return nil }
        return PageFacts(surfaceFrame: surface.frameInWindow, embeddedViews: [], browserID: nil, hostWindowNumber: nil,
                         hasKeyboardFocus: surface.window?.firstResponder === surface)
    }

    public func shutdown() async -> ShutdownOutcome {
        if let shutdownOutcome { return shutdownOutcome }
        for (id, surface) in pages {
            if let incarnation = ledger.retire(id) {
                log(.closeRequested, incarnation)
                finishClosing(surface, incarnation)
            }
        }
        pages.removeAll()
        shutdownOutcome = .clean
        return .clean
    }

    // MARK: Private

    private func load(_ url: URL, in surface: StubSurface) {
        surface.show(url)
        let id = surface.page
        delegate?.engine(self, page: id, didEmit: .loadingChanged(isLoading: true, canGoBack: false, canGoForward: false))
        delegate?.engine(self, page: id, didEmit: .committed(url))
        delegate?.engine(self, page: id, didEmit: .titleChanged(url.host ?? url.absoluteString))
        delegate?.engine(self, page: id, didEmit: .loadingChanged(isLoading: false, canGoBack: false, canGoForward: false))
    }

    /// The stub has no asynchronous close: OnBeforeClose follows the request at once.
    private func finishClosing(_ surface: StubSurface, _ incarnation: PageLedger.Incarnation) {
        surface.removeFromSuperview()
        switch ledger.closed(incarnation) {
        case .retiredClosed(let idLiveAgain):
            log(.closed, incarnation)
            if !idLiveAgain { delegate?.engine(self, page: incarnation.page, didEmit: .closed) }
        case .liveClosedByPage, .stale:
            break
        }
    }

    private func log(_ kind: PageLogEntry.Kind, _ incarnation: PageLedger.Incarnation) {
        pageLog.append(PageLogEntry(page: incarnation.page, generation: incarnation.generation, kind: kind, browserID: nil,
                                    uptime: ProcessInfo.processInfo.systemUptime))
    }
}

@MainActor
final class StubSurface: PageSurfaceView {
    let incarnation: PageLedger.Incarnation
    private(set) var url: URL?
    var evaluated: [String] = []
    private let label = NSTextField(labelWithString: "")

    init(page: PageID, incarnation: PageLedger.Incarnation) {
        self.incarnation = incarnation
        super.init(page: page)
        layer?.backgroundColor = NSColor.white.cgColor
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: centerXAnchor),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 8),
        ])
    }

    override var acceptsFirstResponder: Bool { true }

    /// The stub page consumes no key, so the window's shortcut table may decide before AppKit's own handling
    /// (NSWindow takes Ctrl+Tab for keyboard navigation before any view's `keyDown`); a real engine's surface keeps
    /// the default, because Chromium must see the key first (CEF's handler then routes it).
    override var routesKeysThroughWindow: Bool { true }

    func show(_ url: URL) {
        self.url = url
        label.stringValue = url.absoluteString
    }

    var frameInWindow: CGRect? {
        guard let window, let content = window.contentView else { return nil }
        let r = convert(bounds, to: content)
        return content.isFlipped ? r : CGRect(x: r.minX, y: content.bounds.height - r.maxY, width: r.width, height: r.height)
    }
}
