import BrkBase
import BrkDomain
import Foundation
import XCTest
@testable import BrkApp

@MainActor final class IndependentBrowserBasicNetworkReviewTests: XCTestCase {
    func testEngineChangeCancelsPreviousProviderBeforeDebounce() async throws {
        StubSuggest.reset()
        let ctx = Context(now: Instant(milliseconds: 1_790_000_000_000), newID: { UUID().uuidString })
        var state = StateCodec.restore(nil, seed: RestoreSeed(startURL: nil, contentSize: CGSize(width: 1280, height: 776)), ctx: ctx).state
        func snapshot() -> AppSnapshot { project(state, ProjectionContext(now: ctx.now, calendar: Calendar(identifier: .gregorian))) }
        let original = try XCTUnwrap(snapshot().windows.keys.first)
        state = reduce(state, .user(original, .window(.new)), ctx).state
        let settingsOwner = try XCTUnwrap(snapshot().windows.keys.first { $0 != original })
        state = reduce(state, .user(settingsOwner, .settings(.profile(.default, .searchSuggestions(true)))), ctx).state
        state = reduce(state, .user(original, .commandBar(.open(.newTab))), ctx).state
        let request = reduce(state, .user(original, .commandBar(.queryChanged("owned-fixture-query"))), ctx)
        state = request.state
        guard case .fetchSuggestions(let owner, let query, let endpoint)? = request.effects.first else { return XCTFail("Missing initial network request") }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubSuggest.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        var received: [Input] = []
        let fetcher = SuggestionFetcher(send: { received.append($0) }, session: session, override: nil)
        fetcher.fetch(owner, query: query, url: endpoint)
        state = reduce(state, .user(settingsOwner, .settings(.profile(.default, .searchEngine(SearchEngine.bing.id)))), ctx).state
        guard case .commandBar(let bar)? = snapshot().windows[original]?.overlay else { return XCTFail("Other window's command bar should stay open") }
        XCTAssertEqual(bar.engine.id, SearchEngine.bing.id)
        fetcher.reconcile(snapshot())
        try await Task.sleep(for: .milliseconds(650))
        print("REPRO switched to Bing: requested=\(StubSuggest.urls.map(\.absoluteString)), delivered=\(received.count)")
        XCTAssertTrue(StubSuggest.urls.isEmpty, "The old provider request must be cancelled before debounce expires")
        XCTAssertTrue(received.isEmpty, "An old provider must not publish into the newly configured engine's bar")
        fetcher.cancel(owner)
    }
    func testProfileChangedFromAnotherWindowCancelsPendingRequest() async throws {
        StubSuggest.reset()
        let ctx = Context(now: Instant(milliseconds: 1_790_000_000_000), newID: { UUID().uuidString })
        var state = StateCodec.restore(nil, seed: RestoreSeed(startURL: nil, contentSize: CGSize(width: 1280, height: 776)), ctx: ctx).state
        func snapshot() -> AppSnapshot { project(state, ProjectionContext(now: ctx.now, calendar: Calendar(identifier: .gregorian))) }
        let owner = try XCTUnwrap(snapshot().windows.keys.first)
        state = reduce(state, .user(owner, .window(.new)), ctx).state
        let other = try XCTUnwrap(snapshot().windows.keys.first { $0 != owner })
        state = reduce(state, .user(other, .profile(.create(name: "Other", icon: nil))), ctx).state
        let profile = try XCTUnwrap(snapshot().settings.profiles.first { $0.profile.id != .default }?.profile.id)
        for id in [ProfileID.default, profile] {
            state = reduce(state, .user(other, .settings(.profile(id, .searchSuggestions(true)))), ctx).state
        }
        state = reduce(state, .user(owner, .commandBar(.open(.newTab))), ctx).state
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [StubSuggest.self]
        let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
        var replies: [Input] = []
        let fetcher = SuggestionFetcher(send: { replies.append($0) }, session: session, override: nil)
        fetcher.reconcile(snapshot())
        let root = try XCTUnwrap(snapshot().windows[owner]?.favorites.root)
        fetcher.fetch(owner, query: "owned-profile-query", url: try XCTUnwrap(SearchEngine.google.suggestURL("owned-profile-query")))
        state = reduce(state, .user(other, .profile(.assign(.current, to: profile))), ctx).state
        guard case .commandBar(let bar)? = snapshot().windows[owner]?.overlay else { return XCTFail("Other window's bar closed") }
        XCTAssertTrue(bar.suggestionsEnabled)
        XCTAssertNotEqual(snapshot().windows[owner]?.favorites.root, root)
        fetcher.reconcile(snapshot())
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertTrue(StubSuggest.urls.isEmpty)
        XCTAssertTrue(replies.isEmpty)
        fetcher.cancel(owner)
    }

    func testCapturedCurrentConfigurationDeliversSuggestions() async throws {
        StubSuggest.reset()
        let ctx = Context(now: Instant(milliseconds: 1_790_000_000_000), newID: { UUID().uuidString })
        var state = StateCodec.restore(nil, seed: RestoreSeed(startURL: nil, contentSize: CGSize(width: 1280, height: 776)), ctx: ctx).state
        let context = ProjectionContext(now: ctx.now, calendar: Calendar(identifier: .gregorian))
        let owner = try XCTUnwrap(project(state, context).windows.keys.first)
        state = reduce(state, .user(owner, .settings(.profile(.default, .searchSuggestions(true)))), ctx).state
        state = reduce(state, .user(owner, .commandBar(.open(.newTab))), ctx).state
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [StubSuggest.self]
        let session = URLSession(configuration: configuration); defer { session.invalidateAndCancel() }
        var replies: [Input] = []
        let fetcher = SuggestionFetcher(send: { replies.append($0) }, session: session, override: nil)
        fetcher.reconcile(project(state, context))
        fetcher.fetch(owner, query: "owned-current-query", url: try XCTUnwrap(SearchEngine.google.suggestURL("owned-current-query")))
        try await Task.sleep(for: .milliseconds(650))
        XCTAssertEqual(StubSuggest.asked, ["owned-current-query"])
        XCTAssertEqual(replies.count, 1)
        fetcher.cancel(owner)
    }

}
