import BrkBase
import BrkDomain
import Foundation
import XCTest
@testable import BrkApp

/// Test launches with `BRK_TEST_NO_GLOBAL_SHORTCUT=1` take no combination system-wide; every other launch keeps
/// taking the New Little Window shortcut while Links' switch is on.
@MainActor
final class LittleEntryPointsTests: XCTestCase {
    private let littleArc = KeyChord([.option, .command], .n)

    private func settings(linksSwitch: Bool? = nil) -> SettingsSnapshot {
        let now = Instant(milliseconds: 1_790_000_000_000)
        let ctx = Context(now: now, newID: { UUID().uuidString })
        let pc = ProjectionContext(now: now, calendar: Calendar(identifier: .gregorian))
        var state = StateCodec.restore(nil, seed: RestoreSeed(startURL: nil, contentSize: CGSize(width: 1280, height: 776)), ctx: ctx).state
        if let on = linksSwitch, let window = project(state, pc).windows.keys.first {
            state = reduce(state, .user(window, .settings(.links(.globalLittleArcShortcut(on)))), ctx).state
        }
        return project(state, pc).settings
    }

    func testTheLinksSwitchOffTakesNothing() {
        let off = settings(linksSwitch: false)
        XCTAssertEqual(off.links.globalLittleArcShortcut, false)
        XCTAssertNil(LittleEntryPoints.systemWideChord(off, environment: [:]))
        XCTAssertEqual(LittleEntryPoints.systemWideChord(settings(linksSwitch: true), environment: [:]), littleArc)
    }
}
