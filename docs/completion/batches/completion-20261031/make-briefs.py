#!/usr/bin/env python3
"""Generate the slice briefs and manifest for the completion-20261031 batch from the canonical ledger.

Run from the repository root: python3 docs/completion/batches/completion-20261031/make-briefs.py
The parent runs it once before dispatch and again only to regenerate after a ledger change.
"""
import json
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[4]
HERE = pathlib.Path(__file__).resolve().parent
LEDGER = json.loads((ROOT / "docs/completion/features.json").read_text())
ROWS = {row["id"]: row for row in LEDGER["features"]}
HEAD = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()

SLICES = [
    {
        "id": "browser-ops",
        "wave": 1,
        "title": "Browser operations close-out: download/navigation regression, keys, developer tools, output, fullscreen, edit menu, popups",
        "feature_ids": ["A037", "A041", "A044", "A045", "A046", "A048", "A049"],
        "scenario_prefix": "BO",
        "brief": """Finish the browser-operation rows the browser-basic slice left partial, and return downloads to verified.

Start with the T13 regression. During an in-progress download, a new navigation to a held (still pending) document must keep its requested URL and must not rewrite the prior History record's title. The combined run at `a485d69` fails with `old progress erased the newer navigation` (`9fa756c74b:verify/completion/browser-basic-parent/native-sites-combined/logs/T13.log`, scenario body `navigationDuringTransfer` in `Sources/BrkE2E/TransferScenarios.swift`). Reproduce with `python3 scripts/run-native.py <unique-name> --only T13 --run-timeout 600` after building. Write the failing unit test first against the reducer or page-observation path, make the smallest production fix so download progress never overwrites a newer navigation's requested URL or title, then rerun T13 together with T1-T15. A048 returns to verified only when T13 and the other transfer scenarios pass in your signed build.

BB1 (`outputs` in `Sources/BrkE2E/BrowserBasicScenarios.swift`) times out after 20 s waiting for the output terminal result while BB6 passes the same MHTML/PDF/print-cancel generation with fixtures. Diagnose where the completion notification is lost (DocumentOutputs, OutputSheets, the reducer's output result event) and fix it. If the root cause is the native save panel not receiving input, use the explicit preconfigured destination path for the byte checks and state that the panel gesture belongs to the file-panels slice; do not leave BB1 failing.

A037: model the raw pre-key out-parameter intent, measure Chrome accelerator ordering on the embedded host, preserve the Downloads Cmd+Shift+J app priority and the explicit page-priority override, and extend real tests to affected Chrome commands, swallowed and unswallowed events, native fields, user remaps, duplicate paths and two windows. A041: View Source, DevTools toggle, inspect element at a point, console and network panel selection through the supported `ShowDevTools` inspect point or documented commands, the JavaScript-from-Apple-Events setting and developer mode; auxiliary windows must belong to their page and close on page close and quit; resolve the `.later(.developerMenu)` entries in `Sources/BrkDomain/Actions.swift` into working actions or explicit unsupported notes. A044 except the panel gesture: wrap PDF and print callbacks with validated output and cancellation receipts, make Share write a local file, and implement Cast through the `cef_media_router` sink/route API with an owned observer; no receiver hardware exists on this Mac, so prove enumeration, route creation and termination against the API with its real result and record the hardware gap, never a fake receiver. A045: connect DOM and video fullscreen (`OnFullscreenModeChange`) to the native window, Escape precedence (overlay, then page fullscreen, then window), focus return and no hidden CEF host activation; physical key and traffic-light input remain a manual gap. A046: real execution in native fields, HTML input, textarea, contenteditable and frames; resolve pasteAsPlainText versus pasteAndMatchStyle; enable spelling, substitutions, transformations, speech and font actions only where the responder supports them and make menu validation reflect that; menu topology is not execution. A049: preserve raw disposition, user gesture, frame and popup identity; open real popup windows for window.open including empty URL plus document.write and opener-dependent flows; keep hidden-private ownership and the Option+Cmd privacy fixes.

Owned paths: `Sources/BrkCEF/{ChromePage,DocumentOutputs,HostWindows,KeyTranslation,EmbeddedSurface+Editing}.swift`, `Sources/BrkEngine/PressCorrelator.swift`, `Sources/BrkDomain/{KeyRouting,Rules/Keys,Rules/BrowserBasic}.swift`, the Edit section of `Sources/BrkApp/MainMenu.swift`, `Sources/BrkApp/OutputSheets.swift`, `Sources/BrkE2E/{TransferScenarios,BrowserBasicScenarios}.swift` and your new `BrowserOpsScenarios.swift`. Do not touch the open/save panel input helper, Find, site policy, extensions or data removal.""",
    },
    {
        "id": "file-panels",
        "wave": 1,
        "title": "Native open/save panel input and the import, export and sync receipts that depend on it",
        "feature_ids": ["A122", "A143", "A144"],
        "scenario_prefix": "FP",
        "brief": """Resolve the one blocker behind the ImportSync-Import, ImportSync-Export and ImportSync-Sync failures: the macOS open and save panels run in a separate Apple XPC process (`com.apple.appkit.xpc.openAndSavePanelService`) and the fixture's in-process input never reaches them (`timed out after 8.0 s waiting for native sheet contains 1 bookmarks`).

Read the previous bounded attempt first: `/Users/administrator/.t3/worktrees/brk/t3-da37a8f1/verify/completion/native-picker-input/REPORT.md` (branch `t3/native-picker-input`, commit `576dc75`). Its external helper `scripts/native-picker-input.swift` and the opt-in `Sources/BrkE2E/NativePickerInput.swift` are reusable; copy or cherry-pick them with attribution in your report. That report names two corrections that were never run: record the proposed click point and the top window's PID, number and bounds before the hit guard rejects a click; and compare the system-wide accessibility focused application and focused element with the owned tree while refreshing application-state observations through a pumped run loop. Apply both. Then make at most two bounded native attempts, each at most 180 s of actual run under the native lock, to drive the real panel: focus it, type the fixture path through the panel's path field (Cmd+Shift+G) or select the fixture row, confirm, and let the existing scenario assertions prove preview, accept and cancel, saved JSON and HTML bytes, two-root sync convergence and disconnect. Do not change OS permissions, do not assign `panel.url` or invoke a panel completion from inside the product, and do not read any user browser profile.

If both attempts fail, apply the fallback acceptance the parent has decided for this batch: the panel is shown and recorded (window number, bounds, screenshot), the real post-selection production command is exercised with an explicitly selected fixture URL (the pattern extension installation already uses), and the scenario asserts the downstream behavior. Rows accepted that way are proposed `implemented` with an explicit `manual` gap for the physical gesture, never `verified`. Either way the three ImportSync scenarios must stop failing: a step that depends on an unavailable physical gesture ends in SKIPPED with the reason, not FAIL, and the downstream assertions still run through the explicit path. Keep the LocalAuthentication and protected Keychain exercise for A122 as a stated manual gap; credentials stay in the app-specific Keychain collection and website autofill is out of scope. A144's creative-document export waits for the easels-notes slice.

Owned paths: `Sources/BrkE2E/{Harness,NativePickerInput,ImportSyncScenarios}.swift`, `scripts/native-picker-input.swift`, your new `FilePanelScenarios.swift`, and `Sources/BrkApp/{SidebarDataPanels,ExportSheets,SidebarSyncIO,ShareExport}.swift` only for the explicit post-selection command path. BB1 and the output adapters belong to browser-ops.""",
    },
    {
        "id": "privacy-data",
        "wave": 1,
        "title": "Profiles, incognito, scoped data removal and their restart receipts",
        "feature_ids": ["A042", "A093", "A094", "A095"],
        "scenario_prefix": "Data",
        "brief": """Finish the data-lifecycle rows. The sites-extensions slice delivered real clearing; the parent's independent review found the after-restart assertions prove localStorage only (`9fa756c74b:verify/completion/sites-extensions-parent/review`, finding EV1).

A042: add post-restart receipts, in native scenarios, for host, domain and HttpOnly cookies, IndexedDB, Cache Storage, service-worker registrations and the HTTP cache, plus survival of an unrelated origin and of another profile, for both Clear Cookies and Refresh and Clear Cache and Refresh. A093: prove profile-scoped extension catalog, pins and enable state; storage classes beyond cookies per profile; active download ownership when a space is reassigned to another profile or the profile is deleted; clear-data separated from deletion; keep the initialization readiness and incarnation and focus protections. A094: closing and reopening the last private window resets every storage class without quitting (fixture proof exists; extend it), define and test active-download behavior when the private context expires, and run a disk and diagnostic-log audit for private titles and paths after quit with the exact audited set stated. A095: implement the active-protected-operation clear-data matrix natively (clear during an active download, a pending output, an open Find, a frozen page), implement profile-wide origin-storage deletion through an origin index or the request context, or state the exact unsupported scope in the UI; two profiles and unrelated origins; truthful privacy controls in settings with correct scope labels instead of a History button.

Owned paths: `Sources/BrkCEF/{SiteData,CEFProfiles}.swift`, the request-context lifecycle parts of `Sources/BrkCEF/CEFEngine.swift`, `Sources/BrkDomain/Rules/{Profiles,Library}.swift` clear-data rules, the clear-data UI in `Sources/BrkLibrary` and `Sources/BrkSettings`, and your new `DataScenarios.swift`. `WebsitePolicy.swift` and `Extensions.swift` belong to extensions-sites; add only additive hooks there and list them.""",
    },
    {
        "id": "extensions-sites",
        "wave": 1,
        "title": "Extension actions and popups, extension shortcuts, site permissions, blocking and per-site rules",
        "feature_ids": ["A096", "A097", "A098", "A107", "A108", "A109", "A110"],
        "scenario_prefix": "Ext",
        "brief": """Finish the extension and site-control rows.

A097 first. The corrected toolbar prototype at `/Users/administrator/.t3/worktrees/brk/t3-319171fb` (detached commit `3f14e28`, report `verify/completion/extension-actions/REPORT.md`, adapter under `prototype-support/`) attaches the Chrome toolbar with the public `CefPanel.AddChildViewAt` call the way cefclient does; it compiled and signed but never ran. Run it once as your first bounded native experiment. Then build the feature: a native extension action strip, or the Chrome toolbar's Extensions button if that is what works, that enumerates installed actions, pins per profile, invokes an action, hosts the popup with real typing and clicks, closes it on owner navigation, owner close, profile change and quit, and refuses in private windows per policy. `Target.attachToBrowserTarget` returns `Not allowed` in the in-process channel; that route is closed, do not retry it. If after two more bounded experiments no popup can be shown, deliver the enumeration and pin UI and report BLOCKED for the popup with the runtime evidence.

A096: implement the per-extension incognito-allowed toggle and prove both outcomes for content scripts in private contexts; the physical folder gesture belongs to file-panels. A098: a real shortcut editing UI with duplicate and reserved chord handling, and tests for the page, native-editor and Brk-remap priority matrix. A108: native remembered-choice readback during document loading; bridge OS authorization (AVCaptureDevice, CLLocationManager, UNUserNotificationCenter) so a site prompt is offered only when the OS grants Brk, and record that a real OS prompt cannot be driven on this host. A109: native main-frame, cross-origin subframe and redirect coverage; load the shipped subset from a documented rule format, import a user-provided EasyList-syntax file for the supported subset and document what is unsupported; refresh with errors. A110: the WebAudio and media exemption matrix; the PiP exemption waits for captures-media, so expose a typed hook. A107: finish readback and export; the Boost and capture actions wait for their slices and the parent wires them after integration.

Owned paths: `Sources/BrkCEF/{Extensions,WebsitePolicy}.swift`, the vendored toolbar adapter under `Vendor/CefSwift/Sources/CefKit`, `Sources/BrkSettings/SiteControlsHost.swift`, `Sources/BrkApp/{SitePanels,ExtensionInstallPermissions,SiteRulesFiles,SiteToolsAdapter}.swift`, `Sources/BrkE2E/ExtensionScenarios.swift` and your new `ExtScenarios.swift`. `SiteData.swift` and `CEFProfiles.swift` belong to privacy-data.""",
    },
    {
        "id": "sidebar-tabs",
        "wave": 1,
        "title": "Favorites badges, join meeting, custom icons, loading glow, hover cards, crashed page",
        "feature_ids": ["A014", "A015", "A021", "A030", "A031", "A032"],
        "scenario_prefix": "SidebarTools",
        "brief": """Finish the six sidebar rows.

A014: native badge and subtitle rendering on Favorites tiles from the implemented GitHub-notification and iCalendar adapters, with freshness and update rules and a visible authorization state; no OAuth, the sources stay an explicit user-provided token or an exported .ics file. A015: Ctrl+Cmd+J opens the next meeting from the selected calendar file, gives expiry and no-meeting feedback, and the destination is proven natively; file consent goes through the explicit-selection command path because the panel gesture belongs to file-panels. A021: icon and emoji pickers for tabs, folders, splits and spaces with the full repertoire, keyboard navigation, cancel, clear and restart persistence; `Sources/BrkApp/TabIconPicker.swift` exists. A030: the loading glow driven by real load progress from the engine callbacks, cleared on completion, failure and cancellation, placed and timed against `docs/arc-anatomy`; no Arc pixel claim. A031: metadata cards exist; add dismissible previews for arbitrary webpage links on deliberate hover (title, URL, favicon fetched in the page's own context, never across profiles), lifetime rules and the settings control; the AI summary belongs to ai-features, so expose a hook. A032: the full sad-tab presentation (illustration, message, Reload) and the failed-recovery path where a second crash stays sad with retry; R7b covers automatic recovery only.

Owned paths: `Sources/BrkSidebar/*`, the sad-tab view in `Sources/BrkContent`, `Sources/BrkDomain/{Rules/Tabs,Rules/TabTools,TabToolsModel,CalendarFile}.swift`, `Sources/BrkApp/TabIconPicker.swift`, additive render-terminated and load-progress callbacks in `Sources/BrkCEF/CEFEngine.swift`, and your new `SidebarToolsScenarios.swift`.""",
    },
    {
        "id": "ai-features",
        "wave": 1,
        "title": "Local-CLI AI features: command bar question, ask on page, previews, tidy tabs, renames, instant links, browse for me, translation, Max pane",
        "feature_ids": ["A134", "A135", "A136", "A137", "A138", "A139", "A140", "A141", "A142"],
        "scenario_prefix": "AI",
        "brief": """Build the AI features on the existing seam: `Sources/BrkApp/AIProvider.swift` runs the user's local `claude` or `codex` command-line tool, `Sources/BrkDomain/Rules/Assist.swift` asks through `Effect.ai` and applies `SystemEvent.aiResult`. The user decided no API keys.

Repair the seam first (A138's remaining item): reproduce and fix CLI cancellation, process termination on timeout and quit, and pipe draining for large outputs; add partial-output streaming. Tests use a fixture provider executable under `Tests/Fixtures` (a script that answers deterministically, delays or hangs on command) so unit and native runs never need the network. Make exactly one real-provider smoke receipt with whichever of `claude` (`claude -p ... --output-format text`) or `codex` (`codex exec --skip-git-repo-check ...`) is installed, record its command, duration and output, and run nothing else against the real tools.

A134: Opt+Cmd+G and the `.later(.aiCommandBar)` entry ask from the command bar; the answer is cancellable and failures are actionable. A135: a question over the active page's extracted main-frame text in the page's own context, attributed to that page, never reading other profiles or private pages. A136: a bounded summary on deliberate link hover with cancel and an unavailable state; use the sidebar-tabs hover hook if merged, otherwise your own narrow trigger in your files. A137: a validated JSON plan that rejects stale or foreign IDs, groups only eligible Today tabs, with undo. A138: completed-download rename with safe filenames and collision handling; pinned-tab rename is already wired. A139: resolve a bar query to a validated destination (the tool proposes, Brk checks URL shape and reachability in the right context) with ordinary search as the explicit fallback. A140: read selected sources in the correct browsing context through request-owned hidden pages that close afterwards, and build a local answer document whose citations link those sources. A141: translate visible text in chunks while preserving controls (replace text nodes, keep the DOM), with profile-scoped never-translate languages and sites. A142: switches per delivered feature and provider choice, no API key field.

Owned paths: `Sources/BrkApp/AIProvider.swift` and new AI files in BrkApp, `Sources/BrkDomain/Rules/Assist.swift` and new AI rules and model files, the ask mode in `Sources/BrkOverlays/CommandBarView.swift` and `Suggest.swift`, the Max pane in `Sources/BrkSettings`, an answer-document view in `Sources/BrkContent`, and your new `AIScenarios.swift`. Domain code stays pure; the tools run only in BrkApp.""",
    },
    {
        "id": "captures-media",
        "wave": 1,
        "title": "Capture, Media library, picture in picture, media controls, sound effects",
        "feature_ids": ["A102", "A103", "A104", "A105", "A106"],
        "scenario_prefix": "Capture",
        "brief": """Build captures and media.

Probe first: the per-page DevTools channel (`CefDevTools`, request IDs from the shared allocator) can issue `Page.getLayoutMetrics` and `Page.captureScreenshot` with `clip` and `captureBeyondViewport` on the embedded Chrome path; prove it before designing around it, and do not reuse off-screen-rendering assumptions. A102: an area-selection overlay on the content card, full-page capture by protocol or stitching, portrait framing, export and storage, checks of output dimensions and pixels against the fixture, cancellation, navigation races, and private captures that never persist. A103: a capture storage model (profile-scoped folder plus index), its projection, the Media page with previews, open, export, remove, and restart survival. A104: probe video-element and document picture in picture separately on the embedded host (`requestPictureInPicture` through the page, or the Chrome command if the runtime offers it); explicit entry and automatic entry when leaving a video tab as a setting consumer; ownership across navigation, tab, window and profile changes; private contexts; defined activation failure and multiple-player behavior. A105: extend the bundled audibility extension (`Sources/BrkCEF/AudibilityExtension`) or MediaSession observation to report play and pause state per player, and execute play and pause for the playing tab from its sidebar row, with background behavior and lifecycle. A106: an event-to-sound mapping with bundled assets and a settings consumer; audible when enabled, silent when disabled, never blocking the UI.

Expose a typed hook for the per-site PiP exemption (extensions-sites) and for inserting a capture into an Easel (later slice). Owned paths: new capture and media files in `Sources/BrkCEF`, `Sources/BrkCEF/AudibilityExtension`, the Media page in `Sources/BrkLibrary`, capture and media model and rules in `Sources/BrkDomain`, the capture overlay in `Sources/BrkContent`, the sound and auto-PiP settings consumers, `.later(.captures)` entries in `Sources/BrkDomain/Actions.swift`, and your new `CaptureScenarios.swift` and `MediaScenarios.swift`.""",
    },
    {
        "id": "boosts",
        "wave": 1,
        "title": "Boosts: per-site CSS and JavaScript, Zap, editor, gallery, install, export and import",
        "feature_ids": ["A099"],
        "scenario_prefix": "Boost",
        "brief": """Build Boosts: profile-scoped per-site CSS and JavaScript, Zap (click an element to hide it, persisted as a CSS rule), an editor with live preview, a gallery of local presets, install from a local export file, disable, remove, export and import.

Design twice before coding. Launch at most two bounded, read-only Codex design children with the same brief and synthesize one `DESIGN.md` under your evidence directory. Decisions to settle: storage (default: a separate versioned file per profile under the profile data root; `StateCodec` stays at version 3 and the parent owns any format bump), injection ownership (reuse the isolated-world CSS mechanism the website theme uses in `Sources/BrkCEF/WebsitePolicy.swift` with its own namespace; JavaScript boosts need a per-boost confirmation and run only on committed documents of matching origins), scope matching (origin, host or all sites), private windows (no new boosts; existing public boosts apply only when the user opts in). The Library Boosts page lists the profile's boosts; the legacy advanced boost is the raw CSS and JavaScript editor. Resolve the `.later(.boosts)` entries in `Sources/BrkDomain/Actions.swift`.

Owned paths: new Boosts model, rules and codec files in `Sources/BrkDomain`, a new Boosts injection file in `Sources/BrkCEF` with an additive document-lifecycle hook into `WebsitePolicy.swift`, the Boosts page in `Sources/BrkLibrary`, the editor and Zap overlay in `Sources/BrkOverlays` or `Sources/BrkContent`, and your new `BoostScenarios.swift`. Expose a command for the site control center's Boost action; the parent wires it after integration.""",
    },
    {
        "id": "easels-notes",
        "wave": 2,
        "title": "Notes and Easels, their appearance and export",
        "feature_ids": ["A100", "A101"],
        "scenario_prefix": "Creative",
        "brief": """Build Notes and Easels as Brk-owned documents. Design twice before coding (two bounded read-only Codex design children, one synthesized `DESIGN.md`): document storage per profile, the sidebar item kind for a note or easel, split hosting, private-session drafts that never persist, and export formats (Markdown and HTML for notes; PNG and a JSON document for easels). A100: rich-text notes editable in the sidebar panel and in a split, persisted, exportable, and `Export {app} Notes` in the Help menu resolved. A101: an easel canvas with captures (consume the captures-media insertion hook when merged), drawing and text objects, editing, reopening and export. Both follow the website appearance setting (A043's consumer) and feed A144's creative-document export through the export path file-panels delivered. Resolve the `.later(.notes)` and `.later(.easels)` entries in `Sources/BrkDomain/Actions.swift`. Owned paths: new creative-document model, rules and codec files in `Sources/BrkDomain`, editors in `Sources/BrkContent`, the Easels and Notes Library page, and your new `CreativeScenarios.swift`.""",
    },
    {
        "id": "settings-panes",
        "wave": 2,
        "title": "Settings window, General, Profiles, Shortcuts, Advanced and App Icon panes with their runtime consumers",
        "feature_ids": ["A113", "A114", "A115", "A116", "A117", "A118"],
        "scenario_prefix": "Settings",
        "brief": """Finish the settings rows by connecting every switch to its runtime consumer. A113: add the App Icon pane and finish the window. A114: quit confirmation inside ordered shutdown; previews, blocker and translation controls drive the merged consumers. A115: default document app behavior and native per-profile checks for search, download location and archive threshold. A116: cover the remaining intended shortcuts and alternates, conflicts and recording through actual controls. A117: restore policy, sound, reorder haptics, toolbar URL, page dragging, auto PiP, theme CSS, Boosts and quote behavior through their owning layers (sound and auto PiP from captures-media, Boosts from boosts, both merged before this slice starts); the update channel stays deferred. A118: original Brk icon choices, application integration and persistence. Owned paths: `Sources/BrkSettings/*`, `Sources/BrkDomain/{SettingsModel,Rules/Settings}.swift`, `Sources/BrkApp/{SettingsWindowController,Lifecycle}.swift`, and your new `SettingsScenarios.swift`.""",
    },
    {
        "id": "menus-system",
        "wave": 2,
        "title": "Default browser and incoming links, Help menu, About, menu bar coverage, Dock tile, status item, AppleScript",
        "feature_ids": ["A112", "A125", "A129", "A130", "A131", "A132", "A133"],
        "scenario_prefix": "System",
        "brief": """Finish the system-integration rows. A112: accurate default-browser status through Launch Services, the OS confirmation flow (never change the default browser during tests), cold-launch URL ordering and real external delivery with an owned helper app or `open` receipts. A125: resolve the `.later(.help)`, `.later(.restoreData)` and `.later(.troubleshooting)` entries into working local documentation, restore from a backup, trace recording, task manager and diagnostics. A129: Brk credits, packaged version and icon metadata, the actual About panel captured. A130: every in-scope menu row works or carries the explicit updater deferral; dynamic entries validated. A131: Brk-owned Dock tile behavior (badge or progress) across active and inactive states. A132: a menu-bar status item that opens Little Brk. A133: a documented AppleScript dictionary (sdef) for windows, tabs and spaces with correct object identity, exercised through `osascript`, keeping private ownership and the explicit JavaScript permission. Owned paths: `Sources/BrkApp/{MainMenu,Lifecycle,ExternalLinks}.swift`, new Help, Dock, status-item and scripting files in BrkApp, `Sources/BrkDomain/Actions.swift` entries for those groups, and your new `SystemScenarios.swift`.""",
    },
    {
        "id": "little-arc-folders",
        "wave": 2,
        "title": "Command bar actions, Little Brk entry points and auto-archive, Live Folders",
        "feature_ids": ["A068", "A085", "A086", "A092"],
        "scenario_prefix": "Little",
        "brief": """Finish four rows. A068: every remaining menu action, folder destination and installed extension is searchable from the command bar. A085: global shortcut registration and the menu-bar entry for Little Brk (coordinate with the status item from menus-system through its command), real external-app delivery receipts and private-link protection. A086: define idle by actual interaction and activity, protect panels with active media or downloads, and add native active-versus-idle and restart threshold checks. A092: error, loading and freshness states for GitHub Live Folders and a reauthorization flow for authenticated refresh without saving tokens. Owned paths: `Sources/BrkOverlays/Suggest.swift`, `Sources/BrkDomain/Rules/{CommandBar,Windows,Peek,Archive}.swift`, `Sources/BrkApp/{LittleEntryPoints,LittleWindowController,ExternalLinks}.swift`, the Live Folder parts of `Sources/BrkDomain/SidebarTree.swift` and `Sources/BrkSidebar/TablistView.swift`, and your new `LittleScenarios.swift`.""",
    },
]

