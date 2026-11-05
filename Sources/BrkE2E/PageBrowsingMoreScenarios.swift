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
        Scenario("PB4", "Edit menu in web editors: spelling panel, Check Document Now, grammar, spell check while typing, substitutions, speech, Bold/Italic/Underline", cefOnly: "web editing", editMenu),
        Scenario("PB5", "popups keep opener and requested geometry; their dialogs sheet on the popup and their downloads reach the owner's Downloads", cefOnly: "CEF popups", popups),
        Scenario("PB6", "automatic picture in picture after the page's user activation expired, and back on return", cefOnly: "embedded PiP", automaticPiP),
        Scenario("PB6S", "sound effects recorded from Brk's own system audio output when on, silence when off", cefOnly: "signed sound resources", soundOutput),
        Scenario("PB7", "Inspect Elements: DevTools element picker selects the clicked node; typing in the DevTools console reaches the page", cefOnly: "native developer windows", inspectPicker),
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
    static func services(_ app: AppUnderTest, _ page: PageID) throws -> [String] { try facts(app, page).textServices ?? [] }
    static func waitService(_ app: AppUnderTest, _ page: PageID, _ entry: String, timeout: Double = 8) throws {
        try app.waitUntil("text service \(entry)", timeout: timeout) { try services(app, page).contains(entry) }
    }
    static func richReady(_ app: AppUnderTest, _ page: PageID, _ text: String, select: (Int, Int)? = nil) throws {
        let encoded = String(decoding: try JSONEncoder().encode(text), as: UTF8.self)
        let selection = select.map { "r.setStart(t,\($0.0));r.setEnd(t,\($0.1))" } ?? "r.setStart(t,0);r.collapse(true)"
        try app.evaluate(page, "(()=>{const e=document.getElementById('rich');e.textContent=\(encoded);e.focus();const t=e.firstChild,r=document.createRange();\(selection);getSelection().removeAllRanges();getSelection().addRange(r);document.title='rich-ready'})()")
        try app.waitUntil("rich editor ready") { try title(app, page) == "rich-ready" }
    }

    @Sendable static func editMenu(_ app: AppUnderTest) throws {
        let page = try load(app, "page-browsing.html")
        defer { try? record(app, "text-services", (try? services(app, page)) ?? []) }

        // Check Document Now finds the first misspelling and selects it; the spelling panel's Change replaces it.
        try richReady(app, page, "Thiss is a sentense about grammar.")
        try app.perform(.menuAction("Check Document Now"))
        try waitService(app, page, "spelling:Thiss")
        try expect(try pageText(app, page, "getSelection().toString()") == "Thiss", "Check Document Now did not select the misspelling")
        try app.perform(.menuAction("Show Spelling and Grammar"))
        try waitService(app, page, "spelling:sentense")
        try waitService(app, page, "panel:spelling")
        try app.recordWindows("spelling-panel")
        try app.perform(.sendAction(selector: "changeSpelling:", text: "sentence"))
        try app.waitUntil("Change replaced the word") { try pageText(app, page, "rich.textContent") == "Thiss is a sentence about grammar." }
        try app.perform(.sendAction(selector: "ignoreSpelling:", text: "Thiss"))
        try waitService(app, page, "ignore:Thiss")
        try richReady(app, page, "Thiss is a sentence about grammar.")
        try app.perform(.menuAction("Check Document Now"))
        try waitService(app, page, "spelling:none")
        app.passed("spelling: next misspelling, panel, Change and Ignore")

        // Check Grammar With Spelling: Check Document Now stops on the grammar issue.
        try app.perform(.menuAction("Check Grammar With Spelling"))
        try waitService(app, page, "grammar-checking:true")
        try richReady(app, page, "I has a apple.")
        try app.perform(.menuAction("Check Document Now"))
        try waitService(app, page, "grammar:has")
        try app.perform(.menuAction("Check Grammar With Spelling"))
        try waitService(app, page, "grammar-checking:false")

        // Check Spelling While Typing: Chromium's own red underline appears and disappears with it.
        try richReady(app, page, "wrongg speling everywheer", select: (25, 25))
        try app.type(" ")
        app.sleep(1.5)
        let marks = try spellingMarks(app, page)
        try app.perform(.menuAction("Check Spelling While Typing"))
        try waitService(app, page, "spellcheck:false")
        app.sleep(1.2)
        let cleared = try spellingMarks(app, page)
        try app.perform(.menuAction("Check Spelling While Typing"))
        try waitService(app, page, "spellcheck:true")
        try record(app, "spelling-marks", ["on": marks, "off": cleared])
        try expect(marks > 6 && cleared <= marks / 4, "spell check while typing did not control the underlines (on \(marks), off \(cleared) red pixels)")
        app.passed("grammar and spell checking while typing")

        // Substitutions panel Replace: enabled smart quotes, dashes and text replacement apply in the editor.
        try app.perform(.menuAction("Show Substitutions"))
        try waitService(app, page, "panel:substitutions")
        try richReady(app, page, "She said \"hello\" -- twice")
        try app.perform(.sendAction(selector: "checkTextInDocument:", text: nil))
        try app.waitUntil("substitutions applied") { try pageText(app, page, "rich.textContent") == "She said \u{201C}hello\u{201D} \u{2014} twice" }
        try app.perform(.menuAction("Smart Quotes"))
        try waitService(app, page, "quotes:false")
        try richReady(app, page, "Plain \"quotes\" -- stay")
        try app.perform(.sendAction(selector: "checkTextInDocument:", text: nil))
        try app.waitUntil("only dashes applied") { try pageText(app, page, "rich.textContent") == "Plain \"quotes\" \u{2014} stay" }
        try app.perform(.menuAction("Smart Quotes"))
        try waitService(app, page, "quotes:true")
        app.passed("substitutions follow their toggles")

        // Speech speaks the selection.
        try richReady(app, page, "Speak only this part, not the rest.", select: (0, 20))
        try app.perform(.menuAction("Start Speaking"))
        try waitService(app, page, "speak:true:Speak only this part")
        try app.perform(.menuAction("Stop Speaking"))
        try waitService(app, page, "speak-stop")

        // Bold, Italic (NSFontManager) and Underline on the selection.
        for (item, tag) in [("Bold", "b"), ("Italic", "i"), ("Underline", "u")] {
            try richReady(app, page, "format me", select: (0, 6))
            try app.perform(.menuAction(item))
            try app.waitUntil("\(item) applied") { try pageText(app, page, "rich.innerHTML").contains("<\(tag)>format</\(tag)>") }
        }
        try app.screenshot("formatted")
        app.passed("speech and Bold, Italic, Underline")
    }

    /// Red pixels of Chromium's misspelling underline under the rich editor's text, from one window capture.
    static func spellingMarks(_ app: AppUnderTest, _ page: PageID) throws -> Int {
        let rect = try pageText(app, page, "(()=>{const r=rich.getBoundingClientRect();return [r.left,r.top,r.width,r.height].map(Math.round).join(',')})()").split(separator: ",").compactMap { Double($0) }
        guard rect.count == 4, let surface = try facts(app, page).surfaceFrame else { throw Check(description: "editor frame unknown") }
        let shot = try app.screenshot("spelling-\(UUID().uuidString.prefix(4))")
        guard let provider = CGDataProvider(url: shot.url as CFURL),
              let image = CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { throw Check(description: "unreadable capture") }
        let scale = Double(image.width) / (try app.native().contentSize.width)
        let width = image.width, height = image.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                                      space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw Check(description: "no bitmap") }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        let x0 = Int((surface.minX + rect[0]) * scale), x1 = Int((surface.minX + rect[0] + rect[2]) * scale)
        let y0 = Int((surface.minY + rect[1]) * scale), y1 = Int((surface.minY + rect[1] + rect[3]) * scale)
        var red = 0
        for y in max(0, y0)..<min(height, y1) { for x in max(0, x0)..<min(width, x1) {
            let i = (y * width + x) * 4
            if pixels[i] > 170, pixels[i + 1] < 110, pixels[i + 2] < 110 { red += 1 }
        } }
        return red
    }

    // MARK: PB5 popups

    @Sendable static func popups(_ app: AppUnderTest) throws {
        let page = try load(app, "page-browsing.html")
        defer { try? record(app, "popup-facts", facts(app, page)) }
        let downloads = app.dataDirectory.appendingPathComponent("popup-downloads")
        try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
        try app.dispatch(.settings(.profile(.default, .downloadsDirectory(downloads.path))))
        try app.dispatch(.settings(.profile(.default, .promptForDownloadLocation(false))))

        // An anonymous popup with features from the page in front: its own window, opener and geometry kept.
        try clicked(app, page, "window.child=window.open('popup-child.html','','popup,left=240,top=180,width=520,height=380')")
        var report: [String: Any] = [:]
        try app.waitUntil("popup reported to its opener", timeout: 12) {
            guard let t = try title(app, page), t.hasPrefix("popup:") else { return false }
            report = (try? JSONSerialization.jsonObject(with: Data(t.dropFirst(6).utf8))) as? [String: Any] ?? [:]
            return !report.isEmpty
        }
        try record(app, "popup-geometry", report.mapValues { "\($0)" })
        try expect(report["opener"] as? Bool == true, "popup lost window.opener: \(report)")
        let iw = report["iw"] as? Double ?? 0, ih = report["ih"] as? Double ?? 0, sx = report["sx"] as? Double ?? -1, sy = report["sy"] as? Double ?? -1
        try expect(abs(iw - 520) <= 2 && abs(ih - 380) <= 2, "popup content size \(iw)x\(ih), requested 520x380")
        try expect(abs(sx - 240) <= 40 && abs(sy - 180) <= 60, "popup position \(sx),\(sy), requested 240,180")
        guard let popupWindow = try facts(app, page).auxiliaryWindows?.first else { throw Check(description: "popup is not a native window of the page") }
        try expect(allTabs(try app.view()).count == 2, "the popup also became a tab")
        _ = try app.send(.mediaWindowScreenshot(number: popupWindow, path: app.shotsDirectory.appendingPathComponent("PB5-popup-window.png").path))
        app.passed("popup window, opener and geometry")

        // Its alert and confirm become sheets on the popup window; the answer reaches the script.
        try app.evaluate(page, "setTimeout(()=>{child.alert('Hello from the popup');document.title='alert-closed'},0)")
        try app.waitUntil("alert sheet on the popup") { (try facts(app, page).auxiliaryEvents ?? []).contains { $0.hasPrefix("dialog:alert:\(popupWindow):") } }
        _ = try app.send(.mediaWindowScreenshot(number: popupWindow, path: app.shotsDirectory.appendingPathComponent("PB5-popup-alert.png").path))
        try app.perform(.windowSheetButton(number: popupWindow, title: "OK"))
        try app.waitUntil("alert answered") { try title(app, page) == "alert-closed" }
        try app.evaluate(page, "setTimeout(()=>{const r=child.confirm('Keep going?');document.title='confirm:'+r},0)")
        try app.waitUntil("confirm sheet on the popup") { (try facts(app, page).auxiliaryEvents ?? []).contains { $0.hasPrefix("dialog:confirm:\(popupWindow):") } }
        try app.perform(.windowSheetButton(number: popupWindow, title: "Cancel"))
        try app.waitUntil("confirm answered Cancel") { try title(app, page) == "confirm:false" }
        app.passed("popup dialogs as sheets on the popup")

        // A download the popup starts is the owner's: it lands in the owner's downloads folder and Library.
        try app.evaluate(page, "child.location.href='/download?pb-popup'")
        try app.waitUntil("popup download forwarded") { (try facts(app, page).auxiliaryEvents ?? []).contains { $0.hasPrefix("download:") } }
        try app.waitUntil("popup download bytes on disk", timeout: 15) {
            (try? FileManager.default.contentsOfDirectory(atPath: downloads.path))?.contains { $0.hasPrefix("fixture") } == true
        }
        try app.dispatch(.library(.open(.downloads)))
        try app.waitUntil("download row in the owner's Library") { if case .library(let l)? = try app.view().overlay { !l.downloads.isEmpty } else { false } }
        try app.screenshot("popup-download-in-library")
        try app.dispatch(.library(.close))
        app.passed("popup download forwarded to the owner")

        let windows = Set(try facts(app, page).auxiliaryWindows ?? [])
        try app.dispatch(.tab(.close(.item(page.item))))
        try app.waitUntil("popup closes with its owner") { windows.isDisjoint(with: Set(try app.native().appWindows.filter(\.isVisible).map(\.number))) }
    }

    // MARK: PB6 automatic picture in picture

    @Sendable static func automaticPiP(_ app: AppUnderTest) throws {
        try app.dispatch(.settings(.advanced(.autoPictureInPicture(true))))
        let url = app.site.url("capture-media.html")
        let item = try app.load(url), page = PageID(window: app.window!, item: item)
        try app.waitForPageInput(page, at: url)
        try app.waitUntil("video plays") { try tab(item, in: app.view())?.mediaPlayers.contains { $0.kind == .video && !$0.paused } == true }
        let other = try load(app, "page2.html")
        try app.dispatch(.tab(.focus(item)))
        // Scripts the harness runs count as user activation, so the page reports its own state on a timer; no input
        // reaches it from here on and its transient activation (5 s in Chromium) expires.
        try app.evaluate(page, "setInterval(()=>{document.title='ua:'+navigator.userActivation.isActive},200)")
        app.sleep(6.5)
        try app.waitUntil("page reports no user activation", timeout: 10) { try title(app, page) == "ua:false" }
        try app.dispatch(.tab(.focus(other.item)))
        try app.waitUntil("automatic PiP after activation expired", timeout: 10) {
            guard let row = try tab(item, in: app.view()) else { return false }
            if let error = row.mediaError { throw Check(description: "automatic PiP failed: \(error)") }
            return row.mediaPlayers.contains { $0.pictureInPicture }
        }
        try app.recordWindows("auto-pip-open")
        try app.dispatch(.tab(.focus(item)))
        try app.waitUntil("PiP returns to the tab") { try tab(item, in: app.view())?.mediaPlayers.contains { $0.pictureInPicture } == false }
        try app.dispatch(.settings(.advanced(.autoPictureInPicture(false))))
        try app.dispatch(.tab(.focus(other.item)))
        for _ in 0..<10 { try expect(try tab(item, in: app.view())?.mediaPlayers.contains { $0.pictureInPicture } == false, "PiP entered with the setting off"); app.sleep(0.1) }
        app.note("Automatic entry ran after the page itself reported navigator.userActivation.isActive false (6.5 s after the last script the harness ran in it).")
    }

    // MARK: PB6S sound output

    @Sendable static func soundOutput(_ app: AppUnderTest) throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let source = root.appendingPathComponent("verify/completion/browser-basic-parent/round3-page-browsing/tools/record-app-audio.swift")
        let tool = app.dataDirectory.appendingPathComponent("record-app-audio")
        let compile = Process()
        compile.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        compile.arguments = ["swiftc", "-O", "-o", tool.path, source.path]
        try compile.run(); compile.waitUntilExit()
        try expect(compile.terminationStatus == 0, "recorder did not compile")
        guard case .hello(let hello) = try app.send(.hello) else { throw Check(description: "hello") }
        try app.dispatch(.settings(.advanced(.soundEffects(true))))
        let a = try load(app, "page2.html"), b = try load(app, "red.html")
        let wav = app.shotsDirectory.deletingLastPathComponent().appendingPathComponent("PB6S-brk-output.wav")
        let json = app.shotsDirectory.deletingLastPathComponent().appendingPathComponent("PB6S-brk-output.json")
        let recorder = Process(), out = Pipe()
        recorder.executableURL = tool
        recorder.arguments = [String(hello.pid), "9", wav.path, json.path]
        recorder.standardOutput = out
        try recorder.run()
        var ready = false
        let deadline = uptime() + 15
        var buffer = Data()
        while uptime() < deadline, !ready {
            let chunk = out.fileHandleForReading.availableData
            if chunk.isEmpty { if !recorder.isRunning { break }; app.sleep(0.05); continue }
            buffer += chunk
            ready = String(decoding: buffer, as: UTF8.self).contains("ready")
        }
        try expect(ready, "recorder did not start: \(String(decoding: buffer, as: UTF8.self))")
        app.sleep(1)
        let onAt = uptime()
        try app.dispatch(.tab(.close(.item(a.item))))                       // archives: Brk's archive cue
        app.sleep(2)
        try app.dispatch(.settings(.advanced(.soundEffects(false))))
        app.sleep(0.5)
        let offAt = uptime()
        try app.dispatch(.tab(.close(.item(b.item))))                       // archives again, sound effects off
        app.sleep(2)
        recorder.waitUntilExit()
        try expect(recorder.terminationStatus == 0, "recorder failed: \(String(decoding: buffer + out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self))")
        let summary = try JSONSerialization.jsonObject(with: Data(contentsOf: json)) as? [String: Any] ?? [:]
        let trace = (summary["trace"] as? [[String: Double]]) ?? []
        func loudest(_ from: Double, _ to: Double) -> Double { trace.filter { ($0["t"] ?? 0) >= from && ($0["t"] ?? 0) < to }.map { $0["rms"] ?? 0 }.max() ?? 0 }
        let before = loudest(onAt - 1, onAt), on = loudest(onAt, onAt + 1.5), off = loudest(offAt, offAt + 1.5)
        try record(app, "levels", ["quietBefore": before, "cueOn": on, "cueOff": off, "frames": summary["frames"] as? Double ?? 0])
        try expect(!trace.isEmpty, "no audio buffers were recorded")
        try expect(on > 0.003 && on > before * 10, "the archive cue was not heard on Brk's output (rms \(on), before \(before))")
        try expect(off < 0.0005, "sound effects off still produced output (rms \(off))")
        app.note("Recorded Brk's own audio through ScreenCaptureKit: archive cue rms \(String(format: "%.4f", on)) with sound effects on, \(String(format: "%.5f", off)) off. WAV in PB6S-brk-output.wav.")
    }

    // MARK: PB7 Inspect Elements and DevTools input

    @Sendable static func inspectPicker(_ app: AppUnderTest) throws {
        let page = try load(app, "page-browsing.html")
        defer { try? record(app, "developer", facts(app, page)) }
        try app.perform(.menuAction("Inspect Elements"))
        try app.waitUntil("DevTools element picker on", timeout: 20) { try facts(app, page).developerResult == "inspect mode" }
        try app.recordWindows("picker-on")
        let rect = try pageText(app, page, "(()=>{const r=document.getElementById('target-b').getBoundingClientRect();return [r.left+r.width/2,r.top+r.height/2].map(Math.round).join(',')})()")
            .split(separator: ",").compactMap { Double($0) }
        guard rect.count == 2, let surface = try facts(app, page).surfaceFrame else { throw Check(description: "target frame unknown") }
        _ = try app.send(.activate(window: page.window))
        try app.hover(CGPoint(x: surface.minX + rect[0], y: surface.minY + rect[1]))
        try app.evaluate(page, "document.getElementById('target-b').onclick=()=>document.title='target clicked'")
        let before = try title(app, page)
        try app.click(at: CGPoint(x: surface.minX + rect[0], y: surface.minY + rect[1]))
        try app.waitUntil("picker selected the clicked node", timeout: 15) { (try facts(app, page).developerResult ?? "").contains("target-b") }
        try expect(try title(app, page) == before, "the picking click also reached the page's click handler")
        app.passed("element picker selected #target-b from a click in the page")

        // Input in the auxiliary DevTools window: the console evaluates what is typed there in the inspected page.
        _ = try app.send(.dispatch(window: page.window, command: .page(.developer(.console))))
        try app.waitUntil("console panel", timeout: 12) { try facts(app, page).developerResult == "console selected" }
        guard let tools = try facts(app, page).auxiliaryWindows?.first else { throw Check(description: "no DevTools window") }
        try app.perform(.focusAppWindow(number: tools))
        app.sleep(0.5)
        try app.type("document.title='typed-in-devtools'")
        try app.press("return")
        try app.waitUntil("console input evaluated in the page") { try title(app, page) == "typed-in-devtools" }
        _ = try app.send(.mediaWindowScreenshot(number: tools, path: app.shotsDirectory.appendingPathComponent("PB7-devtools-console.png").path))
        app.passed("typing in the DevTools window reached its console")
    }
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
    /// A two-finger trackpad scroll posted to the window server at `point`: `began` with no travel, one `changed`
    /// event per step (points, as `scrollingDeltaX/Y` read them), `ended`, then optional inertia events. These take
    /// the real path into the app (window server, the window's `sendEvent`, the view under the pointer); events
    /// injected in-process do not, and a scroll view that tracks a whole gesture by itself only shows up here.
    static func swipe(_ app: AppUnderTest, at point: CGPoint, steps: [(Double, Double)], inertia: [(Double, Double)] = [], window: WindowID) throws {
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
        try scroll(0, 0, phase: 1, momentum: 0)
        for step in steps { try scroll(step.0, step.1, phase: 2, momentum: 0) }
        try scroll(0, 0, phase: 4, momentum: 0)
        for (n, step) in inertia.enumerated() { try scroll(step.0, step.1, phase: 0, momentum: n == 0 ? 1 : 2) }
        if !inertia.isEmpty { try scroll(0, 0, phase: 0, momentum: 3) }
        usleep(400_000)
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
