# Favorites badges, join meeting, custom icons, loading glow, hover cards, crashed page

Read README.md in this directory first. This is a complete implementation slice, not an audit-only assignment.

Finish the six sidebar rows.

A014: native badge and subtitle rendering on Favorites tiles from the implemented GitHub-notification and iCalendar adapters, with freshness and update rules and a visible authorization state; no OAuth, the sources stay an explicit user-provided token or an exported .ics file. A015: Ctrl+Cmd+J opens the next meeting from the selected calendar file, gives expiry and no-meeting feedback, and the destination is proven natively; file consent goes through the explicit-selection command path because the panel gesture belongs to file-panels. A021: icon and emoji pickers for tabs, folders, splits and spaces with the full repertoire, keyboard navigation, cancel, clear and restart persistence; `Sources/BrkApp/TabIconPicker.swift` exists. A030: the loading glow driven by real load progress from the engine callbacks, cleared on completion, failure and cancellation, placed and timed against `docs/arc-anatomy`; no Arc pixel claim. A031: metadata cards exist; add dismissible previews for arbitrary webpage links on deliberate hover (title, URL, favicon fetched in the page's own context, never across profiles), lifetime rules and the settings control; the AI summary belongs to ai-features, so expose a hook. A032: the full sad-tab presentation (illustration, message, Reload) and the failed-recovery path where a second crash stays sad with retry; R7b covers automatic recovery only.

Owned paths: `Sources/BrkSidebar/*`, the sad-tab view in `Sources/BrkContent`, `Sources/BrkDomain/{Rules/Tabs,Rules/TabTools,TabToolsModel,CalendarFile}.swift`, `Sources/BrkApp/TabIconPicker.swift`, additive render-terminated and load-progress callbacks in `Sources/BrkCEF/CEFEngine.swift`, and your new `SidebarToolsScenarios.swift`.

## Owned feature acceptance

### A014 Favorite badges and subtitles

Render site-derived unread badges and calendar subtitles on supported Favorites with clear update behavior.

Current assessment: partial.
- Selected GitHub notifications and nonrecurring iCalendar metadata adapters are implemented. Native badge/calendar selection, freshness and authorization evidence remains. No OAuth or live calendar account sync is claimed.

Current behavior: TabRow and FavoritesView have no unread-count or next-event data path.

Existing pointers: `Sources/BrkDomain/Snapshot.swift`, `Sources/BrkSidebar/FavoritesView.swift`

### A015 Join meeting

Ctrl+Cmd+J opens the next available calendar meeting and handles missing or expired meetings.

Current assessment: partial.
- Next-meeting selection and no-meeting feedback are implemented for selected nonrecurring .ics exports. Native file consent, expiry feedback and actual meeting destination proof remains.

Current behavior: joinLiveMeeting is later(joinMeeting).

Existing pointers: `Sources/BrkDomain/Actions.swift`, `Sources/BrkDomain/Command.swift`

### A021 Custom icons

Choose or clear a custom icon or emoji for tabs, folders, splits and spaces, and retain it after restart.

Current assessment: partial.
- Build item icon pickers, complete the intended icon repertoire and confirm keyboard, cancel and reset behavior.

Current behavior: setIcon persists item icons and views draw them; only the space dialog exposes an emoji field and 16 named choices.

Existing pointers: `Sources/BrkDomain/Model.swift`, `Sources/BrkDomain/Rules/Sidebar.swift`, `Sources/BrkSidebar/Glyphs.swift`, `Sources/BrkOverlays/SpaceDialogHost.swift`

### A030 Page loading glow

Show the intended loading glow during page loads and clear it on completion, failure or cancellation.

Current assessment: partial.
- Implement or validate the full glow behavior and compare its placement and timing with the reference.

Current behavior: Loading events drive a URL-pill gradient shimmer and icon spinners; no Arc glow renderer exists.

Existing pointers: `Sources/BrkSidebar/SidebarView.swift`, `Sources/BrkSidebar/Glyphs.swift`, `Sources/BrkDomain/Rules/Tabs.swift`

### A031 Hover cards and link previews

Hover supported Favorites, folders and recent pages or links to show dismissible preview cards controlled by settings.

Current assessment: partial.
- Metadata-only delayed hover cards and the settings control are implemented for sidebar rows and Favorites. Arbitrary webpage link previews and native lifetime/visual checks remain.

Current behavior: There is no hover-card model or native presentation; tooltips and favicon loading are not previews.

Existing pointers: `Sources/BrkSidebar/Controls.swift`, `Sources/BrkSidebar/FavoritesView.swift`, `Sources/BrkDomain/Snapshot.swift`

### A032 Crashed page

Show a recoverable crashed-page state with the intended illustration and usable retry behavior.

Current assessment: partial.
- Complete the sad-tab presentation and failed-recovery path; R7b proves automatic recovery only.

Current behavior: rendererGone projects crashed and automatically requests recover; CardView shows text saying Reloading.

Existing pointers: `Sources/BrkDomain/Rules/Tabs.swift`, `Sources/BrkContent/ContentAreaView.swift`, `Sources/BrkCEF/CEFEngine.swift`

## Deliverable

Commit implementation, production tests, native scenarios (names start with `SidebarTools`) and evidence under `a4cc460bef:verify/completion/batch2-sidebar-tabs/REPORT.md`. Include `proposal.json` with exactly the assigned IDs (A014, A015, A021, A030, A031, A032), truthful final status, remaining work and repository-local evidence for the parent, in the shape of the existing `06656768e1:verify/completion/batch-tabs/proposal.json`. Do not edit the canonical inventory. Final reply: PASS, ISSUES or BLOCKED; starting and final commit; changed files; actual commands and results; limitations; clean-worktree status. No PR or publishing.
