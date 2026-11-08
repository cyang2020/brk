import AppKit
import BrkBase
import BrkDomain
import WebKit

// The page sandbox: where an agent's HTML is shown (docs/design/ai-conversations.md, "The page sandbox"). The HTML is
// written by an agent that may have read untrusted pages, so it runs with nothing to reach:
//
// - WebKit, not Chromium: no profile's cookies, storage, cache, service workers or extensions live in this engine at all,
//   and each view has its own non-persistent data store, thrown away with it.
// - The document is served by `brk-page:` (one resource, this page) with a Content-Security-Policy header the page cannot
//   take back: inline style and script, data: and blob: only, no connections, frames, workers, forms or base URL, and
//   `sandbox allow-scripts`, which gives the document an opaque origin, so cookies stay empty and storage throws.
// - A content rule list blocks every load that is not brk-page:, data:, blob: or about:. CSP does not cover
//   `<link rel=preconnect>`, which opened a TCP connection to the host it names (seen in PageSandboxTests); the rule list
//   stops it. The page does not load until the list is in place.
// - The navigation delegate lets the first load through and cancels every navigation after it. A real click on an
//   http(s) link goes to Brk as `onLink` from the bridge, which only takes trusted clicks; Brk opens it as a tab, asking
//   first where the conversation had read pages. A navigation the delegate sees is never taken for a click: WebKit does
//   not say whether a script started it.
// - Brk's bridge runs in an isolated script world the page cannot see. The page itself only reads `window.brk.data`
//   and posts console lines.

/// Brk's theme as the page's CSS variables (T3 Code's names), for light, dark and the Space's color.
public struct PageTheme: Equatable, Sendable {
    public let scheme: Scheme
    public let variables: [(String, String)]

    public static func == (a: PageTheme, b: PageTheme) -> Bool { a.scheme == b.scheme && a.variables.map(\.0) == b.variables.map(\.0) && a.variables.map(\.1) == b.variables.map(\.1) }

