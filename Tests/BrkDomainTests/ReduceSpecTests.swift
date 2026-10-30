import XCTest

@testable import BrkDomain

// The behavioral spec, ported case by case from the Electron version's domain tests (each name and doc comment is
// the original sentence with commands renamed to the Swift vocabulary). Drive state only through the public
// surface, as `Driver` does: StateCodec.restore(nil, ...) plus commands, never literal state; assert on what views
// and the engine read (snapshots, pages, effects, saved bytes). Each case is skipped until W1 writes it.
//
// Dropped from the port: prototype-member-ids.test.ts (Swift dictionaries have no prototype members) and the
// handler-group disjointness test (Swift's exhaustive switch in `Work.run` makes it a compile error).

final class ReduceSpecTests: XCTestCase {
    // MARK: - electron-v1:src/domain/reduce.test.ts
    // MARK: reduce: tabs
    /// .commandBar(.submit) with the new-tab bar open adds a tab at the top of the current space Today and focuses it (project row status current)
    func test_commandbarSubmitWithTheNewTabBarOpenAddsATabAtTheTopOfTheCurrentSpaceToday() throws { throw XCTSkip(pendingW1) }

    /// .commandBar(.submit) refuses input that resolves to nothing and keeps the bar open
    func test_commandbarSubmitRefusesInputThatResolvesToNothingAndKeepsTheBarOpen() throws { throw XCTSkip(pendingW1) }

    /// .commandBar(.submit) with no bar open behaves like the new-tab bar
    func test_commandbarSubmitWithNoBarOpenBehavesLikeTheNewTabBar() throws { throw XCTSkip(pendingW1) }

    /// .commandBar(.submit) with a navigate target sets the tab url and emits Effect.page(.navigate) without adding a row
    func test_commandbarSubmitWithANavigateTargetSetsTheTabUrlAndEmitsEffectPageNavigate() throws { throw XCTSkip(pendingW1) }

    /// .commandBar(.open) with the same target is a no-op that keeps the opening identity; a different target is a new opening
    func test_commandbarOpenWithTheSameTargetIsANoOpThatKeepsTheOpeningIdentityADifferent() throws { throw XCTSkip(pendingW1) }

    /// an archive command picked from the command bar closes the bar, while archive commands keep the archive page open
    func test_anArchiveCommandPickedFromTheCommandBarClosesTheBarWhileArchiveCommands() throws { throw XCTSkip(pendingW1) }

    /// .commandBar(.open) edit-current is centered while the sidebar is hidden, and new-tab when nothing is shown
    func test_commandbarOpenEditCurrentIsCenteredWhileTheSidebarIsHiddenAndNewTabWhen() throws { throw XCTSkip(pendingW1) }

    /// the command bar lists open tabs with the focused one first, then by recency, and the history
    func test_theCommandBarListsOpenTabsWithTheFocusedOneFirstThenByRecencyAndTheHistory() throws { throw XCTSkip(pendingW1) }

    /// .commandBar(.dismiss) closes the bar; any other user command closes it too, including archive and settings commands
    func test_commandbarDismissClosesTheBarAnyOtherUserCommandClosesItTooIncludingArchive() throws { throw XCTSkip(pendingW1) }

    /// .tab(.focus) on the already focused tab returns the same state object (no rev bump, docChanged false)
    func test_tabFocusOnTheAlreadyFocusedTabReturnsTheSameStateObjectNoRevBumpDocChanged() throws { throw XCTSkip(pendingW1) }

    /// .tab(.focus) on another tab bumps rev, shows it, and is ignored for an unknown id
    func test_tabFocusOnAnotherTabBumpsRevShowsItAndIsIgnoredForAnUnknownId() throws { throw XCTSkip(pendingW1) }

    /// .tab(.togglePin) moves Today -> end of Pinned and sets pinnedUrl = url; again moves it to the top of Today and clears pinnedUrl
    func test_tabTogglePinMovesTodayEndOfPinnedAndSetsPinnedUrlUrlAgainMovesItToTheTop() throws { throw XCTSkip(pendingW1) }

    /// .tab(.close) on a Today tab archives it with reason manual and focuses the most recent other tab of the space
    func test_tabCloseOnATodayTabArchivesItWithReasonManualAndFocusesTheMostRecentOther() throws { throw XCTSkip(pendingW1) }

