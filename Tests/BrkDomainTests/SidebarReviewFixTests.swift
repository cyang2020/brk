import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

/// Round 4, R4-9: the R4-6 review's defects in the domain (verify/completion/review-r4/sidebar-windows/REVIEW.md):
/// a cancelled reconnect keeps a good badge (A014), Ctrl+Cmd+J answers in every window and tells an unreadable file
/// from an expired one (A015), Gmail and Outlook Favorites get a mail card (A031). The last Today tab's successor is
/// Arc's as it was (checked on real Arc by the parent); its tests document that rule.
final class SidebarReviewFixTests: XCTestCase {
    private func request(_ transition: Transition) throws -> SiteRequest {
        try XCTUnwrap(transition.effects.compactMap { if case .siteRequest(let r) = $0 { r } else { nil } }.first)
    }

    func testCancellingAReconnectKeepsTheUnreadDot() throws {
        let d = Driver(startURL: url("https://github.com/notifications"))
        let item = d.todayIDs[0]
        let root = try XCTUnwrap(d.state.doc.favorites[.default])
        d.user(.item(.move(item, to: .into(parent: root, index: 0))))
        let first = try request(d.user(.tabTools(.site(.connectGitHub(favorite: item)))))
        d.system(.siteResult(first.id, .unread(repository: "fixture/repo", count: 2)))
        XCTAssertEqual(d.view.favorites.tiles.first?.badgeTint, .black)
        let again = try request(d.user(.tabTools(.site(.connectGitHub(favorite: item)))))
        d.system(.siteResult(again.id, .cancelled))
        let tile = try XCTUnwrap(d.view.favorites.tiles.first)
        XCTAssertEqual(tile.badge, 2, "the cancelled sheet replaced the count")
        XCTAssertEqual(tile.badgeTint, .black, "the unread dot went away")
        XCTAssertEqual(d.view.tabTools.toast?.text, "Source selection cancelled")
    }

    func testCancellingTheFirstConnectStillSaysSo() throws {
        let d = Driver(startURL: url("https://github.com/notifications"))
        let item = d.todayIDs[0]
        let root = try XCTUnwrap(d.state.doc.favorites[.default])
        d.user(.item(.move(item, to: .into(parent: root, index: 0))))
        let first = try request(d.user(.tabTools(.site(.connectGitHub(favorite: item)))))
        d.system(.siteResult(first.id, .cancelled))
        XCTAssertNil(d.view.favorites.tiles.first?.badgeTint)
        XCTAssertEqual(d.state.session.favoriteFeeds[item]?.access, .cancelled)
    }

    func testJoinMeetingInAPrivateWindowOrLittleArcSaysWhyNothingOpens() throws {
        let d = Driver()
        let calendar = try request(d.user(.tabTools(.site(.connectCalendar))))
        let meeting = CalendarMeeting(title: "Now", url: url("https://example.com/meet"), start: T0, end: T0.advanced(by: .seconds(600)))
        d.system(.siteResult(calendar.id, .calendar([meeting])))
        for command in [Command.window(.newIncognito), .window(.newLittle(url("https://example.com/little")))] {
            let before = Set(d.snapshot.windows.keys)
            d.user(command)
            let w = try XCTUnwrap(d.snapshot.windows.keys.first { !before.contains($0) })
            let transition = d.user(.tabTools(.site(.joinMeeting)), in: w)
            XCTAssertTrue(transition.effects.compactMap { if case .siteRequest(let r) = $0 { r } else { nil } }.isEmpty, "\(command) asked for a source")
            XCTAssertEqual(d.view(of: w).tabTools.toast?.text, TopAppCopy.joinMeetingNeedsStandardWindow, "\(command) gave no feedback")
            XCTAssertFalse(d.snapshot.pages.contains { $0.initialURL == meeting.url }, "\(command) opened the meeting")
        }
    }

