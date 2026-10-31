import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

final class SidebarToolsTests: XCTestCase {
    private func request(_ transition: Transition) throws -> SiteRequest {
        try XCTUnwrap(transition.effects.compactMap { if case .siteRequest(let r) = $0 { r } else { nil } }.first)
    }
    func testSourceStatusNeverPresentsExpiredOrFailedUnreadAsFresh() throws {
        let d = Driver()
        let item = d.todayIDs[0]
        let root = try XCTUnwrap(d.state.doc.favorites[.default])
        d.user(.item(.move(item, to: .into(parent: root, index: 0))))
        let req = try request(d.user(.tabTools(.site(.connectGitHub(favorite: item)))))
        XCTAssertEqual(d.view.favorites.tiles.first?.sourceStatus, "Connecting…")
        d.system(.siteResult(req.id, .unread(repository: "fixture/repo", count: 7)))
        XCTAssertEqual(d.view.favorites.tiles.first?.badge, 7)
        XCTAssertTrue(d.view.favorites.tiles.first?.sourceStatus?.hasPrefix("Updated") == true)
        d.advance(.seconds(301))
        XCTAssertNil(d.view.favorites.tiles.first?.badge)
        XCTAssertEqual(d.view.favorites.tiles.first?.sourceStatus, "Expired · reconnect")
        let retry = try request(d.user(.tabTools(.site(.connectGitHub(favorite: item)))))
        d.system(.siteResult(retry.id, .failed("Token revoked")))
        XCTAssertNil(d.view.favorites.tiles.first?.badge)
        XCTAssertEqual(d.view.favorites.tiles.first?.sourceStatus, "Access failed · reconnect")
        XCTAssertFalse(String(decoding: d.savedFile, as: UTF8.self).contains("Token revoked"))
    }
    func testExplicitCalendarSelectionStaysScopedAndRequiresAFile() throws {
        let d = Driver()
        XCTAssertTrue(d.user(.tabTools(.site(.selectCalendar(url("https://example.com/events.ics"), join: false)))).effects.allSatisfy {
            if case .siteRequest = $0 { return false }; return true
        })
        let file = URL(fileURLWithPath: "/tmp/brk-sidebar-fixture.ics")
        let selected = try request(d.user(.tabTools(.site(.selectCalendar(file, join: true)))))
        XCTAssertEqual(selected.kind, .calendarFile(file, join: true))
        let meeting = CalendarMeeting(title: "Fixture", url: url("https://example.com/meeting"), start: T0, end: T0.advanced(by: .seconds(60)))
        d.system(.siteResult(selected.id, .calendar([meeting])))
        XCTAssertEqual(d.current?.url, meeting.url)
        d.advance(.seconds(61)); d.user(.tabTools(.site(.joinMeeting)))
        XCTAssertTrue(d.view.tabTools.toast?.text.contains("No available meeting") == true)
        d.advance(.seconds(241)); _ = try request(d.user(.tabTools(.site(.joinMeeting))))
        XCTAssertTrue(d.view.tabTools.toast?.text.contains("expired") == true)
        let restored = Driver(file: d.savedFile)
        XCTAssertTrue(restored.state.session.calendars.isEmpty)
    }
    func testCalendarSubtitleAndSourceExpiryAreProjectedWithoutSavingMeetings() throws {
        let d = Driver(startURL: url("https://calendar.google.com/"))
        let item = d.todayIDs[0]
        let root = try XCTUnwrap(d.state.doc.favorites[.default])
        d.user(.item(.move(item, to: .into(parent: root, index: 0))))
        XCTAssertEqual(d.view.favorites.tiles.first?.sourceStatus, "Select calendar export")
        let selected = try request(d.user(.tabTools(.site(.connectCalendar))))
        d.system(.siteResult(selected.id, .calendar([CalendarMeeting(title: "Planning", url: url("https://example.com/meet"), start: T0, end: T0.advanced(by: hour))])))
        XCTAssertEqual(d.view.favorites.tiles.first?.subtitle, "Planning")
        d.advance(.seconds(300))
        XCTAssertNil(d.view.favorites.tiles.first?.subtitle)
        XCTAssertEqual(d.view.favorites.tiles.first?.sourceStatus, "Calendar expired · select again")
        XCTAssertFalse(String(decoding: d.savedFile, as: UTF8.self).contains("Planning"))
    }
    func testProgressUsesRealReadingsAndClearsAtAllTerminalPaths() {
        let d = Driver()
        let item = d.todayIDs[0]
        d.page(item, .loadingChanged(isLoading: true, canGoBack: false, canGoForward: false))
        d.page(item, .loadProgress(0.42))
        XCTAssertEqual(d.view.urlPill.loadProgress, 0.42)
        d.page(item, .navigationRequested(url("https://example.com/replacement")))
        XCTAssertEqual(d.view.urlPill.loadProgress, 0)
        d.page(item, .loadProgress(0.42))
        d.page(item, .loadProgress(0.1)); d.page(item, .loadProgress(.nan))
        XCTAssertEqual(d.view.urlPill.loadProgress, 0.42)
        d.page(item, .loadingChanged(isLoading: false, canGoBack: false, canGoForward: false))
        XCTAssertEqual(d.view.urlPill.loadProgress, 0)
        d.page(item, .loadProgress(0.9)); XCTAssertEqual(d.view.urlPill.loadProgress, 0)
        for terminal in [PageEvent.loadFailed(code: -2, description: "Fixture", url: start.absoluteString), .rendererGone] {
            d.page(item, .loadingChanged(isLoading: true, canGoBack: false, canGoForward: false)); d.page(item, .loadProgress(0.6))
            d.page(item, terminal)
            XCTAssertFalse(d.view.urlPill.loading); XCTAssertEqual(d.view.urlPill.loadProgress, 0)
        }
        d.page(item, .loadingChanged(isLoading: true, canGoBack: false, canGoForward: false)); d.page(item, .loadProgress(0.7))
        d.user(.page(.stop(.focused)))
        XCTAssertFalse(d.view.urlPill.loading); XCTAssertEqual(d.view.urlPill.loadProgress, 0)
    }
    func testSecondCrashStaysSadUntilExplicitReload() throws {
        let d = Driver()
        let item = d.todayIDs[0], page = PageID(window: d.window, item: d.todayIDs[0])
        XCTAssertTrue(d.page(item, .rendererGone).effects.contains(.page(page, .recover)))
        d.page(item, .committed(start))
        XCTAssertFalse(d.state.session.live[page]?.crashed ?? true)
        XCTAssertFalse(d.page(item, .rendererGone).effects.contains(.page(page, .recover)))
        XCTAssertEqual(d.view.content.panes.first?.content, .crashed(page))
        XCTAssertTrue(d.user(.page(.reload(.focused, ignoringCache: false))).effects.contains(.page(page, .recover)))
        XCTAssertFalse(d.page(item, .rendererGone).effects.contains(.page(page, .recover)))
        d.page(item, .committed(start))
        XCTAssertEqual(d.view.content.panes.first?.content, .page(page))
    }
    func testAllIconKindsSurviveRestartAndClear() throws {
        let d = Driver()
        let item = d.todayIDs[0]
        for icon in NamedIcon.allCases.map({ CustomIcon.named($0) }) + [.emoji("🧑🏽‍🚀"), .symbol("sparkles")] {
            d.user(.item(.setIcon(item, icon)))
            let restored = Driver(file: d.savedFile)
            XCTAssertEqual(restored.row(item)?.icon, icon)
        }
        d.user(.item(.setIcon(item, nil)))
        XCTAssertNil(Driver(file: d.savedFile).row(item)?.icon)
        d.user(.tabTools(.preferences(includeFavorites: true, previews: false)))
        XCTAssertFalse(d.snapshot.pages[0].hoverPreviews)
        XCTAssertFalse(Driver(file: d.savedFile).snapshot.pages[0].hoverPreviews)
    }
}