    /// the Pinned-tab menu offers Close and Keep Pinned and a separate Archive Tab that archives it
    func test_thePinnedTabMenuOffersCloseAndKeepPinnedAndASeparateArchiveTabThatArchives() throws { throw XCTSkip(pendingW1) }

    /// .tab(.archive) keeps a Today tab menu to a single Archive Tab entry (.tab(.close))
    func test_tabArchiveKeepsATodayTabMenuToASingleArchiveTabEntryTabClose() throws { throw XCTSkip(pendingW1) }

    /// .tab(.close) on a Pinned tab keeps the row, drops it from loaded, and moves activeBySpace to the most recent other loaded tab
    func test_tabCloseOnAPinnedTabKeepsTheRowDropsItFromLoadedAndMovesActiveBySpaceTo() throws { throw XCTSkip(pendingW1) }

    /// .tab(.close) on the only loaded tab of a space deletes the activeBySpace entry: project reports no panes and normalize does not refill it
    func test_tabCloseOnTheOnlyLoadedTabOfASpaceDeletesTheActiveBySpaceEntryProjectReports() throws { throw XCTSkip(pendingW1) }

    /// .tab(.reset) on a pinned tab whose url drifted restores pinnedUrl and emits Effect.page(.navigate)
    func test_tabResetOnAPinnedTabWhoseUrlDriftedRestoresPinnedUrlAndEmitsEffectPageNavigate() throws { throw XCTSkip(pendingW1) }

    /// .tab(.step) walks sidebarOrder without wrapping; a split counts as one stop
    func test_tabStepWalksSidebarOrderWithoutWrappingASplitCountsAsOneStop() throws { throw XCTSkip(pendingW1) }

    /// .tab(.cycleRecent) freezes the recent order on the first press; the commit stamps the net on-screen change
    func test_tabCycleRecentFreezesTheRecentOrderOnTheFirstPressTheCommitStampsTheNet() throws { throw XCTSkip(pendingW1) }

    /// .tab(.cycleRecent) with one tab is a no-op
    func test_tabCycleRecentWithOneTabIsANoOp() throws { throw XCTSkip(pendingW1) }

    /// any user command other than .tab(.cycleRecent) commits a pending cycle (robust against a lost Control keyUp)
    func test_anyUserCommandOtherThanTabCycleRecentCommitsAPendingCycleRobustAgainstA() throws { throw XCTSkip(pendingW1) }

    /// .page events for an archived or unknown tab is ignored: same state object
    func test_pageEventsForAnArchivedOrUnknownTabIsIgnoredSameStateObject() throws { throw XCTSkip(pendingW1) }

    /// .page events is ignored for an unloaded pinned tab, and the same patch twice changes nothing the second time
    func test_pageEventsIsIgnoredForAnUnloadedPinnedTabAndTheSamePatchTwiceChangesNothing() throws { throw XCTSkip(pendingW1) }

    /// .page events url pushes a history entry, deduplicated by url and capped at Metrics.persistence.historyCap
    func test_pageEventsUrlPushesAHistoryEntryDeduplicatedByUrlAndCappedAtMetricsPersistence() throws { throw XCTSkip(pendingW1) }

    /// .openRequested from a Favorites tab opens in the window current space Today; background keeps focus
    func test_openrequestedFromAFavoritesTabOpensInTheWindowCurrentSpaceTodayBackground() throws { throw XCTSkip(pendingW1) }

    /// .openRequested refuses a disallowed URL, a file URL from a web page, and an unknown opener
    func test_openrequestedRefusesADisallowedURLAFileURLFromAWebPageAndAnUnknownOpener() throws { throw XCTSkip(pendingW1) }

    /// .gainedFocus on a pane of the active split sets focusedId so a later .tab(.close) resolves focused to that pane
    func test_gainedfocusOnAPaneOfTheActiveSplitSetsFocusedIdSoALaterTabCloseResolves() throws { throw XCTSkip(pendingW1) }

    /// .gainedFocus on a tab that is not a pane is a no-op
    func test_gainedfocusOnATabThatIsNotAPaneIsANoOp() throws { throw XCTSkip(pendingW1) }

