import XCTest

@testable import BrkDomain

// URL policy, placement rules, theme resolution and archive buckets, ported from the Electron tests of
// src/shared/url.ts, placement.ts, theme.ts and src/renderer/overlay/archive-groups.ts (bucketing moved into the
// projection, so it is tested here). Owners: W1 (url, placement), W5 (theme), W4 (archive buckets).

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
    func test_matchesTheWCAGEndpointsAndAMidGrey() throws { throw XCTSkip(pendingW1) }

    // MARK: resolveTheme
    /// picks the light scheme and light tokens for a light primary
    func test_picksTheLightSchemeAndLightTokensForALightPrimary() throws { throw XCTSkip(pendingW1) }

    /// picks the dark scheme and dark tokens for a dark primary
    func test_picksTheDarkSchemeAndDarkTokensForADarkPrimary() throws { throw XCTSkip(pendingW1) }

    /// gives the default mid-tone blue the light scheme (black text has the higher contrast)
    func test_givesTheDefaultMidToneBlueTheLightSchemeBlackTextHasTheHigherContrast() throws { throw XCTSkip(pendingW1) }

    /// lets a forced appearance override the luminance
    func test_letsAForcedAppearanceOverrideTheLuminance() throws { throw XCTSkip(pendingW1) }

    // MARK: themeFromPrimary
    /// keeps the primary first and adds two analogous companions with grain 0.25 and auto appearance
    func test_keepsThePrimaryFirstAndAddsTwoAnalogousCompanionsWithGrain025AndAutoAppearance() throws { throw XCTSkip(pendingW1) }

    /// keeps a grey grey and only nudges its lightness
    func test_keepsAGreyGreyAndOnlyNudgesItsLightness() throws { throw XCTSkip(pendingW1) }

    /// produces colors the stored schema accepts for every preset
    func test_producesColorsTheStoredSchemaAcceptsForEveryPreset() throws { throw XCTSkip(pendingW1) }

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
