# Capture, Media library, picture in picture, media controls, sound effects

Read README.md in this directory first. This is a complete implementation slice, not an audit-only assignment.

Build captures and media.

Probe first: the per-page DevTools channel (`CefDevTools`, request IDs from the shared allocator) can issue `Page.getLayoutMetrics` and `Page.captureScreenshot` with `clip` and `captureBeyondViewport` on the embedded Chrome path; prove it before designing around it, and do not reuse off-screen-rendering assumptions. A102: an area-selection overlay on the content card, full-page capture by protocol or stitching, portrait framing, export and storage, checks of output dimensions and pixels against the fixture, cancellation, navigation races, and private captures that never persist. A103: a capture storage model (profile-scoped folder plus index), its projection, the Media page with previews, open, export, remove, and restart survival. A104: probe video-element and document picture in picture separately on the embedded host (`requestPictureInPicture` through the page, or the Chrome command if the runtime offers it); explicit entry and automatic entry when leaving a video tab as a setting consumer; ownership across navigation, tab, window and profile changes; private contexts; defined activation failure and multiple-player behavior. A105: extend the bundled audibility extension (`Sources/BrkCEF/AudibilityExtension`) or MediaSession observation to report play and pause state per player, and execute play and pause for the playing tab from its sidebar row, with background behavior and lifecycle. A106: an event-to-sound mapping with bundled assets and a settings consumer; audible when enabled, silent when disabled, never blocking the UI.

Expose a typed hook for the per-site PiP exemption (extensions-sites) and for inserting a capture into an Easel (later slice). Owned paths: new capture and media files in `Sources/BrkCEF`, `Sources/BrkCEF/AudibilityExtension`, the Media page in `Sources/BrkLibrary`, capture and media model and rules in `Sources/BrkDomain`, the capture overlay in `Sources/BrkContent`, the sound and auto-PiP settings consumers, `.later(.captures)` entries in `Sources/BrkDomain/Actions.swift`, and your new `CaptureScenarios.swift` and `MediaScenarios.swift`.

## Owned feature acceptance

### A102 Capture

Area, full-page and portrait screenshots capture correct webpage pixels/scale, allow intended selection/export, and handle long/sticky/GPU content and private data with explicit ownership.

Current assessment: missing.
- Probe a supported capture source on the actual embedded Chrome path; do not reuse OSR assumptions.
- Implement area selection, full-page stitching or tested protocol capture, portrait framing and export/storage.
- Verify output dimensions/pixels, cancellation, navigation races and private retention.

Current behavior: Three capture actions disabled. Control socket window screenshot and vendor OSR paint APIs are not product capture.

Existing pointers: `Sources/BrkDomain/Actions.swift`, `Sources/BrkApp/Control/ControlExecutor.swift`, `Vendor/CefSwift/Sources/CefKit/CefRenderHandler.swift`, `Vendor/CefSwift/Sources/CCef/include/include/capi/cef_browser_capi.h`

### A103 Media page

Media Library lists real captures with preview/open/export/remove behavior and defined disk/profile/private retention.

Current assessment: missing.
- Add capture storage/model/projection and a real Media page with lifecycle/error handling.
- Verify actual capture artifacts are indexed, survive intended restart, and are removed/exported correctly.

Current behavior: View Media opens LaterPageView with an empty placeholder; there is no capture ledger.

Existing pointers: `Sources/BrkLibrary/LibraryView.swift`, `Sources/BrkLibrary/LibraryPages.swift`, `Sources/BrkDomain/SettingsModel.swift`, `Sources/BrkDomain/Actions.swift`

### A104 Picture in picture

Video and Meet PiP work with explicit/automatic entry when leaving a video tab, respect user activation/settings/site rules, and close or reattach correctly on navigation/tab/window/profile changes.

Current assessment: missing.
- Probe video-element and document/Meet PiP separately on pinned embedded host.
- Add playback ownership/state and host lifecycle; test private contexts, focus and active downloads/quit.
- Define activation failure and multiple-player behavior; do not treat a command name as support.

Current behavior: autoPictureInPicture setting has no consumer. Raw context command ID exists; no Brk PiP flow.

Existing pointers: `Sources/BrkDomain/SettingsModel.swift`, `Sources/BrkDomain/Rules/Settings.swift`, `Sources/BrkSettings/SettingsPanes.swift`, `Sources/BrkCEF/ChromePage.swift`, `Vendor/CefSwift/Sources/CCef/include/include/cef_command_ids.h`

### A105 Media controls

Playing tabs expose truthful play/pause controls and media state, with correct frame/player targeting, background behavior and lifecycle.

Current assessment: missing.
- Determine a supported playback/status path and multi-frame/player ownership.
- Implement controls and verify real media response, autoplay/activation failure, tab closure and private behavior.

Current behavior: No Brk player state/control UI. CefBrowser.isAudioMuted exists but is unused and does not pause media.

Existing pointers: `Sources/BrkBase/Page.swift`, `Sources/BrkCEF/ChromePage.swift`, `Vendor/CefSwift/Sources/CefKit/CefBrowser.swift`, `Vendor/CefSwift/Sources/CCef/include/include/capi/cef_audio_handler_capi.h`

### A106 Sound effects

Capture and other intended events play the defined Brk sounds when enabled and are silent when disabled, without blocking UI.

Current assessment: missing.
- Define event-to-sound mapping and assets, connect event execution and setting consumer, verify audible and disabled behavior.

Current behavior: soundEffects is persisted but unused; NSSound.beep is only a generic application effect.

Existing pointers: `Sources/BrkDomain/SettingsModel.swift`, `Sources/BrkDomain/Rules/Settings.swift`, `Sources/BrkSettings/SettingsPanes.swift`, `Sources/BrkApp/AppStore.swift`

## Deliverable

Commit implementation, production tests, native scenarios (names start with `Capture`) and evidence under `verify/completion/batch2-captures-media/REPORT.md`. Include `proposal.json` with exactly the assigned IDs (A102, A103, A104, A105, A106), truthful final status, remaining work and repository-local evidence for the parent, in the shape of the existing `verify/completion/batch-tabs/proposal.json`. Do not edit the canonical inventory. Final reply: PASS, ISSUES or BLOCKED; starting and final commit; changed files; actual commands and results; limitations; clean-worktree status. No PR or publishing.
