# Notes and Easels, their appearance and export

Read README.md in this directory first. This is a complete implementation slice, not an audit-only assignment.

Build Notes and Easels as Brk-owned documents. Design twice before coding (two bounded read-only Codex design children, one synthesized `DESIGN.md`): document storage per profile, the sidebar item kind for a note or easel, split hosting, private-session drafts that never persist, and export formats (Markdown and HTML for notes; PNG and a JSON document for easels). A100: rich-text notes editable in the sidebar panel and in a split, persisted, exportable, and `Export {app} Notes` in the Help menu resolved. A101: an easel canvas with captures (consume the captures-media insertion hook when merged), drawing and text objects, editing, reopening and export. Both follow the website appearance setting (A043's consumer) and feed A144's creative-document export through the export path file-panels delivered. Resolve the `.later(.notes)` and `.later(.easels)` entries in `Sources/BrkDomain/Actions.swift`. Owned paths: new creative-document model, rules and codec files in `Sources/BrkDomain`, editors in `Sources/BrkContent`, the Easels and Notes Library page, and your new `CreativeScenarios.swift`.

## Owned feature acceptance

### A100 Notes

Create and edit rich-text notes in the sidebar and split view; persist and export them without leaking private-session drafts.

Current assessment: missing.
- No complete user-facing workflow is implemented in current source.

### A101 Easels

Create and reopen an Easel with captures, drawing and text; edit its objects and export the result.

Current assessment: missing.
- No complete user-facing workflow is implemented in current source.

## Deliverable

Commit implementation, production tests, native scenarios (names start with `Creative`) and evidence under `verify/completion/batch2-easels-notes/REPORT.md`. Include `proposal.json` with exactly the assigned IDs (A100, A101), truthful final status, remaining work and repository-local evidence for the parent, in the shape of the existing `verify/completion/batch-tabs/proposal.json`. Do not edit the canonical inventory. Final reply: PASS, ISSUES or BLOCKED; starting and final commit; changed files; actual commands and results; limitations; clean-worktree status. No PR or publishing.
