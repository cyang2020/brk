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
    private var suspended = false
    private var document: DocumentToken?
    private var session: CefDevTools?
    private var poll: Task<Void, Never>?
    private var fetch: Task<Void, Never>?
    private var popover: NSPopover?
    private var current: String?
    private var dismissed: String?
    private var world: Int?
    private struct FrameWorld { let frame: String; let context: Int; let main: Bool }
    private var frameWorlds: [FrameWorld] = []
    var frameCount: Int { frameWorlds.count }
    private var currentFrame: String?
    private(set) var title: String?
    private(set) var destination: URL?
    private var escape: Any?
    private var activityObservers: [NSObjectProtocol] = []
    private(set) var lastFailure: String?

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
        for observer in activityObservers { NotificationCenter.default.removeObserver(observer) }
        activityObservers.removeAll()
        closeCard(); session?.invalidate(); session = nil
        world = nil; frameWorlds = []; currentFrame = nil; current = nil; dismissed = nil
        if !keepDocument { document = nil }
    }
    private func start(_ document: DocumentToken) {
        guard poll == nil, let transport = CefDevTools(browser: browser) else { return }
        session = transport
        activityObservers = [NSWindow.didResignKeyNotification, NSWindow.didBecomeKeyNotification, NSApplication.didResignActiveNotification, NSApplication.didBecomeActiveNotification].map { name in
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                let owner = (note.object as? NSWindow).map { ObjectIdentifier($0) }
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let ownWindow = self.surface?.window.map { ObjectIdentifier($0) }
                    if name == NSWindow.didBecomeKeyNotification {
                        if owner == ownWindow { self.suspended = false }
                        return
                    }
                    if name == NSApplication.didBecomeActiveNotification {
                        if self.surface?.window?.isKeyWindow == true { self.suspended = false }
                        return
                    }
                    if name == NSWindow.didResignKeyNotification, owner != ownWindow { return }
                    if name == NSWindow.didResignKeyNotification, self.pointerInCard() { return }
                    self.suspended = true
                    self.dismissed = self.current; self.fetch?.cancel(); self.closeCard()
                }
            }
        }
        poll = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.refreshFrames()
                var ticks = 0
                while !Task.isCancelled, self.document == document, self.enabled {
                    if ticks % 12 == 0 { try await self.refreshFrames() }
                    ticks += 1
                    if self.suspended, self.surface?.window?.isKeyWindow == true { self.suspended = false }
                    // Shift held over a link is Max's 5-Second Preview (Arc's answer card, P45-a): this card stays away.
                    if self.available(), !self.suspended, !NSEvent.modifierFlags.contains(.shift) {
                        var candidate: (FrameWorld, [String: Any])?
                        for frame in self.frameWorlds {
                            if let value = try? await self.evaluate("globalThis.__brkPreview.read()", context: frame.context) as? [String: Any], value["href"] is String {
                                candidate = (frame, value); break
                            }
                        }
                        if let (frame, hover) = candidate, let href = hover["href"] as? String,
                           let url = URL(string: href), ["http", "https"].contains(url.scheme?.lowercased() ?? ""),
                           url.user == nil, url.password == nil {  // a userinfo address reads as a different site on the card; no preview
                            if self.current != href || self.currentFrame != frame.frame {
                                self.closeCard(); self.fetch?.cancel(); self.current = href; self.currentFrame = frame.frame
                                if self.dismissed != href { self.fetchPreview(url, hover: hover, document: document, frame: frame) }
                            }
                        } else if !self.pointerInCard() {
                            self.fetch?.cancel(); self.fetch = nil; self.current = nil; self.dismissed = nil; self.closeCard()
                        }
                    } else {
                        self.fetch?.cancel()
                        if let current = self.current { self.dismissed = current }
                        self.current = nil; self.closeCard()
                    }
                    try await Task.sleep(for: .milliseconds(150))
                }
            } catch { if self.document == document { self.lastFailure = String(describing: error); self.closeCard() } }
        }
    }
    private func refreshFrames() async throws {
        let tree = try await call("Page.getFrameTree")
        guard let root = tree["frameTree"] as? [String: Any] else { return }
        func flatten(_ node: [String: Any]) -> [String] {
            let own = (node["frame"] as? [String: Any])?["id"] as? String
            return (own.map { [$0] } ?? []) + (node["childFrames"] as? [[String: Any]] ?? []).flatMap(flatten)
        }
        // Bound work on pages with very many frames. Every refresh reuses Chrome's existing isolated worlds.
        let ids = Array(flatten(root).prefix(64))
        var frames: [FrameWorld] = []
        for id in ids {
            let result = try? await call("Page.createIsolatedWorld", ["frameId": id, "worldName": "Brk link previews"])
            guard let context = result?["executionContextId"] as? Int else { continue }
            let frame = FrameWorld(frame: id, context: context, main: id == ids.first)
            do { _ = try await evaluate(Self.tracker, context: context) }
            catch { lastFailure = String(describing: error); continue }
            frames.append(frame)
        }
        frameWorlds = frames
        world = frames.first?.context
    }

    private func call(_ method: String, _ params: [String: Any] = [:]) async throws -> [String: Any] {
        try Task.checkCancellation()
        guard let session else { throw CancellationError() }
        return (try JSONSerialization.jsonObject(with: await session.call(method, parameters: params))) as? [String: Any] ?? [:]
    }
    private func evaluate(_ expression: String, context: Int? = nil) async throws -> Any? {
        guard let world = context ?? world else { throw CancellationError() }
        let result = try await call("Runtime.evaluate", ["expression": expression, "contextId": world, "returnByValue": true])
        if let exception = result["exceptionDetails"] as? [String: Any] {
            let detail = (exception["exception"] as? [String: Any])?["description"] as? String ?? exception["text"] as? String ?? "Link preview script failed"
            throw NSError(domain: "BrkLinkPreview", code: 1, userInfo: [NSLocalizedDescriptionKey: detail])
        }
        return (result["result"] as? [String: Any])?["value"]
    }
    private func resource(_ url: URL, limit: Int, frameID: String) async throws -> Data {
        guard let transport = session, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { throw CancellationError() }
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
    private func fetchPreview(_ url: URL, hover: [String: Any], document: DocumentToken, frame: FrameWorld) {
        fetch = Task { @MainActor [weak self] in
            guard let self else { return }
            let fallback = String((hover["text"] as? String ?? url.host ?? "Link preview").prefix(200))
            var title = fallback, text = "", image: NSImage?
            var status = ""
            do {
                let data = try await self.resource(url, limit: 262_144, frameID: frame.frame)
                try Task.checkCancellation()
                let html = String(decoding: data, as: UTF8.self)
                let literal = String(decoding: try JSONSerialization.data(withJSONObject: html, options: .fragmentsAllowed), as: UTF8.self)
                let base = String(decoding: try JSONSerialization.data(withJSONObject: url.absoluteString, options: .fragmentsAllowed), as: UTF8.self)
                let parsed = try await self.evaluate("(() => {const d=new DOMParser().parseFromString(\(literal),'text/html');const i=d.querySelector('link[rel~=icon]');return {title:d.title.slice(0,200),text:(d.body?.textContent||'').slice(0,12000),icon:new URL(i?.getAttribute('href')||'/favicon.ico',\(base)).href};})()") as? [String: Any]
                if let value = parsed?["title"] as? String, !value.isEmpty { title = value }
                text = parsed?["text"] as? String ?? ""
                if let icon = parsed?["icon"] as? String, let iconURL = URL(string: icon),
                   let bytes = try? await self.resource(iconURL, limit: 131_072, frameID: frame.frame) { image = NSImage(data: bytes) }
            } catch { self.lastFailure = String(describing: error); status = "Preview unavailable. You can still open this link." }
            guard !Task.isCancelled, self.document == document, self.current == url.absoluteString, self.currentFrame == frame.frame,
                  self.dismissed != url.absoluteString, self.available(), let surface = self.surface else { return }
            // Recheck the DOM after transport; leaving or replacing the link cancels its result.
            guard let latest = try? await self.evaluate("globalThis.__brkPreview.read()", context: frame.context) as? [String: Any],
                  latest["href"] as? String == url.absoluteString else { return }
            let request = LinkPreviewRequest(document: document, url: url, title: title, text: text)
            let card = LinkPreviewCard(title: title, url: url, image: image, status: status)
            card.dismiss = { [weak self] in self?.dismissed = url.absoluteString; self?.closeCard() }
            card.summary = { [weak self, weak card] in
                self?.summarize(request) { [weak self, weak card] result in
                    guard self?.document == document, self?.current == url.absoluteString, self?.currentFrame == frame.frame else { return }
                    card?.feedback(result ?? "No summary provider is enabled.")
                }
            }
            let controller = NSViewController(); controller.view = card
            let popover = NSPopover(); popover.behavior = .semitransient; popover.animates = false
            popover.delegate = self; popover.contentViewController = controller
            self.popover = popover; self.title = title; self.destination = url
            let zoom = Double(BrowserZoom.percentage(level: self.browser.zoomLevel)) / 100
            var origin = CGPoint.zero
            if !frame.main {
                guard let owner = try? await self.call("DOM.getFrameOwner", ["frameId": frame.frame]),
                      let node = owner["backendNodeId"] as? Int,
                      let box = try? await self.call("DOM.getBoxModel", ["backendNodeId": node]),
                      let content = (box["model"] as? [String: Any])?["content"] as? [Double], content.count == 8 else { self.closeCard(); return }
                origin = CGPoint(x: content[0], y: content[1])
            }
            guard !Task.isCancelled, self.document == document, self.available() else { self.closeCard(); return }
            let x = (origin.x + (latest["x"] as? Double ?? 0)) * zoom, y = (origin.y + (latest["y"] as? Double ?? 0)) * zoom
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
      let candidate=null,since=0,suppressed=null,lastHref='';
      const clear=()=>{candidate=null;since=0;lastHref=''};
      addEventListener('pointerover',e=>{if(!e.isTrusted)return;
        const a=e.composedPath().find(n=>n instanceof HTMLAnchorElement);
        if(a!==candidate){candidate=a||null;since=performance.now();suppressed=null;lastHref=a?.href||'';}
      },true);
      addEventListener('pointerout',e=>{if(!e.relatedTarget||!candidate?.contains(e.relatedTarget))clear()},true);
      addEventListener('pointerdown',clear,true);addEventListener('scroll',clear,true);
      addEventListener('keydown',e=>{if(e.key==='Escape'){suppressed=candidate;clear()}},true);
      globalThis.__brkPreview={read(){
        if(!candidate?.isConnected)clear();
        if(!candidate){const a=document.querySelector('a:hover');if(a&&a!==suppressed){candidate=a;since=performance.now();lastHref=a.href}}
        if(candidate&&candidate.href!==lastHref){lastHref=candidate.href;since=performance.now()}
        if(!candidate?.isConnected||candidate===suppressed||performance.now()-since<650||document.hidden)return null;
        const r=candidate.getBoundingClientRect();return {href:candidate.href,text:candidate.textContent.trim(),x:r.x,y:r.y,w:r.width,h:r.height};
      }};
    })()
    """#
}

/// The hovered link's card (Arc Previews; ARC colors from visual-and-copy.md: PreviewBackgroundColor #FFFFFF /
/// #212222, PreviewToolbarButtonBackground #596069 @ 0.7 / #FFFFFF @ 0.5): the site's icon and host, the page title,
/// its address, a line for the summary, Summarize, and × to dismiss.
@MainActor
private final class LinkPreviewCard: NSView {
    var dismiss: (() -> Void)?
    var summary: (() -> Void)?
    private let note = NSTextField(wrappingLabelWithString: "")
    private let icon = NSImageView()
    private let host = NSTextField(labelWithString: "")
    private let heading = NSTextField(wrappingLabelWithString: "")
    private let address = NSTextField(labelWithString: "")
    private let close = NSButton()
    private let summarize = NSButton()

    init(title: String, url: URL, image: NSImage?, status: String) {
        super.init(frame: NSRect(origin: .zero, size: Metrics.sidebarTools.previewSize.value))
        identifier = NSUserInterfaceItemIdentifier("web-link-preview")
        setAccessibilityIdentifier("web-link-preview")
        wantsLayer = true
        icon.image = image ?? NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        icon.imageScaling = .scaleProportionallyUpOrDown
        host.stringValue = url.host ?? url.absoluteString
        host.font = .systemFont(ofSize: 12, weight: .medium)
        host.lineBreakMode = .byTruncatingMiddle
        heading.stringValue = title
        heading.font = .systemFont(ofSize: 14, weight: .semibold)
        heading.maximumNumberOfLines = 2
        heading.lineBreakMode = .byTruncatingTail
        address.stringValue = url.absoluteString
        address.font = .systemFont(ofSize: 11)
        address.lineBreakMode = .byTruncatingMiddle
        note.stringValue = status
        note.font = .systemFont(ofSize: 11)
        note.maximumNumberOfLines = 3
        close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "Dismiss")?
            .withSymbolConfiguration(.init(pointSize: 11, weight: .semibold))
        close.isBordered = false
        close.target = self; close.action = #selector(closeCard)
        summarize.title = "Summarize"
        summarize.isBordered = false
        summarize.wantsLayer = true
        summarize.layer?.cornerRadius = Metrics.sidebarTools.previewButtonRadius.value
        summarize.font = .systemFont(ofSize: 12, weight: .medium)
        summarize.target = self; summarize.action = #selector(summarizeCard)
        for view in [icon, host, heading, address, note, close, summarize] as [NSView] { addSubview(view) }
        restyle()
    }
    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let w = bounds.width, inset = 14.0
        icon.frame = NSRect(x: inset, y: 14, width: 16, height: 16)
        close.frame = NSRect(x: w - inset - 20, y: 12, width: 20, height: 20)
        host.frame = NSRect(x: inset + 24, y: 14, width: close.frame.minX - inset - 32, height: 16)
        let titleHeight = min(heading.sizeThatFits(NSSize(width: w - 2 * inset, height: 60)).height, 40)
        heading.frame = NSRect(x: inset, y: 40, width: w - 2 * inset, height: titleHeight)
        address.frame = NSRect(x: inset, y: heading.frame.maxY + 4, width: w - 2 * inset, height: 15)
        note.frame = NSRect(x: inset, y: address.frame.maxY + 6, width: w - 2 * inset, height: max(0, bounds.height - address.frame.maxY - 46))
        let s = summarize.intrinsicContentSize
        summarize.frame = NSRect(x: inset - 2, y: bounds.height - 12 - 22, width: s.width + 20, height: 22)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        restyle()
    }

    private func restyle() {
        let dark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        layer?.backgroundColor = (dark ? NSColor(srgbRed: 0x21 / 255, green: 0x22 / 255, blue: 0x22 / 255, alpha: 1) : .white).cgColor
        let secondary = NSColor.secondaryLabelColor
        host.textColor = secondary
        address.textColor = secondary
        note.textColor = secondary
        heading.textColor = .labelColor
        close.contentTintColor = secondary
        summarize.layer?.backgroundColor = (dark ? NSColor(white: 1, alpha: 0.5) : NSColor(srgbRed: 0x59 / 255, green: 0x60 / 255, blue: 0x69 / 255, alpha: 0.7)).cgColor
        summarize.contentTintColor = .white
        summarize.attributedTitle = NSAttributedString(string: "Summarize", attributes: [.foregroundColor: NSColor.white, .font: NSFont.systemFont(ofSize: 12, weight: .medium)])
    }

    func feedback(_ text: String) { note.stringValue = String(text.prefix(240)) }
    @objc private func closeCard() { dismiss?() }
    @objc private func summarizeCard() { feedback("Summarizing…"); summary?() }
}
