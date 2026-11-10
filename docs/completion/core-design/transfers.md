# Implement real download control and context disposal

This is the next implementation unit after window-owned pages. It resolves review C2 and C3 for downloads and the browser/context resources they retain. Find, document output and broad browsing-data removal remain separate units. Use the established ownership design; do not run another design arena or copy either diagnostic prototype into production.

## Addressing and public contracts

Keep the existing DownloadID as the public operation identity. Internally index native callbacks by `(BrowserToken, nativeDownloadID)` and mint one DownloadID on the first update or decision. Keep terminal tombstones until that browser closes so a late callback cannot allocate a new transfer. Copy borrowed item values during the callback. Preserve complete, cancelled, interrupted, in-progress and interruption reason separately.

Extend PageSpec with a typed download policy: directory destination or ask-location with a starting directory. Projection supplies the current profile's settings; private pages use the existing explicit default destination policy. Capture this policy, the browser token, its immutable context epoch and native owner on the first callback. Do not consult the tab's later profile, current key window or fallback default when a callback arrives. Buffer early progress until valid URL/name information exists; never fabricate a URL to create a Library row.

Extend the existing WebEngine rather than adding another facade:

- `cancelDownload(DownloadID)` requests cancellation of one operation.
- `disposeContext(ContextDisposal)` synchronously revokes the named context and schedules its drain. Its final result arrives through the existing delegate.
- The delegate reports `DownloadUpdate` independently of PageEvent, offers `DownloadDestinationPrompt` with a one-shot reply, dismisses that prompt by ticket, and reports one final `ContextDisposalResult`.

The [typed sketch](Transfers.swift) names the boundary values. Extend existing production vocabulary where it already has the same role. Delete PageEvent.download, page-addressed settings decisions, ChromePage destination ownership, immediate release of download-control callbacks, and ledger-only cancel when all callers migrate. Preserve old completed download records during codec migration. Unfinished records still restore as failed, not resumed.

## Private epochs and immediate revocation

Extend BrowsingContext's private case with a fresh PrivateSessionID. The domain owns the active private epoch. All current private windows share it; closing the last one revokes it immediately. A newly opened private window receives a different ID, even while old resources drain. Never serialize private epochs or metadata.

Add a context-disposal effect with its own ID and final completion event. AppStore submits these effects synchronously before publishing the new page demand, so reconcile cannot start or continue work in a context that the reducer has revoked. The engine method marks the context revoked before returning; it owns asynchronous cancellation and final callbacks. Repeated requests are idempotent. Never return an uncorrelated `draining` outcome.

Profile deletion refuses new work, retains a deletion-in-progress record, and removes that record only after the final result. Preserve the existing default-profile and assigned-space guards. A successful result distinguishes released in-memory data from a persistent directory scheduled for deletion at next launch. It must not claim immediate disk deletion. Failed drains retain a recoverable deletion state. Never delete downloaded user files as part of profile removal.

## Resource ownership and shutdown

One engine owner tracks every browser incarnation through presented, retained and closing states, including host destruction. Presentation demand and operation retention are separate reasons for a browser to remain alive. Derive retention from owned operation records or one authoritative lease collection; do not add a hidden browser map outside shutdown accounting. The lease mechanism must also support the later document-output owner, whose callbacks may outlive presentation.

Each transfer record owns its decision/control references, destination reservation and browser/context lease. Replacing a retained callback releases the previous reference exactly once. Release on rejection, absent owner, duplicate/terminal update and shutdown too. Keep all reference operations on the required CEF thread. Validate each incoming/outgoing reference contract instead of applying one universal release helper; A's failed PDF experiment demonstrates that hazard.

When an accepted public download loses its source tab/window or the tab changes profile, stop page observations but retain the exact initiating browser and context until the transfer ends. Never reconstruct its URL, POST, blob or authentication request in another browser. Multiple transfers retain the browser until the last one finishes. A pending destination decision instead cancels when its source or native owner disappears. Park the surface without restoring borrowed views early or making the CEF host key. Return those views exactly once during final close.