PARENT_ROWS = {
    "A043": "Website appearance: Easels and Notes consumers come from easels-notes; the parent records the receipt.",
    "A081": "Library: Media, Easels and Notes, Boosts and Spaces pages come from their slices; the parent verifies the whole after integration.",
    "A148": "Arc pixel reference: blocked on the user's Arc login; unchanged in this batch.",
}


def row_section(row):
    lines = [f"### {row['id']} {row['feature']}", "", row["acceptance"], "", f"Current assessment: {row['status']}."]
    for item in row.get("remaining", []):
        lines.append(f"- {item}")
    if row.get("current_behavior"):
        lines += ["", f"Current behavior: {row['current_behavior']}"]
    if row.get("implementation"):
        lines += ["", "Existing pointers: " + ", ".join(f"`{p}`" for p in row["implementation"])]
    return "\n".join(lines)


def brief_document(s):
    rows = [ROWS[i] for i in s["feature_ids"]]
    parts = [
        f"# {s['title']}",
        "",
        "Read README.md in this directory first. This is a complete implementation slice, not an audit-only assignment.",
        "",
        s["brief"],
        "",
        "## Owned feature acceptance",
        "",
        "\n\n".join(row_section(r) for r in rows),
        "",
        "## Deliverable",
        "",
        f"Commit implementation, production tests, native scenarios (names start with `{s['scenario_prefix']}`) and evidence under "
        f"`verify/completion/batch2-{s['id']}/REPORT.md`. Include `proposal.json` with exactly the assigned IDs "
        f"({', '.join(s['feature_ids'])}), truthful final status, remaining work and repository-local evidence for the parent, "
        "in the shape of the existing `06656768e1:verify/completion/batch-tabs/proposal.json`. Do not edit the canonical inventory. "
        "Final reply: PASS, ISSUES or BLOCKED; starting and final commit; changed files; actual commands and results; "
        "limitations; clean-worktree status. No PR or publishing.",
        "",
    ]
    return "\n".join(parts)


