import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation
import ImageIO
import Vision

/// Slice B2's local models through the entry points a person uses, on a real launch with real keys and clicks at the
/// window server; the control socket only reads state and takes screenshots. The models are the ones downloaded on this
/// Mac (~/.cache/brk-models), cloned into the run's data folder before launch, so the On This Mac card shows them
/// downloaded.
///
/// - `AIRealLocal-none`: no agent on this Mac (the instance searches no folder for one) and no key. Tidy groups by the
///   search model, Place New Tabs and the duplicate question go to JevK5, the command bar and History find a page by
///   meaning.
/// - `AIRealLocal-claude`: Claude Code on its small model. Tidy and Place New Tabs go to the text model, the duplicate
///   question still to JevK5, the page check flags a page the phrase patterns miss by JevK5, and @ in the panel finds a
///   tab by meaning.
///
/// Opt-in: BRK_E2E_REAL_LOCAL=1 (JevK5 holds 3.2 GB while loaded; the Claude run spends about ten small-model requests
/// and one tab-session turn). BRK_E2E_REAL_LOCAL_PART=tidy,place,duplicates,bar,history,check,mention picks steps.
/// Results: real-local-<agent>.txt in the shots folder.
enum AIRealLocalScenarios {
    static var all: [Scenario] {
        guard ProcessInfo.processInfo.environment["BRK_E2E_REAL_LOCAL"] == "1" else { return [] }
        return [Scenario("AIRealLocal-none", "no agent and no key, the local models downloaded: Tidy, Place New Tabs, duplicates, search by meaning in the bar and History",
                         cefOnly: "local models, real input") { try route($0, agent: nil) }]
    }

    /// The downloaded models, cloned (APFS: no copy of the gigabytes) into the store layout under the data folder.
    static func cloneModels(into dataDirectory: URL) throws {
        let cache = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".cache/brk-models")
        let models: [(id: String, folder: String, file: String, sha256: String)] = [
            ("embeddinggemma-2-q8", "embeddinggemma-2-gguf", "embeddinggemma-2-Q8_0.gguf", "2188ac1deca4b77dffefd603c2776a9d76d9d74ec01841392982ebb840b09135"),
            ("jevk5-4b-v0.3-q4", "jevk5-gguf", "jevk5-4b-v0.3-Q4_K_M.gguf", "94ca0d7745c47f79091b0892ca657c81d9dc9e4ed0238ba0a7ea261d8938c882"),
        ]
        for model in models {
            let source = cache.appendingPathComponent(model.folder).appendingPathComponent(model.file)
            guard FileManager.default.fileExists(atPath: source.path) else { throw Check(description: "no \(source.path); download the models first (verify/ai-native/b-local-models)") }
            let folder = dataDirectory.appendingPathComponent("Local Models", isDirectory: true).appendingPathComponent(model.id, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let target = folder.appendingPathComponent(model.file)
            if !FileManager.default.fileExists(atPath: target.path) { try FileManager.default.copyItem(at: source, to: target) }
            try Data(model.sha256.utf8).write(to: folder.appendingPathComponent(model.file + ".sha256"))
        }
    }

    private final class Log {
        let url: URL
        var failures = 0
        init(_ url: URL) { self.url = url; try? Data().write(to: url) }
        func write(_ line: String) {
            print("[real-local] " + line)
            if let handle = try? FileHandle(forWritingTo: url) { handle.seekToEndOfFile(); handle.write(Data((line + "\n").utf8)); try? handle.close() }
        }
        func check(_ name: String, _ body: () throws -> String) {
            let start = Date()
            func seconds() -> String { String(format: "%.1f", Date().timeIntervalSince(start)) }
            do { let result = try body(); write("PASS \(name) (\(seconds()) s, load \(load())): \(result)") }
            catch { failures += 1; write("FAIL \(name) (\(seconds()) s, load \(load())): \(error)") }
        }
    }

    static func load() -> String {
        var loads = [Double](repeating: 0, count: 3)
        guard getloadavg(&loads, 3) == 3 else { return "?" }
        return loads.map { String(format: "%.1f", $0) }.joined(separator: " ")
    }

    // MARK: Real input (the window-server events the other real-route scenarios post)

    nonisolated(unsafe) private static var pid: Int32 = 0
    nonisolated(unsafe) private static weak var app: AppUnderTest?

