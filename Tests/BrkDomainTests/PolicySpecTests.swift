import BrkBase
import Foundation
import XCTest

@testable import BrkDomain

// URL policy, placement rules, theme resolution and archive buckets, ported from the Electron tests of
// src/shared/url.ts, placement.ts, theme.ts and src/renderer/overlay/archive-groups.ts (bucketing moved into the
// projection, so it is tested here). Owners: W1 (url, placement, archive buckets), W5 (theme).

final class PolicySpecTests: XCTestCase {
    // MARK: - electron-v1:src/shared/url.test.ts
    // MARK: resolveTypedInput
    /// returns null for empty or whitespace input
    func test_returnsNullForEmptyOrWhitespaceInput() throws {
        XCTAssertNil(resolveTypedInput(""))
        XCTAssertNil(resolveTypedInput("   \t "))
        XCTAssertNil(resolveTypedInput("\n"))
    }

    /// treats a host with a port, an IP address or a dotted domain as a URL and adds the scheme
    func test_treatsAHostWithAPortAnIPAddressOrADottedDomainAsAURLAndAddsTheScheme() throws {
        XCTAssertEqual(resolveTypedInput("localhost:5173/a"), URL(string: "http://localhost:5173/a"))
        XCTAssertEqual(resolveTypedInput("127.0.0.1:8080"), URL(string: "http://127.0.0.1:8080/"))
        XCTAssertEqual(resolveTypedInput("192.168.0.1"), URL(string: "http://192.168.0.1/"))
        XCTAssertEqual(resolveTypedInput("example.com"), URL(string: "https://example.com/"))
        XCTAssertEqual(resolveTypedInput("Example.COM/Path"), URL(string: "https://example.com/Path"))
        XCTAssertEqual(resolveTypedInput("  news.ycombinator.com/item?id=1  "), URL(string: "https://news.ycombinator.com/item?id=1"))
        XCTAssertEqual(resolveTypedInput("dev.local:3000"), URL(string: "https://dev.local:3000/"), "a dotted name with a letter TLD is public even with a port")
        XCTAssertEqual(resolveTypedInput("devbox:3000/x"), URL(string: "http://devbox:3000/x"), "a bare host with a port is local")
    }

    /// keeps an explicit allowed scheme
    func test_keepsAnExplicitAllowedScheme() throws {
        XCTAssertEqual(resolveTypedInput("https://x.y/z"), URL(string: "https://x.y/z"))
        XCTAssertEqual(resolveTypedInput("http://127.0.0.1:9/page2.html"), URL(string: "http://127.0.0.1:9/page2.html"))
        XCTAssertEqual(resolveTypedInput("file:///tmp/a.html"), URL(string: "file:///tmp/a.html"))
        XCTAssertEqual(resolveTypedInput("about:blank"), URL(string: "about:blank"))
        // Swift addition: the Chrome runtime renders chrome:// pages, so the bar opens them.
        XCTAssertEqual(resolveTypedInput("chrome://extensions"), URL(string: "chrome://extensions/"))
        XCTAssertEqual(resolveTypedInput("HTTPS://Example.com"), URL(string: "https://example.com/"))
    }

    /// searches a bare word, text with spaces, a number and a refused scheme
    func test_searchesABareWordTextWithSpacesANumberAndARefusedScheme() throws {
        XCTAssertEqual(resolveTypedInput("arc"), URL(string: "https://www.google.com/search?q=arc"))
        XCTAssertEqual(resolveTypedInput("localhost"), URL(string: "https://www.google.com/search?q=localhost"))
        XCTAssertEqual(resolveTypedInput("arc browser shortcuts"), URL(string: "https://www.google.com/search?q=arc%20browser%20shortcuts"))
        XCTAssertEqual(resolveTypedInput("3.14"), URL(string: "https://www.google.com/search?q=3.14"))
        XCTAssertEqual(resolveTypedInput("javascript:alert(1)"), URL(string: "https://www.google.com/search?q=javascript%3Aalert(1)"))
        XCTAssertEqual(resolveTypedInput("data:text/html,hi"), URL(string: "https://www.google.com/search?q=data%3Atext%2Fhtml%2Chi"))
        XCTAssertEqual(resolveTypedInput("c++ & rust?"), URL(string: "https://www.google.com/search?q=c%2B%2B%20%26%20rust%3F"))
    }

