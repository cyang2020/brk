import AppKit
import BrkBase
import BrkControl
import BrkDomain
import BrkEngine

/// The app side of the control socket (protocol: BrkControl/Protocol.swift). Accepts on a background queue,
/// decodes one `ControlRequest` per line, runs it on the main actor through `ControlExecutor`, writes the reply.
/// Started only when BRK_CONTROL_SOCKET is set; never in a normal launch.
final class ControlServer: @unchecked Sendable {
    private let path: String
    private let executor: ControlExecutor
    private let queue = DispatchQueue(label: "brk.control")

    init(path: String, executor: ControlExecutor) {
        self.path = path
        self.executor = executor
    }

    func start() throws {
        // TODO(W6): unlink(path); socket/bind/listen; DispatchSource read source on `queue` accepting connections;
        // per connection: read lines; decode (a decode error replies .failed with the decoder message);
        // `await MainActor.run { executor.run(op) }` - ops that wait (settle, quit) are async on the main actor.
        fatalError("not implemented")
    }

    func stopAccepting() {
        // TODO(W6): cancel the accept source; keep open connections until their in-flight reply is written.
    }
}

/// Executes control ops against the running app, on the main actor, through the same paths a user takes:
/// `dispatch` -> `AppStore.dispatch`; `press`/`type`/`click`/`hover` -> in-process NSEvents into `NSApp.sendEvent`
/// (spike unknown 3: injected events reach CEF's key handler exactly like real ones); `view` -> the store's
/// snapshot; `native` -> computed frames from the window controller plus a walk of the live view tree for
/// accessibility identifiers and `engine.facts(for:)`; `screenshot`/`pixel` -> CGWindowListCreateImage.
@MainActor
final class ControlExecutor {
    private unowned let store: AppStore
    private let engine: any WebEngine
    private let clock: OffsetClock?

    init(store: AppStore, engine: any WebEngine, clock: OffsetClock?) {
        self.store = store
        self.engine = engine
        self.clock = clock
    }

    func run(_ op: ControlOp) async -> ControlResult {
        // TODO(W6): one case per ControlOp; `.advanceClock` without a test clock -> .failed("BRK_TEST_CLOCK not set").
        fatalError("not implemented")
    }
}
