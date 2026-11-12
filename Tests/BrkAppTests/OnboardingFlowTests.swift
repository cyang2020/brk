import AppKit
import BrkBase
import BrkImport
import BrkUIKit
import Foundation
import XCTest
@testable import BrkApp
@testable import BrkDomain

/// The onboarding and Import from Another Browser… flow over a fresh profile's store, with the read answered in place of
/// the other browser's files and the macOS keychain prompt, and an empty folder in place of Application Support (so the
/// steps do not depend on which browsers this Mac has).
@MainActor
final class OnboardingFlowTests: XCTestCase {
    /// Stands in for the keychain prompt: the read waits until `answer()`.
    final class Prompt: @unchecked Sendable {
        private let semaphore = DispatchSemaphore(value: 0)
        func wait() { semaphore.wait() }
        func answer() { semaphore.signal() }
    }

    private var sent: [Input] = []

    private func controller(_ h: Harness, forward: Bool,
                            read: @escaping @Sendable (ImportChoice, @escaping @Sendable (String?) -> Void) -> ImportRead) -> OnboardingController {
        OnboardingController(host: .init(
            snapshot: { h.store.snapshot },
            target: { h.store.state.sidebarImportTarget(in: $0) },
            dispatch: { [unowned self] input in
                self.sent.append(input)
                if forward { h.store.dispatch(input) }
            },
            engine: h.engine,
            now: { Instant(milliseconds: 1_790_000_000_000) },
            showBrowserWindow: { _ in },
            read: read,
            applicationSupport: h.directory.appendingPathComponent("no-browsers", isDirectory: true)))
    }

    nonisolated private static func safari(_ read: ProfileRead) -> ImportRead {
        ImportRead(sourceName: "Safari", kind: .safari,
                   profiles: [ProfileImport(profile: SourceProfile(id: "Safari", name: "Safari", path: URL(fileURLWithPath: "/tmp")), read: read)])
    }

    /// Picks Safari, chooses its export file and starts the read.
    private func importSafari(_ onboarding: OnboardingController) async throws {
        onboarding.handle(.pickBrowser("safari"))
        onboarding.handle(.next)
        onboarding.handle(.useSafariFile(URL(fileURLWithPath: "/tmp/Safari Export.zip")))
        onboarding.handle(.next)
        try await waitFor("the read finished") { onboarding.state.progressDone }
    }

