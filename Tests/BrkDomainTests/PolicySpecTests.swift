import XCTest

@testable import BrkDomain

// URL policy, placement rules, theme resolution and archive buckets, ported from the Electron tests of
// src/shared/url.ts, placement.ts, theme.ts and src/renderer/overlay/archive-groups.ts (bucketing moved into the
// projection, so it is tested here). Owners: W1 (url, placement, archive buckets), W5 (theme).

final class PolicySpecTests: XCTestCase {
    // MARK: - electron-v1:src/shared/url.test.ts
    // MARK: resolveTypedInput
    /// returns null for empty or whitespace input
    func test_returnsNullForEmptyOrWhitespaceInput() throws { throw XCTSkip(pendingW1) }

    /// treats a host with a port, an IP address or a dotted domain as a URL and adds the scheme
    func test_treatsAHostWithAPortAnIPAddressOrADottedDomainAsAURLAndAddsTheScheme() throws { throw XCTSkip(pendingW1) }

    /// keeps an explicit allowed scheme
    func test_keepsAnExplicitAllowedScheme() throws { throw XCTSkip(pendingW1) }

    /// searches a bare word, text with spaces, a number and a refused scheme
    func test_searchesABareWordTextWithSpacesANumberAndARefusedScheme() throws { throw XCTSkip(pendingW1) }

    // MARK: isAllowedUrl
    /// allows http, https, file and about:blank
    func test_allowsHttpHttpsFileAndAboutBlank() throws { throw XCTSkip(pendingW1) }

    /// refuses every other scheme and unparseable text
    func test_refusesEveryOtherSchemeAndUnparseableText() throws { throw XCTSkip(pendingW1) }

    // MARK: displayUrl
    /// drops the scheme, www. and the trailing slash
    func test_dropsTheSchemeWwwAndTheTrailingSlash() throws { throw XCTSkip(pendingW1) }

    /// shows a file path and leaves other text alone
    func test_showsAFilePathAndLeavesOtherTextAlone() throws { throw XCTSkip(pendingW1) }

    // MARK: - electron-v1:src/shared/placement.test.ts
    // MARK: canPlace
    /// lets Favorites hold tabs only, flat
    func test_letsFavoritesHoldTabsOnlyFlat() throws { throw XCTSkip(pendingW1) }

    /// lets Pinned hold tabs, splits and nested folders
    func test_letsPinnedHoldTabsSplitsAndNestedFolders() throws { throw XCTSkip(pendingW1) }

    /// lets Today hold tabs and splits, never folders
    func test_letsTodayHoldTabsAndSplitsNeverFolders() throws { throw XCTSkip(pendingW1) }

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

    /// gives the default mid-tone blue the light scheme (black text has the higher contrast)
    func test_givesTheDefaultMidToneBlueTheLightSchemeBlackTextHasTheHigherContrast() throws {
        XCTAssertEqual(SpaceTheme.default.colors, [RGBA(hex: "#7EB8D6")])
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
        let theme = SpaceTheme.default
        XCTAssertEqual([theme.texture.rawValue, theme.appearance.rawValue, theme.wheel.rawValue], ["grain", "auto", "analogous"])
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
    func test_onAMondaySundayIsYesterdayAndSaturdayIsPastMonthTheWeekHasNoEarlierDays() throws { throw XCTSkip(pendingW1) }

    /// on a Tuesday, Monday is yesterday and Sunday is past-month
    func test_onATuesdayMondayIsYesterdayAndSundayIsPastMonth() throws { throw XCTSkip(pendingW1) }

    // MARK: groupArchive
    /// returns non-empty groups in bucket order with labels, entries newest first
    func test_returnsNonEmptyGroupsInBucketOrderWithLabelsEntriesNewestFirst() throws { throw XCTSkip(pendingW1) }

    /// labels the past-week group "Earlier This Week"
    func test_labelsThePastWeekGroupEarlierThisWeek() throws { throw XCTSkip(pendingW1) }

    /// returns no groups for no entries
    func test_returnsNoGroupsForNoEntries() throws { throw XCTSkip(pendingW1) }

    // MARK: archivedWhen
}
