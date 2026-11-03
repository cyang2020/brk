import AppKit
import XCTest

@testable import BrkLibrary
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
    private let frame = CGRect(x: 112, y: 0, width: 305, height: 776)

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
        page.searchChanged()
    }

    private func entries(_ page: NSView) -> [String] {
        visible(page).compactMap { $0.accessibilityIdentifier() }.filter { $0.hasPrefix("archive-entry-") }
    }

    /// Arc's two-line rows (P32-e): title over the grey address; when, why and the space are in the tooltip and the
    /// context menu, not on the row
    func testGroupsInProjectionOrderWithEachEntrysTitleAndURL() {
        let page = makePage()
        XCTAssertEqual(visible(page).compactMap { $0.accessibilityIdentifier() }.filter { $0.hasPrefix("archive-group-") },
                       ["archive-group-today", "archive-group-pastWeek", "archive-group-beyond"])
        XCTAssertEqual(texts(in: view("archive-group-pastWeek", in: page)).first, "Earlier This Week")
        let e1 = view("archive-entry-e1", in: page) as? ArchiveEntryView, e3 = view("archive-entry-e3", in: page) as? ArchiveEntryView
        XCTAssertEqual(e1?.texts, ["Swift Forums", "forums.swift.org"])
        XCTAssertEqual(e1?.meta, "3:05 PM · Manually Closed · Work")
        XCTAssertEqual(e1?.toolTip, "3:05 PM · Manually Closed · Work")
        XCTAssertEqual(e3?.meta, "Mon 3:05 PM · Cleared from Today · Home")
        XCTAssertEqual((view("archive-entry-e4", in: page) as? ArchiveEntryView)?.meta, "Oct 12, 2025 · Folder or Space deleted")
        XCTAssertEqual(e3?.contextMenu().items.map(\.title), ["Restore", "", "Mon 3:05 PM · Cleared from Today · Home"])
        XCTAssertTrue(view("archive-entry-e3", in: page)!.isDescendant(of: view("archive-group-pastWeek", in: page)!))
        XCTAssertEqual(page.filterField.placeholder, "Search Archive…")
        XCTAssertFalse(page.filterButton.isHidden)
    }

    func testRestoreButtonAndContextMenuRestoreThatEntry() {
        let page = makePage()
        (view("archive-restore-e3", in: page) as? NSButton)?.performClick(nil)
        let restore = (view("archive-entry-e1", in: page) as? ArchiveEntryView)?.contextMenu().items.first
        _ = (restore?.target as? NSObject)?.perform(restore!.action!, with: restore)
        XCTAssertEqual(sent, [.archive(.restore(ArchiveID("e3"))), .archive(.restore(ArchiveID("e1")))])
    }

    /// Clear Archive is in the Filter menu; it asks in a bar under the search field, Cancel backs out
    func testClearArchiveAsksInlineFirstAndCancelBacksOut() throws {
        let page = makePage()
        XCTAssertNil(view("archive-clear", in: page), "no Clear button until it is asked")
        let clear = try XCTUnwrap(page.filterMenu().items.last)
        XCTAssertEqual(clear.title, "Clear Archive…")
        _ = (clear.target as? NSObject)?.perform(clear.action!, with: clear)
        XCTAssertEqual(sent, [])
        XCTAssertTrue(texts(in: page).contains("Are you sure you'd like to Clear Archive?"))
        page.cancelClearButton.performClick(nil)
        XCTAssertFalse(texts(in: page).contains("Are you sure you'd like to Clear Archive?"))
        page.beginClearConfirmation()
        (view("archive-clear", in: page) as? NSButton)?.performClick(nil)
        XCTAssertEqual(sent, [.archive(.clear)])
    }

    /// the Filter menu's "Archive tabs after" offers Arc's seven choices with the current one ticked
    func testThresholdMenuOffersArcsSevenChoicesAndDispatchesTheChosenOne() throws {
        let page = makePage()
        let after = try XCTUnwrap(page.filterMenu().items.first { $0.title == "Archive tabs after" }?.submenu)
        XCTAssertEqual(after.items.map(\.title), ["1 hour", "6 hours", "12 hours", "24 hours", "7 days", "30 days", "Never"])
        XCTAssertEqual(after.items.filter { $0.state == .on }.map(\.title), ["12 hours"])
        page.choose(.twelveHours)
        page.choose(.sevenDays)
        XCTAssertEqual(sent, [.settings(.autoArchive(.sevenDays))], "choosing the current threshold again dispatches nothing")
    }

    /// the search narrows by title, URL or space; the Filter menu by how the tab closed; emptied groups go
    func testSearchAndFilterNarrowAndHideGroupsTheyEmpty() {
        let page = makePage()
        type("work", in: page)
        XCTAssertEqual(entries(page), ["archive-entry-e1"])
        type("ÉXAMPLE", in: page)
        XCTAssertNotNil(view("archive-entry-e2", in: page))
        XCTAssertNotNil(view("archive-entry-e4", in: page))
        XCTAssertNil(view("archive-entry-e1", in: page))
        type("nothing like it", in: page)
        XCTAssertTrue(texts(in: page).contains("No archived tabs match your filter."))
        type("", in: page)
        XCTAssertEqual(page.filterMenu().items.prefix(5).map(\.title), ["How was the tab closed?", "Auto-Closed", "Manually Closed", "Cleared from Today", "Folder or Space deleted"])
        page.toggle(.auto)
        XCTAssertEqual(entries(page), ["archive-entry-e1", "archive-entry-e3", "archive-entry-e4"])
    }

    func testAnEmptyArchiveShowsArcsHintAndCannotBeCleared() {
        let page = makePage(ArchiveSnapshot(openID: 1, groups: [], threshold: .never))
        XCTAssertTrue(texts(in: page).contains("Hover your mouse over a tab and press the × to archive it."))
        XCTAssertEqual(page.filterMenu().items.last?.isEnabled, false)
        page.beginClearConfirmation()
        XCTAssertNil(view("archive-clear", in: page))
    }

    func testEscapeInAnEmptySearchClosesTheLibrary() {
        let page = makePage()
        type("x", in: page)
        // With text in the search, Esc clears it first.
        XCTAssertTrue(page.filterField.control(page.filterField.field, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        XCTAssertEqual(page.filterField.stringValue, "")
        XCTAssertEqual(sent, [])
        XCTAssertTrue(page.filterField.control(page.filterField.field, textView: NSTextView(), doCommandBy: #selector(NSResponder.cancelOperation(_:))))
        XCTAssertEqual(sent, [.library(.close)])
    }

    func testTheSameOpeningKeepsTheSearchAndANewOpeningClearsIt() {
        let page = makePage()
        type("work", in: page)
        var restored = archiveFixture
        restored.groups.removeLast()
        page.show(restored, in: frame, scheme: .light)
        XCTAssertEqual(page.filterField.stringValue, "work")
        XCTAssertEqual(entries(page), ["archive-entry-e1"])
        restored.openID = 2
        page.show(restored, in: frame, scheme: .light)
        XCTAssertEqual(page.filterField.stringValue, "")
        XCTAssertEqual(entries(page), ["archive-entry-e1", "archive-entry-e2", "archive-entry-e3"])
    }
}
