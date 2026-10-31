import AppKit
import BrkBase
import BrkEngine
import CefKit

/// Native controls and CEF references belonging to one page's original request context.
@MainActor final class PageCast: NSObject {
    let id = UUID().uuidString
    let router: CefMediaRouting?
    let unavailableReason: String?
    var visibleWindowNumber: Int? { panel.isVisible ? panel.windowNumber : nil }
    private let panel: NSPanel
    private let receivers = NSPopUpButton(frame: .zero, pullsDown: false)
    private let source = NSTextField(string: "")
    private let status = NSTextField(wrappingLabelWithString: "Discovering receivers…")
    private let connectButton = NSButton(title: "Connect", target: nil, action: nil)
    private let stopButton = NSButton(title: "Stop Casting", target: nil, action: nil)

    init(browser: CefBrowser, context: BrowsingContext) {
        // The pinned CEF global router traps during runtime shutdown; an owned profile drains safely.
        if context == .profile(.default) {
            router = nil
            unavailableReason = "Cast is unavailable in the Default profile because this Chromium build cannot close its receiver service safely. Use a separate profile for Cast presentations."
        } else {
            router = CefMediaRouting(browser: browser)
            unavailableReason = router == nil ? "The receiver service is unavailable for this page." : nil
        }
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
        status.stringValue = unavailableReason ?? router?.lastError ?? ((router?.sinks.isEmpty ?? true) ? "No receivers found on this network." : "\(router?.sinks.count ?? 0) receiver(s), \(router?.routes.count ?? 0) route(s)")
    }
    @objc private func connect() {
        guard let id = receivers.selectedItem?.representedObject as? String else { return }
        router?.connect(sourceURN: source.stringValue, sinkID: id)
    }
    @objc private func stopRoutes() { router?.terminateOwnedRoutes(); router?.refresh() }
    @objc private func refresh() { router?.refresh() }
    func stop() { panel.close(); router?.stop() }
}

extension ChromePage {
    func showCast() {
        guard engine.isLive(self), surface.window?.isVisible == true else { return }
        if cast == nil {
            let controller = PageCast(browser: browser, context: context)
            let lease = BrowserResources<ChromePage>.Lease.auxiliary("cast-" + controller.id)
            controller.router?.onPendingChange = { [weak self, weak controller] pending in
                guard let self else { return }
                if pending { _ = self.engine.resources.acquire(lease, browser: self.incarnation) }
                else {
                    self.drainingCasts.removeAll { $0 === controller }
                    self.engine.resources.release(lease, browser: self.incarnation)
                    self.engine.closeIfUnowned(self.incarnation)
                }
            }
            cast = controller
            if ProcessInfo.processInfo.environment["BRK_CONTROL_SOCKET"] != nil, let url = browser.url { controller.router?.validateSource(url.absoluteString) }
        }
        cast?.show()
    }
    func stopCasting() {
        guard let cast else { return }
        self.cast = nil
        if cast.router?.hasPendingRoutes == true { drainingCasts.append(cast) }
        cast.stop()
    }
}
