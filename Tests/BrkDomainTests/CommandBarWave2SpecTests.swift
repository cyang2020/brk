import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

/// Owner: F4. The command bar's wave-2 contract: the profile's search engine, site search, search suggestions
/// through the effect and event pair, the type-travel index (every real menu action is a result), shortcut
/// remapping with conflicts.
final class CommandBarWave2SpecTests: XCTestCase {
    /// a search uses the current space's profile's default engine
    func test_searchesUseTheProfilesEngine() {
        let d = Driver()
        d.user(.settings(.profile(.default, .searchEngine(SearchEngine.duckDuckGo.id))))
        d.user(.commandBar(.open(.newTab)))
        XCTAssertEqual(d.bar?.engine.name, "DuckDuckGo")
        XCTAssertEqual(d.bar?.siteSearch.map(\.keyword), ["google", "bing", "ecosia", "kagi"])
        d.user(.commandBar(.submit("arc browser")))
        XCTAssertEqual(d.current?.url, url("https://duckduckgo.com/?q=arc%20browser"))
    }

    /// site search submits the query on the named engine, whatever the default is
    func test_siteSearchSubmitsOnTheNamedEngine() {
        let d = Driver()
        d.user(.commandBar(.open(.newTab)))
        d.user(.commandBar(.submitSearch(engine: SearchEngine.bing.id, query: " swift ")))
        XCTAssertEqual(d.current?.url, url("https://www.bing.com/search?q=swift"))
        XCTAssertNil(d.view.overlay)
        d.user(.commandBar(.open(.newTab)))
        assertUnchanged(d.state, d.user(.commandBar(.submitSearch(engine: SearchEngineID("nope"), query: "x"))))
        assertUnchanged(d.state, d.user(.commandBar(.submitSearch(engine: SearchEngine.bing.id, query: "   "))))
    }

    /// typing asks the engine for suggestions (an effect with the suggest URL) when the profile allows it; the answer is projected with its query
    func test_suggestionsGoThroughTheEffectAndEventPair() {
        let d = Driver()
        d.user(.commandBar(.open(.newTab)))
        let t = d.user(.commandBar(.queryChanged("swi")))
        XCTAssertEqual(t.effects, [.fetchSuggestions(d.window, query: "swi", url: url("https://suggestqueries.google.com/complete/search?client=firefox&q=swi"))])
        XCTAssertFalse(t.changed, "the query is view-local; only the fetch leaves")
        d.system(.suggestions(d.window, query: "swi", ["swift", "swim"]))
        XCTAssertEqual(d.bar?.suggestions, ["swift", "swim"])
        XCTAssertEqual(d.bar?.suggestedFor, "swi")
        XCTAssertEqual(d.user(.commandBar(.queryChanged("   "))).effects, [])
        XCTAssertEqual(d.bar?.suggestions, [], "a blank query clears them")
        d.user(.settings(.profile(.default, .searchSuggestions(false))))
        XCTAssertEqual(d.user(.commandBar(.queryChanged("swi"))).effects, [], "suggestions off: no fetch")
        d.user(.commandBar(.dismiss))
        assertUnchanged(d.state, d.user(.commandBar(.queryChanged("x"))))
        assertUnchanged(d.state, d.system(.suggestions(d.window, query: "x", ["xy"])))
    }

    /// every real menu action with a listing is a command bar result; rows of later waves are not
    func test_theTypeTravelIndexListsEveryRealAction() {
        let d = Driver()
        d.user(.commandBar(.open(.newTab)))
        let actions = Set(d.bar?.actions ?? [])
        XCTAssertTrue(actions.isSuperset(of: [.newWindow, .showLittleArc, .viewPreferences, .viewLibrary, .viewDownloads, .viewHistory, .changeProfile]))
        XCTAssertFalse(actions.contains(where: { $0.spec.later != nil }))
        XCTAssertEqual(d.bar?.spaces.map(\.isCurrent), [true])
    }

