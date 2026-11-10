import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation

/// Owner: W3. The Library button's flyout and badge (Arc's `HomeBadging`; docs/arc-anatomy/library-flyout.md) with real
/// downloads from the loopback site and the real pointer: the rest needed before it opens, the rows (the newest four,
/// newest at the bottom), the area that keeps it open, the Space dots that close it, the preview a click on a finished
/// download opens; a running download's disc, ring and ×.
enum LibraryFlyoutScenarios {
    static let all = [
        Scenario("LibraryFlyout-Hover", "resting the real pointer on the Library button opens the newest four downloads above it as Arc does; a real click on a finished one previews it", cefOnly: "real downloads and window-server pointer", hover),
        Scenario("LibraryFlyout-Running", "a running download shows its disc on the button and a ring, progress and × in its row; the real × cancels it", cefOnly: "real downloads and window-server pointer", running),
        Scenario("LibraryFlyout-Flight", "a real click on a download link throws the download icon from the pointer into the Library button; with the sidebar hidden it lands in Arc's bin at the corner", cefOnly: "real downloads and window-server pointer", flight),
    ]

    /// Arc's pale blue fixture Space (capture-brk-scenes.py's SKY), so the pictures sit beside Arc's.
    static let sky = SpaceTheme(colors: [RGBA(0.90, 0.95, 0.99), RGBA(0.95, 0.975, 0.99)], texture: .grain, intensity: SpaceTheme.default.intensity, appearance: .light)
    static let files = ["notes.txt", "report.pdf", "photo.png", "sunset.png", "data.csv"]

    // MARK: Setup

    /// Downloads `names` from the site's flyout folder into this run's data directory, in order, and waits for each.
    private static func prepare(_ app: AppUnderTest, _ names: [String], theme: SpaceTheme = sky) throws {
        let folder = app.dataDirectory.appendingPathComponent("flyout-downloads")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try app.dispatch(.settings(.profile(.default, .downloadsDirectory(folder.path))))
        try app.dispatch(.space(.update(try app.view().space.id, title: nil, icon: nil, theme: theme)))
        for name in names {
            _ = try app.send(.load(window: app.window, url: app.site.url("attach/flyout/\(name)")))
            try app.waitUntil("\(name) downloaded", timeout: 15) {
                try flyout(app).items.contains { $0.title.hasPrefix((name as NSString).deletingPathExtension) && !$0.running }
            }
            app.sleep(0.4)
        }
        try app.settle()
    }

    private static func flyout(_ app: AppUnderTest) throws -> LibraryFlyoutSnapshot {
        guard let flyout = try app.view().libraryFlyout else { throw Check(description: "the window has no Library flyout") }
        return flyout
    }

    private static let list = ViewID.tabTool("library-flyout")
    private static let badge = ViewID.tabTool("library-badge")
    private static func row(_ index: Int) -> ViewID { .tabTool("library-flyout-row-\(index)") }
    private static func open(_ app: AppUnderTest) throws -> Bool { isShown(try app.native(), list) }

    // MARK: The real pointer

    private static func screen(_ app: AppUnderTest, _ point: CGPoint) throws -> CGPoint {
        let frame = try app.native().windowFrame
        return CGPoint(x: frame.minX + point.x, y: CGDisplayBounds(CGMainDisplayID()).height - frame.maxY + point.y)
    }