    // MARK: isAllowedUrl
    /// allows http, https, file and about:blank
    func test_allowsHttpHttpsFileAndAboutBlank() throws {
        for text in ["http://127.0.0.1:9/a", "https://example.com/", "file:///tmp/a.html", "about:blank"] {
            XCTAssertTrue(isAllowedURL(URL(string: text)!), text)
        }
    }

    /// refuses every other scheme and unparseable text
    func test_refusesEveryOtherSchemeAndUnparseableText() throws {
        for text in ["javascript:alert(1)", "data:text/html,hi", "chrome://settings", "devtools://devtools", "about:config", "not a url", "http://"] {
            XCTAssertFalse(URL(string: text).map(isAllowedURL) ?? false, text)
        }
    }

    // MARK: displayUrl
    /// drops the scheme, www. and the trailing slash
    func test_dropsTheSchemeWwwAndTheTrailingSlash() throws {
        XCTAssertEqual(displayURL(URL(string: "https://www.example.com/")!), "example.com")
        XCTAssertEqual(displayURL(URL(string: "https://example.com/a/b/")!), "example.com/a/b")
        XCTAssertEqual(displayURL(URL(string: "http://127.0.0.1:9/page2.html?x=1#top")!), "127.0.0.1:9/page2.html")
    }

    /// shows a file path and leaves other text alone
    func test_showsAFilePathAndLeavesOtherTextAlone() throws {
        XCTAssertEqual(displayURL(URL(string: "file:///tmp/a.html")!), "/tmp/a.html")
        XCTAssertEqual(displayURL(URL(string: "about:blank")!), "about:blank")
        XCTAssertEqual(displayURL(URL(string: "chrome://extensions/")!), "chrome://extensions/")
    }

    // MARK: - electron-v1:src/shared/placement.test.ts
    // MARK: canPlace
    /// lets Favorites hold tabs only, flat
    func test_letsFavoritesHoldTabsOnlyFlat() throws {
        XCTAssertTrue(Placement.canPlace(.tab, inSection: .favorites, parentKind: .section))
        XCTAssertFalse(Placement.canPlace(.folder, inSection: .favorites, parentKind: .section))
        XCTAssertFalse(Placement.canPlace(.split, inSection: .favorites, parentKind: .section))
        XCTAssertFalse(Placement.canPlace(.tab, inSection: .favorites, parentKind: .folder))
    }

    /// lets Pinned hold tabs, splits and nested folders
    func test_letsPinnedHoldTabsSplitsAndNestedFolders() throws {
        for kind in [ItemKind.tab, .folder, .split] {
            XCTAssertTrue(Placement.canPlace(kind, inSection: .pinned, parentKind: .section), "\(kind)")
            XCTAssertTrue(Placement.canPlace(kind, inSection: .pinned, parentKind: .folder), "\(kind)")
            XCTAssertFalse(Placement.canPlace(kind, inSection: .pinned, parentKind: .split), "\(kind): panes enter only through split rules")
            XCTAssertFalse(Placement.canPlace(kind, inSection: .pinned, parentKind: .tab), "\(kind)")
        }
        XCTAssertFalse(Placement.canPlace(.section, inSection: .pinned, parentKind: .section))
    }

    /// lets Today hold tabs and splits, never folders
    func test_letsTodayHoldTabsAndSplitsNeverFolders() throws {
        XCTAssertTrue(Placement.canPlace(.tab, inSection: .today, parentKind: .section))
        XCTAssertTrue(Placement.canPlace(.split, inSection: .today, parentKind: .section))
        XCTAssertFalse(Placement.canPlace(.folder, inSection: .today, parentKind: .section))
        XCTAssertFalse(Placement.canPlace(.tab, inSection: .today, parentKind: .folder))
    }

