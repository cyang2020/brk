# Spaces, sidebar layout and full theme tools

Read README.md in this directory first. This is a complete implementation slice, not an audit-only assignment.

Complete window/sidebar control behavior, real floating-sidebar tracking, toolbar mode and full-URL preference, Space header visibility, staged space creation/profile choice, native reorder/delete confirmation/manager, gesture-driven Space switching, and full theme editing. Implement color editing/count/intensity/saturation/lightness/dark bias/presets/undo and independent light/dark values with backward-compatible decoding. Complete the Library Spaces destination; A081 remains cross-feature and cannot be declared fully complete while Media/Notes/Easels/Boosts remain outside this batch. Do not invent Arc pixel references: use existing binary-derived anatomy and Brk layout/readability evidence, keep A148 independent. Integrate haptics settings for owned gestures. Theme CSS injection A065 belongs to sites; expose effective theme values through a narrow, typed snapshot for that consumer. Main focus: BrkTheme, domain Theme/SpaceTools, BrkOverlays space forms/manager, sidebar header/dock/resize/toolbar, Library Spaces. Tablist selection/folder behavior and split tools are owned elsewhere. Dedicated scenarios use SpaceTools names.

## Owned feature acceptance

### A001 Window shell and title row

Render traffic lights, sidebar toggle, back, forward and reload or stop above the address pill; controls act on the intended window.

Current assessment: implemented.
- Check real control clicks and hidden-sidebar traffic-light behavior against an authenticated reference; same-tab multiwindow ownership remains unresolved.

### A003 Sidebar width

Dragging the sidebar edge clamps to 164...500 pt, snaps at 228 and hides below 82; restore retains width.

Current assessment: implemented.
- Run pointer drags across thresholds, snap release and restart; physical haptics and reference animation are unverified.

### A005 Floating sidebar on hover

Hovering the left edge of a hidden sidebar reveals a floating sidebar over an unchanged content card; leaving closes it safely.

Current assessment: implemented.
- Verify pointer tracking with CEF content, menus and window edges; compare real reference reveal timing.

### A006 Toolbar mode

Toggle an address toolbar above the content and route editing and full-URL preference through that toolbar.

Current assessment: missing.
- Implement toolbar state, geometry, controls and keyboard or page focus interactions.

### A007 Space header

Show the space name and icon above its list and let the user hide or reveal the header.

Current assessment: partial.
- Add header visibility preference and layout behavior, including a single unnamed space.

### A056 Create a space

Create a space through an animated flow with name, icon, theme preview and profile selection.

Current assessment: partial.
- Add the profile card and creation stages, then verify the complete native flow and cancellation.

### A057 Switch spaces

Dock clicks and Opt+Cmd+arrows switch spaces, restore each window's selection and crossfade the background.

Current assessment: implemented.
- Check rapid keyboard switches and shared-tab attachment; reference motion remains unverified.

### A058 Swipe between spaces

Two-finger horizontal swipes page the sidebar between spaces with appropriate gesture ownership and cancellation.

Current assessment: missing.
- Implement gesture recognition and interactive progress without stealing page scrolling.

### A059 Rename, icon and theme of a space

Edit a space's name, icon and basic theme, save them, and cancel without changing the saved space.

Current assessment: implemented.
- Verify native edit and restart for all controls; the full theme editor is tracked separately in A063.

### A060 Delete and reorder spaces

Delete a space after confirmation, protect the last space, and drag to reorder dock spaces persistently.

Current assessment: partial.
- Add deletion confirmation and space drag interactions with cancellation and multiwindow checks.

### A061 Space manager

Provide a searchable space grid, reorder controls and Export into Folder using local files.

Current assessment: missing.
- Build the manager and define local export format or folder semantics without online sharing.

### A062 Theme background

Render a Metal gradient with selectable grain, sand, denim or tweed texture and stable crossfades.

Current assessment: implemented.
- Compare gradient positions, texture appearance and low-power fallback with an authenticated reference; procedural images are approximations.

### A063 Theme editor

Edit color-pad positions and color count, saturation, noise, intensity, preset pages, dark bias and undo with live preview.

Current assessment: partial.
- Add the color pad, add or remove colors, saturation and lightness, dark bias, paged presets and undo; verify every control changes output.

### A064 Light and dark theme values

Persist and render independently editable light and dark theme values and select the appropriate set.

Current assessment: missing.
- Add paired values and migration; test switching appearance without overwriting either set.

### A081 Library

Provide working Downloads, Archive, Easels and Notes, Media, Boosts and Spaces workflows in one Library.

Current assessment: partial.
- Complete Media, Easels and Notes, Boosts and Spaces with their owning features; real download cancellation is a platform dependency.

## Deliverable

Commit implementation, production tests, native scenarios and evidence under `verify/completion/batch-spaces/REPORT.md`. Include `proposal.json` with exactly the assigned IDs, truthful final status, remaining work and repository-local evidence for the parent. Do not edit the canonical inventory. Final reply: PASS/ISSUES/BLOCKED, starting/final commit, changed files, actual commands/results, limitations, and clean-worktree status. No PR or publishing.