    /// browsing commands resolve the focused tab into effects; an unloaded or unknown target emits nothing
    func test_browsingCommandsResolveTheFocusedTabIntoEffectsAnUnloadedOrUnknownTarget() throws { throw XCTSkip(pendingW1) }

    // MARK: reduce: tree
    /// .item(.move) refuses moving a folder into its own descendant (state unchanged)
    func test_itemMoveRefusesMovingAFolderIntoItsOwnDescendantStateUnchanged() throws { throw XCTSkip(pendingW1) }

    /// .item(.move) refuses what canPlace forbids: a folder into Today, anything into a split
    func test_itemMoveRefusesWhatCanPlaceForbidsAFolderIntoTodayAnythingIntoASplit() throws { throw XCTSkip(pendingW1) }

    /// .item(.move) within the same parent counts the index after the item is detached, so applying it twice is a no-op
    func test_itemMoveWithinTheSameParentCountsTheIndexAfterTheItemIsDetachedSoApplying() throws { throw XCTSkip(pendingW1) }

    /// .item(.move) to a dock space puts a Today item at the top of that space Today and a Pinned item at the end of its Pinned
    func test_itemMoveToADockSpacePutsATodayItemAtTheTopOfThatSpaceTodayAndAPinnedItem() throws { throw XCTSkip(pendingW1) }

    /// .item(.newFolder) adds a folder at the top of Pinned in rename mode and expands Pinned; .item(.toggleFolder) collapses it
    func test_itemNewFolderAddsAFolderAtTheTopOfPinnedInRenameModeAndExpandsPinnedItem() throws { throw XCTSkip(pendingW1) }

    /// .item(.deleteFolder) archives every tab inside with reason container-deleted and removes the folder
    func test_itemDeleteFolderArchivesEveryTabInsideWithReasonContainerDeletedAndRemoves() throws { throw XCTSkip(pendingW1) }

    /// .item(.rename) with null cancels; with "" clears customTitle; a page title update never clobbers customTitle
    func test_itemRenameWithNullCancelsWithClearsCustomTitleAPageTitleUpdateNeverClobbers() throws { throw XCTSkip(pendingW1) }

    /// .item(.beginRename) with the sidebar hidden peeks it so the input is visible
    func test_itemBeginRenameWithTheSidebarHiddenPeeksItSoTheInputIsVisible() throws { throw XCTSkip(pendingW1) }

    // MARK: reduce: split
    /// .split(.addPane) on a tab replaces it in place by a split of [tab, empty pane] and opens the command bar targeting the empty pane
    func test_splitAddPaneOnATabReplacesItInPlaceByASplitOfTabEmptyPaneAndOpensTheCommand() throws { throw XCTSkip(pendingW1) }

    /// .split(.addPane) with nothing shown, or on a Favorites tab, is a no-op
    func test_splitAddPaneWithNothingShownOrOnAFavoritesTabIsANoOp() throws { throw XCTSkip(pendingW1) }

    /// .split(.addPane) on a split with Metrics.content.maxPanes panes is a no-op
    func test_splitAddPaneOnASplitWithMetricsContentMaxPanesPanesIsANoOp() throws { throw XCTSkip(pendingW1) }

    /// .split(.addPane) inserts the new pane after the focused pane with an equal share
    func test_splitAddPaneInsertsTheNewPaneAfterTheFocusedPaneWithAnEqualShare() throws { throw XCTSkip(pendingW1) }

    /// .split(.closePane) leaving one pane dissolves the split into that tab, in place (normalize)
    func test_splitClosePaneLeavingOnePaneDissolvesTheSplitIntoThatTabInPlaceNormalize() throws { throw XCTSkip(pendingW1) }

    /// .split(.closePane) in Pinned moves the pane out after the split and unloads it instead of archiving
    func test_splitClosePaneInPinnedMovesThePaneOutAfterTheSplitAndUnloadsItInsteadOf() throws { throw XCTSkip(pendingW1) }

    /// .split(.resize) normalizes fractions to sum 1 and clamps each to at least Metrics.content.minPaneFraction
    func test_splitResizeNormalizesFractionsToSum1AndClampsEachToAtLeastMetricsContent() throws { throw XCTSkip(pendingW1) }