    /// a user override moves a shortcut: the new chord routes, the old one passes to the page
    func test_overridesRouteThroughTheReducer() {
        let d = Driver()
        d.user(.settings(.shortcuts(.setChord(.newTab, KeyChord(.command, .e)))))
        let moved = d.key(KeyChord(.command, .e), stage: .beforePage, pressID: 1)
        XCTAssertTrue(moved.keyHandled)
        XCTAssertNotNil(d.bar)
        d.user(.commandBar(.dismiss))
        XCTAssertFalse(d.key(KeyChord(.command, .t), stage: .beforePage, pressID: 2).keyHandled)
        XCTAssertEqual(d.snapshot.settings.shortcuts.first { $0.action == .newTab }?.state, .valid(KeyChord(.command, .e)))
        XCTAssertEqual(d.snapshot.settings.shortcuts.first { $0.action == .newTab }?.source, .userDefined)
        d.user(.settings(.shortcuts(.setPriority(.reloadPage, .app))))
        XCTAssertTrue(d.key(KeyChord(.command, .r), stage: .beforePage, pressID: 3).keyHandled, "Cmd+R now wins before the page")
        d.user(.settings(.shortcuts(.reset(.newTab))))
        XCTAssertTrue(d.key(KeyChord(.command, .t), stage: .beforePage, pressID: 4).keyHandled)
        d.user(.settings(.shortcuts(.resetAll)))
        XCTAssertFalse(d.key(KeyChord(.command, .r), stage: .beforePage, pressID: 5).keyHandled)
        XCTAssertEqual(Driver(file: d.savedFile).outcome, .restored(repairs: []))
    }

    /// Arc's one default conflict shows as a state on both actions and routes to neither
    func test_theDefaultConflictIsAState() {
        let d = Driver()
        let rows = d.snapshot.settings.shortcuts
        guard case .conflict(_, let with)? = rows.first { $0.action == .newIncognitoWindow }?.state else { return XCTFail("no conflict") }
        XCTAssertEqual(with, [.newFolder])
        XCTAssertFalse(d.key(KeyChord([.shift, .command], .n), stage: .menu, pressID: 1).keyHandled, "a conflicting chord routes to no one, even with a native view focused")
        d.user(.settings(.shortcuts(.setChord(.newIncognitoWindow, nil))))
        XCTAssertEqual(d.snapshot.settings.shortcuts.first { $0.action == .newIncognitoWindow }?.state, .unset)
        XCTAssertTrue(d.key(KeyChord([.shift, .command], .n), stage: .menu, pressID: 2).keyHandled, "unsetting one side frees the chord (New Folder has page priority, so the menu stage)")
        XCTAssertEqual(d.view.renaming, d.pinnedIDs.first, "New Folder ran")
    }

    // MARK: F4 stubs

    func test_suggestRanksTopDomainsAndEngineSuggestionsLikeArc() throws {
        throw XCTSkip("F4: Suggest.rank adds TopDomains.json rows, the engine's suggestions under the typed row, site-search hints (Tab or Space) and Arc's host dedup list")
    }

    func test_everyMenuActionIsReachableByTitleAndTriggers() throws {
        throw XCTSkip("F4: the type-travel index ranks all 65 real actions by title and Arc's trigger words, plus focus/move to space and open preference pane")
    }

    func test_theShortcutsPaneRecordsChordsAndShowsConflicts() throws {
        throw XCTSkip("F4: the Shortcuts pane records a chord, shows Arc's three priorities, 'Reset Shortcut to Default', 'Remove Conflicting Shortcut' (W2-9)")
    }

    func test_theMenuRebuildsWhenOverridesChange() throws {
        throw XCTSkip("F4: MainMenu.build(overrides:) runs again when Doc.keyOverrides changes so key equivalents follow the user")
    }

    func test_theFullEditMenuHasArcsStandardSubmenus() throws {
        throw XCTSkip("F4: Edit > Spelling and Grammar, Substitutions, Transformations, Speech, Format > Font; app Services and Show All; Window Zoom and Bring All to Front")
    }
}