    /// `background`: the color the page sits on (the panel's or the conversation card's), so a box can match it.
    public init(_ theme: ResolvedTheme, background: RGBA? = nil) {
        scheme = theme.scheme
        let dark = theme.scheme == .dark
        let space = theme.gradient.first ?? RGBA(hex: "#3478F6")
        // The Space's color as an accent the text can stand on: darkened on light, lightened on dark until it reads.
        let primary = Self.readable(space, on: dark ? RGBA(hex: "#1E1E1E") : RGBA(hex: "#FFFFFF"))
        let onPrimary = Self.luminance(primary) > 0.45 ? "#111111" : "#FFFFFF"
        let base = background ?? (dark ? RGBA(hex: "#1E1E1E") : RGBA(hex: "#FFFFFF"))
        func css(_ c: RGBA) -> String {
            String(format: "rgba(%d, %d, %d, %.3f)", Int((c.red * 255).rounded()), Int((c.green * 255).rounded()), Int((c.blue * 255).rounded()), c.alpha)
        }
        let charts = dark ? ["#7AB8FF", "#FFB46B", "#6FD3A0", "#C59BFF", "#FF8FA8", "#5ED3D6"] : ["#2F6FDE", "#E07B1F", "#1F9D63", "#8A57E0", "#D6466F", "#14929A"]
        variables = [
            ("--background", css(base)),
            ("--foreground", dark ? "#F2F2F5" : "#1D1D1F"),
            ("--muted", dark ? "rgba(255, 255, 255, 0.07)" : "rgba(0, 0, 0, 0.04)"),
            ("--muted-foreground", dark ? "#A1A1A8" : "#6E6E73"),
            ("--card", dark ? "rgba(255, 255, 255, 0.06)" : "rgba(0, 0, 0, 0.035)"),
            ("--card-foreground", dark ? "#F2F2F5" : "#1D1D1F"),
            ("--popover", dark ? "#2A2A2E" : "#FFFFFF"),
            ("--popover-foreground", dark ? "#F2F2F5" : "#1D1D1F"),
            ("--secondary", dark ? "rgba(255, 255, 255, 0.1)" : "rgba(0, 0, 0, 0.06)"),
            ("--secondary-foreground", dark ? "#F2F2F5" : "#1D1D1F"),
            ("--border", dark ? "rgba(255, 255, 255, 0.14)" : "rgba(0, 0, 0, 0.1)"),
            ("--ring", css(primary)),
            ("--primary", css(primary)),
            ("--primary-foreground", onPrimary),
            ("--accent", css(RGBA(primary.red, primary.green, primary.blue, dark ? 0.22 : 0.12))),
            ("--accent-foreground", dark ? "#F2F2F5" : "#1D1D1F"),
            ("--destructive", dark ? "#FF6B6B" : "#D93636"),
            ("--destructive-foreground", "#FFFFFF"),
            ("--warning", dark ? "#FFC453" : "#B7791F"),
            ("--warning-foreground", "#111111"),
            ("--success", dark ? "#5CD38E" : "#1F8A4C"),
            ("--success-foreground", "#FFFFFF"),
            ("--info", dark ? "#6CB6FF" : "#1F6FD1"),
            ("--info-foreground", "#FFFFFF"),
            ("--code-background", dark ? "rgba(255, 255, 255, 0.08)" : "rgba(0, 0, 0, 0.05)"),
            ("--code-foreground", dark ? "#F2F2F5" : "#1D1D1F"),
        ] + charts.enumerated().map { ("--chart-\($0.offset + 1)", $0.offset == 0 ? css(primary) : $0.element) } + [
            ("--radius", "8px"),
            ("--font-sans", "-apple-system, BlinkMacSystemFont, \"SF Pro Text\", \"PingFang SC\", \"Hiragino Sans\", system-ui, sans-serif"),
            ("--font-mono", "ui-monospace, \"SF Mono\", Menlo, monospace"),
        ]
    }

    var json: String {
        let object: [String: Any] = ["scheme": scheme == .dark ? "dark" : "light", "variables": Dictionary(uniqueKeysWithValues: variables)]
        return String(decoding: (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8), as: UTF8.self)
    }

