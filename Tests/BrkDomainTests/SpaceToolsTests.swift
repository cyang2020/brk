import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

final class SpaceToolsTests: XCTestCase {
    /// The Spaces either side of the current one come with the snapshot: the sidebar draws their pages while the column moves.
    func testTheSnapshotCarriesTheNeighbouringSpacesPages() throws {
        let d = Driver()
        let first = d.view.space.id
        let tab = d.open("a.example")
        let second = d.newSpace("Second", color: RGBA(hex: "#336699"))
        let inSecond = d.open("b.example")
        let third = d.newSpace("Third", color: RGBA(hex: "#993366"))
        XCTAssertEqual(d.view.neighbors.previous?.space.id, second)
        XCTAssertNil(d.view.neighbors.next, "the last Space has nothing after it")
        d.user(.space(.focus(second)))
        let around = d.view.neighbors
        XCTAssertEqual(around.previous?.space.id, first)
        XCTAssertEqual(around.next?.space.id, third)
        d.user(.space(.focus(first)))
        XCTAssertNil(d.view.neighbors.previous)
        let page = try XCTUnwrap(d.view.neighbors.next)
        XCTAssertEqual(page.space.title, "Second")
        XCTAssertEqual(page.theme, resolveTheme(try XCTUnwrap(d.state.doc.spaces[second]).theme, systemScheme: .light))
        XCTAssertEqual(page.favorites.root, d.view.favorites.root, "one profile, one set of Favorites")
        let row = try XCTUnwrap(page.space.today.rows.first { $0.id == inSecond })
        if case .tab(let shown) = row { XCTAssertEqual(shown.status, .current, "the tab that Space would show looks current on its page") } else { XCTFail("not a tab") }
        // What the current Space shows is untouched by working out its neighbours' rows.
        let here = try XCTUnwrap(d.view.space.today.rows.first { $0.id == tab })
        if case .tab(let shown) = here { XCTAssertEqual(shown.status, .current) } else { XCTFail("not a tab") }
    }

    func testClosingNativeOwnerRetiresSpaceToolsRequestsEvenForLastSavedWindow() throws {
        let d = Driver()
        let second = d.newSpace("Owner close")
        d.user(.space(.requestDelete(second)))
        let request = try XCTUnwrap(d.view.pendingSpaceDeletion)
        guard case .exportSpaceFolder(_, let token, _)? = d.user(.space(.exportIntoFolder(second))).effects.first else {
            return XCTFail("no export")
        }
        d.system(.window(d.window, .closed))
        XCTAssertNotNil(d.state.doc.windows[d.window], "last standard window remains saved")
        XCTAssertNil(d.state.session.windows[d.window]?.pendingSpaceDeletion)
        XCTAssertNil(d.state.session.windows[d.window]?.spaceExport)
        d.user(.space(.confirmDelete(second, token: request.token, confirmed: true)))
        XCTAssertNotNil(d.state.doc.spaces[second])
        d.system(.spaceExportFinished(d.window, token: token, .failed("late result")))
        XCTAssertNil(d.state.session.windows[d.window]?.spaceExportMessage)
    }