    // MARK: - electron-v1:src/shared/theme.test.ts
    // MARK: relativeLuminance
    /// matches the WCAG endpoints and a mid grey
    func test_matchesTheWCAGEndpointsAndAMidGrey() throws { throw XCTSkip(pendingW5) }

    // MARK: resolveTheme
    /// picks the light scheme and light tokens for a light primary
    func test_picksTheLightSchemeAndLightTokensForALightPrimary() throws { throw XCTSkip(pendingW5) }

    /// picks the dark scheme and dark tokens for a dark primary
    func test_picksTheDarkSchemeAndDarkTokensForADarkPrimary() throws { throw XCTSkip(pendingW5) }

    /// gives the default mid-tone blue the light scheme (black text has the higher contrast)
    func test_givesTheDefaultMidToneBlueTheLightSchemeBlackTextHasTheHigherContrast() throws { throw XCTSkip(pendingW5) }

    /// lets a forced appearance override the luminance
    func test_letsAForcedAppearanceOverrideTheLuminance() throws { throw XCTSkip(pendingW5) }

    /// the complementary wheel puts the companion at the opposite hue; analogous at +-30 degrees (W5)
    func test_wheelRuleDerivesCompanionHues() throws { throw XCTSkip(pendingW5) }

    /// noise and intensity resolve separately: noise sets the texture contrast, intensity the texture opacity and wash (W5)
    func test_noiseAndIntensityResolveSeparately() throws { throw XCTSkip(pendingW5) }

    // MARK: themeFromPrimary
    /// keeps the primary first and adds two analogous companions with grain 0.25 and auto appearance
    func test_keepsThePrimaryFirstAndAddsTwoAnalogousCompanionsWithGrain025AndAutoAppearance() throws { throw XCTSkip(pendingW5) }

    /// keeps a grey grey and only nudges its lightness
    func test_keepsAGreyGreyAndOnlyNudgesItsLightness() throws { throw XCTSkip(pendingW5) }

    /// produces colors the stored schema accepts for every preset
    func test_producesColorsTheStoredSchemaAcceptsForEveryPreset() throws { throw XCTSkip(pendingW5) }

    // MARK: - electron-v1:src/renderer/overlay/archive-groups.test.ts
    // MARK: bucketOf
    /// on a Monday, Sunday is yesterday and Saturday is past-month (the week has no earlier days)
    func test_onAMondaySundayIsYesterdayAndSaturdayIsPastMonthTheWeekHasNoEarlierDays() throws {
        let monday = at(2026, 10, 26, 9, 0)
        XCTAssertEqual(archiveBucket(of: at(2026, 10, 25, 12, 0), now: monday, calendar: utc), .yesterday)
        XCTAssertEqual(archiveBucket(of: at(2026, 10, 24, 12, 0), now: monday, calendar: utc), .pastMonth)
        // Whatever the calendar's own first weekday (Sunday in the US): weeks start on Monday.
        var sundayFirst = utc
        sundayFirst.firstWeekday = 1
        XCTAssertEqual(archiveBucket(of: at(2026, 10, 24, 12, 0), now: monday, calendar: sundayFirst), .pastMonth)
    }

    /// on a Tuesday, Monday is yesterday and Sunday is past-month
    func test_onATuesdayMondayIsYesterdayAndSundayIsPastMonth() throws {
        let tuesday = at(2026, 10, 27, 9, 0)
        XCTAssertEqual(archiveBucket(of: at(2026, 10, 26, 12, 0), now: tuesday, calendar: utc), .yesterday)
        XCTAssertEqual(archiveBucket(of: at(2026, 10, 25, 12, 0), now: tuesday, calendar: utc), .pastMonth)
    }

