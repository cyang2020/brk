# Local-CLI AI features: command bar question, ask on page, previews, tidy tabs, renames, instant links, browse for me, translation, Max pane

Read README.md in this directory first. This is a complete implementation slice, not an audit-only assignment.

Build the AI features on the existing seam: `Sources/BrkApp/AIProvider.swift` runs the user's local `claude` or `codex` command-line tool, `Sources/BrkDomain/Rules/Assist.swift` asks through `Effect.ai` and applies `SystemEvent.aiResult`. The user decided no API keys.

Repair the seam first (A138's remaining item): reproduce and fix CLI cancellation, process termination on timeout and quit, and pipe draining for large outputs; add partial-output streaming. Tests use a fixture provider executable under `Tests/Fixtures` (a script that answers deterministically, delays or hangs on command) so unit and native runs never need the network. Make exactly one real-provider smoke receipt with whichever of `claude` (`claude -p ... --output-format text`) or `codex` (`codex exec --skip-git-repo-check ...`) is installed, record its command, duration and output, and run nothing else against the real tools.

A134: Opt+Cmd+G and the `.later(.aiCommandBar)` entry ask from the command bar; the answer is cancellable and failures are actionable. A135: a question over the active page's extracted main-frame text in the page's own context, attributed to that page, never reading other profiles or private pages. A136: a bounded summary on deliberate link hover with cancel and an unavailable state; use the sidebar-tabs hover hook if merged, otherwise your own narrow trigger in your files. A137: a validated JSON plan that rejects stale or foreign IDs, groups only eligible Today tabs, with undo. A138: completed-download rename with safe filenames and collision handling; pinned-tab rename is already wired. A139: resolve a bar query to a validated destination (the tool proposes, Brk checks URL shape and reachability in the right context) with ordinary search as the explicit fallback. A140: read selected sources in the correct browsing context through request-owned hidden pages that close afterwards, and build a local answer document whose citations link those sources. A141: translate visible text in chunks while preserving controls (replace text nodes, keep the DOM), with profile-scoped never-translate languages and sites. A142: switches per delivered feature and provider choice, no API key field.

Owned paths: `Sources/BrkApp/AIProvider.swift` and new AI files in BrkApp, `Sources/BrkDomain/Rules/Assist.swift` and new AI rules and model files, the ask mode in `Sources/BrkOverlays/CommandBarView.swift` and `Suggest.swift`, the Max pane in `Sources/BrkSettings`, an answer-document view in `Sources/BrkContent`, and your new `AIScenarios.swift`. Domain code stays pure; the tools run only in BrkApp.

## Owned feature acceptance

### A134 ChatGPT in the command bar

Submit a command-bar question to the selected local AI CLI and display a cancellable answer or actionable failure.

Current assessment: missing.
- No complete user-facing workflow is implemented in current source.

### A135 Ask on Page

Answer questions from the active page context, preserve source attribution, and never expose unrelated profile or private data.

Current assessment: missing.
- No complete user-facing workflow is implemented in current source.

### A136 5-second previews

Show a bounded link-summary preview on deliberate hover, with cancellation and an unavailable state.

Current assessment: missing.
- No complete user-facing workflow is implemented in current source.

### A137 Tidy Tabs and Organize Today Tabs

Group only the current eligible Today tabs using a validated AI plan; reject stale or foreign IDs and provide undo.

Current assessment: missing.
- No complete user-facing workflow is implemented in current source.

### A138 Tidy pinned titles and downloads

Rename pinned tabs and completed downloads with the configured local AI provider, safe filenames and collision handling.

Current assessment: partial.
- Pinned-tab rename is wired. Download renaming and a real-provider verification remain.
- Reproduce and repair CLI cancellation, process termination and pipe-draining behavior before expanding AI tasks.

### A139 Instant Links

Resolve a query to a relevant validated web destination and open it, with ordinary search as an explicit fallback.

Current assessment: missing.
- No complete user-facing workflow is implemented in current source.

### A140 Browse for Me (Ask Arc)

Read selected web sources in the correct browsing context and present an answer whose citations refer to those sources.

Current assessment: missing.
- No complete user-facing workflow is implemented in current source.

### A141 Translation

Translate page content while preserving controls; remember profile-scoped never-translate language and site choices.

Current assessment: missing.
- No complete user-facing workflow is implemented in current source.

### A142 Max pane

Expose functional settings for the delivered Max features and local CLI providers, without requiring an API key.

Current assessment: partial.
- The pane and provider controls exist; most Max task handlers remain unimplemented.

## Deliverable

Commit implementation, production tests, native scenarios (names start with `AI`) and evidence under `a1c5b74838:verify/completion/batch2-ai-features/REPORT.md`. Include `proposal.json` with exactly the assigned IDs (A134, A135, A136, A137, A138, A139, A140, A141, A142), truthful final status, remaining work and repository-local evidence for the parent, in the shape of the existing `06656768e1:verify/completion/batch-tabs/proposal.json`. Do not edit the canonical inventory. Final reply: PASS, ISSUES or BLOCKED; starting and final commit; changed files; actual commands and results; limitations; clean-worktree status. No PR or publishing.