    /// moving a pane out of its split with .item(.move) leaves a one-pane split that normalize dissolves
    func test_movingAPaneOutOfItsSplitWithItemMoveLeavesAOnePaneSplitThatNormalizeDissolves() throws { throw XCTSkip(pendingW1) }

    // MARK: reduce: spaces and archive
    /// .space(.create) creates an empty space, switches to it and closes the dialog; a blank title gets the fallback name
    func test_spaceCreateCreatesAnEmptySpaceSwitchesToItAndClosesTheDialogABlankTitle() throws { throw XCTSkip(pendingW1) }

    /// .space(.focus) switches the gradient and rows and returns to that space last active item
    func test_spaceFocusSwitchesTheGradientAndRowsAndReturnsToThatSpaceLastActiveItem() throws { throw XCTSkip(pendingW1) }

    /// .space(.step) moves to the neighbour without wrapping
    func test_spaceStepMovesToTheNeighbourWithoutWrapping() throws { throw XCTSkip(pendingW1) }

    /// .space(.move) reorders the dock with the index clamped
    func test_spaceMoveReordersTheDockWithTheIndexClamped() throws { throw XCTSkip(pendingW1) }

    /// .space(.update) patches title, icon and theme and closes the edit dialog; the same values change nothing
    func test_spaceUpdatePatchesTitleIconAndThemeAndClosesTheEditDialogTheSameValuesChange() throws { throw XCTSkip(pendingW1) }

    /// .space(.togglePinnedSection) collapses and expands the current space Pinned section
    func test_spaceTogglePinnedSectionCollapsesAndExpandsTheCurrentSpacePinnedSection() throws { throw XCTSkip(pendingW1) }

    /// .space(.delete) of the last space is refused
    func test_spaceDeleteOfTheLastSpaceIsRefused() throws { throw XCTSkip(pendingW1) }

    /// .space(.delete) archives its Pinned and Today tabs with reason container-deleted and moves windows on it to the neighbour in spaceOrder
    func test_spaceDeleteArchivesItsPinnedAndTodayTabsWithReasonContainerDeletedAndMoves() throws { throw XCTSkip(pendingW1) }

    /// .clockTick archives idle Today tabs older than the threshold but never a visible tab, a Pinned tab or a Favorites tab
    func test_clocktickArchivesIdleTodayTabsOlderThanTheThresholdButNeverAVisibleTabA() throws { throw XCTSkip(pendingW1) }

    /// .clockTick twice at the same time is a no-op the second time (same state object)
    func test_clocktickTwiceAtTheSameTimeIsANoOpTheSecondTimeSameStateObject() throws { throw XCTSkip(pendingW1) }

    /// .clockTick with autoArchiveAfter never archives nothing
    func test_clocktickWithAutoArchiveAfterNeverArchivesNothing() throws { throw XCTSkip(pendingW1) }

    /// .settings(.autoArchive) changes the threshold the sweep uses and the archive view shows
    func test_settingsAutoArchiveChangesTheThresholdTheSweepUsesAndTheArchiveViewShows() throws { throw XCTSkip(pendingW1) }

    /// .tab(.clearToday) keeps the tabs visible in any window
    func test_tabClearTodayKeepsTheTabsVisibleInAnyWindow() throws { throw XCTSkip(pendingW1) }

    /// .archive(.open) opens the archive in the content card and is idempotent; .archive(.clear) empties it
    func test_archiveOpenOpensTheArchiveInTheContentCardAndIsIdempotentArchiveClearEmpties() throws { throw XCTSkip(pendingW1) }

    /// .archive(.restore) puts the tab back in its source section when the space still exists, else at the top of the dispatching window current space Today
    func test_archiveRestorePutsTheTabBackInItsSourceSectionWhenTheSpaceStillExistsElse() throws { throw XCTSkip(pendingW1) }

    /// .archive(.restoreLast) restores archive[0] and focuses it; with an empty archive it is a no-op
    func test_archiveRestoreLastRestoresArchive0AndFocusesItWithAnEmptyArchiveItIsANo() throws { throw XCTSkip(pendingW1) }

    /// .archive(.restoreLast) prefers the newest manual/clear entry over an auto-archived one that landed later
    func test_archiveRestoreLastPrefersTheNewestManualClearEntryOverAnAutoArchivedOne() throws { throw XCTSkip(pendingW1) }

