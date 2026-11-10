import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

/// Owner: F4. The command bar's wave-2 contract: the profile's search engine, site search, search suggestions
/// through the effect and event pair, the type-travel index (every real menu action is a result), shortcut
/// remapping with conflicts.
final class CommandBarWave2SpecTests: XCTestCase {
    /// What goes to the search engine; the file and app sources' own effect has CommandBarQuickSourcesTests.
    private func notLocalSearch(_ effect: Effect) -> Bool {
        if case .searchLocal = effect { return false }
        return true
    }

    /// a search uses the current space's profile's default engine
    func test_searchesUseTheProfilesEngine() {
        let d = Driver()
        d.user(.settings(.profile(.default, .searchEngine(SearchEngine.duckDuckGo.id))))
        d.user(.commandBar(.open(.newTab)))
        XCTAssertEqual(d.bar?.engine.name, "DuckDuckGo")
        // The other built-ins, then the sites the bar offers site search on beside the input (P02-c, Q01-b).
        XCTAssertEqual(d.bar?.siteSearch.map(\.keyword), ["google", "bing", "ecosia", "kagi", "wikipedia.org", "youtube.com", "docs.google.com", "drive.google.com", "maps.google.com", "github.com", "amazon.com", "reddit.com"])
        d.user(.commandBar(.submit("arc browser")))
        XCTAssertEqual(d.current?.url, url("https://duckduckgo.com/?q=arc%20browser"))
    }

