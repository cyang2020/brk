# Settings window, General, Profiles, Shortcuts, Advanced and App Icon panes with their runtime consumers

Read README.md in this directory first. This is a complete implementation slice, not an audit-only assignment.

Finish the settings rows by connecting every switch to its runtime consumer. A113: add the App Icon pane and finish the window. A114: quit confirmation inside ordered shutdown; previews, blocker and translation controls drive the merged consumers. A115: default document app behavior and native per-profile checks for search, download location and archive threshold. A116: cover the remaining intended shortcuts and alternates, conflicts and recording through actual controls. A117: restore policy, sound, reorder haptics, toolbar URL, page dragging, auto PiP, theme CSS, Boosts and quote behavior through their owning layers (sound and auto PiP from captures-media, Boosts from boosts, both merged before this slice starts); the update channel stays deferred. A118: original Brk icon choices, application integration and persistence. Owned paths: `Sources/BrkSettings/*`, `Sources/BrkDomain/{SettingsModel,Rules/Settings}.swift`, `Sources/BrkApp/{SettingsWindowController,Lifecycle}.swift`, and your new `SettingsScenarios.swift`.

## Owned feature acceptance

### A113 Settings window

Provide General, Max, Profiles, Shortcuts, Links, Advanced and App Icon panes in a native settings window; omit excluded Account features.

Current assessment: partial.
- Add App Icon and finish runtime consumers; the six mounted panes and persistence alone do not complete their features.

Current behavior: A single settings window mounts six SwiftUI panes, sizes them and handles close keys; App Icon is absent.

Existing pointers: `Sources/BrkApp/SettingsWindowController.swift`, `Sources/BrkSettings/SettingsHost.swift`, `Sources/BrkDomain/SettingsModel.swift`

### A114 General pane

General settings must actually warn before quit and control previews, ad blocking and translation; updater remains deferred.

Current assessment: partial.
- Wire quit confirmation into ordered shutdown; implement previews, blocker and translation controls with their platform consumers.

Current behavior: Default-browser notice is wired. QuitWarning helper exists but Lifecycle never calls it; appearance is also stored without a page consumer.

Existing pointers: `Sources/BrkSettings/SettingsPanes.swift`, `Sources/BrkSettings/QuitWarning.swift`, `Sources/BrkApp/Lifecycle.swift`, `Sources/BrkDomain/SettingsModel.swift`

### A115 Profiles pane

Profile settings control search, default document app, download location and archive threshold for that profile.

Current assessment: partial.
- Add default document app behavior and native per-profile checks for each setting.

Current behavior: Search, suggestions, downloads directory or prompt, and threshold are consumed; default document app has no model or control.

Existing pointers: `Sources/BrkSettings/SettingsPanes.swift`, `Sources/BrkApp/KeyRouter.swift`, `Sources/BrkDomain/Rules/CommandBar.swift`, `Sources/BrkDomain/Rules/Archive.swift`

### A116 Shortcuts pane and remapping

Remap all intended shortcuts, assign priority, display conflicts and use the same bindings in menus and native or CEF routing.

Current assessment: partial.
- Cover the remaining intended shortcuts and alternates; verify conflicts and recording through actual controls, not only dispatching settings.

Current behavior: The recorder and KeyBindings cover 122 action IDs with primary-chord overrides; fixed alternates and AppKit-standard items are outside that editor.

Existing pointers: `Sources/BrkSettings/Panes/ShortcutsPane.swift`, `Sources/BrkDomain/Actions.swift`, `Sources/BrkDomain/KeyRouting.swift`, `Sources/BrkApp/MainMenu.swift`

### A117 Advanced pane

Each Advanced switch must change the named runtime behavior; updates and update-channel selection may remain deferred.

Current assessment: partial.
- Implement restore policy, sound, reorder haptics, toolbar URL, page dragging, auto PiP, theme CSS, Boosts and quote behavior through their owning layers.

Current behavior: All nine switches persist and render. None has a runtime consumer; restore-off still restores two windows in the probe.

Existing pointers: `Sources/BrkDomain/SettingsModel.swift`, `Sources/BrkDomain/Rules/Settings.swift`, `Sources/BrkSettings/SettingsPanes.swift`, `Sources/BrkApp/Lifecycle.swift`, `Sources/BrkDomain/Codec.swift`

### A118 App Icon pane

Pick an available Brk app icon, apply it to the application and retain the choice without account or referral gates.

Current assessment: missing.
- Implement original Brk icon choices, application integration and persistence; referral exclusion does not exclude the picker.

Current behavior: SettingsPane has no App Icon case and no runtime icon-choice state or consumer.

Existing pointers: `Sources/BrkDomain/SettingsModel.swift`, `Sources/BrkSettings/SettingsHost.swift`, `Sources/BrkApp/Lifecycle.swift`

## Deliverable

Commit implementation, production tests, native scenarios (names start with `Settings`) and evidence under `verify/completion/batch2-settings-panes/REPORT.md`. Include `proposal.json` with exactly the assigned IDs (A113, A114, A115, A116, A117, A118), truthful final status, remaining work and repository-local evidence for the parent, in the shape of the existing `06656768e1:verify/completion/batch-tabs/proposal.json`. Do not edit the canonical inventory. Final reply: PASS, ISSUES or BLOCKED; starting and final commit; changed files; actual commands and results; limitations; clean-worktree status. No PR or publishing.
