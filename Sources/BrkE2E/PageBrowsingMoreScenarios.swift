import BrkBase
import BrkControl
import BrkDomain
import CoreGraphics
import Foundation

/// R3-7, continued: fullscreen gestures and interruptions, Edit menu services in web editors, popups, automatic
/// picture in picture, sound effects on the system output, and DevTools' element picker and input.
extension PageBrowsingScenarios {
    static let more = [
        Scenario("PB3", "fullscreen: window-server Ctrl+Cmd+F, Escape and the green button; toggles during the animation, a fullscreen page hidden or closed", cefOnly: "native fullscreen", fullscreen),
    ]

    /// Runs `script` from a real click on a button the page shows, so the page has user activation.
    static func clicked(_ app: AppUnderTest, _ page: PageID, _ script: String) throws {
        let encoded = String(decoding: try JSONEncoder().encode(script), as: UTF8.self)
        try app.evaluate(page, "(()=>{document.getElementById('pb-action')?.remove();let b=document.createElement('button');b.id='pb-action';b.textContent='Run';b.style='position:fixed;right:12px;bottom:12px;width:160px;height:50px;z-index:999999';b.onclick=()=>{(0,eval)(\(encoded))};document.body.append(b);document.title='pb action ready'})()")
        try app.waitUntil("action button") { try title(app, page) == "pb action ready" }
        guard let frame = try facts(app, page).surfaceFrame else { throw Check(description: "No native page frame") }
        _ = try app.send(.activate(window: page.window))
        try app.click(at: CGPoint(x: frame.maxX - 92, y: frame.maxY - 37))
    }
    static func settledFullscreen(_ app: AppUnderTest, _ window: WindowID? = nil, timeout: Double = 15) throws -> Bool {
        var result = false
        try app.waitUntil("fullscreen transition settles", timeout: timeout) {
            let n = try app.native(window)
            result = n.fullscreen
            return n.fullscreenTransitioning != true
        }
        app.sleep(0.3)
        return try app.native(window).fullscreen && result
    }

    // MARK: PB3 fullscreen

