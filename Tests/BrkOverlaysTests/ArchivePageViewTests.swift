import AppKit
import XCTest

@testable import BrkOverlays
import BrkBase
@testable import BrkDomain

// The bucket math (`archiveBucket`) and the grouping live in BrkDomain's projection; these cases pin what the page
// does with a projected ArchiveSnapshot: what it shows, and what each control dispatches.

private func entry(_ id: String, _ title: String, _ url: String, _ ms: Int64, _ reason: ArchiveReason, _ space: String?) -> ArchiveEntry {
    ArchiveEntry(id: ArchiveID(id), title: title, url: URL(string: url), favicon: nil, archivedAt: Instant(milliseconds: ms),
                 reason: reason, fromSpaceTitle: space)
}

private let archiveFixture = ArchiveSnapshot(openID: 1, groups: [
    ArchiveGroup(bucket: .today, entries: [
        entry("e1", "Swift Forums", "https://forums.swift.org/", 1_793_372_700_000, .manual, "Work"),       // Fri 30 Oct 2026 15:05 UTC
        entry("e2", "Hub pricing", "https://hub.example.com/pricing", 1_793_366_000_000, .auto, nil),
    ]),
    ArchiveGroup(bucket: .pastWeek, entries: [
        entry("e3", "Release notes", "https://resources.arc.net/notes", 1_793_027_100_000, .clearToday, "Home"), // Mon 26 Oct 15:05
    ]),
    ArchiveGroup(bucket: .beyond, entries: [
        entry("e4", "Old page", "https://old.example.com/", 1_760_256_000_000, .containerDeleted, nil),         // 12 Oct 2025
    ]),
], threshold: .twelveHours)

@MainActor
final class ArchivePageViewTests: XCTestCase {
    private var sent: [Command] = []
    private let frame = CGRect(x: 270, y: 10, width: 1000, height: 756)

    private func makePage(_ archive: ArchiveSnapshot = archiveFixture) -> ArchivePageView {
        let page = ArchivePageView(dispatch: { [unowned self] in self.sent.append($0) })
        page.timeZone = TimeZone(identifier: "UTC")!
        page.show(archive, in: frame, scheme: .light)
        return page
    }

    private func visible(_ page: NSView) -> [NSView] { page.descendants.filter { !$0.isHiddenOrHasHiddenAncestor } }

    private func view(_ identifier: String, in page: NSView) -> NSView? {
        visible(page).first { $0.accessibilityIdentifier() == identifier }
    }

    private func texts(in view: NSView?) -> [String] {
        guard let view else { return [] }
        return ([view] + view.descendants).filter { !$0.isHiddenOrHasHiddenAncestor }
            .compactMap { ($0 as? NSTextField)?.stringValue }.filter { !$0.isEmpty }
    }

    private func type(_ text: String, in page: ArchivePageView) {
        page.filterField.stringValue = text
        page.controlTextDidChange(Notification(name: NSControl.textDidChangeNotification, object: page.filterField))
    }

    func testGroupsInProjectionOrderWithEachEntrysTitleURLWhenWhyAndSpace() {
        let page = makePage()
        XCTAssertEqual(visible(page).compactMap { $0.accessibilityIdentifier() }.filter { $0.hasPrefix("archive-group-") },
                       ["archive-group-today", "archive-group-pastWeek", "archive-group-beyond"])
        XCTAssertEqual(texts(in: view("archive-group-pastWeek", in: page)).first, "Earlier This Week")
        XCTAssertEqual(texts(in: view("archive-entry-e1", in: page)), ["Swift Forums", "forums.swift.org", "3:05 PM · Closed · Work"])
        XCTAssertEqual(texts(in: view("archive-entry-e3", in: page)), ["Release notes", "resources.arc.net/notes", "Mon 3:05 PM · Cleared from Today · Home"])
        XCTAssertEqual(texts(in: view("archive-entry-e4", in: page)), ["Old page", "old.example.com", "Oct 12, 2025 · Folder or Space deleted"])
        // Each entry sits inside its group, so its frame is inside the group's frame on screen.
        XCTAssertTrue(view("archive-entry-e3", in: page)!.isDescendant(of: view("archive-group-pastWeek", in: page)!))
        XCTAssertEqual(texts(in: page).first, "Archive")
    }

