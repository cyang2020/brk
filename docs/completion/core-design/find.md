# Implement native page find and scoped editing

Implement A039 and resolve review C4. The existing design comparison already selected window-owned pages and document-scoped operations. Read the current engine, MainDocumentState, key routing, menu table, native focus rules, and the candidate find evidence. Do not repeat the design arena or start agents. This unit includes all six existing actions: Find, Find and Replace, Find Next, Find Previous, Use Selection to Find, and Jump to Selection.

## User behavior and state

Use a native AppKit find bar in the focused page card, including Peek. It has a query, next/previous, actual count/ordinal, close, and an editable-context replacement mode with Replace and Replace All. Reuse the application's theme and pure layout boundaries. Empty query clears highlights. Zero matches has no fabricated ordinal. Transient searching and failures have useful plain-language text. Do not expose CEF IDs, JSON, callback mechanics, or implementation labels in the product.

The window owns this UI; every active search is bound to a particular PageID, BrowserToken and ready DocumentToken. Switching tab, space, split focus or Peek target closes the old find session. Same-slot main-document navigation invalidates old results, preserves the visible query, and searches again only when the new document is ready. Never resurrect an old document token. Closing the bar stops its native search and restores page focus only where appropriate; never activate a background window or replace another window's native editor.

Find opening dismisses the command bar or Library, but keeps an active Peek and searches it. Escape closes find before dismissing Peek. Other conflicting native overlays close find. Settings-native editing must not silently invoke find in a remembered background browser. Next/previous with a closed bar may reopen that window/context's last nonempty query; otherwise open an empty query field. Do not persist search or selection data, share private queries with public windows, or use the system Find pasteboard as an unrequested cross-context store.

Preserve the extracted page-first shortcut priorities and user remaps. Verify renderer-prevented and unhandled events with real keys. The current CefKit bridge ignores the pre-key shortcut-intent out parameter; measure and correctly bridge that intent if needed so Chrome's built-in find does not contend with Brk's find. Derive the intent from the same routing decision, not a second hand-maintained shortcut table. Do not switch all Find keys to app priority to make the tests pass. Preserve Downloads' separately documented priority and all existing input regressions.

## Correlate generated CEF IDs

Extend the existing WebEngine and event vocabulary using [Find.swift](Find.swift). Wire CEF's find-next/direction, stop-finding and find-result handler. Keep native identifiers and C pointers inside the adapter.

The pinned CEF `find` method has no caller ID. Chromium allocates IDs globally, filters old search sessions and may send further updates after `finalUpdate`. Do not predict `last + 1` per browser or stamp a callback with whichever query is current. These facts are documented in the original candidate and independent review.

Before replacing a query, invalidate its old registry entry, enter a reset state, and stop the old native session. Create the new pending request/document fence before calling find. Bind the first eligible non-reset native ID on that browser under the pinned filtering rules. Record each binding. Serialize next/previous steps; while a newer step awaits its ID, ignore known older step IDs. A final callback completes a pass, not the lifetime of the query. Keep accepting valid later updates for the current step until replacement, close, invalidation or a newer step.

Handle main-frame loads, renderer loss, DOM changes and subframe changes explicitly. The token adapter must be tested, not merely raw find callbacks. Avoid asynchronous hops between receiving a native callback and checking its registry/document fence. Unsupported or ambiguous results are suppressed rather than mislabeled. Recheck the pinned assumptions on CEF upgrades.

## Selection and replacement

Use a real frame-scoped renderer/CDP bridge with typed results. Do not use document titles as a product response channel. Keep JSON, CEF frame IDs, execution-context IDs and borrowed references inside BrkCEF/CefKit. Use CEF's actual focused frame, with explicit main-document and frame-document identity. An async response from a navigated, closed, replaced or foreign frame must not reach the UI.

Use Selection to Find reads the actual selected text. Jump to Selection scrolls the still-current selection, not the last find rectangle. Replacement supports enabled text inputs, textareas and contenteditable regions whose input/undo behavior is verified. Passwords, read-only fields, inaccessible or cross-origin frames, stale selections and active IME composition are refused without reading/mutating protected values. Define same-origin from actual frame/security origin, accounting for inherited blank/srcdoc contexts; do not grant universal cross-origin access or disable browser security.

The adapter owns opaque selection tickets containing the original element/range, frame/document identity and selection revision. Revalidate immediately before an edit. Never treat native find highlighting as proof of the DOM's current editable selection. Replacement mode must state and enforce its editable scope; page-wide search must not silently edit another field. Losing that scope disables mutation until a new valid capture.

Treat queries as literal Unicode text. Preserve correct UTF-16 offsets, input/beforeinput behavior, nonselected markup and native undo. Do not implement replacement by assigning an element's whole value/innerHTML and pretending undo works. Tests must establish actual text and undo behavior for each supported editable kind. If a page's synchronous input handler changes the remaining edit plan, stop and report the true applied count instead of continuing at stale offsets. Do not claim a single undo group unless measured.

Mutations are identified and applied once. A timeout is not proof that an asynchronous edit never ran. Preserve idempotence for the same request and report an unconfirmed result where appropriate. Never automatically retry a potentially applied edit. A DOM mutation invalidates stale selection tickets; frame navigation and private expiry discard their records.

## Ownership and acceptance

One owner integrates BrkBase find vocabulary, domain commands/session/snapshots, actions/menus, layout/overlay/native focus, WebEngine, BrkCEF/CefKit callbacks and the scoped renderer bridge. Reuse browser/document/context lifetimes and preserve transfer, context-menu, private, focus, History and identity corrections. A find query does not keep a retired page alive. Stop or invalidate before retiring; do not call methods on an already closed native browser. Any DevTools registration/request owner releases its references on every completion, invalidation and shutdown path. Use the demonstrated reference-transfer convention, not the failed prototype's blanket release-after-call.

Remove the six `.later(.findInPage)` routes only as their real actions become usable. Do not mark A039 complete while selection, replacement or Jump remain placeholders. C5 output, C6 broad data clearing and all other inventory features remain scheduled.

Verify the real production correlation/selection code with unit fixtures: interleaved browsers and generated IDs, queued steps, old/reset IDs, repeated final/nonfinal updates, navigation/close, duplicate mutations, stale element/frame/selection, protected controls and timeout ambiguity. Native cases must exercise the actual bar, keyboard/remaps/page-first routing, two windows with the same logical tab, split/Peek/private targets, focus return, changing page content, selection text/jump, replacement/input events and undo in each supported editable kind. Assert actual result values and DOM content. A dispatcher receipt or visible bar alone is insufficient.

Run the signed build and the full native suite after focused checks. Use the common native lock, a freshly built bundle and an explicit short `/tmp` data root. Work only with fixture pages and owned processes. Preserve failed attempts and exact commands/source/binary identities under `c21611c615:verify/completion/find-integration/REPORT.md`. No original browser data, canonical inventory/plan/audit edits, PR, publishing, or extra agents. Complete implementation and verification, commit, and leave the assigned worktree clean. Record any necessary signature correction with concrete evidence instead of silently dropping scope.
