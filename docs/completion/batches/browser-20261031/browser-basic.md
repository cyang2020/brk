# Browser foundations and native operations

Read README.md in this directory first. This is a complete implementation slice, not an audit-only assignment.

Deliver actual navigation/zoom/edit/developer operations, output/save/print/PDF/share/cast, window/blank/stay-on-top/restore controls, complete command/address-bar interactions and Little Arc/Peek/external-link behavior. Resolve C5 output ownership before implementation using the original core design probes and current browser/document/context lifetimes. Native operation UI must belong to the initiating window and retain exactly the resources needed until cancellation/completion. Validate output bytes by parsing/reopening, and preserve files on ambiguous outcomes. Do not count a visible print sheet as printer submission or an advertised Cast command as a working receiver. Use an owned virtual destination or real supported receiver evidence where available and keep external hardware gaps explicit. Wire restoreWindowsOnLaunch and relevant settings. Do not implement A039 Find, site-data/permission policy or extension management; those have other owners. Do not read or cherry-pick a running worker checkout. Provide additive hooks that can coexist with the find adapter. Main focus files: BrkCEF browser/operations adapters, BrkEngine, BrkApp native operations/window/links/lifecycle, domain BrowserOperations rules, command-bar sources. Dedicated new tests/scenarios use BrowserBasic names.

## Owned feature acceptance

### A036 Back, forward, reload, stop

Back, forward, normal/forced reload and stop target the focused loaded page, including split and Peek, honor shortcut priorities, and preserve focus after navigation.

Current assessment: implemented.
- Verify real back/forward/stop and forced cache-bypass behavior, split/Peek targets and private contexts; existing native evidence covers only part of the row.

### A037 Key priorities and press twice

App priority, page priority and page-first/second-press behavior work for every implemented chord and user override, with preventDefault, repeat, native editors, distinct windows and exactly-once dispatch.

Current assessment: partial.
- Model the raw pre-key out-parameter intent and measure Chrome accelerator ordering before changing contracts.
- Preserve default Downloads Cmd+Shift+J app priority and explicit page-priority override.
- Extend real tests to affected Chrome commands, swallowed/unswallowed events, native fields, remaps and duplicate paths.

### A038 Zoom

Zoom in/out/reset follows Chrome preset percentages and limits, displays the effective value, and affects the focused page with correct key priority.

Current assessment: partial.
- Implement exact preset/limit behavior and effective-value readback.
- Verify actual rendered scale and focus across normal, split and Peek pages.

### A040 Copy URL

Copy URL, URL as Markdown and URL as Quote write the expected clipboard text for the focused tab or Peek without navigation or profile leakage.

Current assessment: implemented.
- Verify native pasteboard contents from menu and keyboard for all three formats, including Peek and titles requiring Markdown escaping.
- Confirm quote semantics against authenticated reference; current quote is title plus URL, not selected page text.

### A041 Developer tools

View Source, DevTools toggle, element inspection, console, network, JavaScript from Apple Events setting and developer mode execute their named behavior on the correct page and close safely.

Current assessment: partial.
- Wrap source/inspect and explicit panel selection or supported commands; resolve Apple Events and developer-mode behavior.
- Verify real auxiliary windows, input, page association and shutdown after reparenting.

### A044 Save, print, share, cast

Save Page As creates a usable offline page in supported formats; Print and PDF export report completion/cancellation; Share writes a local file; Cast selects and controls a real receiver, with correct page/window/profile ownership.

Current assessment: partial.
- Implement save-page content rather than confuse link export with saved HTML.
- Wrap PDF callbacks, validate output, and test native print/save dialogs after embedding.
- Connect version-safe Chrome command lookup if used; cef_id_for_command_id_name is not in the current loader symbols.
- Verify local export save panel; its existing test is skipped and write errors are currently swallowed.
- Implement and test Cast routing with a receiver; no evidence exists yet.

### A045 Full screen and Exit

Ctrl+Cmd+F enters/leaves native fullscreen; Escape closes the current overlay first and exits page/video or window fullscreen when appropriate, without activating a hidden CEF host.

Current assessment: partial.
- Connect or explicitly reconcile DOM/video fullscreen with the native window.
- Verify physical key/traffic-light input, fullscreen media, overlay precedence, and focus return.

### A046 Edit menu

All standard editing, spelling/grammar, substitutions, transformations, speech and font actions are enabled only when their responder supports them and work in native editors and applicable webpage editing contexts.

Current assessment: partial.
- Exercise menu clicks and shortcuts in native fields, HTML input, textarea, contenteditable and frames.
- Resolve selector differences such as pasteAsPlainText: vs CefBrowser.pasteAndMatchStyle and unsupported rich editing.
- Implement the missing spelling/substitution/transformation/speech/font behavior; do not count menu topology tests as execution.

### A047 History

Cmd+Y presents the profile history with search/open/remove behavior and an explicit complete retention/visit model; private visits never appear or persist.

Current assessment: partial.
- Resolve full-history semantics vs latest-per-URL cap and implement any missing visit/pagination behavior.
- Keep browsing-data clearing tracked under A095; current History clear must not imply successful site-data deletion.
- Verify search/open/remove and repeated-visit persistence, including private contexts.

### A049 Links that open new tabs and popups

Cmd+click opens a background tab; foreground-modifier opens and popups retain correct disposition, opener/context and requested window behavior, including private and hidden source pages.

Current assessment: partial.
- Preserve raw disposition/user-gesture/frame/popup identity before adding real popup windows.
- Test empty-URL window.open/document.write and opener-dependent auth flows; current .handled cancels CEF popup creation.
- Preserve hidden-private ownership and Option+Cmd privacy fixes.

### A050 Session restore