    /// a restored tab is not swept again at once even if it was idle for long
    func test_aRestoredTabIsNotSweptAgainAtOnceEvenIfItWasIdleForLong() throws { throw XCTSkip(pendingW1) }

    /// archive entries are capped at Metrics.persistence.archiveCap, oldest dropped
    func test_archiveEntriesAreCappedAtMetricsPersistenceArchiveCapOldestDropped() throws { throw XCTSkip(pendingW1) }

    // MARK: window chrome
    /// .sidebar(.toggle) hides the sidebar (content fills the window) and again restores it
    func test_sidebarToggleHidesTheSidebarContentFillsTheWindowAndAgainRestoresIt() throws { throw XCTSkip(pendingW1) }

    /// .sidebar(.peek) floats the hidden sidebar only while it is hidden; toggling ends the peek
    func test_sidebarPeekFloatsTheHiddenSidebarOnlyWhileItIsHiddenTogglingEndsThePeek() throws { throw XCTSkip(pendingW1) }

    /// .sidebar(.openDialog) opens the space dialog (peeking a hidden sidebar), moves focus to the sidebar, and null closes it
    func test_sidebarOpenDialogOpensTheSpaceDialogPeekingAHiddenSidebarMovesFocusToThe() throws { throw XCTSkip(pendingW1) }

    /// .sidebar(.popupMenu) emits a native menu built from state whose entries dispatch real commands
    func test_sidebarPopupMenuEmitsANativeMenuBuiltFromStateWhoseEntriesDispatchRealCommands() throws { throw XCTSkip(pendingW1) }

    // MARK: persistence (StateCodec.restore / StateCodec.encode)
    /// StateCodec.encode then StateCodec.restore round-trips Doc exactly (items, spaces, order, favorites, archive, history, windows, settings) and rebuilds Session fresh
    func test_statecodecEncodeThenStateCodecRestoreRoundTripsDocExactlyItemsSpacesOrder() throws { throw XCTSkip(pendingW1) }

    /// StateCodec.restore of null is a fresh profile with one space, one window and one Today tab at startUrl
    func test_statecodecRestoreOfNullIsAFreshProfileWithOneSpaceOneWindowAndOneTodayTab() throws { throw XCTSkip(pendingW1) }

    /// StateCodec.restore repairs an orphan child reference and reports it in RestoreOutcome.restored(repairs:)
    func test_statecodecRestoreRepairsAnOrphanChildReferenceAndReportsItInRestoreOutcome() throws { throw XCTSkip(pendingW1) }

    /// StateCodec.restore repairs a missing section root and a folder that sits in Today
    func test_statecodecRestoreRepairsAMissingSectionRootAndAFolderThatSitsInToday() throws { throw XCTSkip(pendingW1) }

    /// StateCodec.restore rejects a file with an unknown version, and a file whose doc has no spaces
    func test_statecodecRestoreRejectsAFileWithAnUnknownVersionAndAFileWhoseDocHasNoSpaces() throws { throw XCTSkip(pendingW1) }

    /// a restored Today tab whose page later fails to load keeps its url and title (failure is live state only)
    func test_aRestoredTodayTabWhosePageLaterFailsToLoadKeepsItsUrlAndTitleFailureIsLive() throws { throw XCTSkip(pendingW1) }

    // MARK: layout clamps (domain side)
    /// .sidebar(.resize) clamps the width to Metrics.sidebar.minWidth...maxWidth
    func test_sidebarResizeClampsTheWidthToMetricsSidebarMinWidthMaxWidth() throws { throw XCTSkip(pendingW1) }

    /// .geometry updates contentSize so project reflects the new size, and persists bounds
    func test_geometryUpdatesContentSizeSoProjectReflectsTheNewSizeAndPersistsBounds() throws { throw XCTSkip(pendingW1) }

    /// normalize clamps a stored sidebar width outside the range on restore
    func test_normalizeClampsAStoredSidebarWidthOutsideTheRangeOnRestore() throws { throw XCTSkip(pendingW1) }

    /// a user command for a window that does not exist is dropped
    func test_aUserCommandForAWindowThatDoesNotExistIsDropped() throws { throw XCTSkip(pendingW1) }

    // MARK: handler groups
    /// are disjoint, so spreading them into one table cannot shadow a handler
    func test_areDisjointSoSpreadingThemIntoOneTableCannotShadowAHandler() throws { throw XCTSkip(pendingW1) }