    static func luminance(_ c: RGBA) -> Double {
        func channel(_ v: Double) -> Double { v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * channel(c.red) + 0.7152 * channel(c.green) + 0.0722 * channel(c.blue)
    }

    /// `color` moved toward black or white until it has 4.5:1 contrast on `background`.
    static func readable(_ color: RGBA, on background: RGBA) -> RGBA {
        let bg = luminance(background)
        func contrast(_ c: RGBA) -> Double { let l = luminance(c); return (max(l, bg) + 0.05) / (min(l, bg) + 0.05) }
        var c = RGBA(color.red, color.green, color.blue, 1)
        let towardWhite = bg < 0.5
        for _ in 0..<20 where contrast(c) < 4.5 {
            let t = 0.12
            c = towardWhite ? RGBA(c.red + (1 - c.red) * t, c.green + (1 - c.green) * t, c.blue + (1 - c.blue) * t, 1)
                : RGBA(c.red * (1 - t), c.green * (1 - t), c.blue * (1 - t), 1)
        }
        return c
    }
}

/// The policy the page's document is served with, and the scheme it is served on.
public enum PageSandboxPolicy {
    public static let scheme = "brk-page"
    public static let documentURL = URL(string: "brk-page://page/")!
    public static let contentSecurityPolicy = [
        "default-src 'none'", "script-src 'unsafe-inline'", "style-src 'unsafe-inline'", "img-src data: blob:", "font-src data:",
        "media-src data: blob:", "connect-src 'none'", "frame-src 'none'", "child-src 'none'", "worker-src 'none'", "object-src 'none'",
        "manifest-src 'none'", "form-action 'none'", "base-uri 'none'", "sandbox allow-scripts",
    ].joined(separator: "; ")
    static let headers = [
        "Content-Type": "text/html; charset=utf-8",
        "Content-Security-Policy": contentSecurityPolicy,
        "X-DNS-Prefetch-Control": "off",
        "Referrer-Policy": "no-referrer",
        "Cache-Control": "no-store",
    ]
    /// Every load but the page's own document and inline data. WebKit's filters take no `|`, so one rule per scheme.
    static let blockList = #"[{"trigger":{"url-filter":".*"},"action":{"type":"block"}},"#
        + #"{"trigger":{"url-filter":"^brk-page:"},"action":{"type":"ignore-previous-rules"}},{"trigger":{"url-filter":"^data:"},"action":{"type":"ignore-previous-rules"}},"#
        + #"{"trigger":{"url-filter":"^blob:"},"action":{"type":"ignore-previous-rules"}},{"trigger":{"url-filter":"^about:"},"action":{"type":"ignore-previous-rules"}}]"#
}

/// What a page tells its host.
public enum PageSandboxEvent: Equatable, Sendable {
    /// A real click on an http(s) link.
    case link(URL)
    /// The document's height in points, whenever it changes.
    case height(Int)
    case console(String)
    case loaded
}

/// One page in the sandbox. Owns its web view and its data store.
@MainActor
public final class PageSandboxView: NSView {
    public var onEvent: ((PageSandboxEvent) -> Void)?
    /// Keep as Tab and the other items of the page's own menu; nil leaves the menu empty.
    public var menuItems: (() -> [NSMenuItem])?
    private let web: SandboxWebView
    private let handler: DocumentHandler
    private let bridge = Bridge()
    private var theme: PageTheme
    private var loadedDocument = false
    public private(set) var console: [String] = []
    public private(set) var contentHeight: Int?
    public let pageID: AIPageID?

    /// `html` is the whole document; `data` the JSON text the page reads as `window.brk.data`.
    public init(html: String, data: String?, theme: PageTheme, page: AIPageID? = nil) {
        pageID = page
        self.theme = theme
        handler = DocumentHandler(html: html)
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.setURLSchemeHandler(handler, forURLScheme: PageSandboxPolicy.scheme)
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.preferences.isFraudulentWebsiteWarningEnabled = false
        configuration.preferences.isElementFullscreenEnabled = false
        configuration.mediaTypesRequiringUserActionForPlayback = .all
        configuration.allowsAirPlayForMediaPlayback = false
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        let world = WKContentWorld.world(name: "brk-sandbox")
        let content = configuration.userContentController
        content.add(bridge, contentWorld: world, name: "brk")
        content.add(bridge, contentWorld: .page, name: "brkConsole")
        content.addUserScript(WKUserScript(source: Self.pageScript(data: data), injectionTime: .atDocumentStart, forMainFrameOnly: true, in: .page))
        content.addUserScript(WKUserScript(source: Self.bridgeScript(theme: theme), injectionTime: .atDocumentStart, forMainFrameOnly: true, in: world))
        web = SandboxWebView(frame: .zero, configuration: configuration)
        super.init(frame: .zero)
        web.setValue(false, forKey: "drawsBackground")
        web.allowsBackForwardNavigationGestures = false
        web.allowsMagnification = false
        web.navigationDelegate = bridge
        web.uiDelegate = bridge
        web.menuItems = { [weak self] in self?.menuItems?() ?? [] }
        addSubview(web)
        bridge.owner = self
        Task { @MainActor [weak self] in
            // No rule list, no page: CSP alone lets preconnect through.
            guard let rules = await Self.rules() else {
                self?.received(.console("error: the page sandbox could not start, so the page was not shown"))
                return
            }
            self?.web.configuration.userContentController.add(rules)
            self?.web.load(URLRequest(url: PageSandboxPolicy.documentURL))
        }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }

    override public func layout() {
        super.layout()
        web.frame = bounds
    }

