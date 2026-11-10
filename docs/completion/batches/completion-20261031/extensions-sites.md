# Extension actions and popups, extension shortcuts, site permissions, blocking and per-site rules

Read README.md in this directory first. This is a complete implementation slice, not an audit-only assignment.

Finish the extension and site-control rows.

A097 first. The corrected toolbar prototype at `/Users/administrator/.t3/worktrees/brk/t3-319171fb` (detached commit `3f14e28`, report `verify/completion/extension-actions/REPORT.md`, adapter under `prototype-support/`) attaches the Chrome toolbar with the public `CefPanel.AddChildViewAt` call the way cefclient does; it compiled and signed but never ran. Run it once as your first bounded native experiment. Then build the feature: a native extension action strip, or the Chrome toolbar's Extensions button if that is what works, that enumerates installed actions, pins per profile, invokes an action, hosts the popup with real typing and clicks, closes it on owner navigation, owner close, profile change and quit, and refuses in private windows per policy. `Target.attachToBrowserTarget` returns `Not allowed` in the in-process channel; that route is closed, do not retry it. If after two more bounded experiments no popup can be shown, deliver the enumeration and pin UI and report BLOCKED for the popup with the runtime evidence.

A096: implement the per-extension incognito-allowed toggle and prove both outcomes for content scripts in private contexts; the physical folder gesture belongs to file-panels. A098: a real shortcut editing UI with duplicate and reserved chord handling, and tests for the page, native-editor and Brk-remap priority matrix. A108: native remembered-choice readback during document loading; bridge OS authorization (AVCaptureDevice, CLLocationManager, UNUserNotificationCenter) so a site prompt is offered only when the OS grants Brk, and record that a real OS prompt cannot be driven on this host. A109: native main-frame, cross-origin subframe and redirect coverage; load the shipped subset from a documented rule format, import a user-provided EasyList-syntax file for the supported subset and document what is unsupported; refresh with errors. A110: the WebAudio and media exemption matrix; the PiP exemption waits for captures-media, so expose a typed hook. A107: finish readback and export; the Boost and capture actions wait for their slices and the parent wires them after integration.

Owned paths: `Sources/BrkCEF/{Extensions,WebsitePolicy}.swift`, the vendored toolbar adapter under `Vendor/CefSwift/Sources/CefKit`, `Sources/BrkSettings/SiteControlsHost.swift`, `Sources/BrkApp/{SitePanels,ExtensionInstallPermissions,SiteRulesFiles,SiteToolsAdapter}.swift`, `Sources/BrkE2E/ExtensionScenarios.swift` and your new `ExtScenarios.swift`. `SiteData.swift` and `CEFProfiles.swift` belong to privacy-data.

## Owned feature acceptance

### A096 Install and manage

Users can install/manage/remove extensions through a supported store/local flow and management UI in Brk, with per-profile persistence, permissions, error reporting and correct private policy.

Current assessment: partial.
- Private extension execution is not proven. Private installation and management are explicitly disabled.
- The native OS folder chooser is displayed and source-close cancellation is exercised. Automated installation uses the explicitly selected fixture through the same production post-selection confirmation command; a physical folder-selection gesture is not claimed.

Current behavior: User-selected unpacked installation, manifest permission confirmation, native Chrome management, actual catalogs, enable/disable, profile persistence and pinning are implemented. The pinned chooser OPEN-mode compatibility is bound to the approved document and directory.

Existing pointers: `Sources/BrkApp/AppStore.swift`, `Sources/BrkCEF/Extensions.swift`, `Vendor/CefSwift/Sources/CefKit/CefFileDialog.swift`

### A097 Extension buttons and picker

Installed extension actions appear in a native picker/toolbar with per-profile pinning and usable popup/permission UI whose windows close safely.

Current assessment: partial.
- Action invocation has produced Method not allowed in the pinned in-process channel. Other submitted attempts do not establish success.
- Actual popup input, extension-origin permission UI, focus and navigation/profile/shutdown ownership are not proven. Action buttons remain unavailable.

Current behavior: The native extension picker enumerates current Chromium state and persists profile pin choices. No saved toggle, API submission or disabled button is counted as popup completion.

Existing pointers: `Sources/BrkSettings/SiteControlsHost.swift`, `Sources/BrkCEF/Extensions.swift`, `Sources/BrkBase/Extensions.swift`

### A098 Extension shortcuts