    func testJoinMeetingAfterAnUnreadableFileSaysTheFileIsUnreadable() throws {
        let d = Driver()
        let file = URL(fileURLWithPath: "/tmp/bad.ics")
        let selected = try request(d.user(.tabTools(.site(.selectCalendar(file, join: true)))))
        d.system(.siteResult(selected.id, .failed("Calendar could not be read. Select a nonrecurring .ics export with HTTPS meeting URLs.")))
        let again = d.user(.tabTools(.site(.joinMeeting)))
        let retry = try request(again)
        XCTAssertEqual(retry.kind, .calendar(join: true), "the file panel is offered again")
        XCTAssertEqual(d.view.tabTools.toast?.text, TopAppCopy.calendarUnreadable)
        XCTAssertFalse(d.view.tabTools.toast?.text.contains("expired") ?? true)
        // An expired good calendar still says expired.
        let good = CalendarMeeting(title: "Later", url: url("https://example.com/meet"), start: T0.advanced(by: .seconds(60)), end: T0.advanced(by: .seconds(600)))
        d.system(.siteResult(retry.id, .calendar([good])))
        d.advance(.seconds(301))
        _ = try request(d.user(.tabTools(.site(.joinMeeting))))
        XCTAssertTrue(d.view.tabTools.toast?.text.contains("expired") ?? false)
    }

    // Arc 1.170, checked by the parent on 2026-11-04: closing the last Today tab shows the pinned tab the window used
    // most recently; only without one is the content area the empty card (Q02-b). Brk already does this.
    func testClosingTheLastTodayTabShowsTheRecentlyUsedPinnedTab() throws {
        let d = Driver()
        let pinned = d.open("https://example.com/pinned")
        d.user(.tab(.togglePin(.focused)))
        XCTAssertTrue(d.pinnedIDs.contains(pinned))
        let last = d.open("https://example.com/last")
        d.user(.tab(.focus(pinned)))
        d.advance(.seconds(5))
        d.user(.tab(.focus(last)))
        for id in d.todayIDs where id != last { d.user(.tab(.close(.item(id)))) }
        XCTAssertEqual(d.current?.id, last, "closing a tab that is not shown changed the selection")
        d.user(.tab(.close(.item(last))))
        XCTAssertTrue(d.todayIDs.isEmpty)
        XCTAssertEqual(d.current?.id, pinned, "Arc shows the pinned tab used last")
        XCTAssertEqual(d.paneIDs, [pinned])
    }

    func testClosingTheLastTodayTabWithoutARecentlyUsedPinnedTabShowsTheEmptyCard() throws {
        let d = Driver()
        let pinned = d.open("https://example.com/pinned")
        d.user(.tab(.togglePin(.focused)))
        let last = d.open("https://example.com/last")
        // Close and Keep Pinned: the pinned row stays, its page is gone, so it is not a tab in use.
        d.user(.tab(.close(.item(pinned))))
        XCTAssertFalse(d.loadedIDs.contains(pinned))
        for id in d.todayIDs where id != last { d.user(.tab(.close(.item(id)))) }
        d.user(.tab(.close(.item(last))))
        XCTAssertNil(d.current, "nothing is shown (Q02-b's empty card)")
        XCTAssertTrue(d.paneIDs.isEmpty)
    }

    // MARK: Mail previews (A031)

    func testMailboxTitlesGiveTheUnreadCountAndMessageTitlesTheSubject() {
        XCTAssertEqual(TopAppCopy.unreadCount(inMailboxTitle: "Inbox (3) - fixture@example.com - Gmail"), 3)
        XCTAssertEqual(TopAppCopy.unreadCount(inMailboxTitle: "Inbox - fixture@example.com - Gmail"), 0)
        XCTAssertEqual(TopAppCopy.unreadCount(inMailboxTitle: "(12) Mail - Fixture Person - Outlook"), 12)
        XCTAssertNil(TopAppCopy.unreadCount(inMailboxTitle: "Quarterly plan - fixture@example.com - Gmail"))
        XCTAssertNil(TopAppCopy.unreadCount(inMailboxTitle: "Inbox zero tips"))
        XCTAssertEqual(TopAppCopy.mailSubject("Quarterly plan - fixture@example.com - Gmail"), "Quarterly plan")
        XCTAssertEqual(TopAppCopy.mailSubject("Re: Plan - draft - fixture@example.com - Gmail"), "Re: Plan - draft")
        XCTAssertEqual(TopAppCopy.mailSubject("Lunch? - Fixture Person - Outlook"), "Lunch?")
        XCTAssertEqual(TopAppCopy.mailSubject("Plain title"), "Plain title")
    }