    @Sendable static func fullscreen(_ app: AppUnderTest) throws {
        var trace: [String: String] = [:]
        defer { try? record(app, "fullscreen", trace) }
        let page = try load(app, "key-coverage.html")

        // Window-server Ctrl+Cmd+F: page first (not consumed), then the app toggles; the same press again leaves.
        if WindowServerKeys.allowed {
            try WindowServerKeys.press(app, KeyChord([.control, .command], .f), window: page.window)
            try app.waitUntil("physical Ctrl+Cmd+F enters", timeout: 15) { try app.native().fullscreen && app.native().fullscreenTransitioning != true }
            try app.screenshot("physical-shortcut-entered")
            try WindowServerKeys.press(app, KeyChord([.control, .command], .f), window: page.window)
            try expect(try !settledFullscreen(app), "physical Ctrl+Cmd+F did not leave fullscreen")
            trace["physical-shortcut"] = "entered and left"

            // The green traffic light, clicked through the window server, enters; a physical Escape leaves. The
            // window first moves to the screen's top-left corner, clear of other processes' windows.
            let screen = CGDisplayBounds(CGMainDisplayID())
            let size = try app.native().windowFrame.size
            try app.setWindowFrame(CGRect(x: 0, y: screen.height - 40 - size.height, width: size.width, height: size.height))
            app.sleep(0.5)
            let n = try app.native()
            guard let zoom = n.actual["window-zoom-button"], !zoom.hidden else { throw Check(description: "no green button on screen") }
            let display = CGDisplayBounds(CGMainDisplayID())
            let point = CGPoint(x: n.windowFrame.minX + zoom.frame.midX, y: display.height - n.windowFrame.maxY + zoom.frame.midY)
            try PhysicalPointer.click(app, at: point, window: page.window)
            try app.waitUntil("green button enters fullscreen", timeout: 15) { try app.native().fullscreen && app.native().fullscreenTransitioning != true }
            try app.screenshot("green-button-entered")
            try WindowServerKeys.press(app, KeyChord([], .escape), window: page.window)
            try expect(try !settledFullscreen(app), "physical Escape did not leave green-button fullscreen")
            trace["green-button"] = "entered at \(point); Escape left"
            app.passed("window-server Ctrl+Cmd+F, green button and Escape")
        } else {
            app.note("Posting window-server events is not permitted for this runner; physical gestures not run.")
        }

        // A second toggle while AppKit animates the first is kept and applied when the animation ends.
        try app.waitForPageInput(page, at: app.site.url("key-coverage.html"))
        try app.dispatch(.app(.toggleFullScreen))
        try app.waitUntil("entry animation started") { try app.native().fullscreenTransitioning == true || app.native().fullscreen }
        try app.dispatch(.app(.toggleFullScreen))
        try expect(try !settledFullscreen(app, timeout: 20), "a toggle during the entry animation was lost (window stayed fullscreen)")
        try app.dispatch(.app(.toggleFullScreen))
        try expect(try settledFullscreen(app), "the next toggle after an interrupted entry did not enter")
        try app.dispatch(.app(.toggleFullScreen))
        try expect(try !settledFullscreen(app), "leaving after the interrupted entry failed")
        trace["toggle-during-animation"] = "second toggle applied after the animation"
        app.passed("toggle during the animation")

        // Document fullscreen, then the user switches tabs: the page leaves fullscreen and so does the window.
        let other = try load(app, "page2.html")
        let video = try load(app, "browser-basic.html?pb-fullscreen")
        try clicked(app, video, "document.onfullscreenchange=()=>document.title='fs:'+!!document.fullscreenElement;document.documentElement.requestFullscreen().catch(e=>document.title='fs-error:'+e.name)")
        try app.waitUntil("document fullscreen fills the window", timeout: 15) { try title(app, video) == "fs:true" && app.native().fullscreen && app.native().fullscreenTransitioning != true }
        try app.dispatch(.tab(.focus(other.item)))
        try expect(try !settledFullscreen(app), "switching away from a fullscreen page left the window fullscreen")
        try app.screenshot("switched-away-windowed")
        // A hidden document runs no rendering steps, so its fullscreenchange arrives once it is shown again.
        try app.dispatch(.tab(.focus(video.item)))
        try app.waitForPageInput(video, at: app.site.url("browser-basic.html?pb-fullscreen"))
        try app.waitUntil("the page left document fullscreen") { try title(app, video) == "fs:false" }
        try expect(try pageText(app, video, "String(!!document.fullscreenElement)") == "false" && !settledFullscreen(app),
                   "back on the page, it or the window is fullscreen again")
        trace["hidden-source"] = "tab switch: window and document left fullscreen; nothing re-entered on return"

        // Document fullscreen, then its tab closes.
        try clicked(app, video, "document.documentElement.requestFullscreen().catch(e=>document.title='fs-error:'+e.name)")
        try app.waitUntil("document fullscreen again", timeout: 15) { try title(app, video) == "fs:true" && app.native().fullscreen && app.native().fullscreenTransitioning != true }
        try app.dispatch(.tab(.close(.item(video.item))))
        try expect(try !settledFullscreen(app), "closing a fullscreen tab left the window fullscreen")
        trace["closed-source"] = "tab close: window left fullscreen"

        // Window fullscreen first, then document fullscreen and its exit: the window stays fullscreen.
        let again = try load(app, "browser-basic.html?pb-native-first")
        try app.dispatch(.app(.toggleFullScreen))
        try expect(try settledFullscreen(app), "window fullscreen did not enter")
        try clicked(app, again, "document.onfullscreenchange=()=>document.title='fs:'+!!document.fullscreenElement;document.documentElement.requestFullscreen()")
        try app.waitUntil("document fullscreen inside window fullscreen", timeout: 15) { try title(app, again) == "fs:true" }
        try app.evaluate(again, "document.exitFullscreen()")
        try app.waitUntil("document left fullscreen", timeout: 15) { try title(app, again) == "fs:false" }
        try expect(try settledFullscreen(app), "leaving document fullscreen also left the window fullscreen the user chose")
        try app.dispatch(.app(.toggleFullScreen))
        try expect(try !settledFullscreen(app), "final leave failed")
        trace["native-first"] = "document exit kept window fullscreen"
        app.passed("hidden, closed and nested fullscreen sources")
    }

    // MARK: PB4 Edit menu

