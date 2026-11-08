import AppKit
import BrkBase
@testable import BrkContent
import BrkDomain
import Darwin
import XCTest

/// The page sandbox (BrkContent/PageSandbox.swift) holds against a page that tries to reach out: a local listener counts
/// every connection while the page uses each way a page has to load, send or navigate; cookies and storage are not
/// there; the only way out is a real click on an http(s) link, which goes to Brk.
@MainActor
final class PageSandboxTests: XCTestCase {
    /// A TCP listener on 127.0.0.1 that counts what connects and what the first line asked for.
    private final class Listener: @unchecked Sendable {
        let port: UInt16
        private let fd: Int32
        private let lock = NSLock()
        private var requests: [String] = []
        private var accepted = 0
        private var running = true

        init() throws {
            let descriptor = socket(AF_INET, SOCK_STREAM, 0)
            var on: Int32 = 1
            setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &on, socklen_t(MemoryLayout<Int32>.size))
            var address = sockaddr_in()
            address.sin_family = sa_family_t(AF_INET)
            address.sin_addr.s_addr = inet_addr("127.0.0.1")
            address.sin_port = 0
            let bound = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) } }
            guard bound == 0, Darwin.listen(descriptor, 16) == 0 else { throw POSIXError(.EADDRINUSE) }
            var length = socklen_t(MemoryLayout<sockaddr_in>.size)
            _ = withUnsafeMutablePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(descriptor, $0, &length) } }
            fd = descriptor
            port = UInt16(bigEndian: address.sin_port)
            let thread = Thread { [self] in loop() }
            thread.start()
        }

        private func loop() {
            while lock.withLock({ running }) {
                let client = Darwin.accept(fd, nil, nil)
                guard client >= 0 else { continue }
                var buffer = [UInt8](repeating: 0, count: 2048)
                var timeout = timeval(tv_sec: 1, tv_usec: 0)
                setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                let n = Darwin.read(client, &buffer, buffer.count)
                let line = n > 0 ? String(decoding: buffer[0..<n], as: UTF8.self).split(separator: "\r\n").first.map(String.init) ?? "" : "(connected, sent nothing)"
                lock.withLock { accepted += 1; requests.append(line) }
                let reply = "HTTP/1.1 200 OK\r\nContent-Length: 2\r\nAccess-Control-Allow-Origin: *\r\n\r\nok"
                _ = reply.withCString { Darwin.write(client, $0, strlen($0)) }
                Darwin.close(client)
            }
        }

        var seen: (count: Int, requests: [String]) { lock.withLock { (accepted, requests) } }

        func stop() {
            lock.withLock { running = false }
            Darwin.shutdown(fd, SHUT_RDWR)
            Darwin.close(fd)
        }
    }

    private func window(for view: NSView, width: CGFloat = 480, height: CGFloat = 400, front: Bool = false) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: -30_000, y: -30_000, width: width, height: height), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        // Off screen either way; ordered in so that WebKit takes mouse events.
        if front { window.orderFrontRegardless() }
        window.contentView = view
        view.frame = NSRect(x: 0, y: 0, width: width, height: height)
        addTeardownBlock { @MainActor in window.contentView = nil; window.close() }
        return window
    }

    private func loaded(_ view: PageSandboxView, timeout: Double = 15) async throws {
        var done = false
        let previous = view.onEvent
        view.onEvent = { event in if event == .loaded { done = true }; previous?(event) }
        let start = ProcessInfo.processInfo.systemUptime
        while !done, ProcessInfo.processInfo.systemUptime - start < timeout { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertTrue(done, "the page did not load")
    }

    private var theme: PageTheme { PageTheme(resolveTheme(.default, systemScheme: .light)) }

    func testAPageCannotReachTheNetworkByAnyWayItHas() async throws {
        let listener = try Listener()
        defer { listener.stop() }
        let base = "http://127.0.0.1:\(listener.port)"
        let html = """
        <!doctype html><html><head>
        <link rel="stylesheet" href="\(base)/css">
        <link rel="preconnect" href="\(base)/preconnect">
        <link rel="dns-prefetch" href="\(base)/dns">
        <link rel="prefetch" href="\(base)/prefetch">
        <link rel="preload" as="script" href="\(base)/preload">
        <link rel="icon" href="\(base)/icon">
        <style>@import url("\(base)/import"); body { background-image: url("\(base)/bg"); } @font-face { font-family: x; src: url("\(base)/font"); } p { font-family: x; }</style>
        <script src="\(base)/script"></script>
        <meta http-equiv="refresh" content="1;url=\(base)/refresh">
        </head><body>
        <p>text</p>
        <img src="\(base)/img"><video src="\(base)/video"></video><audio src="\(base)/audio"></audio>
        <object data="\(base)/object"></object><embed src="\(base)/embed">
        <iframe src="\(base)/frame"></iframe>
        <form id="f" action="\(base)/form" method="post"><input name="q" value="secret"></form>
        <script>
        const tries = [];
        const attempt = (name, run) => { try { const r = run(); if (r && r.catch) r.catch(() => {}); tries.push(name); } catch (e) { tries.push(name + ':' + e.name); } };
        attempt('fetch', () => fetch('\(base)/fetch?d=secret'));
        attempt('xhr', () => { const x = new XMLHttpRequest(); x.open('GET', '\(base)/xhr'); x.send(); });
        attempt('beacon', () => navigator.sendBeacon('\(base)/beacon', 'secret'));
        attempt('websocket', () => new WebSocket('ws://127.0.0.1:\(listener.port)/ws'));
        attempt('eventsource', () => new EventSource('\(base)/sse'));
        attempt('worker', () => new Worker('\(base)/worker.js'));
        attempt('image', () => { const i = new Image(); i.src = '\(base)/image-object'; });
        attempt('open', () => window.open('\(base)/open'));
        attempt('form', () => document.getElementById('f').submit());
        setTimeout(() => attempt('location', () => { location.href = '\(base)/location'; }), 200);
        setTimeout(() => attempt('replace', () => location.replace('\(base)/replace')), 300);
        </script></body></html>
        """
        let view = PageSandboxView(html: html, data: nil, theme: theme)
        _ = window(for: view)
        try await loaded(view)
        // Long enough for the refresh, the timers and anything a load would have started.
        try await Task.sleep(for: .seconds(3))
        let seen = listener.seen
        XCTAssertEqual(seen.count, 0, "the page reached the listener: \(seen.requests)")
        XCTAssertEqual(view.currentURL, PageSandboxPolicy.documentURL, "the page stayed where it was")
        XCTAssertEqual(view.allowedNavigations, [PageSandboxPolicy.documentURL], "only the first load went through")
        XCTAssertTrue(view.console.contains { $0.contains("Blocked by the page sandbox") }, "violations reach the console the agent sees: \(view.console)")
    }

    func testAPageHasNoCookiesOrStorageAndAnOpaqueOrigin() async throws {
        let view = PageSandboxView(html: "<!doctype html><p>hi</p>", data: nil, theme: theme)
        _ = window(for: view)
        try await loaded(view)
        let result = await view.evaluateInPage("""
        const out = {};
        try { document.cookie = 'session=stolen'; out.cookie = document.cookie; } catch (e) { out.cookie = 'threw ' + e.name; }
        for (const name of ['localStorage', 'sessionStorage']) { try { window[name].setItem('k', 'v'); out[name] = window[name].getItem('k'); } catch (e) { out[name] = 'threw ' + e.name; } }
        try { indexedDB.open('x'); out.indexedDB = 'opened'; } catch (e) { out.indexedDB = 'threw ' + e.name; }
        try { out.caches = typeof caches === 'undefined' ? 'none' : await caches.open('x').then(() => 'opened', e => 'rejected ' + e.name); } catch (e) { out.caches = 'threw ' + e.name; }
        out.origin = String(window.origin);
        return JSON.stringify(out);
        """)
        let parsed = try XCTUnwrap(result.flatMap { try JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: String] }, result ?? "nil")
        XCTAssertEqual(parsed["cookie"], "", "a cookie set by the page is not kept")
        XCTAssertEqual(parsed["localStorage"], "threw SecurityError")
        XCTAssertEqual(parsed["sessionStorage"], "threw SecurityError")
        XCTAssertEqual(parsed["indexedDB"], "threw SecurityError")
        XCTAssertNotEqual(parsed["caches"], "opened")
        XCTAssertEqual(parsed["origin"], "null", "sandbox allow-scripts: an opaque origin")
    }

    func testOnlyARealClickOnAWebLinkReachesBrk() async throws {
        let html = """
        <!doctype html><body style="margin:0">
        <a id="web" href="https://shop.example/item?id=2" style="display:block;height:60px">Shop</a>
        <a id="file" href="file:///etc/passwd" style="display:block;height:60px">File</a>
        <a id="blank" target="_blank" href="https://other.example/" style="display:block;height:60px">New window</a>
        </body>
        """
        let view = PageSandboxView(html: html, data: nil, theme: theme)
        let window = window(for: view, height: 300, front: true)
        var links: [URL] = []
        view.onEvent = { if case .link(let url) = $0 { links.append(url) } }
        try await loaded(view)
        // A script's click is not the user's.
        _ = await view.evaluateInPage("document.getElementById('web').click(); document.getElementById('blank').click(); return 1")
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertEqual(links, [], "a synthetic click opened \(links)")
        func click(_ y: CGFloat) {
            let point = NSPoint(x: 20, y: window.contentView!.bounds.height - y)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                     windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { continue }
                window.sendEvent(event)
            }
        }
        click(30)
        click(90)
        click(150)
        let start = ProcessInfo.processInfo.systemUptime
        while links.count < 2, ProcessInfo.processInfo.systemUptime - start < 5 { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertEqual(links, [URL(string: "https://shop.example/item?id=2")!, URL(string: "https://other.example/")!], "only the web links, as Brk opens them")
        XCTAssertEqual(view.currentURL, PageSandboxPolicy.documentURL)
    }

    func testARightClickOpensBrksMenuNotThePages() async throws {
        let html = "<!doctype html><body style=\"margin:0;height:200px\"><script>window.menus = 0; document.addEventListener('contextmenu', e => { window.menus++; e.preventDefault(); });</script></body>"
        let view = PageSandboxView(html: html, data: nil, theme: theme)
        let window = window(for: view, height: 200, front: true)
        var asked = 0
        view.menuItems = {
            asked += 1
            let item = NSMenuItem(title: "Keep as Tab", action: nil, keyEquivalent: "")
            // The menu tracks modally in the event-tracking run loop mode, where the main queue does not run: a timer there closes it.
            nonisolated(unsafe) let opened = item
            let timer = Timer(timeInterval: 0.3, repeats: false) { _ in MainActor.assumeIsolated { opened.menu?.cancelTrackingWithoutAnimation() } }
            RunLoop.main.add(timer, forMode: .common)
            return [item]
        }
        try await loaded(view)
        let point = NSPoint(x: 40, y: 100)
        for type in [NSEvent.EventType.rightMouseDown, .rightMouseUp] {
            guard let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                 windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) else { continue }
            window.sendEvent(event)
        }
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(asked, 1, "Brk's menu was not asked for")
        let pageSaw = await view.evaluateInPage("return window.menus")
        XCTAssertEqual(pageSaw, "0", "the page saw the right click")
    }

    func testThePageReadsItsDataAndTheThemeLive() async throws {
        let html = """
        <!doctype html><script>
        window.seen = [];
        window.addEventListener('message', e => { if (e.data && e.data.method === 'ui/notifications/host-context-changed') window.seen.push(e.data.params.theme); });
        </script>
        """
        let view = PageSandboxView(html: html, data: #"{"rows":[1,2,3]}"#, theme: theme)
        _ = window(for: view)
        try await loaded(view)
        let first = await view.evaluateInPage("return [window.brk.data.rows.length, getComputedStyle(document.documentElement).getPropertyValue('--primary').trim(), getComputedStyle(document.documentElement).getPropertyValue('--chart-6').trim(), getComputedStyle(document.body).backgroundColor].join('|')")
        let parts = (first ?? "").split(separator: "|").map(String.init)
        XCTAssertEqual(parts.first, "3", "window.brk.data: \(first ?? "nil")")
        XCTAssertTrue(parts.count == 4 && !parts[1].isEmpty && !parts[2].isEmpty, "theme variables: \(first ?? "nil")")
        XCTAssertEqual(parts.last, "rgba(0, 0, 0, 0)", "the base sheet leaves the body without a background")
        let tampered = await view.evaluateInPage("try { window.brk = {data: 'x'}; } catch (e) {} return typeof window.webkit.messageHandlers.brk")
        XCTAssertEqual(tampered, "undefined", "the page cannot see Brk's bridge")
        let dark = PageTheme(resolveTheme(SpaceTheme(colors: [RGBA(hex: "#20304A")], texture: .grain, intensity: 0.25, appearance: .dark), systemScheme: .dark))
        view.apply(dark)
        try await Task.sleep(for: .milliseconds(300))
        let after = await view.evaluateInPage("return [getComputedStyle(document.documentElement).getPropertyValue('--foreground').trim(), window.seen.join(',')].join('|')")
        XCTAssertEqual(after, "#F2F2F5|light,dark", "the variables changed and the page heard it")
    }

    func testAPreviewPicturesThePageAtItsContentHeightWithItsConsole() async throws {
        let html = """
        <!doctype html><div style="height:300px;background:var(--card);border-radius:var(--radius)">chart</div>
        <script>console.log('drawn', 3); fetch('https://example.com/x').catch(() => console.warn('offline'));</script>
        """
        let preview = await PageSandbox.preview(html: html, data: nil, width: 400, theme: theme)
        let png = try XCTUnwrap(preview.png)
        let image = try XCTUnwrap(NSBitmapImageRep(data: png))
        XCTAssertEqual(image.pixelsWide, 400)
        XCTAssertEqual(preview.contentHeight, 300)
        XCTAssertEqual(image.pixelsHigh, 300)
        XCTAssertTrue(preview.console.contains("log: drawn 3"), "\(preview.console)")
        XCTAssertTrue(preview.console.contains { $0.contains("Blocked by the page sandbox") || $0.contains("offline") }, "\(preview.console)")
    }

    func testTheThemeMapsBrksSchemesAndTheSpacesColor() {
        let light = PageTheme(resolveTheme(.default, systemScheme: .light))
        let dark = PageTheme(resolveTheme(SpaceTheme(colors: [RGBA(hex: "#FFB000")], texture: .grain, intensity: 0.25, appearance: .dark), systemScheme: .dark))
        let names = ["--background", "--foreground", "--muted", "--card", "--popover", "--secondary", "--border", "--ring", "--primary", "--accent",
                     "--destructive", "--warning", "--success", "--info", "--code-background", "--chart-1", "--chart-6", "--radius", "--font-sans", "--font-mono",
                     "--primary-foreground", "--muted-foreground"]
        for name in names { XCTAssertTrue(light.variables.contains { $0.0 == name }, name) }
        XCTAssertEqual(light.scheme, .light)
        XCTAssertEqual(dark.scheme, .dark)
        XCTAssertNotEqual(light.variables.first { $0.0 == "--foreground" }?.1, dark.variables.first { $0.0 == "--foreground" }?.1)
        // The Space's color leads, made readable on the scheme's background.
        let primary = PageTheme.readable(RGBA(hex: "#FFB000"), on: RGBA(hex: "#FFFFFF"))
        XCTAssertLessThan(PageTheme.luminance(primary), PageTheme.luminance(RGBA(hex: "#FFB000")), "a yellow is darkened on white")
    }

    func testTheRuleListCompiles() async {
        let rules = await PageSandboxView.rules()
        XCTAssertNotNil(rules, "without it no page loads")
    }

    func testThePolicyIsWhatTheDesignSays() {
        let csp = PageSandboxPolicy.contentSecurityPolicy
        for directive in ["default-src 'none'", "script-src 'unsafe-inline'", "style-src 'unsafe-inline'", "img-src data: blob:", "connect-src 'none'",
                          "frame-src 'none'", "form-action 'none'", "base-uri 'none'", "sandbox allow-scripts"] {
            XCTAssertTrue(csp.contains(directive), directive)
        }
        XCTAssertFalse(csp.contains("allow-same-origin"), "an opaque origin: no cookies, no storage")
        XCTAssertFalse(csp.contains("allow-popups") || csp.contains("allow-top-navigation") || csp.contains("allow-forms"))
        XCTAssertFalse(csp.contains("http"), "no host is allowed anything")
    }
}