That retention policy applies to Brk's presentation close/reassignment commands. A mandatory native browser close, including a page's `window.close()`, has already begun destruction and cannot be vetoed once CEF reports it ready to close. Publish the page closure before any reentrant download result, request native transfer cancellation, and report the actual terminal result or an explicit failure with retained recovery files. Do not recreate the closed page, reconstruct its request, or infer writer termination from browser closure alone. The parent native census and T15 document this distinction.

Profile deletion and private expiry cancel their pending/active operations, then drain callbacks, browsers, native hosts, context-readiness callbacks and context handles. A late readiness or panel callback cannot recreate a revoked context. Quit revokes new work and drains all these records before the existing ordered CEF shutdown. A timeout is an explicit nonclean result, never permission to shut down beneath live callbacks.

## Decisions, cancellation and files

Use a nonblocking NSSavePanel sheet attached to the captured Brk window, with one active sheet per window. The ticket contains the DownloadID and a decision generation. On reply validate ticket, operation state, original context epoch, application phase and source/owner availability. Repeated answers do nothing. Owner closure dismisses the sheet and denies the uncontinued CEF decision. No answer can fall back to another window or profile.

Cancellation first changes the row to cancelling. If a control callback is not available yet, retain the intent and apply it to the first callback. A completed native result wins a cancellation race when completion already occurred. Otherwise wait for the actual cancelled/interrupted result. A terminal state cannot become receiving or completed again. Preserve the last useful byte count when CEF's cancellation snapshot resets it to zero.

Track exact file ownership. Prefer an operation-owned staging location followed by a collision-safe final commit. Never infer that an adjacent `.crdownload` belongs to this operation, delete a pre-existing user file, or overwrite a newly created collision. Native destination replacement requires the user's normal save-panel confirmation. Completed files are never removed by a late cancellation.

Report the actual terminal state and file disposition. Missing terminal callbacks, writer uncertainty and cleanup errors are failures with retained/unknown file ownership, not successful cancellation. A timeout alone does not prove a writer stopped. Keep ownership until a real callback/closure barrier or report the retained staging path for recovery. Private transfer state remains transient and absent from public Library, saved state and app-owned public diagnostics. Preserve the current private Library behavior in this unit; private expiry must still cancel its actual transport.

## Executable acceptance and ownership

One implementation owner changes BrkBase transfer/context vocabulary, domain profile/session/download state and codec adapters, BrkEngine lifetime accounting, BrkCEF/CefKit callback conversion, AppStore disposal ordering, native destination UI and Library cancellation/status. Preserve every identity/focus/private/History fix and all existing native scenarios. Do not change the canonical inventory, plan, audit or inherited evidence.

Before the signed build, test the actual production state transitions and callback ownership: update before decision, cancel before control, two transfers in one browser, one cancelled while another completes, completion/cancel race, duplicate terminal events, old and replacement incarnations, stale/duplicate destination replies, and context revocation before readiness. Assert exact reference releases using controlled callback fixtures, not only dictionary counts.

Native tests use bounded throttled loopback downloads, server-byte observations and actual output receipts. Cover accepted public source close, source-window close, reassignment, profile deletion, last-private-window cancellation followed by a new epoch, immediate quit while already retained, pending-sheet owner closure, destination collision and simultaneous operations in two profiles. Include POST or blob download so URL reconstruction cannot accidentally pass. Cancellation must stop transport and produce the stated file result. Deletion/private tests must exercise revoke-before-drain, not manually cancel first and then close.

Run the complete signed build and native suite after integration. Use the common native lock, this checkout's fresh bundle, a short isolated data root under `/tmp` and only owned processes. Store exact commands, hashes, before/after results and unresolved failures under `efa2358f1f:verify/completion/transfers-integration/`. No original Arc/profile data, PR or publishing. Commit the working implementation and evidence; do not stop after a sketch, callback dispatch or changed ledger label.