    private static let codes: [Character: (CGKeyCode, Bool)] = {
        var map: [Character: (CGKeyCode, Bool)] = [" ": (49, false), ":": (41, true), ";": (41, false), "-": (27, false), "_": (27, true), ".": (47, false), ",": (43, false),
                                                   "/": (44, false), "?": (44, true), "'": (39, false), "=": (24, false), "&": (26, true), "@": (19, true)]
        for (letter, code) in zip("asdfhgzxcvbqwerytuiopnmljk", [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 11, 12, 13, 14, 15, 16, 17, 32, 34, 31, 35, 45, 46, 37, 38, 40] as [CGKeyCode]) {
            map[letter] = (code, false); map[Character(letter.uppercased())] = (code, true)
        }
        for (digit, code) in zip("1234567890", [18, 19, 20, 21, 23, 22, 26, 28, 25, 29] as [CGKeyCode]) { map[digit] = (code, false) }
        return map
    }()

    private static func brkActive() throws {
        guard case .native(let facts) = try? app?.send(.native(window: nil)), facts.appActive == true else { throw Check(description: "Brk is not the active app; no key posted") }
    }
    private static func type(_ text: String) throws {
        try brkActive()
        let source = CGEventSource(stateID: .hidSystemState)
        func post(_ code: CGKeyCode, _ down: Bool, _ flags: CGEventFlags) {
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return }
            event.flags = flags; event.post(tap: .cghidEventTap); usleep(14_000)
        }
        for character in text {
            guard let (code, shifted) = codes[character] else { throw Check(description: "no key for \(character)") }
            if shifted { post(56, true, .maskShift) }
            post(code, true, shifted ? .maskShift : []); post(code, false, shifted ? .maskShift : [])
            if shifted { post(56, false, []) }
            usleep(18_000)
        }
    }
    private static func key(_ modifiers: Modifiers, _ key: Key) throws {
        try brkActive()
        try NativeSystemInput.postSystemWide(KeyChord(modifiers, key))
        usleep(250_000)
    }
    private static func mouse(_ point: CGPoint, _ types: [CGEventType], button: CGMouseButton = .left) throws {
        guard let front = PhysicalPointer.frontmost(at: point), front.pid == pid else { throw Check(description: "another window is in front at \(point); nothing posted") }
        let source = CGEventSource(stateID: .hidSystemState)
        for type in types {
            guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: point, mouseButton: button) else { throw Check(description: "mouse event") }
            event.post(tap: .cghidEventTap)
            usleep(type == .mouseMoved ? 150_000 : 60_000)
        }
        usleep(300_000)
    }
    private static func click(_ point: CGPoint) throws { try mouse(point, [.mouseMoved, .leftMouseDown, .leftMouseUp]) }
    private static func rightClick(_ point: CGPoint) throws { try mouse(point, [.mouseMoved, .rightMouseDown, .rightMouseUp], button: .right) }
    private static func screen(_ app: AppUnderTest, _ frame: CGRect) throws -> CGPoint {
        let facts = try app.native()
        let top = CGDisplayBounds(CGMainDisplayID()).height - facts.windowFrame.maxY
        return CGPoint(x: facts.windowFrame.minX + frame.midX, y: top + frame.midY)
    }
    private static func click(_ app: AppUnderTest, _ view: ViewID) throws {
        try WindowServerKeys.ensureFrontmost(app, app.window!)
        try click(try screen(app, try visible(app.native(), view).frame))
    }
    private static func hover(_ app: AppUnderTest, _ view: ViewID) throws {
        let f = try visible(app.native(), view).frame
        try PhysicalPointer.move(app, to: CGPoint(x: f.midX, y: f.midY), window: app.window!)
        app.sleep(0.8)
    }
    private static func click(identifier: String? = nil, title: String? = nil, roles: [String] = [], _ what: String, timeout: Double = 8) throws {
        var found: CGRect?
        try app!.waitUntil("\(what) on screen", timeout: timeout) { found = NativeSystemInput.frame(pid: pid, identifier: identifier, title: title, roles: roles); return found != nil }
        try click(CGPoint(x: found!.midX, y: found!.midY))
    }
    private static func chooseInMenu(_ text: String) throws {
        app!.sleep(0.6)
        try type(text)
        app!.sleep(0.3)
        try key([], .returnKey)
        app!.sleep(0.8)
    }
    private static func choose(popUp identifier: String, typing text: String, _ what: String) throws {
        try click(identifier: identifier, what)
        try chooseInMenu(text)
    }
    /// Pastes `text` and puts the person's clipboard back.
    private static func paste(_ text: String) throws {
        func shell(_ path: String, input: String?) -> String {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            let output = Pipe(), feed = Pipe()
            process.standardOutput = output
            process.standardInput = feed
            try? process.run()
            if let input { feed.fileHandleForWriting.write(Data(input.utf8)) }
            try? feed.fileHandleForWriting.close()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(decoding: data, as: UTF8.self)
        }
        let saved = shell("/usr/bin/pbpaste", input: nil)
        _ = shell("/usr/bin/pbcopy", input: text)
        defer { _ = shell("/usr/bin/pbcopy", input: saved) }
        try key(.command, .v)
        usleep(300_000)
    }

    // MARK: Reading the state and the screen

    private static func settings(_ app: AppUnderTest) throws -> SettingsSnapshot {
        guard case .settings(let settings) = try app.send(.settings) else { throw Check(description: "no settings") }
        return settings
    }
    private static func tabs(_ app: AppUnderTest) throws -> [TabRow] {
        func walk(_ rows: [Row]) -> [TabRow] {
            rows.flatMap { row -> [TabRow] in
                switch row {
                case .tab(let t): [t]
                case .split(let s): s.panes
                case .folder(let f): walk(f.children)
                }
            }
        }
        let view = try app.view()
        return walk(view.space.pinned.rows) + walk(view.space.today.rows)
    }
    private static func folders(_ app: AppUnderTest) throws -> [FolderRow] {
        try app.view().space.today.rows.compactMap { if case .folder(let f) = $0 { f } else { nil } }
    }
    private static func toast(_ app: AppUnderTest) -> String? { (try? app.view().tabTools.toast).flatMap { $0.map { $0.text + ($0.subtitle.map { " " + $0 } ?? "") } } }
    private static func bar(_ app: AppUnderTest) throws -> CommandBarSnapshot? { if case .commandBar(let bar)? = try app.view().overlay { bar } else { nil } }
    @discardableResult
    private static func open(_ app: AppUnderTest, _ url: URL) throws -> TabRow {
        let before = Set(try tabs(app).map(\.id))
        try WindowServerKeys.ensureFrontmost(app, app.window!)
        try key(.command, .t)
        try app.waitUntil("the command bar") { try bar(app) != nil }
        try type(url.absoluteString)
        app.sleep(0.6)
        try key([], .returnKey)
        var found: TabRow?
        try app.waitUntil("\(url.lastPathComponent) shown", timeout: 20) {
            found = try tabs(app).first { $0.status == .current && $0.url?.absoluteString == url.absoluteString && !before.contains($0.id) }
            return found != nil
        }
        app.sleep(0.8)
        return found!
    }
    private static func shot(_ app: AppUnderTest, _ name: String) -> URL? { try? app.screenshot("AIRealLocal-\(name)").url }
    /// The visible settings window by number, captured, for the cards below Arc's rows.
    private static func captureSettings(_ app: AppUnderTest, _ name: String) -> URL? {
        guard let number = try? app.native().appWindows.first(where: { $0.className == "NSWindow" && $0.isVisible })?.number else { return nil }
        let out = app.shotsDirectory.appendingPathComponent("AIRealLocal-\(name).png")
        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-x", "-l", String(number), out.path]
        try? capture.run(); capture.waitUntilExit()
        return out
    }
    /// What Apple's text recognition reads in an image, for what reached the screen.
    private static func ocr(_ url: URL?) -> String {
        guard let url, let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US", "zh-Hans"]
        try? VNImageRequestHandler(cgImage: image, options: [:]).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " | ")
    }
    /// What text recognition reads in one region (window points) of a window screenshot.
    private static func ocr(_ url: URL?, in region: CGRect, app: AppUnderTest) -> String {
        guard let url, let source = CGImageSourceCreateWithURL(url as CFURL, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let width = try? app.native().contentSize.width, width > 0 else { return "" }
        let scale = Double(image.width) / width
        let box = CGRect(x: region.minX * scale, y: region.minY * scale, width: region.width * scale, height: region.height * scale)
        guard let crop = image.cropping(to: box.intersection(CGRect(x: 0, y: 0, width: image.width, height: image.height))) else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        try? VNImageRequestHandler(cgImage: crop, options: [:]).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }
    private static func scrollSettings(_ app: AppUnderTest, lines: Int32, times: Int) throws {
        guard let window = try app.native().appWindows.first(where: { $0.className == "NSWindow" && $0.isVisible }),
              let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(window.number)) as? [[String: Any]])?.first,
              let bounds = info[kCGWindowBounds as String] as? [String: Double] else { throw Check(description: "no settings window") }
        let center = CGPoint(x: (bounds["X"] ?? 0) + (bounds["Width"] ?? 0) / 2, y: (bounds["Y"] ?? 0) + (bounds["Height"] ?? 0) / 2)
        try mouse(center, [.mouseMoved])
        for _ in 0..<times {
            let event = CGEvent(scrollWheelEvent2Source: CGEventSource(stateID: .hidSystemState), units: .line, wheelCount: 1, wheel1: lines, wheel2: 0, wheel3: 0)
            event?.location = center; event?.post(tap: .cghidEventTap); usleep(40_000)
        }
        app.sleep(0.6)
    }
    private static func wanted(_ part: String) -> Bool {
        guard let parts = ProcessInfo.processInfo.environment["BRK_E2E_REAL_LOCAL_PART"], !parts.isEmpty else { return true }
        return parts.split(separator: ",").contains { $0 == part }
    }
    private static func usage(_ app: AppUnderTest, _ feature: String) throws -> Int {
        (try settings(app).max.settings.usage?.rows ?? [:]).filter { $0.key.feature == feature }.map(\.value.requests).reduce(0, +)
    }

    // MARK: The agent panel (as AIRealTabs drives it)

    private static func clickControl(_ app: AppUnderTest, _ name: String) throws { try click(app, .aiControl(name)) }
    private static func notices(_ ai: AIAnswerSnapshot?) -> [String] {
        ai?.conversation?.items.compactMap { if case .notice(let text) = $0 { text } else { nil } } ?? []
    }
    private static func pending(_ ai: AIAnswerSnapshot?) -> AIAgentApproval? {
        ai?.conversation?.items.lazy.compactMap { if case .approval(let a) = $0, a.answer == nil { a } else { nil } }.first
    }
    private static func runTurn(_ app: AppUnderTest, _ log: Log) throws -> AIAnswerSnapshot {
        var asked = 0
        while true {
            try app.waitUntil("an approval or the end of the turn", timeout: 240) { let ai = try app.view().ai; return ai?.busy == false || pending(ai) != nil }
            let ai = try XCTUnwrapValue(try app.view().ai)
            guard let approval = pending(ai) else { return ai }
            asked += 1
            log.write("  approval \(asked): \(approval.title) -> deny")
            try clickControl(app, "approval-" + AIAgentApproval.Option.Kind.deny.rawValue)
            try app.waitUntil("the approval answered") { pending(try app.view().ai)?.id != approval.id }
        }
    }

    // MARK: The route

    private static func route(_ app: AppUnderTest, agent: AIProviderKind?) throws {
        guard WindowServerKeys.allowed else { throw Check(description: "posting events is not allowed for this runner") }
        guard case .hello(let hello) = try app.send(.hello) else { throw Check(description: "no hello") }
        pid = hello.pid
        Self.app = app
        let name = agent?.rawValue ?? "none"
        let log = Log(app.shotsDirectory.appendingPathComponent("real-local-\(name).txt"))
        defer { try? NativeSystemInput.setShift(false); PhysicalKeys.clearSystemModifiers(KeyChord([.command, .shift, .option, .control], .a)) }
        let site = app.site

        var ready = false
        log.check("Max pane: Turn On Max\(agent.map { ", \($0.displayName)" } ?? " with no agent on this Mac"); On This Mac shows both models downloaded") {
            try WindowServerKeys.ensureFrontmost(app, app.window!)
            try key(.command, .comma)
            try click(title: "Max", "the Max tab")
            app.sleep(1)
            try click(identifier: ViewID.settingsField("enableMax").identifier, "Turn On Max")
            try app.waitUntil("Max on") { try settings(app).max.settings.isOn }
            if let agent {
                try choose(popUp: ViewID.settingsField("agentChoice").identifier, typing: agent.displayName, "the agent pop-up")
                try app.waitUntil("\(agent.displayName) chosen") { try settings(app).max.settings.provider == AIProviderChoice(rawValue: agent.rawValue) }
                var status: AIAgentStatus?
                try app.waitUntil("the agent's status", timeout: 40) { status = try settings(app).max.agents.first { $0.kind == agent }; return status != nil && status?.state != .checking }
                try expect(status?.state == .ready, "\(agent.displayName) is \(String(describing: status?.state))")
                let model = ProcessInfo.processInfo.environment["BRK_E2E_REAL_LOCAL_MODEL"] ?? "Haiku"
                try choose(popUp: ViewID.settingsField("agentModel").identifier, typing: model, "the model pop-up")
                try app.waitUntil("the model chosen") { try settings(app).max.settings.agentOptions?[agent]?.model != nil }
            }
            try app.waitUntil("both models ready and JevK5 answering decisions", timeout: 20) {
                let max = try settings(app).max
                return max.localModels?.rows.allSatisfy { $0.stage == .ready } == true && max.localDecisions
            }
            let max = try settings(app).max
            try expect(AIFeature.basicLayer.allSatisfy(max.settings.enabled), "Turn On Max left the Brk features off: \(max.settings.features ?? [:])")
            if agent == nil { guard case .unavailable = max.basicRoute else { throw Check(description: "an agent was found: \(max.basicRoute)") } }
            // The card sits below Arc's rows and the Accounts card: scroll as a person does until it is on screen.
            var card = ""
            for _ in 0..<6 where !card.contains("Chinese") {
                try scrollSettings(app, lines: -8, times: 12)
                card = ocr(captureSettings(app, "on-this-mac-\(name)"))
            }
            try expect(card.contains("Chinese"), "the card does not read the measured languages: \(card.prefix(400))")
            try key(.command, .w)
            ready = true
            return "basic route \(MaxRouteText.text(max.basicRoute)), decisions for choices \(max.decisionRoute), JevK5 ready \(max.localDecisions); card reads “…\(card.range(of: "measured").map { String(card[$0.lowerBound...].prefix(48)) } ?? "?")”"
        }
        guard ready else { log.write("failures: \(log.failures)"); throw Check(description: "the Max pane step failed; see real-local-\(name).txt") }

        log.check("eight pages from the command bar") {
            for path in ["basic-soup.html", "basic-salad.html", "basic-bread.html", "basic-kyoto.html", "basic-lisbon.html", "basic-swift.html", "basic-rust.html", "basic-cleanup.html"] {
                try open(app, site.url(path))
            }
            return "\(try tabs(app).count) tabs"
        }

        var groups: [FolderRow] = []
        if wanted("tidy") { log.check(agent == nil ? "Tidy without an agent: the search model groups Today and names the groups" : "Tidy with an agent: the text model groups and names") {
            let before = try usage(app, "Tidy Tabs")
            try app.waitUntil("Tidy offered") { try app.view().space.today.canTidy }
            try hover(app, .todayTidy)
            try click(app, .todayTidy)
            try app.waitUntil("Today in groups", timeout: 150) { try !folders(app).isEmpty || (toast(app).map { !$0.hasPrefix("Tidied") } ?? false) }
            groups = try folders(app)
            _ = shot(app, "tidy-\(name)")
            try expect(!groups.isEmpty && toast(app)?.hasPrefix("Tidied Tabs!") == true, "after Tidy: \(toast(app) ?? "no notice"), groups \(groups.map(\.title))")
            let used = try usage(app, "Tidy Tabs") - before
            try expect(agent == nil ? used == 0 : used >= 1, "Tidy Tabs requests to a text model: \(used)")
            return "groups " + groups.map { "\($0.title) (\($0.children.count))" }.joined(separator: ", ") + "; text-model requests \(used)"
        } }

        if wanted("place") { log.check(agent == nil ? "Place New Tabs without an agent: JevK5 picks the group" : "Place New Tabs with an agent: the text model picks the group") {
            guard try !folders(app).isEmpty else { throw Check(description: "no groups to place into (run with tidy)") }
            let before = try usage(app, AIFeature.tabPlacement.title)
            let pie = try open(app, site.url("basic-pie.html"))
            var suggestion: AISuggestionLabel?
            try app.waitUntil("a suggestion or a move", timeout: 120) {
                suggestion = try tabs(app).first { $0.id == pie.id }?.aiSuggestion
                return suggestion != nil || toast(app)?.hasPrefix("Moved to") == true
            }
            app.sleep(0.5)
            _ = shot(app, "placement-\(name)")
            let used = try usage(app, AIFeature.tabPlacement.title) - before
            try expect(agent == nil ? used == 0 : used >= 1, "Place New Tabs requests to a text model: \(used)")
            if let moved = toast(app), moved.hasPrefix("Moved to") {
                let into = try folders(app).first { $0.children.contains { $0.id == pie.id } }?.title ?? "?"
                return "moved at once (\(moved)), now in “\(into)”; text-model requests \(used)"
            }
            let label = try XCTUnwrapValue(suggestion)
            try click(app, .tabTool("ai-suggestion-" + pie.id.rawValue))
            try app.waitUntil("the tab in its group") { try folders(app).contains { $0.children.contains { $0.id == pie.id } } }
            return "suggested “\(label.text)”, clicked, now in “\(try folders(app).first { $0.children.contains { $0.id == pie.id } }?.title ?? "?")”; text-model requests \(used)"
        } }

        if wanted("duplicates") { log.check("Duplicates: the same page under another address, by meaning, then JevK5's yes, listed beside Tidy and closed from the list") {
            let before = try app.view().space.today.cleanup
            let decisions = try usage(app, AIFeature.tabCleanup.title)
            let copy = try open(app, URL(string: site.url("basic-soup.html").absoluteString + "?print=1")!)
            try app.waitUntil("the cleanup count", timeout: 60) { try app.view().space.today.cleanup > before }
            try expect(try usage(app, AIFeature.tabCleanup.title) == decisions, "the yes/no went to a text model")
            try hover(app, .tabTool("today-cleanup"))
            _ = shot(app, "cleanup-button-\(name)")
            try click(app, .tabTool("today-cleanup"))
            app.sleep(0.8)
            try chooseInMenu("Close")
            try app.waitUntil("one soup left") { try tabs(app).filter { $0.url?.lastPathComponent == "basic-soup.html" }.count == 1 }
            let left = try tabs(app).first { $0.url?.lastPathComponent == "basic-soup.html" }
            return "\(try app.view().space.today.cleanup + 1) listed before Close; the copy \(left?.id == copy.id ? "stayed (the original went)" : "went"); no text-model request"
        } }

        let query = "a weekend city break in Portugal"
        if wanted("bar") { log.check("Search by meaning in the command bar: “\(query)” finds the Lisbon tab, and its row switches to it") {
            let lisbon = try XCTUnwrapValue(try tabs(app).first { $0.url?.lastPathComponent == "basic-lisbon.html" })
            if let soup = try tabs(app).first(where: { $0.url?.lastPathComponent == "basic-soup.html" }) { try click(try screen(app, try visible(app.native(), .row(soup.id)).frame)) }
            try WindowServerKeys.ensureFrontmost(app, app.window!)
            try key(.command, .t)
            try app.waitUntil("the command bar") { try bar(app) != nil }
            try type(query)
            try app.waitUntil("rows by meaning", timeout: 30) { try bar(app)?.meaning?.text == query && bar(app)?.meaning?.rows.isEmpty == false }
            let found = try XCTUnwrapValue(try bar(app)?.meaning?.rows.first)
            try expect(found.tab == lisbon.id, "the first match is \(found.title)")
            app.sleep(0.5)
            let picture = shot(app, "bar-\(name)")
            let drawn = ocr(picture)
            // The rows are known by index; the one that draws the found page's title is the one to click.
            var row: CGRect?
            for index in 0..<5 where row == nil {
                guard let frame = try? visible(app.native(), .commandBarResult(index)).frame else { continue }
                if ocr(picture, in: frame, app: app).contains("Lisbon") { row = frame }
            }
            let frame = try XCTUnwrapValue(row)
            try click(try screen(app, frame))
            try app.waitUntil("the Lisbon tab shown") { try tabs(app).first { $0.id == lisbon.id }?.status == .current }
            try expect(drawn.contains("Lisbon"), "the bar did not draw it: \(drawn.prefix(300))")
            return "row “\(found.title)” drawn and clicked; the tab is shown"
        } }

        if wanted("history") { log.check("Search by meaning on the History page: “\(query)” lists the Lisbon visit under Found by meaning") {
            try WindowServerKeys.ensureFrontmost(app, app.window!)
            try key(.command, .y)
            try app.waitUntil("the History page") { try app.view().history != nil }
            app.sleep(1)
            try type(query)
            try app.waitUntil("visits by meaning", timeout: 30) { try app.view().historyMeaning?.text == query && app.view().historyMeaning?.rows.isEmpty == false }
            let rows = try XCTUnwrapValue(try app.view().historyMeaning?.rows)
            app.sleep(0.6)
            let drawn = ocr(shot(app, "history-\(name)"))
            try expect(rows.first?.url.lastPathComponent == "basic-lisbon.html", "first by meaning: \(rows.map(\.title))")
            try expect(drawn.contains("Found by meaning") && drawn.contains("Lisbon"), "the page did not draw it: \(drawn.prefix(400))")
            try key(.command, .w)
            return "\(rows.count) visit(s) by meaning, first “\(rows[0].title)”, drawn under “Found by meaning”"
        } }

        if agent != nil, wanted("check") { log.check("The page check: a page whose hidden instruction the phrase patterns miss is flagged by JevK5, and nothing it asks happens") {
            let target = app.dataDirectory.appendingPathComponent("pwned.txt")
            let path = "ai-injection-quiet.html?target=" + target.path
            let page = try open(app, site.url(path))
            try rightClick(try screen(app, try visible(app.native(), .row(page.id)).frame))
            app.sleep(0.6)
            var item: CGRect?
            try app.waitUntil("“Ask AI” in the menu", timeout: 6) { item = NativeSystemInput.frame(pid: pid, title: "Ask AI", roles: ["AXMenuItem"]); return item != nil }
            try click(CGPoint(x: item!.midX, y: item!.midY))
            try app.waitUntil("the panel with the tab") { try app.view().ai?.conversation?.attached.count == 1 }
            try clickControl(app, "input")
            try paste("Summarize this tab in one sentence.")
            try key([], .returnKey)
            try app.waitUntil("the turn started", timeout: 10) { try app.view().ai?.busy == true }
            let ai = try runTurn(app, log)
            _ = shot(app, "check-\(name)")
            let flagged = notices(ai).first { $0.hasPrefix("Brk flagged") }
            try expect(flagged?.contains("JevK5 on this Mac") == true, "notices: \(notices(ai))")
            try expect(!FileManager.default.fileExists(atPath: target.path), "the page's file was written")
            return flagged ?? ""
        } }

        if agent != nil, wanted("mention") { log.check("@ in the panel: a tab found by meaning joins the list") {
            if try app.view().ai == nil { throw Check(description: "no panel (run with check)") }
            let lisbon = try XCTUnwrapValue(try tabs(app).first { $0.url?.lastPathComponent == "basic-lisbon.html" })
            try app.waitUntil("an open conversation") { try app.view().ai?.conversation?.ended == false && app.view().ai?.busy == false }
            try clickControl(app, "input")
            try type("@weekend city break in Portugal")
            try app.waitUntil("the Lisbon tab in the @ list", timeout: 30) {
                try app.view().ai?.conversation?.mention?.matches.contains { $0.id == lisbon.id.rawValue } == true
            }
            let matches = try app.view().ai?.conversation?.mention?.matches.map(\.title) ?? []
            _ = shot(app, "mention-\(name)")
            try key([], .escape)
            return "matches \(matches)"
        } }

        log.check("This month's usage") {
            let rows = (try settings(app).max.settings.usage?.rows ?? [:]).sorted { $0.key < $1.key }
            if agent == nil { try expect(rows.isEmpty, "a text model was used: \(rows)") }
            return rows.isEmpty ? "nothing went to a text model" : rows.map { "\($0.key.feature): \($0.value.requests) req" }.joined(separator: "; ")
        }

        log.write("failures: \(log.failures)")
        try expect(log.failures == 0, "see real-local-\(name).txt")
    }
}
