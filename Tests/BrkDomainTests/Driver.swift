import BrkBase
import CoreGraphics
import Foundation
@testable import BrkDomain

let pendingW1 = "W1: not implemented yet"
let pendingW4 = "W4: not implemented yet"
let pendingW5 = "W5: not implemented yet"

/// The app's state owner in miniature: one `AppState`, changed only through `reduce`, read only through `project`
/// and `StateCodec`. Ported from the Electron spec's Driver. A fixed clock (`now`, moved by `advance`) and a counter
/// for ids make every run deterministic.
final class Driver {
    private(set) var state: AppState
    private(set) var now = Instant(milliseconds: 1_790_000_000_000)
    let window: WindowID
    let outcome: RestoreOutcome
    private let ids = Counter()
    private let calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    static let startURL = URL(string: "http://127.0.0.1:9/a")!
    static let contentSize = CGSize(width: 1280, height: 776)

    init(file: Data? = nil, startURL: URL? = Driver.startURL) {
        let restored = StateCodec.restore(file, seed: RestoreSeed(startURL: startURL, contentSize: Driver.contentSize),
                                          ctx: Context(now: now, newID: ids.next))
        state = restored.state
        outcome = restored.outcome
        window = project(restored.state, ProjectionContext(now: now, calendar: calendar)).windows.keys.sorted()[0]
    }

    var ctx: Context { Context(now: now, newID: ids.next) }

    @discardableResult
    func user(_ command: Command) -> Transition { apply(reduce(state, .user(window, command), ctx)) }

    @discardableResult
    func system(_ event: SystemEvent) -> Transition { apply(reduce(state, .system(event), ctx)) }

    @discardableResult
    func key(_ chord: KeyChord, stage: KeyStage, pressID: UInt64, isRepeat: Bool = false, in window: WindowID? = nil) -> Transition {
        let press = KeyPress(chord: chord, phase: .down, isRepeat: isRepeat, editableFieldFocused: false)
        let input = KeyInput(press: press, stage: stage, pressID: PressID(raw: pressID))
        return apply(reduce(state, .key(window ?? self.window, input), ctx))
    }

    func advance(_ duration: Duration) { now = now.advanced(by: duration) }

    var snapshot: AppSnapshot { project(state, ProjectionContext(now: now, calendar: calendar)) }
    var view: WindowSnapshot { snapshot.windows[window]! }
    var todayIDs: [ItemID] { view.space.today.rows.map(\.id) }
    var pinnedIDs: [ItemID] { view.space.pinned.rows.map(\.id) }
    var savedFile: Data { StateCodec.encode(state) }

    /// Cmd+T, type, Enter. Returns the new tab's id.
    func open(_ input: String) -> ItemID {
        let before = Set(todayIDs)
        user(.commandBar(.open(.newTab)))
        user(.commandBar(.submit(input)))
        let added = todayIDs.filter { !before.contains($0) }
        precondition(added.count == 1, "open(\(input)) added \(added.count) tabs")
        return added[0]
    }

    private func apply(_ t: Transition) -> Transition {
        state = t.state
        return t
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func next() -> String { lock.withLock { n += 1; return "t\(n)" } }
}
