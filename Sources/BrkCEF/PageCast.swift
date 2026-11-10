import AppKit
import BrkBase
import BrkEngine
import CefKit

/// Native controls and CEF references for one page's Cast panel. A page in an owned profile uses its own request
/// context's router. The Default profile's pages use the engine's receiver-service context (`CEFEngine.castService`):
/// the pinned CEF global context's router traps inside `cef_shutdown` (3ef85fca08:verify/completion/batch2-browser-ops/
/// CAST-LIFETIME.md), while an owned context drains like any custom profile. A presentation route's source is a
/// Cast or DIAL address, not the page, so the context that discovers receivers does not change what is cast.
@MainActor final class PageCast: NSObject {
    let id = UUID().uuidString
    private(set) var router: CefMediaRouting?
    private(set) var unavailableReason: String?
    /// The receiver-service context is still loading (Default profile, first Cast of the run).
    private(set) var startingService: Bool
    var visibleWindowNumber: Int? { panel.isVisible ? panel.windowNumber : nil }
    private let panel: NSPanel
    private let receivers = NSPopUpButton(frame: .zero, pullsDown: false)
    private let source = NSTextField(string: "")
    private let status = NSTextField(wrappingLabelWithString: "Discovering receivers…")
    private let connectButton = NSButton(title: "Connect", target: nil, action: nil)
    private let stopButton = NSButton(title: "Stop Casting", target: nil, action: nil)

    init(browser: CefBrowser, startingService: Bool) {
        self.startingService = startingService
        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 540, height: 260),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        super.init()
        panel.title = "Cast Presentation"
        panel.isReleasedWhenClosed = false
        let description = NSTextField(wrappingLabelWithString: "Choose a receiver and a Cast or DIAL presentation address. This Chromium build does not expose tab or desktop mirroring through its media router.")
        source.placeholderString = "Cast or DIAL presentation address"
        if let url = browser.url, ["cast", "dial"].contains(url.scheme ?? "") { source.stringValue = url.absoluteString }
        connectButton.target = self; connectButton.action = #selector(connect)
        stopButton.target = self; stopButton.action = #selector(stopRoutes)
        let refresh = NSButton(title: "Refresh", target: self, action: #selector(refresh))
        let buttons = NSStackView(views: [connectButton, stopButton, refresh]); buttons.spacing = 12
        let stack = NSStackView(views: [description, receivers, source, status, buttons])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        panel.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: panel.contentView!.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: panel.contentView!.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: panel.contentView!.topAnchor, constant: 20),
            source.widthAnchor.constraint(equalTo: stack.widthAnchor), receivers.widthAnchor.constraint(equalTo: stack.widthAnchor)
        ])
        render()
    }
    /// Installs the router once its context exists (nil: none could be created).
    func attach(_ router: CefMediaRouting?, unavailableReason: String?) {
        startingService = false
        self.router = router
        self.unavailableReason = router == nil ? (unavailableReason ?? "The receiver service is unavailable for this page.") : nil
        router?.onChange = { [weak self] in self?.render() }
        router?.refresh()
        render()
    }
    func show() { if !panel.isVisible { panel.center() }; panel.makeKeyAndOrderFront(nil); router?.refresh() }
    private func render() {
        let selected = receivers.selectedItem?.representedObject as? String
        receivers.removeAllItems()
        for sink in router?.sinks ?? [] {
            receivers.addItem(withTitle: sink.name); receivers.lastItem?.representedObject = sink.id
            if sink.id == selected { receivers.select(receivers.lastItem) }
        }
        connectButton.isEnabled = !(router?.sinks.isEmpty ?? true)
        source.isEnabled = router != nil
        receivers.isEnabled = router != nil
        stopButton.isEnabled = (router?.ownedRouteCount ?? 0) > 0
        status.stringValue = startingService ? "Starting the receiver service…" : unavailableReason ?? router?.lastError ?? ((router?.sinks.isEmpty ?? true) ? "No receivers found on this network." : "\(router?.sinks.count ?? 0) receiver(s), \(router?.routes.count ?? 0) route(s)")
    }
    @objc private func connect() {
        guard let id = receivers.selectedItem?.representedObject as? String else { return }
        router?.connect(sourceURN: source.stringValue, sinkID: id)
    }
    @objc private func stopRoutes() { router?.terminateOwnedRoutes(); router?.refresh() }
    @objc private func refresh() { router?.refresh() }
    func stop() { panel.close(); startingService = false; router?.stop() }
}

extension ChromePage {
    func showCast() {
        guard engine.isLive(self), surface.window?.isVisible == true else { return }
        if cast == nil {
            let shared = context == .profile(.default)
            let controller = PageCast(browser: browser, startingService: shared)
            cast = controller
            if shared {
                engine.castServiceContext { [weak self, weak controller] context in
                    guard let self, let controller, self.cast === controller, self.engine.isLive(self) else { return }
                    self.attachCast(context.flatMap { CefMediaRouting(context: $0) }, to: controller,
                                    reason: "The receiver service could not start in this session.")
                }
            } else {
                attachCast(CefMediaRouting(browser: browser), to: controller, reason: nil)
            }
        }
        cast?.show()
    }
    private func attachCast(_ router: CefMediaRouting?, to controller: PageCast, reason: String?) {
        let lease = BrowserResources<ChromePage>.Lease.auxiliary("cast-" + controller.id)
        router?.onPendingChange = { [weak self, weak controller] pending in
            guard let self else { return }
            if pending { _ = self.engine.resources.acquire(lease, browser: self.incarnation) }
            else {
                self.drainingCasts.removeAll { $0 === controller }
                self.engine.resources.release(lease, browser: self.incarnation)
                self.engine.closeIfUnowned(self.incarnation)
            }
        }
        controller.attach(router, unavailableReason: reason)
        if ProcessInfo.processInfo.environment["BRK_CONTROL_SOCKET"] != nil, let url = browser.url { router?.validateSource(url.absoluteString) }
    }
    func stopCasting() {
        guard let cast else { return }
        self.cast = nil
        if cast.router?.hasPendingRoutes == true { drainingCasts.append(cast) }
        cast.stop()
    }
}
