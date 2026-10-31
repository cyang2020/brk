# Boosts: per-site CSS and JavaScript, Zap, editor, gallery, install, export and import

Read README.md in this directory first. This is a complete implementation slice, not an audit-only assignment.

Build Boosts: profile-scoped per-site CSS and JavaScript, Zap (click an element to hide it, persisted as a CSS rule), an editor with live preview, a gallery of local presets, install from a local export file, disable, remove, export and import.

Design twice before coding. Launch at most two bounded, read-only Codex design children with the same brief and synthesize one `DESIGN.md` under your evidence directory. Decisions to settle: storage (default: a separate versioned file per profile under the profile data root; `StateCodec` stays at version 3 and the parent owns any format bump), injection ownership (reuse the isolated-world CSS mechanism the website theme uses in `Sources/BrkCEF/WebsitePolicy.swift` with its own namespace; JavaScript boosts need a per-boost confirmation and run only on committed documents of matching origins), scope matching (origin, host or all sites), private windows (no new boosts; existing public boosts apply only when the user opts in). The Library Boosts page lists the profile's boosts; the legacy advanced boost is the raw CSS and JavaScript editor. Resolve the `.later(.boosts)` entries in `Sources/BrkDomain/Actions.swift`.

Owned paths: new Boosts model, rules and codec files in `Sources/BrkDomain`, a new Boosts injection file in `Sources/BrkCEF` with an additive document-lifecycle hook into `WebsitePolicy.swift`, the Boosts page in `Sources/BrkLibrary`, the editor and Zap overlay in `Sources/BrkOverlays` or `Sources/BrkContent`, and your new `BoostScenarios.swift`. Expose a command for the site control center's Boost action; the parent wires it after integration.

## Owned feature acceptance

### A099 Boosts

Create, edit, install, disable, and remove a profile-scoped site boost with CSS, JavaScript and Zap; export and import its data.

Current assessment: missing.
- No complete user-facing workflow is implemented in current source.

## Deliverable

Commit implementation, production tests, native scenarios (names start with `Boost`) and evidence under `verify/completion/batch2-boosts/REPORT.md`. Include `proposal.json` with exactly the assigned IDs (A099), truthful final status, remaining work and repository-local evidence for the parent, in the shape of the existing `verify/completion/batch-tabs/proposal.json`. Do not edit the canonical inventory. Final reply: PASS, ISSUES or BLOCKED; starting and final commit; changed files; actual commands and results; limitations; clean-worktree status. No PR or publishing.