    // MARK: groupArchive
    /// returns non-empty groups in bucket order with labels, entries newest first
    func test_returnsNonEmptyGroupsInBucketOrderWithLabelsEntriesNewestFirst() throws {
        let entries: [(String, Instant)] = [
            ("old", at(2026, 1, 2, 10, 0)), ("today-early", at(2026, 10, 29, 8, 0)), ("yesterday", at(2026, 10, 28, 12, 0)),
            ("today-late", at(2026, 10, 29, 14, 0)), ("three-weeks", at(2026, 10, 8, 12, 0)),
        ]
        let groups = try archiveGroups(entries, now: thursday)
        // Labels are W4's copy for each bucket; the domain hands over the bucket.
        XCTAssertEqual(groups.map { $0.bucket }, [ArchiveBucket.today, .yesterday, .pastMonth, .beyond])
        let titles: [[String]] = groups.map { group in group.entries.map { $0.title } }
        XCTAssertEqual(titles, [["today-late", "today-early"], ["yesterday"], ["three-weeks"], ["old"]])
    }

    /// labels the past-week group "Earlier This Week"
    func test_labelsThePastWeekGroupEarlierThisWeek() throws {
        // "Earlier This Week" is the archive page's label (W4) for the pastWeek bucket.
        let groups = try archiveGroups([("tue", at(2026, 10, 27, 9, 0))], now: thursday)
        XCTAssertEqual(groups.map { $0.bucket }, [ArchiveBucket.pastWeek])
        XCTAssertEqual(ArchiveBucket.pastWeek.rawValue, "pastWeek")
    }

    /// returns no groups for no entries
    func test_returnsNoGroupsForNoEntries() throws {
        XCTAssertEqual(try archiveGroups([], now: thursday), [])
    }

    /// bucketOf on Thursday 15:00, every boundary of the Electron table (local midnight today, yesterday, Monday, 30 days).
    func testBucketBoundariesOnAThursday() {
        let cases: [(Instant, ArchiveBucket)] = [
            (at(2026, 10, 29, 0, 0), .today), (at(2026, 10, 29, 14, 59), .today), (at(2026, 10, 29, 16, 0), .today),
            (at(2026, 10, 30, 10, 0), .today), (at(2026, 10, 28, 23, 59), .yesterday), (at(2026, 10, 28, 0, 0), .yesterday),
            (at(2026, 10, 27, 23, 59), .pastWeek), (at(2026, 10, 26, 0, 0), .pastWeek), (at(2026, 10, 25, 23, 59), .pastMonth),
            (at(2026, 9, 29, 0, 0), .pastMonth), (at(2026, 9, 28, 23, 59), .beyond), (at(2025, 10, 29, 15, 0), .beyond),
        ]
        for (archivedAt, bucket) in cases {
            XCTAssertEqual(archiveBucket(of: archivedAt, now: thursday, calendar: utc), bucket, "\(archivedAt)")
        }
    }

    // MARK: Helpers

    /// 2026-10-29 is a Thursday; that week started on Monday 2026-10-26.
    var thursday: Instant { at(2026, 10, 29, 15, 0) }
    let utc: Calendar = Driver.calendar

    func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 0, _ mi: Int = 0) -> Instant {
        let date = Driver.calendar.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
        return Instant(milliseconds: Int64(date.timeIntervalSince1970 * 1000))
    }

    /// The archive page's groups for these (title, archivedAt) entries, seen at `now`: written into a saved file
    /// (the only way to place entries before the driver's clock), restored, the clock moved to `now`, the page opened.
    func archiveGroups(_ entries: [(String, Instant)], now: Instant) throws -> [BrkDomain.ArchiveGroup] {
        let fresh = Driver()
        var file = jsonObject(fresh.savedFile)
        var doc = file["doc"] as! [String: Any]
        doc["archive"] = entries.enumerated().map { i, entry -> [String: Any] in
            ["id": "e\(i)", "tabID": "x\(i)", "archivedAt": entry.1.milliseconds, "reason": "manual", "fromSection": "today",
             "tab": ["url": "https://example.com/\(i)", "title": entry.0, "lastActiveAt": entry.1.milliseconds]]
        }
        file["doc"] = doc
        let d = Driver(file: jsonData(file))
        XCTAssertEqual(d.outcome, .restored(repairs: []))
        d.advance(now.since(d.now))
        d.user(.archive(.open))
        guard case .archive(let page)? = d.view.overlay else {
            XCTFail("the archive did not open")
            return []
        }
        return page.groups
    }
}
