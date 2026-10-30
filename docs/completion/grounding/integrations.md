# Productivity and local-service groundwork

This parent source pass covers A099 to A101, A119 to A126, and A134 to A148 in `features.json`. It describes the current implementation, not a design for all remaining features.

## Current components and flow

`Rules/Tabs.swift` requests an AI rename when a tab is pinned and the corresponding Max option is enabled. `Rules/Assist.swift` creates a request ID and emits `Effect.ai`. `AppStore` calls `AIProviderSeam.answer`, which finds the selected installed CLI, constructs a prompt, and returns an `AIOutcome`. The reducer applies a successful rename to the original tab ID and removes the pending request. Tidy Today and Ask outcomes currently do nothing. The command-bar AI action is still disabled.

The Max pane stores provider and feature choices through the ordinary settings reducer. Executable discovery establishes installation, not account health or a successful model request. Tests exercise the adapter with a small fixture executable; they do not establish every user's real CLI integration.

The subprocess implementation in `Sources/BrkApp/AIProvider.swift` needs a focused liveness and permissions pass before expansion. It reads stdout and stderr after process termination. Its task-group timeout does not explicitly terminate the Process, and cancellation of the continuation-backed process task needs verification. Large output and a hanging child are concrete reproduction targets. CLI tool access, working directory, prompt/data separation and private-context handling also need an explicit contract before page content is sent to a general coding CLI. These are inspection findings, not measured failures in this pass.

`StateCodec` owns the version-2 saved document and migration/repair. `StateFile` owns atomic/debounced persistence. Ephemeral windows and scratch tabs must stay out of the saved document. New Notes, Easels, Boosts, imports and sync data must retain those boundaries rather than treating all documents as persistent by default.

Sharing already builds an `ExportDocument` through a domain effect. `ExportCodec` writes JSON or Netscape bookmark HTML; `ShareExport` invokes the native save panel and writes the selected file. The original sharing-by-link requirement was replaced by file export at the user's direction. The native save-panel test remains skipped, and there are no creative-document types to export yet. The current writer ignores errors; export acceptance must include visible failure handling as well as success and cancellation.

Boosts, Notes, Easels, onboarding, import, and local-folder sync do not have complete workflows in current source. Their menu rows are `.later` actions or their Library pages are placeholders. A disabled action or stored setting does not change that status.

## Boundaries to preserve

- Browser observations are untrusted data. AI replies must be parsed into narrow validated actions, especially tab grouping and filenames. A reply cannot select unrelated profile IDs or execute arbitrary application commands.
- Private content stays in session-owned storage unless the user explicitly exports it. Account credentials, cookies, private tabs and device-specific paths must not enter sidebar sync.
- Import uses user-selected sources and fixture verification. It must not silently read real password databases during development or mutate a source browser.
- A native document needs a typed identity and lifecycle. Decide how it belongs to a tab, profile, private window, split, export and undo before adding editor views.
- Sync must define crash/retry behavior, conflict resolution and deletion semantics before two devices write the same state. A copied whole `state.json` is not an established sync contract.

## Verification and remaining questions

The parent independently built `95c46b5` and ran all 45 native scenarios. State repair, restart behavior, multi-page shutdown and report production have current evidence under `verify/swift/focus-parent/`. The source-level acceptance rows distinguish these verified foundations from missing product workflows.

The cloud reference Arc still shows Sign In. The user has a signed-in Arc on their own Mac and asked about skipping cloud login. The retained offline-auth investigation found a real test-auth path, but did not establish safe profile/preferences isolation or observe the browser window. It is not yet a visual reference.

Open product details with reasonable implementation defaults include starter content, the local tour, file-based creative sharing, translation through the already approved local CLI providers, and a user-selected sync folder. Defaults must be documented. They must not silently remove features from the 148-row inventory.

## Files read

`Sources/BrkApp/AIProvider.swift`, `AppStore.swift`, `ShareExport.swift`, `StateFile.swift`; `Sources/BrkDomain/Rules/Assist.swift`, `Rules/Tabs.swift`, `Codec.swift`, `Command.swift`, `Actions.swift`; `Sources/BrkSettings/SettingsPanes.swift`; `docs/swift/feature-ledger.md`; `docs/swift/wave2-status.md`; the current native reports and independent review.
