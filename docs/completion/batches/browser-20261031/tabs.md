# Tabs, folders, archive and tab workflows

Read README.md in this directory first. This is a complete implementation slice, not an audit-only assignment.

Complete the actual sidebar tab/folder workflows, recent/linear/numbered navigation and visible switcher, duplicate/reset-all, range/bulk selection and atomic commands, keyboard reveal/scroll/focus, icon picker, audio indicator/mute, loading/crash/toast/hover states, tab groups, per-window folder expansion, aggregate folder tools, structural folder/split archive and restore, and Live Folders. A014/A015 require real supported site/calendar adapters with freshness, consent and no-meeting feedback; implement fixture-backed product interfaces without mining actual user accounts. GitHub Live Folders must use explicit selected repositories/authorization and native loading/empty/error/refresh/open behavior; never send messages or acquire credentials silently. Structural archive must preserve folder/split title/icon/order/orientation/fractions and restore safely when source spaces disappear. Preserve window-owned slot addresses and private/global mutation safeguards. Do not redesign split identity or coordinate with running workers through their checkout; consume existing Split nodes and add backward-readable optional archive records. Main focus: SidebarTree, domain TabTools/FolderTools/Archive rules/snapshots, BrkSidebar, ArchivePage, deterministic site/calendar adapters. Spaces/theme UI and split content geometry belong to other slices. Dedicated scenarios use TabTools names.

## Owned feature acceptance

### A002 URL pill

Show the focused pane address and open an editable address bar over the pill when clicked.

Current assessment: implemented.
- Add native pill-click and split-pane address checks; no authenticated visual comparison exists.

### A008 Today section and New Tab row

Show Today tabs newest first and open the new-tab command bar from the New Tab row.

Current assessment: implemented.
- Add a native New Tab row click check and verify overflow and empty states against the reference.

### A009 Closing a tab archives it

Cmd+W and a row close button archive a Today tab and close its page; private tabs leave no archive record.

Current assessment: implemented.
- Native scenario 8 proves Cmd+W closure; add row-button and shared-tab window behavior checks.

### A010 Pinned tabs

Pin or unpin with Cmd+D; retain the pinned URL, unload while keeping the row, and reset a drifted URL.

Current assessment: implemented.
- CEF scenario 3 covers pin or unpin only; verify close-and-keep and reset navigation through actual menus.

### A011 Reset all pinned tabs in a space

Reset every pinned tab in the current space to its saved URL, including nested folders and split panes.

Current assessment: missing.
- Implement the aggregate command and URL or page handling without affecting other spaces or profiles.

### A012 Collapse pinned section

Support expanded, collapsed and peeked Pinned states, keeping the selected pinned item available in peeked mode.

Current assessment: partial.
- Add the peeked state, its selected-row layout and interactions; test collapse with nested current tabs.

### A013 Favorites grid

Share Favorites between spaces of one profile; support empty state, dropping in and grid reorder.

Current assessment: implemented.
- Domain and geometry tests are not a native drag demonstration; verify same-grid and cross-space pointer drops and profile switching.

### A014 Favorite badges and subtitles

Render site-derived unread badges and calendar subtitles on supported Favorites with clear update behavior.

Current assessment: missing.
- Define supported site adapters, data refresh and privacy boundaries; implement badge and subtitle presentation.

### A015 Join meeting

Ctrl+Cmd+J opens the next available calendar meeting and handles missing or expired meetings.

Current assessment: missing.
- Implement the calendar data source, next-meeting selection and native empty or failure feedback.

### A016 Next and previous tab

Opt+Cmd+Up and Down traverse sidebar units in order, skip collapsed children and treat a split as one stop.

Current assessment: implemented.
- Add native shortcut checks, especially same-tab selection in two standard windows.

### A017 Recent-tab switcher

Ctrl+Tab and reverse cycling show a recent-tab panel, maintain a stable order during the hold and commit on Control release.

Current assessment: partial.
- Project switcher state and implement the native panel, cancel behavior and visual feedback.

### A018 Linear tab cycling

Ctrl+Cmd+Left and Right cycle tabs in the defined linear order, including boundary behavior.

Current assessment: missing.
- Implement and test the linear cycle contract separately from recent-tab cycling.

### A019 Jump to item 1 to 9 and to space N

Number shortcuts jump to items 1...9 and numbered spaces using documented Favorites and final-item rules.

Current assessment: missing.
- Add commands, bindings, settings for ordering and out-of-range behavior, with native routing tests.

### A020 Rename an item

Rename a tab, Favorite or folder inline; Return commits, Escape cancels and collapsed ancestors reveal the editor.

Current assessment: implemented.
- Extend native checks to double-click entry, folder rename and cancel or focus-loss commit; split rename is not supported.

### A021 Custom icons

Choose or clear a custom icon or emoji for tabs, folders, splits and spaces, and retain it after restart.

Current assessment: partial.
- Build item icon pickers, complete the intended icon repertoire and confirm keyboard, cancel and reset behavior.

### A022 Drag and drop in the sidebar

Drag to reorder rows, nest items in folders, add or reorder Favorites and move items to a dock space without cycles or lost tabs.

Current assessment: implemented.
- Run native pointer scenarios for each destination, scrolling and cancellation; R5b uses a domain move, not a pointer drag.