    func testAGmailFavoriteShowsArcsSignedOutTextUntilBrkHasSeenTheMailbox() throws {
        let d = Driver(startURL: url("https://mail.google.com/mail/u/0/"))
        let gmail = d.todayIDs[0]
        let root = try XCTUnwrap(d.state.doc.favorites[.default])
        d.user(.item(.move(gmail, to: .into(parent: root, index: 0))))
        let tile = { d.view.favorites.tiles.first { $0.id == gmail } }
        XCTAssertNil(tile()?.hoverCard, "Arc Previews are off by default")
        d.user(.tabTools(.preferences(includeFavorites: true, previews: true)))
        guard case .mail(let site, let unread, let messages)? = tile()?.hoverCard else { return XCTFail("no mail card") }
        XCTAssertEqual(site, "Gmail")
        XCTAssertNil(unread)
        XCTAssertTrue(messages.isEmpty)
        XCTAssertEqual(TopAppCopy.mailEmpty(unread: unread), "Sign in to your Email to see messages at a glance.")
        XCTAssertNil(tile()?.badgeTint, "no unread dot without a mail source")
        XCTAssertTrue(titles(try XCTUnwrap(popup(d.user(.sidebar(.popupMenu(.item(gmail), at: .zero)))))).contains("Show Hover Preview"))
    }

    func testTheMailCardListsMessagesOpenedInBrkUnderTheMailboxCount() throws {
        let d = Driver(startURL: url("https://mail.google.com/mail/u/0/"))
        let gmail = d.todayIDs[0]
        d.page(gmail, .titleChanged("Inbox (2) - fixture@example.com - Gmail"))
        let root = try XCTUnwrap(d.state.doc.favorites[.default])
        d.user(.item(.move(gmail, to: .into(parent: root, index: 0))))
        let message = d.open("https://mail.google.com/mail/u/0/#inbox/FMfcgzQfixture")
        d.page(message, .titleChanged("Quarterly plan - fixture@example.com - Gmail"))
        d.advance(.seconds(90))
        let other = d.open("https://example.com/elsewhere")
        _ = other
        d.user(.tabTools(.preferences(includeFavorites: true, previews: true)))
        guard case .mail(_, let unread, let messages)? = d.view.favorites.tiles.first(where: { $0.id == gmail })?.hoverCard else { return XCTFail("no mail card") }
        XCTAssertEqual(unread, 2)
        XCTAssertEqual(messages.map(\.title), ["Quarterly plan"], "the opened message by subject; the inbox and other sites are not messages")
        XCTAssertEqual(TopAppCopy.mailHeader(unread: unread), "Recent Emails · 2 unread")
        d.page(gmail, .titleChanged("Inbox - fixture@example.com - Gmail"))
        guard case .mail(_, let none, _)? = d.view.favorites.tiles.first(where: { $0.id == gmail })?.hoverCard else { return XCTFail("no mail card") }
        XCTAssertEqual(none, 0)
        XCTAssertEqual(TopAppCopy.mailEmpty(unread: none), "No unread emails, you can exhale!")
        d.user(.tabTools(.siteDisplay(host: "mail.google.com", .hoverPreview, on: false)))
        XCTAssertNil(d.view.favorites.tiles.first(where: { $0.id == gmail })?.hoverCard, "Show Hover Preview off")
    }
}
