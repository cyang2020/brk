# Browser operations close-out: download/navigation regression, keys, developer tools, output, fullscreen, edit menu, popups

Read README.md in this directory first. This is a complete implementation slice, not an audit-only assignment.

Finish the browser-operation rows the browser-basic slice left partial, and return downloads to verified.

Start with the T13 regression. During an in-progress download, a new navigation to a held (still pending) document must keep its requested URL and must not rewrite the prior History record's title. The combined run at `a485d69` fails with `old progress erased the newer navigation` (`9fa756c74b:verify/completion/browser-basic-parent/native-sites-combined/logs/T13.log`, scenario body `navigationDuringTransfer` in `Sources/BrkE2E/TransferScenarios.swift`). Reproduce with `python3 scripts/run-native.py <unique-name> --only T13 --run-timeout 600` after building. Write the failing unit test first against the reducer or page-observation path, make the smallest production fix so download progress never overwrites a newer navigation's requested URL or title, then rerun T13 together with T1-T15. A048 returns to verified only when T13 and the other transfer scenarios pass in your signed build.

BB1 (`outputs` in `Sources/BrkE2E/BrowserBasicScenarios.swift`) times out after 20 s waiting for the output terminal result while BB6 passes the same MHTML/PDF/print-cancel generation with fixtures. Diagnose where the completion notification is lost (DocumentOutputs, OutputSheets, the reducer's output result event) and fix it. If the root cause is the native save panel not receiving input, use the explicit preconfigured destination path for the byte checks and state that the panel gesture belongs to the file-panels slice; do not leave BB1 failing.

A037: model the raw pre-key out-parameter intent, measure Chrome accelerator ordering on the embedded host, preserve the Downloads Cmd+Shift+J app priority and the explicit page-priority override, and extend real tests to affected Chrome commands, swallowed and unswallowed events, native fields, user remaps, duplicate paths and two windows. A041: View Source, DevTools toggle, inspect element at a point, console and network panel selection through the supported `ShowDevTools` inspect point or documented commands, the JavaScript-from-Apple-Events setting and developer mode; auxiliary windows must belong to their page and close on page close and quit; resolve the `.later(.developerMenu)` entries in `Sources/BrkDomain/Actions.swift` into working actions or explicit unsupported notes. A044 except the panel gesture: wrap PDF and print callbacks with validated output and cancellation receipts, make Share write a local file, and implement Cast through the `cef_media_router` sink/route API with an owned observer; no receiver hardware exists on this Mac, so prove enumeration, route creation and termination against the API with its real result and record the hardware gap, never a fake receiver. A045: connect DOM and video fullscreen (`OnFullscreenModeChange`) to the native window, Escape precedence (overlay, then page fullscreen, then window), focus return and no hidden CEF host activation; physical key and traffic-light input remain a manual gap. A046: real execution in native fields, HTML input, textarea, contenteditable and frames; resolve pasteAsPlainText versus pasteAndMatchStyle; enable spelling, substitutions, transformations, speech and font actions only where the responder supports them and make menu validation reflect that; menu topology is not execution. A049: preserve raw disposition, user gesture, frame and popup identity; open real popup windows for window.open including empty URL plus document.write and opener-dependent flows; keep hidden-private ownership and the Option+Cmd privacy fixes.

Owned paths: `Sources/BrkCEF/{ChromePage,DocumentOutputs,HostWindows,KeyTranslation,EmbeddedSurface+Editing}.swift`, `Sources/BrkEngine/PressCorrelator.swift`, `Sources/BrkDomain/{KeyRouting,Rules/Keys,Rules/BrowserBasic}.swift`, the Edit section of `Sources/BrkApp/MainMenu.swift`, `Sources/BrkApp/OutputSheets.swift`, `Sources/BrkE2E/{TransferScenarios,BrowserBasicScenarios}.swift` and your new `BrowserOpsScenarios.swift`. Do not touch the open/save panel input helper, Find, site policy, extensions or data removal.

## Owned feature acceptance

### A037 Key priorities and press twice

App priority, page priority and page-first/second-press behavior work for every implemented chord and user override, with preventDefault, repeat, native editors, distinct windows and exactly-once dispatch.

Current assessment: partial.
- Model the raw pre-key out-parameter intent and measure Chrome accelerator ordering before changing contracts.
- Preserve default Downloads Cmd+Shift+J app priority and explicit page-priority override.
- Extend real tests to affected Chrome commands, swallowed/unswallowed events, native fields, remaps and duplicate paths.

Current behavior: Pure KeyRouting, per-window memory and PressCorrelator are connected. CefKit ignores is_keyboard_shortcut and has no Chrome-command handler.

Existing pointers: `Sources/BrkDomain/KeyRouting.swift`, `Sources/BrkDomain/Actions.swift`, `Sources/BrkDomain/Rules/Keys.swift`, `Sources/BrkEngine/PressCorrelator.swift`, `Sources/BrkCEF/ChromePage.swift`, `Vendor/CefSwift/Sources/CefKit/BrowserClient.swift`, `Vendor/CefSwift/Sources/CCef/include/include/capi/cef_keyboard_handler_capi.h`, `Vendor/CefSwift/Sources/CCef/include/include/capi/views/cef_browser_view_capi.h`

### A041 Developer tools

View Source, DevTools toggle, element inspection, console, network, JavaScript from Apple Events setting and developer mode execute their named behavior on the correct page and close safely.

Current assessment: partial.
- Wrap source/inspect and explicit panel selection or supported commands; resolve Apple Events and developer-mode behavior.
- Verify real auxiliary windows, input, page association and shutdown after reparenting.

Current behavior: Only DevTools toggle is connected; the other listed developer actions are disabled.

Existing pointers: `Sources/BrkDomain/Actions.swift`, `Sources/BrkCEF/CEFEngine.swift`, `Sources/BrkCEF/HostWindows.swift`, `Vendor/CefSwift/Sources/CefKit/CefBrowser.swift`, `Vendor/CefSwift/Sources/CCef/include/include/capi/cef_frame_capi.h`, `Vendor/CefSwift/Sources/CCef/include/include/capi/cef_browser_capi.h`

### A044 Save, print, share, cast

Save Page As creates a usable offline page in supported formats; Print and PDF export report completion/cancellation; Share writes a local file; Cast selects and controls a real receiver, with correct page/window/profile ownership.

Current assessment: partial.
- Implement save-page content rather than confuse link export with saved HTML.
- Wrap PDF callbacks, validate output, and test native print/save dialogs after embedding.
- Connect version-safe Chrome command lookup if used; cef_id_for_command_id_name is not in the current loader symbols.
- Verify local export save panel; its existing test is skipped and write errors are currently swallowed.
- Implement and test Cast routing with a receiver; no evidence exists yet.

Current behavior: Local Share exports link/title JSON or bookmark HTML. Save/Print/Cast remain disabled. Raw print/PDF/Chrome command and media-router APIs are available.

Existing pointers: `Sources/BrkDomain/Actions.swift`, `Sources/BrkDomain/Rules/Sidebar.swift`, `Sources/BrkApp/ShareExport.swift`, `Vendor/CefSwift/Sources/CCef/include/include/capi/cef_browser_capi.h`, `Vendor/CefSwift/Sources/CCef/include/include/capi/cef_media_router_capi.h`, `Vendor/CefSwift/Sources/CCef/include/ccef_symbols.h`

### A045 Full screen and Exit

Ctrl+Cmd+F enters/leaves native fullscreen; Escape closes the current overlay first and exits page/video or window fullscreen when appropriate, without activating a hidden CEF host.

Current assessment: partial.
- Connect or explicitly reconcile DOM/video fullscreen with the native window.
- Verify physical key/traffic-light input, fullscreen media, overlay precedence, and focus return.

Current behavior: Native fullscreen and overlay-first exit effects exist. CefKit forwards didChangeFullscreen, but ChromePage does not consume it.

Existing pointers: `Sources/BrkDomain/Actions.swift`, `Sources/BrkDomain/Rules/Sidebar.swift`, `Sources/BrkApp/AppStore.swift`, `Sources/BrkCEF/ChromePage.swift`, `Vendor/CefSwift/Sources/CefKit/BrowserClient.swift`

### A046 Edit menu

All standard editing, spelling/grammar, substitutions, transformations, speech and font actions are enabled only when their responder supports them and work in native editors and applicable webpage editing contexts.

Current assessment: partial.
- Exercise menu clicks and shortcuts in native fields, HTML input, textarea, contenteditable and frames.
- Resolve selector differences such as pasteAsPlainText: vs CefBrowser.pasteAndMatchStyle and unsupported rich editing.
- Implement the missing spelling/substitution/transformation/speech/font behavior; do not count menu topology tests as execution.

Current behavior: MainMenu installs AppKit responder selectors. CefBrowser has editing wrappers, but no Brk adapter proves the extended page Edit menu.

Existing pointers: `Sources/BrkApp/MainMenu.swift`, `Vendor/CefSwift/Sources/CefKit/CefBrowser.swift`, `Vendor/CefSwift/Sources/CCef/include/include/capi/cef_frame_capi.h`

### A048 Downloads

Downloads use profile location/ask settings and collision-safe names, show truthful progress and terminal states, open/reveal/remove records, and really cancel transport; ownership survives or explicitly terminates after source close/context change, while private metadata stays ephemeral and quit stays clean.

Current assessment: implemented.
- Regression on main a485d69: T13 old download progress erased the newer navigation's title and pending document. Fix and rerun T13 before restoring verified.

Current behavior: Transfers freeze original browser/context/policy, use real native cancellation and owned staging, survive Brk presentation close/reassignment, and revoke/drain private contexts and profile deletion. Mandatory native browser closure reports a truthful terminal failure/recovery result without recreating the page. Profile data deletion is scheduled for next launch; private Library remains metadata-free.

Existing pointers: `Sources/BrkBase/Page.swift`, `Sources/BrkEngine/WebEngine.swift`, `Sources/BrkCEF/ChromePage.swift`, `Sources/BrkCEF/CEFEngine.swift`, `Sources/BrkApp/KeyRouter.swift`, `Sources/BrkDomain/Rules/Tabs.swift`, `Sources/BrkDomain/Rules/Library.swift`, `Sources/BrkLibrary/LibraryPages.swift`, `Vendor/CefSwift/Sources/CefKit/BrowserClient.swift`, `Vendor/CefSwift/Sources/CefKit/CefDownloads.swift`, `Sources/BrkBase/Transfers.swift`, `Sources/BrkCEF/Transfers.swift`, `Sources/BrkCEF/TransferFiles.swift`, `Sources/BrkEngine/BrowserResources.swift`, `Sources/BrkEngine/ContextLifetimes.swift`, `Sources/BrkApp/DownloadSheets.swift`

### A049 Links that open new tabs and popups

Cmd+click opens a background tab; foreground-modifier opens and popups retain correct disposition, opener/context and requested window behavior, including private and hidden source pages.

Current assessment: partial.
- Preserve raw disposition/user-gesture/frame/popup identity before adding real popup windows.
- Test empty-URL window.open/document.write and opener-dependent auth flows; current .handled cancels CEF popup creation.
- Preserve hidden-private ownership and Option+Cmd privacy fixes.

Current behavior: Popups become foreground domain tabs; on_open_urlfrom_tab loses disposition and all such opens become background. Privacy routing is fixed.

Existing pointers: `Sources/BrkCEF/ChromePage.swift`, `Sources/BrkDomain/Rules/Tabs.swift`, `Sources/BrkDomain/Rules/Peek.swift`, `Vendor/CefSwift/Sources/CefKit/BrowserClient.swift`

## Deliverable

Commit implementation, production tests, native scenarios (names start with `BO`) and evidence under `3ef85fca08:verify/completion/batch2-browser-ops/REPORT.md`. Include `proposal.json` with exactly the assigned IDs (A037, A041, A044, A045, A046, A048, A049), truthful final status, remaining work and repository-local evidence for the parent, in the shape of the existing `06656768e1:verify/completion/batch-tabs/proposal.json`. Do not edit the canonical inventory. Final reply: PASS, ISSUES or BLOCKED; starting and final commit; changed files; actual commands and results; limitations; clean-worktree status. No PR or publishing.
