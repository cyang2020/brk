import AppKit
import BrkBase
import Darwin
@testable import BrkSidebar
@testable import BrkUIKit
import XCTest

/// Favicons Brk fetches itself, outside Chromium: the sidebar's (`FaviconStore`) and the command bar's, Library's and
/// tab switcher's (`FaviconCache`). Their URLs come from every profile and from incognito windows. No fetch puts a cookie
/// in the app's cookie store or a response in its shared URL cache (they were URLSession.shared's: an incognito site's
/// favicon stayed on disk after the window closed, its cookie sent again from normal windows). A standard window's
/// favicons are kept in Brk's own cache, so a launch draws restored rows at once; an incognito window's are kept
/// nowhere. A sidebar favicon whose fetch failed (offline at launch) is fetched again later, less often each time it
/// fails again, and the sidebar keeps a bounded number of favicons in memory.
@MainActor
final class FaviconFetchTests: XCTestCase {
    /// A window that says whether Brk's own fetches for its views may be kept, as a browser window does.
    private final class BrowserLikeWindow: NSWindow, FetchKeepingWindow {
        var keepsFetches = false
    }

    /// A local HTTP server: every path answers a 1 x 1 PNG that may be cached for an hour and sets a cookie; a path
    /// with "first-fails" answers its first request with an HTML page instead (a captive portal's), one with
    /// "always-fails" every request.
    private final class Server: @unchecked Sendable {
        let port: UInt16
        private let fd: Int32
        private let lock = NSLock()
        private var counts: [String: Int] = [:]
        private var running = true
        private let png: Data

        init() throws {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                       isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 4, bitsPerPixel: 32)!
            png = rep.representation(using: .png, properties: [:])!
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
            Thread { [self] in loop() }.start()
        }

        func url(_ path: String) -> URL { URL(string: "http://127.0.0.1:\(port)\(path)")! }
        func requests(_ path: String) -> Int { lock.withLock { counts[path] ?? 0 } }

        private func loop() {
            while lock.withLock({ running }) {
                let client = Darwin.accept(fd, nil, nil)
                guard client >= 0 else { continue }
                var buffer = [UInt8](repeating: 0, count: 4096)
                var timeout = timeval(tv_sec: 1, tv_usec: 0)
                setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
                let n = Darwin.read(client, &buffer, buffer.count)
                let line = n > 0 ? String(decoding: buffer[0..<n], as: UTF8.self).split(separator: "\r\n").first.map(String.init) ?? "" : ""
                let path = line.split(separator: " ").dropFirst().first.map(String.init) ?? "/"
                let count = lock.withLock { counts[path, default: 0] += 1; return counts[path]! }
                let page = (path.contains("first-fails") && count == 1) || path.contains("always-fails")
                let body = page ? Data("<html>Sign in to the Wi-Fi</html>".utf8) : png
                let head = "HTTP/1.1 200 OK\r\nContent-Type: \(page ? "text/html" : "image/png")\r\nContent-Length: \(body.count)\r\n"
                    + "Cache-Control: public, max-age=3600\r\nSet-Cookie: brkprobe=1; Path=/\r\nConnection: close\r\n\r\n"
                let reply = Data(head.utf8) + body
                _ = reply.withUnsafeBytes { Darwin.write(client, $0.baseAddress, reply.count) }
                Darwin.close(client)
            }
        }

