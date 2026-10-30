import AppKit
import BrkBase
@testable import BrkDomain
import XCTest
@testable import BrkSettings

/// Owner: F1. The settings host's first pass: it renders a snapshot without a window and keeps no state of its own.
@MainActor
final class SettingsHostTests: XCTestCase {
    private func snapshot(pane: SettingsPane?) -> SettingsSnapshot {
        SettingsSnapshot(pane: pane, general: .default, profiles: [], links: .default, routes: [], spaces: [],
                         engines: SearchEngine.builtIn.map { SearchEngineCandidate(id: $0.id, name: $0.name, keyword: $0.keyword) },
                         shortcuts: [], max: MaxSnapshot(settings: .default, detected: [], active: nil), advanced: .default)
    }

    func testRendersEveryPaneHeadless() {
        let host = SettingsHost(dispatch: { _ in })
        host.frame = CGRect(origin: .zero, size: Metrics.settings.windowSize.value)
        for pane in SettingsPane.allCases {
            host.render(snapshot(pane: pane))
            host.layoutSubtreeIfNeeded()
        }
        host.render(snapshot(pane: nil))
        XCTAssertEqual(host.accessibilityIdentifier(), "settings")
    }

    func testCopyNamesEveryPaneAndChoice() {
        XCTAssertEqual(SettingsPane.allCases.map(SettingsCopy.title), ["General", "Max", "Profiles", "Shortcuts", "Links", "Advanced"])
        XCTAssertEqual(SettingsCopy.threshold(.twelveHours), "12 hours")
        XCTAssertEqual(SettingsCopy.state(.unset), "unset")
        XCTAssertEqual(SettingsCopy.detected([.claude], active: .claude), "Found on PATH: claude. Using claude.")
    }

    // MARK: F1 stubs

    func testEveryFieldDispatchesItsSettingsCommand() throws {
        throw XCTSkip("F1: each toggle, picker and field dispatches its `.settings(...)` command once and reads back from the snapshot (no local state)")
    }

    func testThePaneToolbarMatchesArcsOrderAndIcons() throws {
        throw XCTSkip("F1: Arc's pane toolbar (General, Max, Profiles, Shortcuts, Links, Advanced) with its icons and window titles ('General Preferences', ...)")
    }

    func testTheLinksPaneEditsAirTrafficControlRoutes() throws {
        throw XCTSkip("F1 with F3: the route editor adds, reorders and removes `LinkRoute`s and offers every space, Little Arc and 'Most Recent Space'")
    }
}
