import BrkBase
import BrkDomain
import CoreGraphics
import Foundation
@testable import BrkLayout

/// Real snapshots for layout cases, built only through the domain's public surface (StateCodec.restore, reduce,
/// project), exactly as the app builds them. Tests then adjust a snapshot's public fields where a case needs a
/// value the reducer would not produce (an exact pane fraction, a hidden sidebar that peeks).
final class LayoutDriver {
    private(set) var state: AppState
    let window: WindowID
    let now = Instant(milliseconds: 1_790_000_000_000)
    private let ids = IDs()
    static let size = CGSize(width: 1280, height: 776)

    init(startURL: URL? = URL(string: "http://127.0.0.1:9/a")) {
        let restored = StateCodec.restore(nil, seed: RestoreSeed(startURL: startURL, contentSize: LayoutDriver.size),
                                          ctx: Context(now: now, newID: ids.next))
        state = restored.state
        window = project(restored.state, ProjectionContext(now: now, calendar: Calendar(identifier: .gregorian))).windows.keys.sorted()[0]
    }

    func user(_ command: Command) {
        state = reduce(state, .user(window, command), Context(now: now, newID: ids.next)).state
    }

    var view: WindowSnapshot { project(state, ProjectionContext(now: now, calendar: Calendar(identifier: .gregorian))).windows[window]! }

    func frames(_ snapshot: WindowSnapshot? = nil, size: CGSize = LayoutDriver.size) -> WindowFrames {
        WindowLayout.compute(snapshot ?? view, contentSize: size)
    }

    @discardableResult
    func open(_ text: String) -> ItemID {
        let before = Set(view.space.today.rows.map(\.id))
        user(.commandBar(.open(.newTab)))
        user(.commandBar(.submit(text)))
        return view.space.today.rows.map(\.id).first { !before.contains($0) }!
    }
}

final class IDs: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    func next() -> String { lock.withLock { n += 1; return "l\(n)" } }
}