        func stop() {
            lock.withLock { running = false }
            Darwin.shutdown(fd, SHUT_RDWR)
            Darwin.close(fd)
        }
    }

    private func waitUntil(_ timeout: Double = 10, _ done: () -> Bool) {
        let start = Date()
        while !done(), Date().timeIntervalSince(start) < timeout { RunLoop.main.run(until: Date().addingTimeInterval(0.02)) }
    }

    /// Nothing about `url` stayed in the app's own cookie store or URL cache.
    private func assertNothingKept(for url: URL, file: StaticString = #filePath, line: UInt = #line) {
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        let cookies = (HTTPCookieStorage.shared.cookies(for: url) ?? []).filter { $0.name == "brkprobe" }
        let cached = URLCache.shared.cachedResponse(for: URLRequest(url: url))
        for cookie in cookies { HTTPCookieStorage.shared.deleteCookie(cookie) }
        URLCache.shared.removeCachedResponse(for: URLRequest(url: url))
        XCTAssertTrue(cookies.isEmpty, "the favicon's cookie went into the shared cookie store", file: file, line: line)
        XCTAssertNil(cached, "the favicon's response went into the shared URL cache", file: file, line: line)
    }

    /// The response in Brk's own favicon cache (the one standard windows' fetches keep), if any.
    private func kept(_ url: URL) -> CachedURLResponse? {
        FaviconFetch.keeping.configuration.urlCache?.cachedResponse(for: URLRequest(url: url))
    }

    /// A standard window's favicon (the command bar's cache) is kept in Brk's own cache: asked for again with nothing in
    /// memory, as at the next launch, it comes from there without a request. No cookie, nothing in the shared cache.
    func testAStandardWindowsFaviconIsKeptInBrksOwnCache() throws {
        let server = try Server()
        defer { server.stop() }
        let path = "/bar-kept-\(UUID().uuidString).png"
        let url = server.url(path)
        var ready = false
        XCTAssertNil(FaviconCache().image(for: url, keepingNothing: false) { _ in ready = true })
        waitUntil { ready }
        XCTAssertTrue(ready, "the favicon did not load")
        waitUntil(5) { kept(url) != nil }
        XCTAssertNotNil(kept(url), "the standard window's favicon was not kept in Brk's own cache")
        ready = false
        XCTAssertNil(FaviconCache().image(for: url, keepingNothing: false) { _ in ready = true })
        waitUntil { ready }
        XCTAssertTrue(ready, "the kept favicon did not load again")
        XCTAssertEqual(server.requests(path), 1, "the kept favicon was fetched over the network again")
        assertNothingKept(for: url)
    }

    /// An incognito window's favicon (the command bar's cache) is kept nowhere: asked for again with nothing in memory,
    /// it is fetched again.
    func testAnIncognitoWindowsFaviconIsKeptNowhere() throws {
        let server = try Server()
        defer { server.stop() }
        let path = "/bar-private-\(UUID().uuidString).png"
        let url = server.url(path)
        for round in 1...2 {
            var ready = false
            XCTAssertNil(FaviconCache().image(for: url, keepingNothing: true) { _ in ready = true })
            waitUntil { ready }
            XCTAssertTrue(ready, "the favicon did not load")
            XCTAssertEqual(server.requests(path), round, "the incognito favicon came from a cache")
        }
        XCTAssertNil(kept(url), "the incognito window's favicon went into Brk's favicon cache")
        assertNothingKept(for: url)
    }

    /// The sidebar's icons fetch through their window: a standard browser window's favicon is kept in Brk's own cache, an
    /// incognito window's nowhere. A view in no browser window keeps nothing.
    func testTheSidebarKeepsAFaviconOnlyForAWindowThatMayKeepIt() throws {
        let server = try Server()
        defer { server.stop() }
        XCTAssertTrue(IconView().fetchesKeepNothing, "a view in no window may keep what it fetches")
        let plain = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 40, height: 40), styleMask: [.borderless], backing: .buffered, defer: false)
        plain.isReleasedWhenClosed = false
        let inPlain = IconView(frame: CGRect(x: 0, y: 0, width: 16, height: 16))
        plain.contentView?.addSubview(inPlain)
        XCTAssertTrue(inPlain.fetchesKeepNothing, "a view in a window that is no browser window may keep what it fetches")
        for keeps in [true, false] {
            let window = BrowserLikeWindow(contentRect: CGRect(x: 0, y: 0, width: 40, height: 40), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.keepsFetches = keeps
            let icon = IconView(frame: CGRect(x: 0, y: 0, width: 16, height: 16))
            window.contentView?.addSubview(icon)
            let url = server.url("/sidebar-\(keeps ? "kept" : "private")-\(UUID().uuidString).png")
            icon.render(.favicon(url), tint: .labelColor)
            waitUntil {
                icon.layoutSubtreeIfNeeded()
                return icon.shownFavicon != nil
            }
            XCTAssertNotNil(icon.shownFavicon, "the favicon did not show")
            if keeps {
                waitUntil(5) { kept(url) != nil }
                XCTAssertNotNil(kept(url), "the standard window's favicon was not kept in Brk's own cache")
            } else {
                RunLoop.main.run(until: Date().addingTimeInterval(0.3))
                XCTAssertNil(kept(url), "the incognito window's favicon went into Brk's favicon cache")
            }
            assertNothingKept(for: url)
        }
    }

    /// Asked again soon after a failed fetch, nothing is fetched (rows redraw many times a second); asked later, the
    /// favicon is fetched again and shows.
    func testASidebarFaviconWhoseFetchFailedIsFetchedAgainLater() throws {
        let server = try Server()
        defer { server.stop() }
        let path = "/first-fails-\(UUID().uuidString).png"
        let url = server.url(path)
        let store = FaviconStore()
        var clock = 1_000.0
        store.now = { clock }
        var ready = false
        XCTAssertNil(store.image(for: url, keepingNothing: true) { ready = true })
        waitUntil { server.requests(path) == 1 }
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        XCTAssertNil(store.image(for: url, keepingNothing: true) {})
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(server.requests(path), 1, "asked again at once, the failed favicon was fetched again")
        clock += 60
        XCTAssertNil(store.image(for: url, keepingNothing: true) { ready = true })
        waitUntil { ready }
        XCTAssertEqual(server.requests(path), 2, "asked a minute later, the failed favicon was not fetched again")
        XCTAssertNotNil(store.image(for: url, keepingNothing: true) {}, "the favicon stayed blank")
    }

    /// A favicon that never loads is asked for less often each time: 30 s after the first failure, then 60 s after the
    /// second. It was fetched again every 30 s for as long as rows redrew.
    func testASidebarFaviconThatKeepsFailingIsAskedForLessOften() throws {
        let server = try Server()
        defer { server.stop() }
        let path = "/always-fails-\(UUID().uuidString).png"
        let url = server.url(path)
        let store = FaviconStore()
        var clock = 1_000.0
        store.now = { clock }
        func ask(after seconds: Double, expecting requests: Int, _ message: String, line: UInt = #line) {
            clock += seconds
            XCTAssertNil(store.image(for: url, keepingNothing: true) {}, line: line)
            waitUntil(3) { server.requests(path) >= requests }
            RunLoop.main.run(until: Date().addingTimeInterval(0.5))
            XCTAssertEqual(server.requests(path), requests, message, line: line)
        }
        ask(after: 0, expecting: 1, "the first ask did not fetch")
        ask(after: 31, expecting: 2, "31 s after the first failure the favicon was not fetched again")
        ask(after: 31, expecting: 2, "31 s after the second failure the favicon was fetched again: the wait did not grow")
        ask(after: 30, expecting: 3, "61 s after the second failure the favicon was not fetched again")
    }

    /// The sidebar keeps at most its limit of favicons in memory; past it, the one asked for longest ago goes and is
    /// fetched again when asked for. It kept every favicon ever shown for the life of the process.
    func testTheSidebarKeepsAtMostItsLimitOfFavicons() throws {
        let server = try Server()
        defer { server.stop() }
        let store = FaviconStore(limit: 2)
        let paths = (1...3).map { "/limit-\($0)-\(UUID().uuidString).png" }
        func load(_ path: String) {
            var ready = false
            XCTAssertNil(store.image(for: server.url(path), keepingNothing: true) { ready = true })
            waitUntil { ready }
            XCTAssertTrue(ready, "\(path) did not load")
        }
        load(paths[0])
        load(paths[1])
        XCTAssertNotNil(store.image(for: server.url(paths[0]), keepingNothing: true) {}, "the first favicon was not kept")
        load(paths[2])
        XCTAssertNotNil(store.image(for: server.url(paths[0]), keepingNothing: true) {}, "the favicon asked for last went")
        XCTAssertNotNil(store.image(for: server.url(paths[2]), keepingNothing: true) {}, "the newest favicon went")
        XCTAssertNil(store.image(for: server.url(paths[1]), keepingNothing: true) {}, "a third favicon stayed past the limit of two")
        waitUntil(3) { server.requests(paths[1]) == 2 }
        XCTAssertEqual(server.requests(paths[1]), 2, "the favicon that went was not fetched again")
    }
}