    static func pageText(_ app: AppUnderTest, _ page: PageID, _ expression: String) throws -> String {
        let marker = "pbv" + String(UUID().uuidString.prefix(6))
        try app.evaluate(page, "document.title='\(marker):'+(\(expression))")
        var out = ""
        try app.waitUntil("page reported \(expression)") {
            guard let t = try title(app, page), t.hasPrefix(marker + ":") else { return false }
            out = String(t.dropFirst(marker.count + 1)); return true
        }
        return out
    }



    // MARK: PB5 popups


    // MARK: PB6 automatic picture in picture


    // MARK: PB6S sound output


    // MARK: PB7 Inspect Elements and DevTools input

}

/// Mouse clicks posted through the window server, only while this run's Brk window is key in the active app.
enum PhysicalPointer {
    /// The frontmost ordinary window (below the system overlay layers) containing `point`, as (pid, window number).
    static func frontmost(at point: CGPoint) -> (pid: Int32, number: Int)? {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer < 20, let bounds = info[kCGWindowBounds as String] as? [String: Double],
                  let pid = info[kCGWindowOwnerPID as String] as? Int32, let number = info[kCGWindowNumber as String] as? Int else { continue }
            let rect = CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
            if rect.contains(point), (info[kCGWindowAlpha as String] as? Double ?? 1) > 0 { return (pid, number) }
        }
        return nil
    }
    /// Refuses (throws) unless this run's Brk window is the frontmost window at the point, so a click never lands on
    /// another application's window or on another Brk process's always-on-top window.
    static func click(_ app: AppUnderTest, at point: CGPoint, window: WindowID) throws {
        try WindowServerKeys.ensureFrontmost(app, window)
        guard case .hello(let hello) = try app.send(.hello), let front = frontmost(at: point), front.pid == hello.pid else {
            throw Check(description: "another window is in front of Brk at \(point) (\(String(describing: frontmost(at: point)))); physical click not posted")
        }
        let source = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.mouseMoved, .leftMouseDown, .leftMouseUp] {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: .left) else { throw Check(description: "mouse event") }
            event.post(tap: .cghidEventTap)
            usleep(type == .mouseMoved ? 150_000 : 60_000)
        }
    }

    private static func post(_ type: CGEventType, at point: CGPoint, clickCount: Int64 = 1) throws {
        guard let event = CGEvent(mouseEventSource: CGEventSource(stateID: .hidSystemState), mouseType: type, mouseCursorPosition: point, mouseButton: .left) else {
            throw Check(description: "mouse event")
        }
        event.setIntegerValueField(.mouseEventClickState, value: clickCount)
        event.post(tap: .cghidEventTap)
    }

    /// `point` in the window's content coordinates (top-left origin) on the screen.
    private static func screen(_ app: AppUnderTest, _ point: CGPoint, window: WindowID) throws -> CGPoint {
        let frame = try app.native(window).windowFrame
        return CGPoint(x: frame.minX + point.x, y: CGDisplayBounds(CGMainDisplayID()).height - frame.maxY + point.y)
    }

    /// Refuses (throws) unless this run's Brk is the frontmost window at the point, like `click`.
    private static func checkFront(_ app: AppUnderTest, at point: CGPoint, window: WindowID) throws {
        try WindowServerKeys.ensureFrontmost(app, window)
        guard case .hello(let hello) = try app.send(.hello), let front = frontmost(at: point), front.pid == hello.pid else {
            throw Check(description: "another window is in front of Brk at \(point); real mouse events not posted")
        }
    }

    /// The real pointer moved to `point` (window content coordinates), gliding as a person's does: tracking areas answer.
    static func move(_ app: AppUnderTest, to point: CGPoint, window: WindowID) throws {
        let at = try screen(app, point, window: window)
        try checkFront(app, at: at, window: window)
        let from = CGEvent(source: nil)?.location ?? at
        for step in 1...12 {
            let t = Double(step) / 12
            try post(.mouseMoved, at: CGPoint(x: from.x + (at.x - from.x) * t, y: from.y + (at.y - from.y) * t))
            usleep(10_000)
        }
        usleep(120_000)
    }

    /// Real wheel lines at `point`; negative scrolls the content up, as a finger moving up does.
    static func scroll(_ app: AppUnderTest, lines: Int32, at point: CGPoint, window: WindowID) throws {
        try move(app, to: point, window: window)
        for _ in 0..<8 {
            CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap)
            usleep(30_000)
        }
        usleep(300_000)
    }

    /// A press with the button held while `held` runs. `point` in window content coordinates.
    static func press(_ app: AppUnderTest, at point: CGPoint, window: WindowID, held: () throws -> Void) throws {
        let at = try screen(app, point, window: window)
        try checkFront(app, at: at, window: window)
        try post(.mouseMoved, at: at); usleep(150_000)
        try post(.leftMouseDown, at: at); usleep(100_000)
        defer { try? post(.leftMouseUp, at: at); usleep(100_000) }
        try held()
    }

    static func doubleClick(_ app: AppUnderTest, at point: CGPoint, window: WindowID) throws {
        let at = try screen(app, point, window: window)
        try checkFront(app, at: at, window: window)
        try post(.mouseMoved, at: at); usleep(150_000)
        for count: Int64 in [1, 2] {
            try post(.leftMouseDown, at: at, clickCount: count); usleep(30_000)
            try post(.leftMouseUp, at: at, clickCount: count); usleep(30_000)
        }
    }

    /// A real drag: press at the first point (window content coordinates), glide through the rest with the button down,
    /// run `held` at the last and release there.
    /// A two-finger trackpad scroll posted to the window server at `point`: `began` (with no travel unless `first`
    /// says, a real gesture's often has some), one `changed` event per step (points, as `scrollingDeltaX/Y` read them), `held`
    /// with the fingers down, the `then` steps, a `pause` with the fingers still, `ended`, then optional inertia events. These
    /// take the real path into the app (window server, the window's `sendEvent`, the view under the pointer); events
    /// injected in-process do not, and a scroll view that tracks a whole gesture by itself only shows up here.
    static func swipe(_ app: AppUnderTest, at point: CGPoint, first: (Double, Double) = (0, 0), steps: [(Double, Double)], held: (() throws -> Void)? = nil,
                      then: [(Double, Double)] = [], pause: Double = 0, inertia: [(Double, Double)] = [], window: WindowID) throws {
        let at = try screen(app, point, window: window)
        try checkFront(app, at: at, window: window)
        try post(.mouseMoved, at: at); usleep(250_000)
        let source = CGEventSource(stateID: .hidSystemState)
        func scroll(_ dx: Double, _ dy: Double, phase: Int64, momentum: Int64) throws {
            guard let event = CGEvent(scrollWheelEvent2Source: source, units: .pixel, wheelCount: 2, wheel1: Int32(dy), wheel2: Int32(dx), wheel3: 0) else {
                throw Check(description: "scroll event")
            }
            event.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
            event.setIntegerValueField(.scrollWheelEventMomentumPhase, value: momentum)
            event.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
            event.location = at
            event.post(tap: .cghidEventTap)
            usleep(16_000)
        }
        try scroll(first.0, first.1, phase: 1, momentum: 0)
        for step in steps { try scroll(step.0, step.1, phase: 2, momentum: 0) }
        var failure: (any Error)?
        if let held {
            usleep(100_000)
            do { try held() } catch { failure = error }
        }
        for step in then { try scroll(step.0, step.1, phase: 2, momentum: 0) }
        if pause > 0 { usleep(UInt32(pause * 1_000_000)) }
        try scroll(0, 0, phase: 4, momentum: 0)
        for (n, step) in inertia.enumerated() { try scroll(step.0, step.1, phase: 0, momentum: n == 0 ? 1 : 2) }
        if !inertia.isEmpty { try scroll(0, 0, phase: 0, momentum: 3) }
        usleep(400_000)
        if let failure { throw failure }
    }

    static func drag(_ app: AppUnderTest, through path: [CGPoint], window: WindowID, held: () throws -> Void) throws {
        guard let first = path.first else { return }
        let start = try screen(app, first, window: window)
        try checkFront(app, at: start, window: window)
        try post(.mouseMoved, at: start); usleep(150_000)
        try post(.leftMouseDown, at: start); usleep(120_000)
        var current = start
        defer { try? post(.leftMouseUp, at: current); usleep(200_000) }
        for point in path.dropFirst() {
            let next = try screen(app, point, window: window), from = current
            for step in 1...24 {
                let t = Double(step) / 24, eased = t * t * (3 - 2 * t)
                current = CGPoint(x: from.x + (next.x - from.x) * eased, y: from.y + (next.y - from.y) * eased)
                try post(.leftMouseDragged, at: current)
                usleep(10_000)
            }
            current = next
        }
        usleep(150_000)
        try held()
    }
}