    /// cover every UiCommand type, and every command type has a behavior test above
    func test_coverEveryUiCommandTypeAndEveryCommandTypeHasABehaviorTestAbove() throws { throw XCTSkip(pendingW1) }

    // MARK: - electron-v1:src/domain/auto-archive-stamps-on-leaving-screen.test.ts
    // MARK: auto-archive stamps a tab as it leaves the screen
    /// a tab read for 11 hours then left with Ctrl+Tab is not archived one hour later
    func test_aTabReadFor11HoursThenLeftWithCtrlTabIsNotArchivedOneHourLater() throws { throw XCTSkip(pendingW1) }

    /// a tab read for 13 hours then dropped on another space is not archived by the next sweep
    func test_aTabReadFor13HoursThenDroppedOnAnotherSpaceIsNotArchivedByTheNextSweep() throws { throw XCTSkip(pendingW1) }

    /// a tab left continuously on screen past the threshold is kept, and stamped only when it finally leaves
    func test_aTabLeftContinuouslyOnScreenPastTheThresholdIsKeptAndStampedOnlyWhenItFinally() throws { throw XCTSkip(pendingW1) }

    // MARK: - electron-v1:src/domain/background-tab-loads.test.ts
    // MARK: a background-opened tab loads
    /// .openRequested background:true marks the tab loaded and keeps focus on the opener
    func test_openrequestedBackgroundTrueMarksTheTabLoadedAndKeepsFocusOnTheOpener() throws { throw XCTSkip(pendingW1) }

    /// a foreground .openRequested still focuses the new tab and loads it
    func test_aForegroundOpenRequestedStillFocusesTheNewTabAndLoadsIt() throws { throw XCTSkip(pendingW1) }

    /// restore stays lazy: only the shown tab is loaded after a restart, not every stored tab
    func test_restoreStaysLazyOnlyTheShownTabIsLoadedAfterARestartNotEveryStoredTab() throws { throw XCTSkip(pendingW1) }

    // MARK: - electron-v1:src/domain/empty-split-pane-not-archived.test.ts
    // MARK: empty split pane is not archived
    /// closing the focused empty pane with Ctrl+Shift+- archives nothing
    func test_closingTheFocusedEmptyPaneWithCtrlShiftArchivesNothing() throws { throw XCTSkip(pendingW1) }

    /// clearing Today with an off-screen empty split pane archives only tabs that have a URL
    func test_clearingTodayWithAnOffScreenEmptySplitPaneArchivesOnlyTabsThatHaveAURL() throws { throw XCTSkip(pendingW1) }

    // MARK: - electron-v1:src/domain/sidebar-peek-keeps-archive.test.ts
    // MARK: peek and resize keep the archive open
    /// hide the sidebar, open the archive, peek: the archive stays open and the sidebar floats over it
    func test_hideTheSidebarOpenTheArchivePeekTheArchiveStaysOpenAndTheSidebarFloatsOver() throws { throw XCTSkip(pendingW1) }

    /// dragging the resize handle while the archive is open keeps it open
    func test_draggingTheResizeHandleWhileTheArchiveIsOpenKeepsItOpen() throws { throw XCTSkip(pendingW1) }

    /// a resize still keeps an open command bar, while toggling the sidebar closes it
    func test_aResizeStillKeepsAnOpenCommandBarWhileTogglingTheSidebarClosesIt() throws { throw XCTSkip(pendingW1) }

    // MARK: - electron-v1:src/domain/space-fallback-title.test.ts
    // MARK: fallback space title
    /// a fresh profile shows "Space 1" but stores an empty title
    func test_aFreshProfileShowsSpace1ButStoresAnEmptyTitle() throws { throw XCTSkip(pendingW1) }

    /// deleting a space and creating another does not duplicate "Space N"
    func test_deletingASpaceAndCreatingAnotherDoesNotDuplicateSpaceN() throws { throw XCTSkip(pendingW1) }

    /// a named space keeps its name; the archive fromSpaceTitle also derives "Space N"
    func test_aNamedSpaceKeepsItsNameTheArchiveFromSpaceTitleAlsoDerivesSpaceN() throws { throw XCTSkip(pendingW1) }
}
