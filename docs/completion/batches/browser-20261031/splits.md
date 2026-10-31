# Complete split-view workflows

Read README.md in this directory first. This is a complete implementation slice, not an audit-only assignment.

Complete two-to-four panes in both orientations with native resize/focus/restart, reachable orientation controls, Separate/Expand/Restore/Separate All, pointer and keyboard segment/pane focus, next/previous and numbered pane commands, and actual drag-tab-into-content hit zones/feedback/cancellation. Define pin/order/window rules and preserve exact window-local selection/addresses, private ownership, and active downloads. Keep the existing logical split/tree representation; tabs owns structural archive snapshots and must be able to consume existing Split metadata. Implement expansion as reversible window presentation state unless evidence requires shared structural change. Verify actual pointer drags and webpage editing, not reducer-dispatched moves. Main focus: domain SplitTools rules/snapshots, BrkLayout content geometry, BrkContent card/divider/drop targets and Sidebar split-segment presentation. Do not edit space theme/manager or find UI. Dedicated scenarios use SplitTools names.

## Owned feature acceptance

### A071 Add and close panes

Add or close panes up to four with a 10 pt gap; preserve pin semantics and dissolve one-pane splits.

Current assessment: implemented.
- CEF scenario 6 covers two panes; verify three or four panes, pointer focus, close and restart natively.

### A072 Resize panes

Dragging a split divider changes adjacent pane fractions within bounds and retains them after restart.

Current assessment: implemented.
- Add native drag and restart checks in both orientations and after window resizing.

### A073 Split as one sidebar row

Represent each split as one sidebar row with individually selectable pane segments.

Current assessment: implemented.
- Verify segment pointer targeting, loading, overflow and same-split selection in two windows.

### A074 Horizontal and vertical

Let users switch a split between side-by-side and stacked layouts and persist the choice.

Current assessment: partial.
- Add an orientation UI and native divider or focus checks for stacked panes.

### A075 Separate, expand, separate all

Separate one pane, expand the current pane and separate all panes without losing their identities or URLs.

Current assessment: partial.
- Implement reachable separate, expand, restore and separate-all commands with explicit pin, order and window rules.

### A076 Drag a tab into the page to split

Dropping a tab onto a content edge previews and creates or extends a split with a defined orientation.

Current assessment: missing.
- Implement content hit zones, drop feedback, cancellation and split-cap or profile restrictions.

### A077 Jump between panes

Keyboard shortcuts select panes one through four and next or previous pane with defined boundaries.

Current assessment: missing.
- Add pane-specific commands and bindings without confusing tab cycling; test native focus and editing.

## Deliverable

Commit implementation, production tests, native scenarios and evidence under `verify/completion/batch-splits/REPORT.md`. Include `proposal.json` with exactly the assigned IDs, truthful final status, remaining work and repository-local evidence for the parent. Do not edit the canonical inventory. Final reply: PASS/ISSUES/BLOCKED, starting/final commit, changed files, actual commands/results, limitations, and clean-worktree status. No PR or publishing.
