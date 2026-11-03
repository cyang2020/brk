import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

final class TabToolsSiteTests: XCTestCase {
    private func request(_ transition: Transition) throws -> SiteRequest {
        try XCTUnwrap(transition.effects.compactMap { if case .siteRequest(let r) = $0 { r } else { nil } }.first)
    }
    func testSelectedRepositoryReconcilesLazyRowsAndKeepsIdentity() throws {
        let d = Driver()
        let r = try request(d.user(.tabTools(.site(.connectGitHub(favorite: nil)))))
        let link = PullRequestLink(title: "Fix fixture", url: url("https://github.com/fixture/repo/pull/1"))
        d.system(.siteResult(r.id, .pullRequests(repository: "fixture/repo", [link])))
        guard case .folder(let folder)? = d.view.space.pinned.rows.first else { return XCTFail("missing live folder") }
        XCTAssertEqual(folder.children.count, 1)
        let child = folder.children[0].id
        XCTAssertFalse(d.loadedIDs.contains(child))
        let refresh = try request(d.user(.tabTools(.site(.refreshFolder(folder.id)))))
        d.system(.siteResult(refresh.id, .pullRequests(repository: "fixture/repo", [link])))
        XCTAssertEqual(d.state.doc.tree[folder.id]?.children, [child])
        let empty = try request(d.user(.tabTools(.site(.refreshFolder(folder.id)))))
        d.system(.siteResult(empty.id, .pullRequests(repository: "fixture/repo", [])))
        XCTAssertEqual(d.state.doc.tree[folder.id]?.children, [])
        func live() -> LiveFolderState? { if case .folder(let f)? = d.view.space.pinned.rows.first { f.live?.state } else { nil } }
        XCTAssertEqual(live(), .empty)
        let failed = try request(d.user(.tabTools(.site(.refreshFolder(folder.id)))))
        d.system(.siteResult(failed.id, .failed("Fixture error")))
        XCTAssertEqual(live(), .failed("Fixture error"))
        let restarted = Driver(file: d.savedFile)
        guard case .folder(let restored)? = restarted.state.doc.tree[folder.id]?.body else { return XCTFail("live config lost") }
        XCTAssertEqual(restored.liveRepository, "fixture/repo")
    }
    func testStaleCancelledAndPrivateSourcesCannotPublish() throws {
        let d = Driver()
        let first = try request(d.user(.tabTools(.site(.connectCalendar))))
        let second = try request(d.user(.tabTools(.site(.connectCalendar))))
        let meetings = [CalendarMeeting(title: "Private fixture", url: url("https://example.com/meet"), start: T0, end: T0.advanced(by: hour))]
        d.system(.siteResult(first.id, .calendar(meetings)))
        XCTAssertTrue(d.state.session.calendars.isEmpty)
        d.system(.siteResult(second.id, .cancelled))
        XCTAssertTrue(d.state.session.calendars.isEmpty)
        d.user(.window(.newIncognito))
        let w = try XCTUnwrap(d.snapshot.windows.first { $0.value.kind == .incognito }?.key)
        XCTAssertTrue(d.user(.tabTools(.site(.joinMeeting)), in: w).effects.isEmpty)
        XCTAssertFalse(String(decoding: d.savedFile, as: UTF8.self).contains("Private fixture"))
    }
    func testCalendarMeetingSelectionExpiryFeedbackAndFavoriteBadgeFreshness() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        let favorite = try XCTUnwrap(d.state.doc.favorites[.default])
        d.user(.item(.move(a, to: .into(parent: favorite, index: 0))))
        let badge = try request(d.user(.tabTools(.site(.connectGitHub(favorite: a)))))
        d.system(.siteResult(badge.id, .unread(repository: "fixture/repo", count: 1)))
        XCTAssertEqual(d.view.favorites.tiles[0].badge, 1)
        let request = try request(d.user(.tabTools(.site(.connectCalendar))))
        let expired = CalendarMeeting(title: "Expired", url: url("https://example.com/old"), start: T0.advanced(by: .seconds(-600)), end: T0.advanced(by: .seconds(-1)))
        let next = CalendarMeeting(title: "Next", url: url("https://example.com/meet"), start: T0, end: T0.advanced(by: .seconds(60)))
        d.system(.siteResult(request.id, .calendar([expired, next])))
        d.user(.tabTools(.site(.joinMeeting)))
        XCTAssertEqual(d.snapshot.pages.first { $0.id.item == d.current?.id }?.initialURL, next.url)
        d.advance(.seconds(61))
        d.user(.tabTools(.site(.joinMeeting)))
        XCTAssertTrue(d.view.tabTools.toast?.text.contains("No available meeting") ?? false)
        d.advance(.seconds(300))
        XCTAssertNil(d.view.favorites.tiles.first?.badge)
        XCTAssertFalse(d.state.doc.tabPreferences.hoverPreviews, "previews stay off until turned on in settings")
    }
    func testCalendarFileSupportsFoldedUTCAndTZIDAndRejectsRecurrence() throws {
        let input = "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nDTSTART:20261031T100000Z\r\nDTEND:20261031T110000Z\r\nSUMMARY:Weekly\r\n  meeting\r\nURL:https://example.com/meeting\r\nEND:VEVENT\r\nEND:VCALENDAR"
        let parsed = try CalendarFile.meetings(Data(input.utf8))
        XCTAssertEqual(parsed.count, 1)
        XCTAssertEqual(parsed[0].title, "Weekly meeting")
        XCTAssertEqual(parsed[0].end.since(parsed[0].start), .seconds(3600))
        XCTAssertThrowsError(try CalendarFile.meetings(Data(input.replacingOccurrences(of: "SUMMARY:", with: "RRULE:FREQ=DAILY\r\nSUMMARY:").utf8)))
        XCTAssertThrowsError(try CalendarFile.meetings(Data("bad".utf8)))
    }
    func testGitHubBoundaryDecodesExactLinksAndRejectsBadJSON() throws {
        let data = Data("[{\"title\":\"Fixture pull request\",\"html_url\":\"https://github.com/fixture/repo/pull/1\"}]".utf8)
        XCTAssertEqual(try SiteCodec.pullRequests(data).first?.title, "Fixture pull request")
        XCTAssertThrowsError(try SiteCodec.pullRequests(Data("bad".utf8)))
    }
    func testCachedFavoriteFeedIsRemovedAfterCrossProfileMove() throws {
        let d = Driver(), favorite = d.todayIDs[0]
        d.user(.item(.move(favorite, to: .into(parent: d.state.doc.favorites[.default]!, index: 0))))
        let transition = d.user(.tabTools(.site(.connectGitHub(favorite: favorite))))
        let request = try XCTUnwrap(transition.effects.compactMap { if case .siteRequest(let r) = $0 { r } else { nil } }.first)
        d.system(.siteResult(request.id, .unread(repository: "owner/private", count: 42)))
        XCTAssertEqual(d.view.favorites.tiles.first?.badge, 42)
        d.user(.profile(.create(name: "Other", icon: nil)))
        let profile = try XCTUnwrap(d.snapshot.settings.profiles.first { $0.profile.name == "Other" }?.profile.id)
        d.user(.item(.move(favorite, to: .into(parent: d.state.doc.favorites[profile]!, index: 0))))
        XCTAssertNil(d.state.session.favoriteFeeds[favorite])
    }

    func testNewestCalendarRequestOwnsItsProfileAcrossWindows() throws {
        let d = Driver()
        let first = d.user(.tabTools(.site(.connectCalendar)))
        let older = try XCTUnwrap(first.effects.compactMap { if case .siteRequest(let r) = $0 { r } else { nil } }.first)
        d.user(.window(.new))
        let other = try XCTUnwrap(d.snapshot.windows.keys.first { $0 != d.window })
        let second = d.user(.tabTools(.site(.connectCalendar)), in: other)
        let newer = try XCTUnwrap(second.effects.compactMap { if case .siteRequest(let r) = $0 { r } else { nil } }.first)
        let meeting = CalendarMeeting(title: "New", url: url("https://example.com/new"), start: T0, end: T0.advanced(by: hour))
        d.system(.siteResult(newer.id, .calendar([meeting])))
        d.system(.siteResult(older.id, .calendar([])))
        XCTAssertEqual(d.state.session.calendars[.default]?.meetings, [meeting])
    }

}