Extension command shortcuts can be inspected and configured per profile and coexist with Brk/page priorities, with duplicate and reserved-key handling.

Current assessment: partial.
- Actual editing, duplicate/reserved chord behavior and the full page/native-editor/Brk-remap priority matrix remain unverified.

Current behavior: Per-profile Chrome shortcut configuration UI is reachable, and the installed harmless extension dispatches its configured Command+Shift+Y command after restart. Existing Brk shortcut table and Downloads priority are preserved.

Existing pointers: `Sources/BrkE2E/ExtensionScenarios.swift`, `Sources/BrkDomain/Rules/SitePolicies.swift`, `Sources/BrkDomain/KeyRouting.swift`

### A107 Site control center

A site control popover shows the active origin/profile, effective permissions/settings and actions for Boosts, capture, copy URL and local file export with current readback.

Current assessment: partial.
- Boost/capture consumers remain in their later batches.
- Local export retains the inherited manual save-panel verification gap.

Current behavior: A native site-controls window shows the actual active origin/profile, saved policy plus asynchronous native policy readback/errors, copy URL and local link export actions. Navigation/profile changes rebind its snapshot.

Existing pointers: `Sources/BrkSettings/SiteControlsHost.swift`, `Sources/BrkApp/SitePanels.swift`, `Sources/BrkSidebar/SidebarView.swift`

### A108 Site permissions

Native site prompts for camera, microphone, location and notifications show the correct origin/capability, support allow/deny/dismiss and settings readback, respect OS permissions, and cannot resolve stale prompts for a new page/profile.

Current assessment: partial.
- Real OS camera, microphone and location allow/deny authorization is not demonstrated on this host.
- Desktop capture is denied until a separate source picker is available.
- Native remembered-choice readback during document loading remains unverified. Production domain regressions now cover committed loading documents and reject uncommitted navigation.

Current behavior: Native one-shot prompts retain origin/frame/mask/browser/document ownership, cancel on invalidation, persist requesting/embedding-origin choices, and release on native dismissal. Notification denial is exercised. App and five helpers have permission usage metadata and signatures.

Existing pointers: `Sources/BrkCEF/WebsitePolicy.swift`, `Vendor/CefSwift/Sources/CefKit/CefPermission.swift`, `Sources/BrkApp/SitePanels.swift`, `scripts/declare-site-permissions.py`

### A109 Ad blocker

Built-in ad/tracker blocking and cookie-banner handling use defined rules, profile/site exceptions and updates, block relevant requests/cosmetic content and preserve normal navigation.

Current assessment: partial.
- Native main-frame, cross-origin subframe and redirect coverage is incomplete.
- The shipped rules and selected JSON format are a defined small subset, not a full EasyList/EasyPrivacy subscription implementation.

Current behavior: Real IO-thread request filtering, independent cosmetics/banner hiding, per-profile/site exceptions, validated selected rule updates, errors and restart persistence work against deterministic fixtures.

Existing pointers: `Vendor/CefSwift/Sources/CefKit/CefRequestFilter.swift`, `Sources/BrkCEF/WebsitePolicy.swift`, `Sources/BrkDomain/Codec.swift`

### A110 Per-site behavior rules

Per-site keep-alive, PiP and suspension-exclusion rules have explicit matching/profile/private scope and affect real scheduling/media behavior without interrupting protected operations.

Current assessment: partial.
- PiP depends on later media implementation.
- Full WebAudio/PiP/media and protected-operation exemption matrix remains unverified.

Current behavior: Per-site hidden-page suspension, keep-alive and exclusion rules drive actual Chromium lifecycle scheduling. Server ticks stop while frozen and resume with visibility/keep-alive. Leases, active downloads and playing HTML audio/video prevent requested suspension.

Existing pointers: `Sources/BrkCEF/WebsitePolicy.swift`, `Sources/BrkDomain/Rules/SitePolicies.swift`

## Deliverable

Commit implementation, production tests, native scenarios (names start with `Ext`) and evidence under `3fb66d7401:verify/completion/batch2-extensions-sites/REPORT.md`. Include `proposal.json` with exactly the assigned IDs (A096, A097, A098, A107, A108, A109, A110), truthful final status, remaining work and repository-local evidence for the parent, in the shape of the existing `06656768e1:verify/completion/batch-tabs/proposal.json`. Do not edit the canonical inventory. Final reply: PASS, ISSUES or BLOCKED; starting and final commit; changed files; actual commands and results; limitations; clean-worktree status. No PR or publishing.