    func testRestoreDispatchesRestoreForThatEntry() {
        let page = makePage()
        (view("archive-restore-e3", in: page) as? NSButton)?.performClick(nil)
        XCTAssertEqual(sent, [.archive(.restore(ArchiveID("e3")))])
    }

    func testClearArchiveAsksInlineFirstAndCancelBacksOut() {
        let page = makePage()
        let clear = view("archive-clear", in: page) as? NSButton
        clear?.performClick(nil)
        XCTAssertEqual(sent, [])
        XCTAssertTrue(texts(in: page).contains("Are you sure you'd like to Clear Archive?"))
        page.cancelClearButton.performClick(nil)
        XCTAssertFalse(texts(in: page).contains("Are you sure you'd like to Clear Archive?"))
        clear?.performClick(nil)
        clear?.performClick(nil)
        XCTAssertEqual(sent, [.archive(.clear)])
    }

    func testThresholdMenuOffersArcsSevenChoicesAndDispatchesTheChosenOne() {
        let page = makePage()
        let menu = view("archive-threshold", in: page) as! NSPopUpButton
        XCTAssertEqual(menu.itemTitles, ["1 hour", "6 hours", "12 hours", "24 hours", "7 days", "30 days", "Never"])
        XCTAssertEqual(menu.titleOfSelectedItem, "12 hours")
        XCTAssertTrue(texts(in: page).contains("Archive tabs after"))
        menu.selectItem(withTitle: "12 hours")
        menu.sendAction(menu.action, to: menu.target)
        menu.selectItem(withTitle: "7 days")
        menu.sendAction(menu.action, to: menu.target)
        XCTAssertEqual(sent, [.settings(.autoArchive(.sevenDays))], "choosing the current threshold again dispatches nothing")
    }

    func testFilterNarrowsByTitleURLOrSpaceAndHidesGroupsItEmpties() {
        let page = makePage()
        type("work", in: page)
        XCTAssertEqual(visible(page).compactMap { $0.accessibilityIdentifier() }.filter { $0.hasPrefix("archive-") && !$0.hasPrefix("archive-restore") },
                       ["archive-threshold", "archive-clear", "archive-group-today", "archive-entry-e1"])
        type("ÉXAMPLE", in: page)
        XCTAssertNotNil(view("archive-entry-e2", in: page))
        XCTAssertNotNil(view("archive-entry-e4", in: page))
        XCTAssertNil(view("archive-entry-e1", in: page))
        type("nothing like it", in: page)
        XCTAssertTrue(texts(in: page).contains("No archived tabs match your filter."))
    }

    func testAnEmptyArchiveShowsArcsHintAndCannotBeCleared() {
        let page = makePage(ArchiveSnapshot(openID: 1, groups: [], threshold: .never))
        XCTAssertTrue(texts(in: page).contains("Hover your mouse over a tab and press the × to archive it."))
        XCTAssertEqual((view("archive-clear", in: page) as? NSButton)?.isEnabled, false)
        XCTAssertEqual((view("archive-threshold", in: page) as? NSPopUpButton)?.titleOfSelectedItem, "Never")
    }

    func testCloseButtonAndEscapeInAnEmptyFilterCloseTheArchive() {
        let page = makePage()
        page.closeButton.performClick(nil)
        type("x", in: page)
        // With text in the filter, Esc is the search field's own: it clears the text.
        XCTAssertFalse(page.control(page.filterField, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        type("", in: page)
        XCTAssertTrue(page.control(page.filterField, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        XCTAssertEqual(sent, [.commandBar(.dismiss), .commandBar(.dismiss)])
    }

    func testTheSameOpeningKeepsTheFilterAndANewOpeningClearsIt() {
        let page = makePage()
        type("work", in: page)
        var restored = archiveFixture
        restored.groups.removeLast()
        page.show(restored, in: frame, scheme: .light)
        XCTAssertEqual(page.filterField.stringValue, "work")
        XCTAssertEqual(visible(page).compactMap { $0.accessibilityIdentifier() }.filter { $0.hasPrefix("archive-entry-") }, ["archive-entry-e1"])
        restored.openID = 2
        page.show(restored, in: frame, scheme: .light)
        XCTAssertEqual(page.filterField.stringValue, "")
        XCTAssertEqual(visible(page).compactMap { $0.accessibilityIdentifier() }.filter { $0.hasPrefix("archive-entry-") },
                       ["archive-entry-e1", "archive-entry-e2", "archive-entry-e3"])
    }
}