Restart restores standard windows/spaces/tabs/geometry lazily when enabled, honors the restore-windows setting when disabled, and never restores private or Little Brk session data.

Current assessment: partial.
- Wire the restore setting to the restore path and define startup behavior when off.
- Verify multiple restored standard windows and profile replacement with exact current per-window focus contract.

### A052 Blank window

Blank Window opens a native browser window whose sidebar has no inherited items and whose lifetime/persistence/profile behavior is explicit.

Current assessment: missing.
- Specify and implement its container, UI and restore/close behavior; a normal new window with an empty card still shares sidebar items.

### A053 Hide, minimize, zoom, bring all to front

Hide, Hide Others, Show All, Minimize, Zoom and Bring All to Front affect the intended native app/window and preserve page/native responder focus.

Current assessment: implemented.
- Verify actual native window ordering, minimize/restore and responder recovery from menus and keys on multiple windows; selector existence alone is insufficient.

### A055 Stay on top

A per-window stay-on-top control changes native stacking level, can be reversed, and has tested restore/fullscreen/multiwindow behavior.

Current assessment: missing.
- Add state/control and host behavior; ordinary Little Brk NSPanel is explicitly non-floating and is not this feature.

### A066 New-tab bar and address bar

Cmd+T opens a centered bar that creates a tab; Cmd+L edits the current tab, preserving exact destinations.

Current assessment: implemented.
- Add a complete native Cmd+L navigate and restart check, including same-tab multiwindow selection; current N2 proves focus transfer.

### A067 Suggestions

Rank and execute open-tab, history, search-engine, top-domain, calculator and bookmark suggestions with exact URL precedence.

Current assessment: partial.
- Add calculator and a defined bookmark source or index; verify private-profile candidate and network boundaries.

### A068 Actions in the bar ("Type Travel")

Search all applicable completed menu actions, spaces, folder destinations and extensions from the command bar.

Current assessment: partial.
- Implement the remaining actions, folder destinations and extensions; W2-8 tests Preferences, not every advertised workflow.

### A069 Site search

Type a site's name, enter its search mode with Tab, and submit an encoded query for that site.

Current assessment: partial.
- Add configurable or discovered site-specific search beyond built-in engines and verify entry, exit and query submission.

### A070 Search engine choice

Choose the default search engine and suggestion opt-in per profile; both control actual command-bar behavior and persist.

Current assessment: implemented.
- Add native checks switching profiles with different engines and suggestion preferences; validate outgoing requests as well as UI state.

### A083 Little Arc window

Little Brk opens a compact one-page panel with working native chrome, focus and the intended floating behavior, without a sidebar or persistent session restore.

Current assessment: partial.
- Resolve and implement floating behavior against actual reference.
- Verify multiple panel/window activation, links that create more scratch tabs, close/restart and page input.

### A084 Little Arc "Open In" and move to a space

Little Brk/Peek Open In moves the page to a selected space or folder, closes the temporary host, and follows an explicit live-state and browsing-context continuity contract.

Current assessment: partial.
- Add folder destinations and validate allowed container placement.
- Decide and test history/form/download continuity and context changes; current implementation reloads a new browser.

### A085 Little Arc entry points

External links, global hotkey, Option+Cmd link click and menu-bar entry can open Little Brk, with correct destination profile and private-link protections.

Current assessment: partial.
- Implement global shortcut registration and menu-bar entry.
- Verify real external-app delivery and physical modifier clicks; retain private links in private context.

### A086 Little Arc auto-archive

Little Brk auto-archive respects configured thresholds and never closes a panel that is actively used; expired panels archive/close once and can be restored appropriately.

Current assessment: partial.
- Define idle using actual relevant interaction/activity; protect actively used panels and media/download work.
- Add native active-vs-idle and restart/never threshold checks.

### A087 Peek

Shift-click and qualifying external-site links from Pinned/Favorites open a Peek; all browsing actions target it, dismissal cleans it up, and private/Little Brk contexts stay correctly scoped.

Current assessment: partial.
- Preserve main-frame metadata and prove iframe navigations do not spuriously open Peek.
- Test Pinned/Favorites same-site/cross-site behavior beyond the suffix heuristic, browsing/selection/copy and Open In.
- Retain private navigation invariants.

### A088 Peek Email

Shift+Cmd+E opens the intended Gmail Peek in the correct profile with normal Peek controls and no account-system integration.

Current assessment: missing.
- Define target selection when multiple mail accounts/profiles exist, implement the action, and verify loaded destination and dismissal.

### A111 Air Traffic Control

Ordered Air Traffic Control rules route matching external hosts to selected space or Little Brk, support edit/reorder/delete/default behavior and follow true most-recent standard-window context.

Current assessment: partial.
- Connect actual window recency if required by Most Recent Space behavior.
- Verify editor/reorder/invalid destination persistence and actual external-app events, not only injected externalURL.
- Keep scope to host pattern semantics until richer path rules are specified.

### A112 Default browser and links from other apps

Brk can become the default http/https browser after OS confirmation, reflects actual registration status, and receives/routes real URLs from other applications on cold and warm launch.

Current assessment: partial.
- Verify Launch Services/user confirmation and real external application delivery on this app bundle.
- Wire accurate current default status and error reporting; test cold-launch URL ordering.
- W2-7 injects the control protocol input and does not prove the OS boundary.

## Deliverable

Commit implementation, production tests, native scenarios and evidence under `416c251e89:verify/completion/batch-browser-basic/REPORT.md`. Include `proposal.json` with exactly the assigned IDs, truthful final status, remaining work and repository-local evidence for the parent. Do not edit the canonical inventory. Final reply: PASS/ISSUES/BLOCKED, starting/final commit, changed files, actual commands/results, limitations, and clean-worktree status. No PR or publishing.