    /// New theme colors, sent to the page live.
    public func apply(_ theme: PageTheme) {
        guard theme != self.theme else { return }
        self.theme = theme
        web.evaluateJavaScript("window.__brkTheme && window.__brkTheme(\(theme.json))", in: nil, in: .world(name: "brk-sandbox"), completionHandler: nil)
    }

    /// Runs `script` in the page's own world and returns its result as text (tests prove what the page can and cannot do).
    public func evaluateInPage(_ script: String) async -> String? {
        await withCheckedContinuation { continuation in
            web.callAsyncJavaScript(script, arguments: [:], in: nil, in: .page) { result in
                switch result {
                case .success(let value): continuation.resume(returning: "\(value)")
                case .failure(let error): continuation.resume(returning: "error: \(error.localizedDescription)")
                }
            }
        }
    }

    /// The address the web view shows now.
    public var currentURL: URL? { web.url }
    /// Navigations the delegate let through, the first load included.
    public var allowedNavigations: [URL] { bridge.allowed }

    /// A picture of what the page shows, `width` points wide and as tall as its bounds, at one pixel per point.
    public func snapshot() async -> Data? {
        let configuration = WKSnapshotConfiguration()
        configuration.rect = web.bounds
        configuration.afterScreenUpdates = true
        guard let image = try? await web.takeSnapshot(configuration: configuration) else { return nil }
        let size = web.bounds.size
        guard size.width >= 1, size.height >= 1,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        theme.backgroundColor.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.draw(in: NSRect(origin: .zero, size: size))
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }

    fileprivate func received(_ event: PageSandboxEvent) {
        switch event {
        case .console(let line):
            guard console.count < 50 else { return }
            console.append(String(line.prefix(500)))
        case .height(let value):
            guard value != contentHeight else { return }
            contentHeight = value
        case .loaded: loadedDocument = true
        case .link: break
        }
        onEvent?(event)
    }

    fileprivate func mayNavigate(_ action: WKNavigationAction) -> Bool {
        // The first load of the page's own document, in the main frame; nothing after it.
        guard !loadedDocument, action.targetFrame?.isMainFrame == true, action.request.url == PageSandboxPolicy.documentURL, bridge.allowed.isEmpty else { return false }
        bridge.allowed.append(PageSandboxPolicy.documentURL)
        return true
    }

    // MARK: Scripts

    private static func pageScript(data: String?) -> String {
        // `data` was encoded by Brk as a JSON object; anything else becomes null.
        let value = data.flatMap { text -> String? in
            guard let parsed = try? JSONSerialization.jsonObject(with: Data(text.utf8)), parsed is [String: Any] else { return nil }
            return text
        } ?? "null"
        return """
        (() => {
          const data = \(value);
          Object.defineProperty(window, 'brk', { value: Object.freeze({ data }), writable: false, configurable: false });
          const post = (level, args) => {
            try {
              const text = args.map(a => { try { return typeof a === 'string' ? a : JSON.stringify(a); } catch (e) { return String(a); } }).join(' ');
              window.webkit.messageHandlers.brkConsole.postMessage(level + ': ' + text.slice(0, 500));
            } catch (e) {}
          };
          for (const level of ['log', 'info', 'warn', 'error', 'debug']) {
            const original = console[level].bind(console);
            console[level] = (...args) => { post(level, args); original(...args); };
          }
          window.addEventListener('error', e => post('error', [String(e.message) + (e.lineno ? ' (line ' + e.lineno + ')' : '')]));
          window.addEventListener('unhandledrejection', e => post('error', ['Unhandled rejection: ' + String(e.reason && e.reason.message || e.reason)]));
          document.addEventListener('securitypolicyviolation', e => post('error', ['Blocked by the page sandbox: ' + e.violatedDirective + (e.blockedURI ? ' ' + e.blockedURI : '')]));
        })();
        """
    }