def main():
    assigned = []
    for s in SLICES:
        for i in s["feature_ids"]:
            assert i in ROWS, i
            assert ROWS[i]["status"] in ("partial", "missing", "implemented"), (i, ROWS[i]["status"])
            assigned.append(i)
    assert len(assigned) == len(set(assigned)), "a row is assigned twice"
    open_rows = {r["id"] for r in LEDGER["features"] if r["status"] in ("partial", "missing")}
    unassigned = sorted(open_rows - set(assigned) - set(PARENT_ROWS))
    assert not unassigned, f"open rows without an owner: {unassigned}"
    for s in SLICES:
        (HERE / f"{s['id']}.md").write_text(brief_document(s))
    manifest = {
        "schema_version": 1,
        "batch": "completion-20261031",
        "base_commit": HEAD,
        "user_request": "Finish every partial and missing feature row in parallel; do not stop; use the pstack skills that fit.",
        "generated_by": "docs/completion/batches/completion-20261031/make-briefs.py",
        "slices": [
            {"id": s["id"], "wave": s["wave"], "title": s["title"], "feature_ids": s["feature_ids"],
             "scenario_prefix": s["scenario_prefix"], "brief": f"{s['id']}.md",
             "evidence": f"verify/completion/batch2-{s['id']}/", "status": "framed"}
            for s in SLICES
        ],
        "parent_rows": PARENT_ROWS,
        "open_rows_at_dispatch": {"partial": sorted(r["id"] for r in LEDGER["features"] if r["status"] == "partial"),
                                  "missing": sorted(r["id"] for r in LEDGER["features"] if r["status"] == "missing")},
    }
    (HERE / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"{len(SLICES)} slices, {len(assigned)} assigned rows, {len(PARENT_ROWS)} parent rows, base {HEAD[:7]}")


if __name__ == "__main__":
    main()
