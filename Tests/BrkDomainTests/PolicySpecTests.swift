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

    /// Today holds tabs, splits and topic folders.
    func test_letsTodayHoldTabsSplitsAndTopicFolders() throws {
        XCTAssertTrue(Placement.canPlace(.tab, inSection: .today, parentKind: .section))
        XCTAssertTrue(Placement.canPlace(.split, inSection: .today, parentKind: .section))
        XCTAssertTrue(Placement.canPlace(.folder, inSection: .today, parentKind: .section))
        XCTAssertTrue(Placement.canPlace(.tab, inSection: .today, parentKind: .folder))
    }

    // MARK: - electron-v1:src/shared/theme.test.ts
    // MARK: relativeLuminance
    /// matches the WCAG endpoints and a mid grey
    func test_matchesTheWCAGEndpointsAndAMidGrey() throws {
        XCTAssertEqual(relativeLuminance(RGBA(hex: "#000000")), 0)
        XCTAssertEqual(relativeLuminance(RGBA(hex: "#FFFFFF")), 1, accuracy: 1e-10)
        XCTAssertEqual(relativeLuminance(RGBA(hex: "#808080")), 0.2159, accuracy: 1e-4)
        XCTAssertEqual(relativeLuminance(RGBA(hex: "#ff0000")), 0.2126, accuracy: 1e-4)
    }

    // MARK: resolveTheme
    /// picks the light scheme and light tokens for a light primary
    func test_picksTheLightSchemeAndLightTokensForALightPrimary() throws {
        let resolved = resolveTheme(SpaceTheme(colors: [RGBA(hex: "#F2EAE4"), RGBA(hex: "#f29bbb")], texture: .grain,
                                               noise: 0.4, intensity: 0.4, appearance: .auto))
        XCTAssertEqual(resolved.scheme, .light)
        // Two base colors, then the primary's first analogous companion (hue +30, 6% lighter).
        XCTAssertEqual(resolved.gradient.map(themeHex), ["#F2EAE4", "#F29BBB", "#FCFCF9"])
        XCTAssertEqual(resolved.tokens, .light)
        XCTAssertEqual(resolved.tokens.tabCurrent, RGBA(1, 1, 1, 0.85))
        XCTAssertEqual(resolved.tokens.foreground, RGBA(0, 0, 0, 0.3))
        XCTAssertEqual(resolved.tokens.itemBackground, RGBA(14 / 255, 15 / 255, 16 / 255, 0.05))
        XCTAssertEqual(resolved.tokens.tabShadowBackground, RGBA(1, 1, 1, 0.9))
        // White wash at min(0.2 + 0.55 x 0.4, 0.5) = 0.42 over the primary: 242 + 13 x 0.42 = 247.46, ...
        XCTAssertEqual([resolved.wash.red, resolved.wash.green, resolved.wash.blue], [1, 1, 1])
        XCTAssertEqual(resolved.wash.alpha, 0.42, accuracy: 1e-12)
        assertColor(resolved.windowColor, 247.46, 242.82, 239.34)
    }

    /// picks the dark scheme and dark tokens for a dark primary
    func test_picksTheDarkSchemeAndDarkTokensForADarkPrimary() throws {
        let resolved = resolveTheme(SpaceTheme(colors: [RGBA(hex: "#2D4468")], texture: .grain, intensity: 0, appearance: .auto))
        XCTAssertEqual(resolved.scheme, .dark)
        XCTAssertEqual(resolved.tokens, .dark)
        XCTAssertEqual(resolved.tokens.foreground, RGBA(1, 1, 1, 0.45))
        XCTAssertEqual(resolved.tokens.tabCurrent, RGBA(250 / 255, 251 / 255, 1, 0.2))
        XCTAssertEqual(resolved.tokens.tabShadow, RGBA(0, 0, 0, 0))
        // Black at 35% of the wash opacity 0.2: alpha 0.07, so the window color is the primary x 0.93.
        XCTAssertEqual(resolved.wash.alpha, 0.07, accuracy: 1e-12)
        XCTAssertEqual([resolved.wash.red, resolved.wash.green, resolved.wash.blue], [0, 0, 0])
        assertColor(resolved.windowColor, 41.85, 63.24, 96.72)
    }

    /// gives the default pink-beige (Arc's first Brand swatch) the light scheme (black text has the higher contrast)
    func test_givesTheDefaultPinkBeigeTheLightSchemeBlackTextHasTheHigherContrast() throws {
        XCTAssertEqual(SpaceTheme.default.colors, [RGBA(hex: "#F2EAE4")])
        XCTAssertEqual(resolveTheme(SpaceTheme.default).scheme, .light)
        // The cutoff is 0.1791: #767676 (0.1812) is light, #757575 (0.1779) is dark.
        let grey = { (hex: String) in resolveTheme(SpaceTheme(colors: [RGBA(hex: hex)], texture: .grain, intensity: 0, appearance: .auto)).scheme }
        XCTAssertEqual(grey("#767676"), .light)
        XCTAssertEqual(grey("#757575"), .dark)
    }

    /// lets a forced appearance override the luminance
    func test_letsAForcedAppearanceOverrideTheLuminance() throws {
        let white = resolveTheme(SpaceTheme(colors: [RGBA(hex: "#FFFFFF")], texture: .grain, intensity: 0, appearance: .dark))
        XCTAssertEqual(white.scheme, .dark)
        XCTAssertEqual(white.tokens.foreground, RGBA(1, 1, 1, 0.45))
        XCTAssertEqual(white.wash.red, 0)
        let black = resolveTheme(SpaceTheme(colors: [RGBA(hex: "#000000")], texture: .grain, intensity: 0, appearance: .light))
        XCTAssertEqual(black.scheme, .light)
        XCTAssertEqual(black.tokens.foreground, RGBA(0, 0, 0, 0.3))
        XCTAssertEqual(black.wash, RGBA(1, 1, 1, 0.2))
    }

    /// the complementary wheel puts the companion at the opposite hue; analogous at +-30 degrees (W5)
    func test_wheelRuleDerivesCompanionHues() throws {
        let red = RGBA(hex: "#FF0000")
        func stops(_ colors: [RGBA], _ wheel: ColorWheel) -> [String] {
            resolveTheme(SpaceTheme(colors: colors, wheel: wheel, texture: .grain, intensity: 0, appearance: .auto)).gradient.map(themeHex)
        }
        // Red is hue 0, s 1, l 0.5. Hue 30 at l 0.56 -> (255, 143, 31); hue 330 at l 0.44 -> (224, 0, 112).
        XCTAssertEqual(stops([red], .analogous), ["#FF0000", "#FF8F1F", "#E00070"])
        // Hue 180 at l 0.56 -> (31, 255, 255); then the primary's hue at l 0.44 -> (224, 0, 0).
        XCTAssertEqual(stops([red], .complementary), ["#FF0000", "#1FFFFF", "#E00000"])
        // Base colors come first; companions only fill up to three stops.
        XCTAssertEqual(stops([red, RGBA(hex: "#0000FF")], .complementary), ["#FF0000", "#0000FF", "#1FFFFF"])
        let three = [red, RGBA(hex: "#00FF00"), RGBA(hex: "#0000FF")]
        XCTAssertEqual(stops(three, .analogous), ["#FF0000", "#00FF00", "#0000FF"])
        XCTAssertEqual(stops(three + [RGBA(hex: "#FFFFFF")], .complementary), ["#FF0000", "#00FF00", "#0000FF"])
    }

    /// noise and intensity resolve separately: noise sets the texture contrast, intensity the texture opacity and wash (W5)
    func test_noiseAndIntensityResolveSeparately() throws {
        func resolve(_ texture: Texture, noise: Double, intensity: Double, _ appearance: AppearanceChoice = .light) -> ResolvedTheme {
            resolveTheme(SpaceTheme(colors: [RGBA(hex: "#7EB8D6")], texture: texture, noise: noise, intensity: intensity, appearance: appearance))
        }
        let low = resolve(.grain, noise: 0.3, intensity: 0.5), high = resolve(.grain, noise: 0.9, intensity: 0.5)
        XCTAssertEqual(low.textureContrast, 0.3)
        XCTAssertEqual(high.textureContrast, 0.9)
        XCTAssertEqual(low.textureOpacity, high.textureOpacity)
        XCTAssertEqual(low.wash, high.wash)
        // Opacity = intensity x the texture's multiplier (grain 0.8, sand 0.15, denim 0.6, tweed 0.4).
        XCTAssertEqual(low.textureOpacity, 0.4, accuracy: 1e-12)
        XCTAssertEqual(resolve(.grain, noise: 0.3, intensity: 1).textureOpacity, 0.8, accuracy: 1e-12)
        XCTAssertEqual(resolve(.sand, noise: 0.3, intensity: 1).textureOpacity, 0.15, accuracy: 1e-12)
        XCTAssertEqual(resolve(.denim, noise: 0.3, intensity: 1).textureOpacity, 0.6, accuracy: 1e-12)
        XCTAssertEqual(resolve(.tweed, noise: 0.3, intensity: 1).textureOpacity, 0.4, accuracy: 1e-12)
        XCTAssertEqual(resolve(.tweed, noise: 0.3, intensity: 0).textureOpacity, 0)
        XCTAssertEqual(resolve(.tweed, noise: 0.3, intensity: 0).textureContrast, 0.3)
        // Wash opacity = min(0.2 + 0.55 x intensity, 0.5): 0.2, 0.475, capped at 0.5 from intensity 0.546 on.
        XCTAssertEqual(resolve(.grain, noise: 0.3, intensity: 0).wash.alpha, 0.2, accuracy: 1e-12)
        XCTAssertEqual(low.wash.alpha, 0.475, accuracy: 1e-12)
        XCTAssertEqual(resolve(.grain, noise: 0.3, intensity: 0.6).wash.alpha, 0.5, accuracy: 1e-12)
        XCTAssertEqual(resolve(.grain, noise: 0.3, intensity: 1).wash.alpha, 0.5, accuracy: 1e-12)
        // Dark: black at 35% of it.
        XCTAssertEqual(resolve(.grain, noise: 0.3, intensity: 0.5, .dark).wash.alpha, 0.16625, accuracy: 1e-12)
        // Out-of-range stored values are clamped.
        let clamped = resolve(.denim, noise: 3, intensity: -1)
        XCTAssertEqual([clamped.textureContrast, clamped.textureOpacity, clamped.wash.alpha], [1, 0, 0.2])
    }

    // MARK: themeFromPrimary (a new space's theme is one primary; resolveTheme adds its companions)
    /// keeps the primary first and adds two analogous companions with grain 0.25 and auto appearance
    func test_keepsThePrimaryFirstAndAddsTwoAnalogousCompanionsWithGrain025AndAutoAppearance() throws {
        var theme = SpaceTheme.default
        XCTAssertEqual([theme.texture.rawValue, theme.appearance.rawValue, theme.wheel.rawValue], ["grain", "auto", "analogous"])
        theme.colors = [RGBA(hex: "#7EB8D6")]   // a saturated primary shows the companion math
        XCTAssertEqual(theme.intensity, 0.25)
        // #7EB8D6 is hue 200.7, s 0.5, l 0.667: hue 230.7 at l 0.727 and hue 170.7 at l 0.607.
        XCTAssertEqual(resolveTheme(theme).gradient.map(themeHex), ["#7EB8D6", "#95A1DD", "#67CFBE"])
        XCTAssertEqual(resolveTheme(theme).textureOpacity, 0.2, accuracy: 1e-12)
    }

    /// keeps a grey grey and only nudges its lightness
    func test_keepsAGreyGreyAndOnlyNudgesItsLightness() throws {
        // l = 128/255 = 0.502; 0.562 x 255 = 143.3 and 0.442 x 255 = 112.7.
        for wheel in ColorWheel.allCases {
            let gradient = resolveTheme(SpaceTheme(colors: [RGBA(hex: "#808080")], wheel: wheel, texture: .grain, intensity: 0,
                                                   appearance: .auto)).gradient
            XCTAssertEqual(gradient.map(themeHex), ["#808080", "#8F8F8F", "#717171"], "\(wheel)")
        }
        // White and black stay inside the range.
        let white = resolveTheme(SpaceTheme(colors: [RGBA(hex: "#FFFFFF")], texture: .grain, intensity: 0, appearance: .auto))
        XCTAssertEqual(white.gradient.map(themeHex), ["#FFFFFF", "#FFFFFF", "#F0F0F0"])
    }

    /// produces colors the stored schema accepts for every preset
    func test_producesColorsTheStoredSchemaAcceptsForEveryPreset() throws {
        let sets = [ThemePresets.brand, ThemePresets.drab, ThemePresets.greyscale, ThemePresets.pastel]
        XCTAssertEqual(sets.map(\.count), [9, 9, 9, 9])
        XCTAssertEqual(ThemePresets.brand[4], RGBA(hex: "#FF8558"))
        for preset in sets.joined() {
            for wheel in ColorWheel.allCases {
                let resolved = resolveTheme(SpaceTheme(colors: [preset], wheel: wheel, texture: .sand, intensity: 1, appearance: .auto))
                XCTAssertEqual(resolved.gradient.count, 3)
                XCTAssertEqual(resolved.gradient[0], preset)
                for stop in resolved.gradient {
                    XCTAssertEqual(stop.alpha, 1)
                    for v in [stop.red, stop.green, stop.blue] { XCTAssertTrue((0...1).contains(v), "\(themeHex(preset)) \(wheel)") }
                }
            }
        }
    }

    private func themeHex(_ c: RGBA) -> String {
        "#" + [c.red, c.green, c.blue].map { String(format: "%02X", Int(($0 * 255).rounded())) }.joined()
    }

    private func assertColor(_ c: RGBA, _ r: Double, _ g: Double, _ b: Double, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(c.red * 255, r, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(c.green * 255, g, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(c.blue * 255, b, accuracy: 0.01, file: file, line: line)
        XCTAssertEqual(c.alpha, 1, file: file, line: line)
    }

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
        d.user(.library(.open(.archive)))
        guard case .library(let library)? = d.view.overlay, let page = library.archive else {
            XCTFail("the archive did not open")
            return []
        }
        return page.groups
    }
}