    private static func bridgeScript(theme: PageTheme) -> String {
        """
        (() => {
          const root = document.documentElement;
          const base = document.createElement('style');
          base.id = 'brk-base';
          base.textContent = 'html,body{margin:0;padding:0;background:transparent;color:var(--foreground);font-family:var(--font-sans);font-size:13px;line-height:1.45;-webkit-font-smoothing:antialiased}*,*::before,*::after{box-sizing:border-box}a{color:var(--primary)}';
          const vars = document.createElement('style');
          vars.id = 'brk-theme';
          root.prepend(vars);
          root.prepend(base);
          const send = message => { try { window.webkit.messageHandlers.brk.postMessage(message); } catch (e) {} };
          window.__brkTheme = theme => {
            vars.textContent = ':root{color-scheme:' + theme.scheme + ';' + Object.entries(theme.variables).map(([k, v]) => k + ':' + v).join(';') + '}';
            window.postMessage({ jsonrpc: '2.0', method: 'ui/notifications/host-context-changed', params: { theme: theme.scheme, styles: { variables: theme.variables } } }, '*');
          };
          window.__brkTheme(\(theme.json));
          document.addEventListener('click', event => {
            if (!event.isTrusted) return;
            const link = event.target && event.target.closest ? event.target.closest('a[href]') : null;
            if (!link) return;
            event.preventDefault();
            if (/^https?:/i.test(link.href)) send({ type: 'open-link', url: link.href });
          }, true);
          let last = -1;
          const measure = () => {
            const height = Math.ceil(root.getBoundingClientRect().height);
            if (height !== last) { last = height; send({ type: 'size', height }); }
          };
          new ResizeObserver(measure).observe(root);
          window.addEventListener('load', () => { measure(); send({ type: 'loaded' }); });
        })();
        """
    }

    // MARK: Rules

    private static var compiled: WKContentRuleList?
    static func rules() async -> WKContentRuleList? {
        if let compiled { return compiled }
        let list = try? await WKContentRuleListStore.default()?.compileContentRuleList(forIdentifier: "brk-page-sandbox-2", encodedContentRuleList: PageSandboxPolicy.blockList)
        compiled = list
        return list
    }

    /// The bridge's side in native code: what the page's scripts may say, checked; every navigation after the first
    /// cancelled; no windows, dialogs, file pickers or devices.
    @MainActor private final class Bridge: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
        weak var owner: PageSandboxView?
        var allowed: [URL] = []

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let owner else { return }
            if message.name == "brkConsole" {
                if let line = message.body as? String { owner.received(.console(line)) }
                return
            }
            guard message.name == "brk", message.world.name == "brk-sandbox", let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
            switch type {
            case "open-link":
                guard let text = body["url"] as? String, text.count <= 2_048, let url = URL(string: text), ["http", "https"].contains(url.scheme?.lowercased()) else { return }
                owner.received(.link(url))
            case "size":
                guard let height = (body["height"] as? NSNumber)?.intValue, height >= 0 else { return }
                owner.received(.height(min(height, 100_000)))
            case "loaded":
                owner.received(.loaded)
            default: break
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            decisionHandler(owner?.mayNavigate(action) == true ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void) {
            decisionHandler(response.response.url == PageSandboxPolicy.documentURL ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            nil
        }

        func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable () -> Void) {
            completionHandler()
        }
        func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping @MainActor @Sendable (Bool) -> Void) {
            completionHandler(false)
        }
        func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping @MainActor @Sendable (String?) -> Void) {
            completionHandler(nil)
        }
        func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo,
                     completionHandler: @escaping @MainActor @Sendable ([URL]?) -> Void) {
            completionHandler(nil)
        }
        func webView(_ webView: WKWebView, requestMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType,
                     decisionHandler: @escaping @MainActor @Sendable (WKPermissionDecision) -> Void) {
            decisionHandler(.deny)
        }
    }

    /// Serves the page's document and nothing else.
    private final class DocumentHandler: NSObject, WKURLSchemeHandler {
        private let html: Data
        init(html: String) { self.html = Data(html.utf8) }

        func webView(_ webView: WKWebView, start task: any WKURLSchemeTask) {
            guard let url = task.request.url, url == PageSandboxPolicy.documentURL, html.count <= AIPageLimits.html,
                  let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: PageSandboxPolicy.headers) else {
                task.didFailWithError(URLError(.resourceUnavailable))
                return
            }
            task.didReceive(response)
            task.didReceive(html)
            task.didFinish()
        }

        func webView(_ webView: WKWebView, stop task: any WKURLSchemeTask) {}
    }
}

