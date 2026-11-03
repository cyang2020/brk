import AppKit
import BrkBase
import BrkDomain
import BrkEngine
import Foundation
import XCTest
@testable import BrkApp

/// A `WebEngine` that records every call in order and answers with plain surfaces, so store, window and quit
/// ordering can be pinned without Chromium. `onReconcile` and `onShutdown` let a test observe or react mid-call.
@MainActor
final class FakeEngine: WebEngine {
    weak var delegate: (any WebEngineDelegate)?
    private(set) var calls: [String] = []
    private(set) var reconciled: [[PageSpec]] = []
    private(set) var performed: [(PageID, PageAction)] = []
    private(set) var focused: [PageID?] = []
    private(set) var shutdowns = 0
    var pageLog: [PageLogEntry] = []
    var shutdownOutcome: ShutdownOutcome = .clean
    var onReconcile: (([PageSpec]) -> Void)?
    var onShutdown: (() -> Void)?
    var onAIRead: ((DocumentToken) async throws -> AIPageContent)?
    private var ledger = PageLedger()
    func token(_ page: PageID) -> BrowserToken { BrowserToken(page: page, generation: ledger.liveGeneration(of: page)!) }
    private var surfaces: [PageID: PageSurfaceView] = [:]

    func reconcile(_ pages: [PageSpec]) {
        calls.append("reconcile")
        reconciled.append(pages)
        for spec in pages where surfaces[spec.id] == nil && spec.initialURL != nil {
            surfaces[spec.id] = PageSurfaceView(page: spec.id)
            let token = ledger.create(spec.id)
            delegate?.engine(self, page: token, didEmit: .browserCreated(spec.context, .unavailable))
        }
        for id in surfaces.keys where !pages.contains(where: { $0.id == id }) { surfaces[id] = nil }
        onReconcile?(pages)
    }

    func surface(for page: PageID) -> PageSurfaceView? {
        calls.append("surface")
        return surfaces[page]
    }

    func perform(_ action: PageAction, on page: PageID) {
        calls.append("perform")
        performed.append((page, action))
    }

    func focus(_ page: PageID?, in window: NSWindow) {
        calls.append("focus")
        focused.append(page)
    }

    func evaluate(_ script: String, in page: PageID) { calls.append("evaluate") }
    /// Diagnostics fakes: a trace writes `traceText` to the file it is asked for; the task list is `taskList`.
    var traceText = "{\"traceEvents\":[]}"
    var tracing = false
    var taskList: [EngineTask] = []
    private(set) var endedTasks: [Int64] = []
    func beginTrace() async -> Bool {
        guard !tracing else { return false }
        tracing = true; calls.append("beginTrace"); return true
    }
    func endTrace(writingTo file: URL?) async -> URL? {
        tracing = false; calls.append(file == nil ? "discardTrace" : "endTrace")
        guard let file else { return nil }
        try? traceText.write(to: file, atomically: true, encoding: .utf8)
        return file
    }
    func tasks() -> [EngineTask] { taskList }
    func endTask(_ id: Int64) -> Bool {
        guard taskList.contains(where: { $0.id == id && $0.killable }) else { return false }
        endedTasks.append(id); taskList.removeAll { $0.id == id }; return true
    }
    func evaluateForResult(_ script: String, in page: PageID) async throws -> String? { calls.append("evaluateForResult"); return "fake:" + script }
    func facts(for page: PageID) -> PageFacts? { nil }
    func readAIPage(_ document: DocumentToken) async throws -> AIPageContent {
        guard let onAIRead else { throw AIPageFailure.unavailable }
        return try await onAIRead(document)
    }
    private(set) var forgotten: [BrowsingContext] = []
    func cancelDownload(_ id: DownloadID) { calls.append("cancelDownload") }
    func disposeContext(_ request: ContextDisposal) {
        let context = request.context
        calls.append("forget")
        forgotten.append(context)
    }

    func shutdown() async -> ShutdownOutcome {
        calls.append("shutdown")
        shutdowns += 1
        onShutdown?()
        return shutdownOutcome
    }
}

/// A store over a fresh profile with one tab (`startURL`), a test clock, a temp state file and a fake engine.
@MainActor
struct Harness {
    let store: AppStore
    let engine: FakeEngine
    let router: KeyRouter
    let stateFile: StateFile
    let directory: URL
    let window: WindowID
    let page: PageID

    static let startURL = URL(string: "http://127.0.0.1:9/index.html")!

    init(startURL: URL? = Harness.startURL) {
        _ = NSApplication.shared
        directory = FileManager.default.temporaryDirectory.appendingPathComponent("brk-app-\(UUID().uuidString)", isDirectory: true)
        stateFile = StateFile(directory: directory)
        engine = FakeEngine()
        let clock = OffsetClock()
        let restored = StateCodec.restore(nil, seed: RestoreSeed(startURL: startURL, contentSize: Metrics.window.defaultSize.value),
                                          ctx: Context(now: clock.now(), newID: { UUID().uuidString }))
        store = AppStore(restored: restored, clock: clock, engine: engine, stateFile: stateFile)
        router = KeyRouter(store: store)
        engine.delegate = router
        window = store.snapshot.windows.keys.sorted()[0]
        page = store.snapshot.pages[0].id
    }

    func cleanUp() {
        store.windowController(window)?.window.orderOut(nil)
        try? FileManager.default.removeItem(at: directory)
    }

    /// A key input as CEF or the menu would deliver it.
    func key(_ chord: String, stage: KeyStage, id: UInt64, isRepeat: Bool = false) -> KeyInput {
        let press = KeyPress(chord: KeyChord(parsing: chord)!, phase: .down, isRepeat: isRepeat, editableFieldFocused: false)
        return KeyInput(press: press, stage: stage, pressID: PressID(raw: id))
    }
}

/// Counts quit requests instead of terminating the test process. Restores the real handler afterwards.
@MainActor
final class QuitCounter {
    private(set) var count = 0
    private let previous: @MainActor () -> Void

    init() {
        previous = Quit.perform
        Quit.confirmed = false
        Quit.perform = { [unowned self] in self.count += 1 }
    }

    func restore() {
        Quit.perform = previous
        Quit.confirmed = false
    }
}
