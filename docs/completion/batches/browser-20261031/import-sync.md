# Onboarding, authorized import, local sync and export

Read README.md in this directory first. This is a complete implementation slice, not an audit-only assignment.

Build real first-run onboarding/welcome/tour/starter-tab choices and user-selected browser import with preview, mapping, accurate counts, cancellation/rollback and unchanged sources. Support bookmark/history formats and supported password import with explicit OS authorization and secure destination; never silently read live browser profiles/keychains/password databases. Use fixture sources and owned test credentials; external authentication/authorization remains a truthful runtime gate. Complete file export for Spaces/folders/selected tabs; creative-document export is cross-feature and must remain partial until those types exist. Local-folder sync must use a purpose-built, versioned whitelist of agreed public sidebar data, not StateCodec/full state.json. Exclude cookies/passwords/history/downloads/private/scratch/windows and device-specific paths; define exact profile mapping without syncing secrets. Compare two real alternatives for merge/conflict/deletion semantics, then implement deterministic replica IDs/revisions/tombstones, retry/crash safety, atomic replacement, two-device simulation, concurrent move/delete/edit conflict outcomes, and visible status/errors/disconnect. Preserve unrelated local settings and per-window state on incoming merges. Folder selection is a native product flow; tests use two owned app data roots and one temporary sync directory. Main focus: domain SidebarImport/SidebarSync/Export types and reducers/codecs, BrkApp import/sync/file panels, onboarding/settings UI. Do not bump the shared StateCodec format independently or replace the domain state owner. Dedicated scenarios use ImportSync names.

## Owned feature acceptance

### A119 Onboarding

Complete an account-free first-run flow that configures a space, Favorites, import choices and optional default-browser selection.

Current assessment: missing.
- No complete user-facing workflow is implemented in current source.

### A120 Arc 101 welcome

Open and complete a local Brk tour that demonstrates the principal Arc workflows.

Current assessment: missing.
- No complete user-facing workflow is implemented in current source.

### A121 Seed tabs for a new profile

Create the selected starter tabs and Favorites once for a new profile, with reproducible defaults and no duplicates after restart.

Current assessment: missing.
- No complete user-facing workflow is implemented in current source.

### A122 Import from other browsers

Import user-selected bookmarks, history and supported passwords with explicit OS authorization, accurate counts and unchanged source data.

Current assessment: missing.
- No complete user-facing workflow is implemented in current source.

### A143 Sidebar sync

Synchronize the agreed sidebar data through a user-selected folder with deterministic conflict/deletion handling and no incognito or credential data.

Current assessment: missing.
- No complete user-facing workflow is implemented in current source.

### A144 Sharing by link

Export spaces, folders, selected tabs and supported creative documents to user-chosen local files; verify the native save flow.

Current assessment: partial.
- JSON/HTML encoding and save-panel code exist. Native save-panel validation and creative-document export remain.

## Deliverable

Commit implementation, production tests, native scenarios and evidence under `464881b882:verify/completion/batch-import-sync/REPORT.md`. Include `proposal.json` with exactly the assigned IDs, truthful final status, remaining work and repository-local evidence for the parent. Do not edit the canonical inventory. Final reply: PASS/ISSUES/BLOCKED, starting/final commit, changed files, actual commands/results, limitations, and clean-worktree status. No PR or publishing.
