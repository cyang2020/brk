import AppKit
import BrkBase
import CefKit

/// Presentation belongs to this browser incarnation. Network.loadNetworkResource uses its frame and cookie
/// context, including private epochs. No URLSession, shared favicon cache, hidden browser or second page owner.
@MainActor
final class PageLinkPreviews: NSObject, NSPopoverDelegate {
    private unowned let browser: CefBrowser
    private weak var surface: NSView?
    private let available: () -> Bool
    private let summarize: (LinkPreviewRequest, @escaping @MainActor (String?) -> Void) -> Void
    private var enabled = true
    private var document: DocumentToken?
    private var session: CefDevTools?
    private var poll: Task<Void, Never>?
    private var fetch: Task<Void, Never>?
    private var popover: NSPopover?
    private var current: String?
    private var dismissed: String?
    private var world: Int?
    private var frameID: String?
    private(set) var title: String?
    private(set) var destination: URL?
    private var escape: Any?

    init(browser: CefBrowser, surface: NSView, available: @escaping () -> Bool,
         summarize: @escaping (LinkPreviewRequest, @escaping @MainActor (String?) -> Void) -> Void) {
        self.browser = browser; self.surface = surface; self.available = available; self.summarize = summarize
    }
    func setEnabled(_ value: Bool) {
        guard value != enabled else { return }
        enabled = value
        if value, let document { start(document) } else { stop(keepDocument: true) }
    }
    func observe(_ event: PageEvent) {
        switch event {
        case .documentChanged(let value):
            let next: DocumentToken? = if case .ready(let token) = value { token } else { nil }
            guard next != document else { return }
            stop(); document = next
            if enabled, let next { start(next) }
        case .navigationRequested, .rendererGone, .closed: stop()
        default: break
        }
    }
    func stop(keepDocument: Bool = false) {
        poll?.cancel(); poll = nil; fetch?.cancel(); fetch = nil
        closeCard(); session?.invalidate(); session = nil
        world = nil; frameID = nil; current = nil; dismissed = nil
        if !keepDocument { document = nil }
    }
    private func start(_ document: DocumentToken) {
        guard poll == nil, let transport = CefDevTools(browser: browser) else { return }
        session = transport
        poll = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let tree = try await self.call("Page.getFrameTree")
                guard self.document == document,
                      let frame = (tree["frameTree"] as? [String: Any])?["frame"] as? [String: Any], let id = frame["id"] as? String else { return }
                self.frameID = id
                let world = try await self.call("Page.createIsolatedWorld", ["frameId": id, "worldName": "Brk link previews"])
                guard self.document == document, let context = world["executionContextId"] as? Int else { return }
                self.world = context
                _ = try await self.evaluate(Self.tracker)
                while !Task.isCancelled, self.document == document, self.enabled {
                    if self.available(), self.surface?.window?.isKeyWindow == true || self.pointerInCard() {
                        let value = try await self.evaluate("globalThis.__brkPreview.read()")
                        if let hover = value as? [String: Any], let href = hover["href"] as? String,
                           let url = URL(string: href), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                            if self.current != href {
                                self.closeCard(); self.fetch?.cancel(); self.current = href
                                if self.dismissed != href { self.fetchPreview(url, hover: hover, document: document) }
                            }
                        } else if !self.pointerInCard() {
                            self.fetch?.cancel(); self.fetch = nil; self.current = nil; self.dismissed = nil; self.closeCard()
                        }
                    } else { self.fetch?.cancel(); self.current = nil; self.closeCard() }
                    try await Task.sleep(for: .milliseconds(150))
                }
            } catch { if self.document == document { self.closeCard() } }
        }
    }
    private func call(_ method: String, _ params: [String: Any] = [:]) async throws -> [String: Any] {
        try Task.checkCancellation()
        guard let session else { throw CancellationError() }
        return (try JSONSerialization.jsonObject(with: await session.call(method, parameters: params))) as? [String: Any] ?? [:]
    }
    private func evaluate(_ expression: String) async throws -> Any? {
        guard let world else { throw CancellationError() }
        let result = try await call("Runtime.evaluate", ["expression": expression, "contextId": world, "returnByValue": true])
        return (result["result"] as? [String: Any])?["value"]
    }
    private func resource(_ url: URL, limit: Int) async throws -> Data {
        guard let transport = session, let frameID, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { throw CancellationError() }
        let result = try await call("Network.loadNetworkResource", ["frameId": frameID, "url": url.absoluteString,
            "options": ["disableCache": false, "includeCredentials": true]])
        guard let resource = result["resource"] as? [String: Any], resource["success"] as? Bool == true,
              let handle = resource["stream"] as? String else { throw CocoaError(.fileReadUnknown) }
        do {
            var data = Data()
            while data.count < limit {
                try Task.checkCancellation()
                let part = try await call("IO.read", ["handle": handle, "size": min(65_536, limit - data.count)])
                guard let text = part["data"] as? String else { break }
                data.append(part["base64Encoded"] as? Bool == true ? Data(base64Encoded: text) ?? Data() : Data(text.utf8))
                if part["eof"] as? Bool == true || text.isEmpty { break }
            }
            _ = try? await transport.call("IO.close", parameters: ["handle": handle])
            return data
        } catch {
            _ = try? await transport.call("IO.close", parameters: ["handle": handle]); throw error
        }
    }
    private func fetchPreview(_ url: URL, hover: [String: Any], document: DocumentToken) {
        fetch = Task { @MainActor [weak self] in
            guard let self else { return }
            let fallback = String((hover["text"] as? String ?? url.host ?? "Link preview").prefix(200))
            var title = fallback, text = "", image: NSImage?
            var status = ""
            do {
                let data = try await self.resource(url, limit: 262_144)
                try Task.checkCancellation()
                let html = String(decoding: data, as: UTF8.self)
                let literal = String(decoding: try JSONSerialization.data(withJSONObject: html, options: .fragmentsAllowed), as: UTF8.self)
                let base = String(decoding: try JSONSerialization.data(withJSONObject: url.absoluteString, options: .fragmentsAllowed), as: UTF8.self)
                let parsed = try await self.evaluate("(() => {const d=new DOMParser().parseFromString(\(literal),'text/html');const i=d.querySelector('link[rel~=icon]');return {title:d.title.slice(0,200),text:(d.body?.textContent||'').slice(0,12000),icon:new URL(i?.getAttribute('href')||'/favicon.ico',\(base)).href};})()") as? [String: Any]
                if let value = parsed?["title"] as? String, !value.isEmpty { title = value }
                text = parsed?["text"] as? String ?? ""
                if let icon = parsed?["icon"] as? String, let iconURL = URL(string: icon),
                   let bytes = try? await self.resource(iconURL, limit: 131_072) { image = NSImage(data: bytes) }
            } catch { status = "Preview unavailable. You can still open this link." }
            guard !Task.isCancelled, self.document == document, self.current == url.absoluteString,
                  self.dismissed != url.absoluteString, self.available(), let surface = self.surface else { return }
            // Recheck the DOM after transport; leaving or replacing the link cancels its result.
            guard let latest = try? await self.evaluate("globalThis.__brkPreview.read()") as? [String: Any],
                  latest["href"] as? String == url.absoluteString else { return }
            let request = LinkPreviewRequest(document: document, url: url, title: title, text: text)
            let card = LinkPreviewCard(title: title, url: url, image: image, status: status)
            card.dismiss = { [weak self] in self?.dismissed = url.absoluteString; self?.closeCard() }
            card.summary = { [weak self, weak card] in
                self?.summarize(request) { [weak self, weak card] result in
                    guard self?.document == document, self?.current == url.absoluteString else { return }
                    card?.feedback(result ?? "No summary provider is enabled.")
                }
            }
            let controller = NSViewController(); controller.view = card
            let popover = NSPopover(); popover.behavior = .semitransient; popover.animates = false
            popover.delegate = self; popover.contentViewController = controller
            self.popover = popover; self.title = title; self.destination = url
            let zoom = Double(BrowserZoom.percentage(level: self.browser.zoomLevel)) / 100
            let x = (latest["x"] as? Double ?? 0) * zoom, y = (latest["y"] as? Double ?? 0) * zoom
            let anchor = NSRect(x: x, y: y, width: max(1, (latest["w"] as? Double ?? 1) * zoom), height: max(1, (latest["h"] as? Double ?? 1) * zoom))
            popover.show(relativeTo: anchor, of: surface, preferredEdge: .maxY)
            self.escape = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard event.keyCode == 53 else { return event }
                MainActor.assumeIsolated { self?.dismissed = url.absoluteString; self?.closeCard() }
                return nil
            }
        }
    }
    private func pointerInCard() -> Bool {
        guard let window = popover?.contentViewController?.view.window else { return false }
        return window.frame.contains(NSEvent.mouseLocation)
    }
    private func closeCard() {
        popover?.delegate = nil; popover?.close(); popover = nil; title = nil; destination = nil
        if let escape { NSEvent.removeMonitor(escape); self.escape = nil }
    }
    func popoverDidClose(_ notification: Notification) { dismissed = current; closeCard() }

    private static let tracker = #"""
    (() => {
      if(globalThis.__brkPreview) return;
      let candidate=null,since=0,suppressed=null;
      const clear=()=>{candidate=null;since=0};
      addEventListener('pointerover',e=>{
        const a=e.composedPath().find(n=>n instanceof HTMLAnchorElement);
        if(a!==candidate){candidate=a||null;since=performance.now();suppressed=null;}
      },true);
      addEventListener('pointerout',e=>{if(!e.relatedTarget||!candidate?.contains(e.relatedTarget))clear()},true);
      addEventListener('pointerdown',clear,true);addEventListener('scroll',clear,true);
      addEventListener('keydown',e=>{if(e.key==='Escape'){suppressed=candidate;clear()}},true);
      globalThis.__brkPreview={read(){
        if(!candidate?.isConnected||candidate===suppressed||performance.now()-since<650||document.hidden)return null;
        const r=candidate.getBoundingClientRect();return {href:candidate.href,text:candidate.textContent.trim(),x:r.x,y:r.y,w:r.width,h:r.height};
      }};
    })()
    """#
}

@MainActor
private final class LinkPreviewCard: NSView {
    var dismiss: (() -> Void)?
    var summary: (() -> Void)?
    private let note = NSTextField(wrappingLabelWithString: "")
    init(title: String, url: URL, image: NSImage?, status: String) {
        super.init(frame: NSRect(origin: .zero, size: Metrics.sidebarTools.previewSize.value))
        identifier = NSUserInterfaceItemIdentifier("web-link-preview")
        let icon = NSImageView(frame: NSRect(x: 14, y: 136, width: 24, height: 24))
        icon.image = image ?? NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        icon.imageScaling = .scaleProportionallyUpOrDown
        let heading = NSTextField(wrappingLabelWithString: title); heading.font = .systemFont(ofSize: 14, weight: .semibold)
        heading.frame = NSRect(x: 48, y: 118, width: 242, height: 44)
        let address = NSTextField(wrappingLabelWithString: url.absoluteString); address.font = .systemFont(ofSize: 11)
        address.textColor = .secondaryLabelColor; address.frame = NSRect(x: 14, y: 78, width: 300, height: 34)
        note.stringValue = status; note.font = .systemFont(ofSize: 11); note.frame = NSRect(x: 14, y: 34, width: 300, height: 40)
        let close = NSButton(title: "×", target: self, action: #selector(closeCard)); close.frame = NSRect(x: 294, y: 142, width: 26, height: 26)
        let summarize = NSButton(title: "Summarize", target: self, action: #selector(summarizeCard)); summarize.frame = NSRect(x: 12, y: 6, width: 110, height: 28); summarize.bezelStyle = .rounded
        for view in [icon, heading, address, note, close, summarize] { addSubview(view) }
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
    func feedback(_ text: String) { note.stringValue = String(text.prefix(240)) }
    @objc private func closeCard() { dismiss?() }
    @objc private func summarizeCard() { feedback("Summarizing…"); summary?() }
}