    /// One mouse-moved event at `point` (window coordinates): the pointer is there at once, so a dwell can be timed.
    @discardableResult
    private static func jump(_ app: AppUnderTest, to point: CGPoint) throws -> TimeInterval {
        let at = try screen(app, point)
        try WindowServerKeys.ensureFrontmost(app, app.window!)
        guard case .hello(let hello) = try app.send(.hello), let front = PhysicalPointer.frontmost(at: at), front.pid == hello.pid else {
            throw Check(description: "another window is in front of Brk at \(at); real pointer not moved")
        }
        CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: .mouseMoved, mouseCursorPosition: at, mouseButton: .left)?.post(tap: .cghidEventTap)
        return ProcessInfo.processInfo.systemUptime
    }

    private static func button(_ app: AppUnderTest) throws -> CGRect { try visible(app.native(), .dockLibrary).frame }
    private static func centre(_ rect: CGRect) -> CGPoint { CGPoint(x: rect.midX, y: rect.midY) }
    /// A point over the page, well away from the sidebar.
    private static func page(_ app: AppUnderTest) throws -> CGPoint {
        let area = try app.native().computed.contentArea
        return CGPoint(x: area.midX, y: area.midY)
    }

    /// Rests on the button until the list shows; returns how long that took.
    @discardableResult
    private static func openList(_ app: AppUnderTest) throws -> TimeInterval {
        let started = try jump(app, to: centre(try button(app)))
        try app.waitUntil("the list open", timeout: 3) { try open(app) }
        return ProcessInfo.processInfo.systemUptime - started
    }

    private static func closedSoon(_ app: AppUnderTest, _ what: String) throws {
        try app.waitUntil(what, timeout: 1.5) { !(try open(app)) }
    }

    // MARK: Scenarios

    @Sendable static func hover(_ app: AppUnderTest) throws {
        try prepare(app, files)
        let snapshot = try flyout(app)
        try expect(snapshot.items.map(\.title) == ["report.pdf", "photo.png", "sunset.png", "data.csv"], "the list is not the newest four, oldest first: \(snapshot.items.map(\.title))")
        try expect(snapshot.badge?.title == "data.csv", "the badge is not the newest download: \(String(describing: snapshot.badge?.title))")
        _ = try jump(app, to: try page(app))
        app.sleep(0.6)
        try expect(!(try open(app)), "the list is open before any hover")
        try expect(isShown(try app.native(), badge), "no badge on the button after a download")
        app.passed("five real downloads: the badge shows the newest file's icon")

        // A quick pass over the button opens nothing (Arc: a rest of 0.28 s did not open it).
        try jump(app, to: centre(try button(app)))
        usleep(120_000)
        try jump(app, to: try page(app))
        app.sleep(0.7)
        try expect(!(try open(app)), "a 0.12 s pass over the button opened the list")
        app.passed("a 0.12 s pass over the button opens nothing")

        // A rest opens it, not before the dwell.
        let started = try jump(app, to: centre(try button(app)))
        usleep(150_000)
        try expect(!(try open(app)), "the list opened within 0.15 s of the pointer's arrival")
        try app.waitUntil("the list open after the rest", timeout: 3) { try open(app) }
        let took = ProcessInfo.processInfo.systemUptime - started
        try expect(took >= 0.25 && took <= 0.9, "the list opened \(took) s after the pointer arrived (Arc: about 0.3 s)")
        app.note(String(format: "the list opened %.2f s after the pointer reached the button", took))
        let n = try app.native()
        let library = try visible(n, .dockLibrary).frame
        let sidebarWidth = try XCTUnwrapFrame(n.computed.sidebar?.frame).width
        for index in 0..<4 {
            let frame = try visible(n, row(index)).frame
            let expected = CGRect(x: 4, y: library.minY - 1 - Double(3 - index) * 56 - 48, width: sidebarWidth - 16, height: 48)
            try expect(abs(frame.minX - expected.minX) < 0.5 && abs(frame.minY - expected.minY) < 0.5 && abs(frame.width - expected.width) < 0.5 && abs(frame.height - 48) < 0.5,
                       "row \(index) at \(frame), Arc's place \(expected)")
        }
        try expect(!isShown(n, row(4)), "a fifth row")
        try expect(!isShown(n, badge), "the badge stays over the open list")
        try expect(try flyout(app).badge == nil, "opening the list did not put the finished item's badge away")
        try app.screenshot("LF-open")
        app.passed("a rest on the button opens four 48 pt rows on a 56 pt pitch, newest next to the button; the badge goes")

        // The newest row: the fill and Arc's tooltip with its name.
        let newest = try visible(n, row(3)).frame
        try jump(app, to: CGPoint(x: newest.minX + 90, y: newest.midY))
        try app.waitUntil("the row's tooltip", timeout: 2) { isShown(try app.native(), .tabTool("arc-tooltip")) }
        app.passed("the row under the pointer fills and Arc's tooltip names the file")

        // Anywhere in the area 256 tall above the button's bottom keeps it; the page closes it at once.
        try jump(app, to: CGPoint(x: 120, y: library.maxY - 240))
        app.sleep(0.6)
        try expect(try open(app), "the list closed with the pointer inside its area, 240 above the button's bottom")
        let left = try jump(app, to: try page(app))
        try closedSoon(app, "the list closed after the pointer left for the page")
        app.note(String(format: "closed %.2f s after the pointer left", ProcessInfo.processInfo.systemUptime - left))
        app.passed("the open list's area keeps it; leaving for the page closes it")

        // Resting on the Space dots strip closes it after 0.5 s.
        try openList(app)
        try jump(app, to: CGPoint(x: library.maxX + 60, y: library.midY))
        app.sleep(0.25)
        try expect(try open(app), "the list closed before the dots' 0.5 s")
        try closedSoon(app, "the list closed after resting on the Space dots")
        app.passed("resting on the Space dots strip closes the list after 0.5 s, not before")

        // A real click on a finished row previews that download over the window; × closes it.
        try openList(app)
        let photo = try visible(app.native(), row(1)).frame
        try PhysicalPointer.click(app, at: try screen(app, CGPoint(x: photo.minX + 90, y: photo.midY)), window: app.window!)
        try app.waitUntil("the preview", timeout: 3) { isShown(try app.native(), .tabTool("library-item-preview")) }
        let previewed = try flyout(app).preview
        try expect(previewed?.title == "photo.png" && previewed?.file?.path.hasSuffix("flyout-downloads/photo.png") == true,
                   "the preview shows \(String(describing: previewed?.title)) at \(String(describing: previewed?.file))")
        app.sleep(1.0)
        try app.screenshot("LF-preview")
        let close = try visible(app.native(), .tabTool("library-item-preview-close")).frame
        try PhysicalPointer.click(app, at: try screen(app, centre(close)), window: app.window!)
        try app.waitUntil("the preview closed", timeout: 3) { !isShown(try app.native(), .tabTool("library-item-preview")) }
        app.passed("a real click on a finished download previews the downloaded file; its × closes the preview")
    }

    // MARK: The download flight (Arc's DownloadToLibrary)

    /// A window picture as RGBA bytes, with its scale (pixels per point).
    private struct Picture {
        let bytes: [UInt8], width: Int, height: Int, scale: Double
        func pixel(_ point: CGPoint) -> (r: Int, g: Int, b: Int) {
            let x = min(width - 1, max(0, Int(point.x * scale))), y = min(height - 1, max(0, Int(point.y * scale)))
            let i = (y * width + x) * 4
            return (Int(bytes[i]), Int(bytes[i + 1]), Int(bytes[i + 2]))
        }
    }

    private static func picture(_ app: AppUnderTest, _ name: String) throws -> Picture {
        let shot = try app.screenshot(name)
        guard let provider = CGDataProvider(url: shot.url as CFURL),
              let image = CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw Check(description: "screenshot \(shot.url.lastPathComponent) unreadable")
        }
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let drawn = bytes.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
            return true
        }
        guard drawn else { throw Check(description: "no bitmap context") }
        return Picture(bytes: bytes, width: image.width, height: image.height, scale: Double(image.width) / max(1, try app.native().contentSize.width))
    }

    /// The thrown icon's ring (Arc's #4C4C4C, a neutral dark grey) where the picture differs from `base`, inside `area`:
    /// its centre in window points, or nil when it is not there.
    private static func icon(_ shot: Picture, base: Picture, in area: CGRect) -> CGPoint? {
        var sx = 0.0, sy = 0.0, n = 0.0
        var y = area.minY
        while y < area.maxY {
            var x = area.minX
            while x < area.maxX {
                let p = shot.pixel(CGPoint(x: x, y: y)), q = base.pixel(CGPoint(x: x, y: y))
                if max(p.r, p.g, p.b) - min(p.r, p.g, p.b) < 14, (40...120).contains(p.g), abs(p.g - q.g) + abs(p.r - q.r) > 60 { sx += x; sy += y; n += 1 }
                x += 1
            }
            y += 1
        }
        return n >= 6 ? CGPoint(x: sx / n, y: sy / n) : nil
    }

    /// Clicks the flight page's link with the real pointer and waits for the window's flight to start.
    private static func throwOne(_ app: AppUnderTest, link: CGPoint) throws -> TimeInterval {
        let before = try flyout(app).flights.count
        try PhysicalPointer.click(app, at: try screen(app, link), window: app.window!)
        try app.waitUntil("the download's flight", timeout: 8) { try flyout(app).flights.count > before }
        return ProcessInfo.processInfo.systemUptime
    }

    @Sendable static func flight(_ app: AppUnderTest) throws {
        try prepare(app, [])
        _ = try app.send(.load(window: app.window, url: app.site.url("flyout-flight.html")))
        try app.settle()
        app.sleep(0.8)
        let n = try app.native()
        let area = n.computed.contentArea
        let link = CGPoint(x: area.minX + area.width * 0.5, y: area.minY + area.height * 0.5)
        let base = try picture(app, "LFF-base")
        // Sidebar shown: the icon is thrown from the click along Arc's arc, crosses the page to the left and falls into
        // the Library button. A window picture takes about 0.3 s, so each one is checked against the planned path
        // around its time rather than frame by frame.
        let height = n.contentSize.height
        guard let plan = DownloadFlightPath.plan(pointer: CGPoint(x: link.x, y: height - link.y), window: n.contentSize, bin: false) else {
            throw Check(description: "no planned path from \(link)")
        }
        let started = try throwOne(app, link: link)
        var seen: [(t: Double, at: CGPoint)] = []
        var index = 0
        while ProcessInfo.processInfo.systemUptime - started < 1.3 {
            let shot = try picture(app, "LFF-\(index)")
            index += 1
            if let at = icon(shot, base: base, in: CGRect(x: area.minX + 4, y: area.minY + 4, width: area.width - 8, height: area.height - 8)) {
                seen.append((ProcessInfo.processInfo.systemUptime - started, at))
            }
        }
        app.note("icon seen at " + seen.map { String(format: "%.2fs (%.0f, %.0f)", $0.t, $0.at.x, $0.at.y) }.joined(separator: ", "))
        try expect(seen.count >= 2, "the icon was seen in \(seen.count) of \(index) pictures of the page")
        // Each sighting lies on the arc planned from the click, in order along it, and one of them before the last
        // quarter of the throw (where arcs from anywhere converge on the button).
        var along: [Int] = []
        var found: [String] = []
        for sight in seen {
            let nearest = plan.frames.indices.map { i in (i, hypot(plan.frames[i].position.x - sight.at.x, height - plan.frames[i].position.y - sight.at.y)) }
                .min { $0.1 < $1.1 } ?? (0, .infinity)
            along.append(nearest.0)
            found.append(String(format: "(%.0f, %.0f) %.0f pt from frame %d", sight.at.x, sight.at.y, nearest.1, nearest.0))
            try expect(nearest.1 < 30, "the icon left Arc's arc from the click: " + found.joined(separator: ", "))
        }
        try expect(along == along.sorted(), "the sightings run backwards along the arc: " + found.joined(separator: ", "))
        try expect((along.first ?? .max) < Int(plan.duration * 60 * 0.75), "the icon was seen only at the end of its throw: " + found.joined(separator: ", "))
        app.note("on Arc's arc: " + found.joined(separator: ", "))
        try expect(seen.last.map { $0.at.x < link.x - 150 } ?? false, "the icon did not cross the page towards the Library button: \(seen.last!)")
        app.sleep(max(0, 2.6 - (ProcessInfo.processInfo.systemUptime - started)))
        let after = try picture(app, "LFF-after")
        try expect(icon(after, base: base, in: area.insetBy(dx: 4, dy: 4)) == nil, "the icon is still on the page 2.6 s after it started")
        app.passed("a real click on a download link throws the icon from the pointer up and across the page into the Library button, then it is gone")

        // Sidebar hidden: Arc's bin slides in at the bottom left corner and the icon lands on its corner.
        try app.dispatch(.sidebar(.toggle))
        try app.waitUntil("the sidebar hidden") { !(try app.view().sidebar.visible) }
        _ = try app.send(.load(window: app.window, url: app.site.url("flyout-flight.html?file=report.pdf")))
        try app.settle()
        app.sleep(0.8)
        let wide = try app.native().computed.contentArea
        let hiddenLink = CGPoint(x: wide.minX + wide.width * 0.5, y: wide.minY + wide.height * 0.5)
        let hiddenBase = try picture(app, "LFF-hidden-base")
        let binSpot = CGPoint(x: 40, y: height - 53), corner = CGRect(x: 50, y: height - 90, width: 40, height: 40)
        let thrown = try throwOne(app, link: hiddenLink)
        app.sleep(max(0, 0.35 - (ProcessInfo.processInfo.systemUptime - thrown)))
        let early = try picture(app, "LFF-bin")
        let fill = early.pixel(binSpot)
        try expect(abs(fill.r - 0xEB) < 12 && abs(fill.g - 0xEB) < 12 && abs(fill.b - 0xEB) < 12, "no bin (#EBEBEB) at the corner 0.35 s in: \(fill)")
        app.sleep(max(0, 2.0 - (ProcessInfo.processInfo.systemUptime - thrown)))
        let rest = try picture(app, "LFF-bin-rest")
        let resting = icon(rest, base: hiddenBase, in: corner)
        try expect(resting.map { hypot($0.x - 70, $0.y - (height - 70)) < 14 } ?? false, "the icon is not on the bin's corner (70, 70 from the bottom left) after 2 s: \(String(describing: resting))")
        app.passed("with the sidebar hidden the bin slides in at the bottom left corner and the icon comes to rest on its corner")
        app.sleep(max(0, 4.0 - (ProcessInfo.processInfo.systemUptime - thrown)))
        let gone = try picture(app, "LFF-bin-gone")
        let back = gone.pixel(binSpot), was = hiddenBase.pixel(binSpot)
        try expect(abs(back.r - was.r) + abs(back.g - was.g) + abs(back.b - was.b) < 12 && icon(gone, base: hiddenBase, in: corner) == nil,
                   "the bin or the icon is still there 4 s after the flight started: \(back) vs \(was)")
        try app.dispatch(.sidebar(.toggle))
        try app.waitUntil("the sidebar back") { try app.view().sidebar.visible }
        app.passed("a second after the landing the bin slides out, and the icon goes after it")
    }

    @Sendable static func running(_ app: AppUnderTest) throws {
        try prepare(app, ["notes.txt"])
        _ = try app.send(.load(window: app.window, url: app.site.url("download-slow?name=big-download.bin&bytes=3000000&seconds=14")))
        try app.waitUntil("the slow download receiving", timeout: 10) {
            try flyout(app).items.last.map { item in
                if case .download(let row) = item.content { row.state == .inProgress && row.received > 0 } else { false }
            } ?? false
        }
        _ = try jump(app, to: try page(app))
        app.sleep(1.5)
        try expect(try flyout(app).badge?.running == true, "the running download is not the badge")
        try expect(isShown(try app.native(), badge), "no disc on the button")
        try openList(app)
        let snapshot = try flyout(app)
        guard let item = snapshot.items.last, case .download(let download) = item.content else { throw Check(description: "no running row") }
        let cancel = ViewID.tabTool("library-flyout-cancel-\(download.id)")
        try expect(isShown(try app.native(), cancel), "the running row has no ×")
        app.sleep(1.2)
        try app.screenshot("LF-running-open")
        app.passed("the running download's row shows its ring, received/total and the ×")
        _ = try jump(app, to: try page(app))
        try closedSoon(app, "the list closed")
        app.sleep(0.3)
        try expect(try flyout(app).badge?.running == true, "opening the list put a running download's disc away (Arc keeps it)")
        app.passed("a running download keeps its disc after the list opened")
        try openList(app)
        let x = try visible(app.native(), cancel).frame
        try PhysicalPointer.click(app, at: try screen(app, centre(x)), window: app.window!)
        try app.waitUntil("the download cancelled", timeout: 8) {
            try flyout(app).items.contains { item in
                if case .download(let row) = item.content { row.id == download.id && (row.state == .cancelled || row.state == .cancelling) } else { false }
            }
        }
        app.passed("the real × cancels the download")
    }

    private static func XCTUnwrapFrame(_ rect: CGRect?) throws -> CGRect {
        guard let rect else { throw Check(description: "no sidebar frame") }
        return rect
    }
}