### A023 Multi-select and bulk actions

Select multiple rows and perform contextual bulk archive, move and new-folder actions, including Other and Below scopes.

Current assessment: partial.
- Add range selection, typed command targets, bulk menus and atomic semantics; verify mixed pinned and Today behavior.

### A024 Duplicate

Duplicate the selected tab or tabs with explicit destination, ordering and fresh identity.

Current assessment: missing.
- Implement single and multi-selection duplication and native entry points.

### A025 Reveal tab and keyboard focus in the sidebar

Ctrl+Space reveals and scrolls to the current item, focuses the sidebar and supports keyboard navigation.

Current assessment: partial.
- Wire reveal commands, ancestor expansion, scrolling and keyboard selection into window-local focus.

### A026 Clear Today

Clear Today archives each current-space Today unit that has no pane on screen in any window.

Current assessment: implemented.
- Verify the Clear button and shortcut with two real windows, including a shared tab and split.

### A027 Restore last closed tab

Shift+Cmd+T restores the latest manually closed or cleared tab, with a defined auto-archive fallback and valid destination.

Current assessment: implemented.
- Add native keyboard, source-space deletion and restarted-session restore checks.

### A028 Sidebar context menus

Provide working context menus for tabs, Favorites, folders, splits and spaces, including their completed workflow actions.

Current assessment: partial.
- Add icon, duplicate, bulk and split-tool actions; confirm destructive actions and run native menu selection checks.

### A029 Audio indicator and mute

Indicate tab audio and allow mute or unmute, retaining the intended saved mute state.

Current assessment: missing.
- Coordinate engine audio events and mute commands with native indicators and persistence.

### A030 Page loading glow

Show the intended loading glow during page loads and clear it on completion, failure or cancellation.

Current assessment: partial.
- Implement or validate the full glow behavior and compare its placement and timing with the reference.

### A031 Hover cards and link previews

Hover supported Favorites, folders and recent pages or links to show dismissible preview cards controlled by settings.

Current assessment: missing.
- Define preview data sources and lifetime, implement hover interactions and settings, and preserve private context.

### A032 Crashed page

Show a recoverable crashed-page state with the intended illustration and usable retry behavior.

Current assessment: partial.
- Complete the sad-tab presentation and failed-recovery path; R7b proves automatic recovery only.

### A033 Tidy titles rule list

Apply explicit non-AI title-shortening rules for known sites while preserving user titles.

Current assessment: missing.
- Add the rule set, precedence and fixtures for matching and nonmatching titles.

### A034 Toasts

Show short dismissible confirmations at the bottom of the correct window and expire them predictably.

Current assessment: missing.
- Implement toast events, queue or replacement policy and native timing tests.

### A035 Tab groups

Create, title, display and operate on tab groups with defined persistence and close behavior.

Current assessment: missing.
- Define group placement and ownership, then implement group operations, restore and native controls.

### A078 Auto-archive

Auto-archive idle Today units using each profile's chosen 1 h through 30 day threshold or Never, excluding every on-screen pane and pinned or Favorite item.

Current assessment: verified.
- Same-tab host arbitration remains a separate window-ownership gap; authenticated visual parity is not claimed.

### A079 Archive page

Show archive entries in date groups, filter them, restore an entry, confirm clearing and edit the profile threshold.

Current assessment: implemented.
- Native scenario 7 covers sweep and restore; add full filter, clear-confirmation and threshold UI checks, including restart.

### A080 Archive whole folders and splits

Archive and restore an entire folder or split as one structural unit, preserving title, icon, children and layout.

Current assessment: partial.
- Add structural archive records and migration; restore nested order, pinned URLs, split orientation and fractions as a unit.

### A082 Auto-archive education banner

Show a dismissible auto-archive education card in the sidebar with accurate threshold copy and saved dismissal.

Current assessment: missing.
- Implement display eligibility, text, dismissal persistence and layout behavior.

### A089 Folders

Create and nest folders in Pinned, expand them, rename them and archive their descendants when deleted.

Current assessment: implemented.
- Verify native nested dragging, deletion and restart; container-unit restore and per-window openness remain separate incomplete rows.

### A090 Collapse and expand all folders

Collapse or expand all folders in the intended space and window without changing hierarchy.

Current assessment: missing.
- Add aggregate commands after settling per-window folder openness; test nested folders and active-item reveal.

### A091 Folder open state per window

Each standard window maintains independent folder expansion state and restores it according to the window persistence contract.

Current assessment: partial.
- Move or represent expansion ownership per window and migrate old saved state; do not patch it in this grounding pass.

### A092 Live Folders

Maintain a GitHub pull-request Live Folder with refresh, opening items and useful loading, empty and error states.

Current assessment: missing.
- Define explicit user-authorized GitHub access, refresh and reconciliation; implement without introducing Brk membership or account requirements.

## Deliverable

Commit implementation, production tests, native scenarios and evidence under `verify/completion/batch-tabs/REPORT.md`. Include `proposal.json` with exactly the assigned IDs, truthful final status, remaining work and repository-local evidence for the parent. Do not edit the canonical inventory. Final reply: PASS/ISSUES/BLOCKED, starting/final commit, changed files, actual commands/results, limitations, and clean-worktree status. No PR or publishing.