    private func waitFor(_ what: String, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() {
            guard Date() < deadline else { return XCTFail("timed out: \(what)") }
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    /// While macOS asks for the computer password, Back is off: leaving the keychain screen let the answered read take
    /// over whatever screen was showing, or run beside a second import.
    func testBackIsOffWhileTheKeychainPromptIsUp() async throws {
        let h = Harness(); defer { h.cleanUp() }
        let prompt = Prompt()
        defer { prompt.answer() }
        let onboarding = controller(h, forward: false) { _, waiting in
            waiting("Default")
            prompt.wait()
            waiting(nil)
            return ImportRead(sourceName: "Chrome", kind: .chrome)
        }
        onboarding.open(mode: .importOnly, owner: h.window)
        defer { onboarding.close() }
        onboarding.handle(.pickBrowser("chrome"))
        onboarding.handle(.next)
        XCTAssertEqual(onboarding.state.step, .keychain, "no Chrome profiles found, so no profile step")
        onboarding.handle(.next)
        XCTAssertTrue(onboarding.state.waitingForPassword)
        XCTAssertFalse(onboarding.state.canGoBack)
        onboarding.handle(.back)
        XCTAssertEqual(onboarding.state.step, .keychain)
        prompt.answer()
        try await waitFor("the read finished") { onboarding.state.progressDone }
        XCTAssertEqual(onboarding.state.step, .progress)
    }

    /// The import lands where it started: switching the browser window to another profile's Space before clicking
    /// Import does not send the bookmarks and history there while the passwords and cookies went to the first.
    func testTheImportLandsInTheSpaceItStartedFrom() async throws {
        let h = Harness(); defer { h.cleanUp() }
        let home = try XCTUnwrap(h.store.state.sidebarImportTarget(in: h.window))
        h.store.dispatch(.user(h.window, .profile(.create(name: "Work", icon: nil))))
        let work = try XCTUnwrap(h.store.snapshot.settings.profiles.first { $0.profile.name == "Work" }?.profile.id)
        h.store.dispatch(.user(h.window, .space(.create(title: "Work", icon: .none, theme: .default, profile: work))))
        let workSpace = try XCTUnwrap(h.store.state.sidebarImportTarget(in: h.window)?.space)
        XCTAssertNotEqual(workSpace, home.space)
        XCTAssertEqual(h.store.state.doc.spaces[workSpace]?.profile, work)
        h.store.dispatch(.user(h.window, .space(.focus(home.space))))
        let visit = ImportedVisit(url: URL(string: "https://visited.example.test/")!, title: "Visited", visitedAt: Instant(milliseconds: 1_789_000_000_000))
        let onboarding = controller(h, forward: true) { _, _ in
            var read = ProfileRead()
            read.bookmarks = [.tab(title: "Doc", url: URL(string: "https://doc.example.test/")!)]
            read.visits = [visit]
            return Self.safari(read)
        }
        onboarding.open(mode: .importOnly, owner: h.window)
        defer { onboarding.close() }
        try await importSafari(onboarding)
        onboarding.handle(.next)
        XCTAssertEqual(onboarding.state.step, .bookmarks)
        h.store.dispatch(.user(h.window, .space(.focus(workSpace))))
        onboarding.handle(.next)
        func folders(_ space: SpaceID) -> [String] {
            let doc = h.store.state.doc
            return (doc.spaces[space].flatMap { doc.tree[$0.pinnedRoot]?.children } ?? []).compactMap { id in
                if case .folder(let folder)? = doc.tree[id]?.body { folder.title } else { nil }
            }
        }
        XCTAssertEqual(folders(home.space), ["Imported from Safari"])
        XCTAssertEqual(folders(workSpace), [])
        XCTAssertEqual(h.store.state.doc.history.filter { $0.url == visit.url }.map(\.profile), [home.profile])
    }

    /// "Not now" on the Max step after Enable Max and Back turns Max off again: the last answer counts.
    func testNotNowAfterEnableAndBackTurnsMaxOff() throws {
        let h = Harness(); defer { h.cleanUp() }
        let onboarding = controller(h, forward: false) { _, _ in ImportRead(sourceName: "", kind: nil) }
        onboarding.open(mode: .firstRun, owner: h.window)
        defer { onboarding.close() }
        for action in [OnboardingAction.next, .next, .skip, .next, .next, .next] { onboarding.handle(action) }
        XCTAssertEqual(onboarding.state.step, .max)
        onboarding.handle(.next)
        XCTAssertEqual(onboarding.state.step, .defaultBrowser, "a test process is not the default browser")
        onboarding.handle(.back)
        XCTAssertEqual(onboarding.state.step, .max)
        onboarding.handle(.skip)
        let maxAnswers = sent.compactMap { input -> Bool? in
            if case .user(_, .settings(.max(.enable(let on)))) = input { return on }
            return nil
        }
        XCTAssertEqual(maxAnswers, [true, false])
    }

    /// Skipping the import, going Back and importing after all offers the imported browser's most visited sites on the
    /// Favorites step, the top four picked, not the built-in list the skip filled.
    func testFavoritesOfferTheImportedSitesAfterSkipAndBack() async throws {
        let h = Harness(); defer { h.cleanUp() }
        let visited = (1...6).map { SourceTopSite(title: "Site \($0)", url: URL(string: "https://site\($0).example.test/")!, score: 100 - $0) }
        let onboarding = controller(h, forward: true) { _, _ in
            var read = ProfileRead()
            read.topSites = visited
            return Self.safari(read)
        }
        onboarding.open(mode: .firstRun, owner: h.window)
        defer { onboarding.close() }
        onboarding.handle(.next)
        onboarding.handle(.next)
        XCTAssertEqual(onboarding.state.step, .pickBrowser)
        onboarding.handle(.skip)
        XCTAssertEqual(onboarding.state.step, .favorites)
        onboarding.handle(.back)
        XCTAssertEqual(onboarding.state.step, .pickBrowser)
        try await importSafari(onboarding)
        onboarding.handle(.next)
        XCTAssertEqual(onboarding.state.step, .favorites)
        XCTAssertEqual(onboarding.state.sites.map(\.id), visited.map(\.url.absoluteString))
        XCTAssertEqual(onboarding.state.sites.filter(\.selected).map(\.id), visited.prefix(4).map(\.url.absoluteString))
    }
}