    func testLegacyV3DefaultsAndIndependentValuesRoundTrip() throws {
        let d = Driver()
        let old = StateCodec.encode(d.state)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: old) as? [String: Any])
        var doc = try XCTUnwrap(json["doc"] as? [String: Any])
        var windows = try XCTUnwrap(doc["windows"] as? [String: [String: Any]])
        for key in Array(windows.keys) {
            windows[key]!.removeValue(forKey: "toolbarVisible")
            windows[key]!.removeValue(forKey: "spaceHeaderVisible")
        }
        doc["windows"] = windows; json["doc"] = doc
        let restored = StateCodec.restore(try JSONSerialization.data(withJSONObject: json), seed: RestoreSeed(startURL: nil, contentSize: CGSize(width: 1200, height: 800)), ctx: d.ctx)
        guard case .restored = restored.outcome else { return XCTFail("old v3 was rejected") }
        let view = project(restored.state, ProjectionContext(now: d.now, calendar: .current)).windows[d.window]!
        XCTAssertFalse(view.sidebar.toolbarVisible)
        XCTAssertTrue(view.sidebar.spaceHeaderVisible)
        var theme = SpaceTheme.default
        theme.variants = ThemeVariants(legacy: theme)
        theme.variants!.light.colors[0].color = RGBA(1, 0, 0)
        theme.variants!.dark.colors[0].color = RGBA(0, 0, 1)
        theme.variants!.selection = .auto
        d.user(.space(.update(d.view.space.id, title: nil, icon: nil, theme: theme)))
        d.user(.sidebar(.toggleToolbar)); d.user(.sidebar(.toggleSpaceHeader))
        let data = StateCodec.encode(d.state)
        let again = StateCodec.restore(data, seed: RestoreSeed(startURL: nil, contentSize: CGSize(width: 1200, height: 800)), ctx: d.ctx)
        XCTAssertEqual(again.state.doc.spaces[d.view.space.id]?.theme, theme)
        XCTAssertEqual(StateCodec.currentVersion, 3)
        for scheme in [Scheme.light, .dark] {
            let rendered = project(again.state, ProjectionContext(now: d.now, calendar: .current, systemScheme: scheme)).windows[d.window]!
            XCTAssertEqual(rendered.theme.scheme, scheme)
            XCTAssertEqual(rendered.theme.gradient[0], scheme == .light ? RGBA(1, 0, 0) : RGBA(0, 0, 1))
            XCTAssertTrue(rendered.sidebar.toolbarVisible); XCTAssertFalse(rendered.sidebar.spaceHeaderVisible)
        }
    }

    func testLegacyAutomaticThemeDoesNotFollowSystemUntilExplicitConversion() {
        var legacy = SpaceTheme.default
        legacy.colors = [RGBA(1, 1, 1)]
        XCTAssertEqual(resolveTheme(legacy, systemScheme: .dark).scheme, .light)
        legacy.variants = ThemeVariants(legacy: legacy)
        legacy.variants!.selection = .auto
        XCTAssertEqual(resolveTheme(legacy, systemScheme: .dark).scheme, .dark)
        XCTAssertEqual(resolveTheme(legacy, systemScheme: .light).scheme, .light)
    }

    func testThemeBoundaryClampsNonfiniteAndDoesNotOverwriteOtherAppearance() {
        var theme = SpaceTheme.default
        theme.variants = ThemeVariants(legacy: theme)
        let light = theme.variants!.light
        theme.variants!.dark.saturation = .infinity
        theme.variants!.dark.colors = [ThemeColor(color: RGBA(.nan, 4, -1), position: ThemePoint(x: .nan, y: 5))]
        let safe = clamped(theme)
        XCTAssertEqual(safe.variants?.light, light)
        XCTAssertEqual(safe.variants?.dark.saturation, 1)
        XCTAssertEqual(safe.variants?.dark.colors[0].color, RGBA(0, 1, 0))
        XCTAssertEqual(safe.variants?.dark.colors[0].position, ThemePoint(x: 0.1, y: 1))
    }

    func testProfileCreationSelectionAndConfirmationGuardAcrossWindows() throws {
        let d = Driver()
        let first = d.view.space.id
        d.user(.profile(.create(name: "Work", icon: nil)))
        let profile = try XCTUnwrap(d.state.doc.profiles.values.first { $0.name == "Work" }?.id)
        d.user(.space(.create(title: "Second", icon: .custom(.named(.briefcase)), theme: .default, profile: profile)))
        let second = d.view.space.id
        XCTAssertEqual(d.state.doc.spaces[second]?.profile, profile)
        d.user(.window(.new))
        let other = try XCTUnwrap(d.state.doc.windows.keys.first { $0 != d.window })
        d.user(.space(.focus(second)), in: other)
        d.user(.space(.requestDelete(second)))
        let oldToken = try XCTUnwrap(d.view.pendingSpaceDeletion?.token)
        XCTAssertNotNil(d.state.doc.spaces[second])
        d.user(.space(.confirmDelete(second, token: oldToken, confirmed: true)), in: other)
        XCTAssertNotNil(d.state.doc.spaces[second], "another window cannot answer this confirmation")
        d.user(.space(.confirmDelete(second, token: oldToken, confirmed: false)))
        XCTAssertNotNil(d.state.doc.spaces[second])
        d.user(.space(.requestDelete(second)))
        let newToken = try XCTUnwrap(d.view.pendingSpaceDeletion?.token)
        d.user(.space(.confirmDelete(second, token: oldToken, confirmed: true)))
        XCTAssertNotNil(d.state.doc.spaces[second], "an old sheet cannot confirm a newer request for the same Space")
        XCTAssertEqual(d.view.pendingSpaceDeletion?.token, newToken)
        d.user(.space(.confirmDelete(second, token: newToken, confirmed: true)))
        XCTAssertNil(d.state.doc.spaces[second])
        XCTAssertEqual(d.state.doc.windows[other]?.space, first)
        d.user(.space(.requestDelete(first)))
        XCTAssertNil(d.view.pendingSpaceDeletion)
    }

    func testSpaceExportExcludesPrivateDataAndFencesCompletion() throws {
        let d = Driver()
        let space = d.view.space.id
        let effect = d.user(.space(.exportIntoFolder(space))).effects.first
        guard case .exportSpaceFolder(let owner, let token, let document)? = effect else { return XCTFail("no export") }
        XCTAssertEqual(owner, d.window)
        XCTAssertFalse(document.entries.isEmpty)
        d.system(.spaceExportFinished(owner, token: "old", .failed("stale")))
        XCTAssertNotNil(d.state.session.windows[owner]?.spaceExport)
        d.system(.spaceExportFinished(owner, token: token, .failed("fixture failure")))
        XCTAssertNil(d.state.session.windows[owner]?.spaceExport)
        XCTAssertTrue(d.state.session.windows[owner]?.spaceExportMessage?.contains("fixture failure") == true)
        d.user(.window(.newIncognito))
        let privateWindow = try XCTUnwrap(d.state.doc.windows.values.first { $0.kind == .incognito }?.id)
        XCTAssertTrue(d.user(.space(.exportIntoFolder(space)), in: privateWindow).effects.isEmpty)
        d.user(.library(.open(.spaces)), in: privateWindow)
        let view = project(d.state, ProjectionContext(now: d.now, calendar: .current)).windows[privateWindow]!
        guard case .library(let library)? = view.overlay else { return XCTFail("no library") }
        XCTAssertFalse(library.canManageSpaces); XCTAssertTrue(library.spaces.isEmpty)
    }
}