extension PageTheme {
    /// The opaque color behind the page, for snapshots.
    var backgroundColor: NSColor {
        let value = variables.first { $0.0 == "--background" }?.1 ?? ""
        let numbers = value.dropFirst(5).dropLast().split(separator: ",").compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard numbers.count == 4 else { return scheme == .dark ? .black : .white }
        return NSColor(srgbRed: numbers[0] / 255, green: numbers[1] / 255, blue: numbers[2] / 255, alpha: 1)
    }
}

/// The web view with Brk's own context menu: the page's items (Keep as Tab), never WebKit's (Reload, Inspect). A right
/// click or a Control-click opens it here, without asking the page: WebKit's own menu goes through the page's process
/// and lets the page cancel it (and in the first Codex run it never opened).
private final class SandboxWebView: WKWebView {
    var menuItems: (() -> [NSMenuItem])?

    private func showMenu(_ event: NSEvent) {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for item in menuItems?() ?? [] { menu.addItem(item) }
        guard !menu.items.isEmpty else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    override func rightMouseDown(with event: NSEvent) { showMenu(event) }
    override func mouseDown(with event: NSEvent) {
        if event.modifierFlags.contains(.control) { showMenu(event) } else { super.mouseDown(with: event) }
    }
    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        menu.removeAllItems()
        for item in menuItems?() ?? [] { menu.addItem(item) }
    }
}

/// `brk_html_preview`: the page rendered off screen, as the agent's check.
public struct PagePreview: Sendable {
    public let png: Data?
    public let contentHeight: Int
    public let console: [String]
    public init(png: Data?, contentHeight: Int, console: [String]) { self.png = png; self.contentHeight = contentHeight; self.console = console }
}

@MainActor
public enum PageSandbox {
    /// Renders `html` at `width` points in a window that is never on screen, waits for it to settle, and pictures it at
    /// its content height (at most 2000 points).
    public static func preview(html: String, data: String?, width: Int, theme: PageTheme, timeout: Double = 8) async -> PagePreview {
        let view = PageSandboxView(html: html, data: data, theme: theme)
        let window = NSWindow(contentRect: NSRect(x: -30_000, y: -30_000, width: width, height: 200), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.frame = NSRect(x: 0, y: 0, width: width, height: 200)
        defer { window.contentView = nil; window.close() }
        var loaded = false
        view.onEvent = { if $0 == .loaded { loaded = true } }
        let start = ProcessInfo.processInfo.systemUptime
        while !loaded, ProcessInfo.processInfo.systemUptime - start < timeout { try? await Task.sleep(for: .milliseconds(50)) }
        // Scripts that draw after load (charts) get a moment.
        try? await Task.sleep(for: .milliseconds(300))
        let height = AIPageLimits.height(view.contentHeight ?? 200)
        window.setContentSize(NSSize(width: width, height: height))
        view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        view.layoutSubtreeIfNeeded()
        try? await Task.sleep(for: .milliseconds(150))
        let png = await view.snapshot()
        var console = view.console
        if !loaded { console.append("error: the page did not finish loading in \(Int(timeout)) seconds") }
        return PagePreview(png: png, contentHeight: view.contentHeight ?? height, console: console)
    }
}