    /// typing asks the engine for suggestions (an effect with the suggest URL) when the profile allows it; the answer is projected with its query
    func test_suggestionsGoThroughTheEffectAndEventPair() {
        let d = Driver()
        d.user(.commandBar(.open(.newTab)))
        let t = d.user(.commandBar(.queryChanged("swi")))
        XCTAssertEqual(t.effects.filter(notLocalSearch), [.fetchSuggestions(d.window, query: "swi", url: url("https://www.google.com/complete/search?client=chrome-omni&gs_ri=chrome-ext-ansg&xssi=t&q=swi"))])
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

    /// type travel lists the real actions that do something in this window now (Arc indexes its menu with each
    /// item's enabled state): never a later-wave row, Go Back only with history, the one Pinned row that applies;
    /// each with its shortcut as routing resolves it
    func test_theTypeTravelIndexListsWhatTheWindowCanDo() {
        let d = Driver()
        d.user(.commandBar(.open(.newTab)))
        let actions = Set(d.bar?.actions ?? [])
        XCTAssertTrue(actions.isSuperset(of: [.newWindow, .showLittleArc, .viewPreferences, .viewLibrary, .viewDownloads, .viewHistory, .changeProfile,
                                              .appearanceDark, .quitArc, .exit]))
        XCTAssertFalse(actions.contains(where: { $0.spec.later != nil }))
        XCTAssertFalse(actions.contains(.goBack), "the start page has no history to go back to")
        XCTAssertFalse(actions.contains(.reopenLastClosedTab), "nothing has been closed")
        XCTAssertTrue(actions.contains(.collapsePinnedSection))
        XCTAssertFalse(actions.contains(.expandPinnedSection), "Pinned is already expanded")
        XCTAssertFalse(actions.contains(.newTab), "the bar's own opener is not a result")
        XCTAssertEqual(d.bar?.spaces.map(\.isCurrent), [true])
        XCTAssertEqual(d.bar?.keys[.newWindow], KeyChord(.command, .n))
        XCTAssertNil(d.bar?.keys[.viewArchive], "no shortcut, no hint")

        d.user(.commandBar(.dismiss))
        d.user(.tab(.close(.focused)))
        d.user(.space(.togglePinnedSection(.current)))
        d.user(.settings(.shortcuts(.setChord(.newWindow, KeyChord([.option, .command], .w)))))
        d.user(.commandBar(.open(.newTab)))
        XCTAssertTrue(d.bar?.actions.contains(.reopenLastClosedTab) ?? false)
        XCTAssertTrue(d.bar?.actions.contains(.expandPinnedSection) ?? false)
        XCTAssertFalse(d.bar?.actions.contains(.collapsePinnedSection) ?? true)
        XCTAssertEqual(d.bar?.keys[.newWindow], KeyChord([.option, .command], .w), "the hint follows the user's shortcut")
    }

    /// a new opening starts without the last opening's suggestions, and switching suggestions off drops the ones
    /// shown at the next keystroke (W2-10's second half)
    func test_staleSuggestionsAreDropped() throws {
        let d = Driver()
        d.user(.commandBar(.open(.newTab)))
        d.user(.commandBar(.queryChanged("swi")))
        d.system(.suggestions(d.window, query: "swi", ["swift", "swim"]))
        XCTAssertEqual(d.bar?.suggestions, ["swift", "swim"])
        d.user(.commandBar(.dismiss))
        d.user(.commandBar(.open(.newTab)))
        XCTAssertEqual(d.bar?.suggestions, [])
        XCTAssertNil(d.bar?.suggestedFor)

        // A second window's bar stays open while the setting changes from the first (a settings command closes only
        // the dispatching window's bar); its next keystroke drops what it was showing and asks for nothing.
        d.user(.window(.new))
        let other = try XCTUnwrap(d.snapshot.windows.keys.first { $0 != d.window })
        d.user(.commandBar(.open(.newTab)), in: other)
        d.user(.commandBar(.queryChanged("swi")), in: other)
        d.system(.suggestions(other, query: "swi", ["swift", "swim"]))
        d.user(.settings(.profile(.default, .searchSuggestions(false))))
        XCTAssertEqual(d.user(.commandBar(.queryChanged("swim")), in: other).effects.filter(notLocalSearch), [])
        guard case .commandBar(let bar)? = d.view(of: other).overlay else { return XCTFail("the other bar closed") }
        XCTAssertEqual(bar.suggestions, [])
    }

    /// the Shortcuts pane's remedies, as commands: a chord the user puts on a taken key is a conflict on both rows
    /// naming each other and routes to no one; "Remove Conflicting Shortcut" unsets the other action, so the chord
    /// works; "Reset Shortcut to Default" and "Reset All Shortcuts" put the table back; a priority is per shortcut
    func test_shortcutRowsShowConflictsAndTheirRemedies() {
        let d = Driver()
        let cmdT = KeyChord(.command, .t)
        d.user(.settings(.shortcuts(.setChord(.reloadPage, cmdT))))
        func row(_ action: ActionID) -> ShortcutRow? { d.snapshot.settings.shortcuts.first { $0.action == action } }
        XCTAssertEqual(row(.reloadPage)?.state, .conflict(cmdT, with: [.newTab]))
        XCTAssertEqual(row(.newTab)?.state, .conflict(cmdT, with: [.reloadPage]))
        XCTAssertEqual(row(.newTab)?.source, .default)
        XCTAssertFalse(d.key(cmdT, stage: .beforePage, pressID: 1).keyHandled, "a conflicting chord routes to no one")
        XCTAssertNil(d.bar)

        d.user(.settings(.shortcuts(.setChord(.newTab, nil))))   // Remove Conflicting Shortcut, on Reload's row
        XCTAssertEqual(row(.reloadPage)?.state, .valid(cmdT))
        XCTAssertEqual(row(.newTab)?.state, .unset)
        XCTAssertEqual(row(.newTab)?.source, .userDefined)
        XCTAssertFalse(d.key(cmdT, stage: .beforePage, pressID: 2).keyHandled, "Reload keeps its page priority: the page goes first")
        XCTAssertTrue(d.key(cmdT, stage: .afterPage, pressID: 2).keyHandled, "and Reload runs when the page passes")

        d.user(.settings(.shortcuts(.setPriority(.reloadPage, .app))))
        XCTAssertEqual(row(.reloadPage)?.priority, .app)
        XCTAssertTrue(d.key(cmdT, stage: .beforePage, pressID: 3).keyHandled)

        d.user(.settings(.shortcuts(.reset(.newTab))))            // Reset Shortcut to Default
        XCTAssertEqual(row(.newTab)?.source, .default)
        XCTAssertEqual(row(.newTab)?.state, .conflict(cmdT, with: [.reloadPage]))
        d.user(.settings(.shortcuts(.resetAll)))                  // Reset All Shortcuts
        XCTAssertEqual(row(.newTab)?.state, .valid(cmdT))
        XCTAssertEqual(row(.reloadPage)?.state, .valid(KeyChord(.command, .r)))
        XCTAssertEqual(row(.reloadPage)?.priority, .page)
        XCTAssertTrue(d.snapshot.settings.shortcuts.allSatisfy { $0.source == .default })
    }
}
