# Implement in ownership order

The final candidate changes interfaces, not the settled Swift/AppKit/CEF architecture. The committed prototype is diagnostic code. Do not merge its env switches, `::coreProbe` command hook, raw logs, global callback dictionaries, or early-returnViews retention into the app.

## Unit 1: make page demand belong to a window

One owner changes `BrkBase/Page.swift`, `BrkEngine/{WebEngine,PageLedger,StubEngine}.swift`, `BrkDomain/{Model,Project,Snapshot,Codec,Normalize,Command,Effect}.swift`, and the page-related rules. Replace `PageID(ItemID)` with a window/tab slot in every demand, action, focus target, and observation path. Add browser and document tokens only where callbacks or pending operations need them. Move live page reports and selected split pane from shared/session-global state to window slots. Keep tree membership and shared item labels in their existing owner.

Migrate `Rules/{Tabs,Split,Peek,Windows,Queries,Shared,Archive,Profiles}.swift` together. Delete the global `Session.loaded`/`live` page-key assumptions, rather than retaining a second projection alongside the new one. Persist window-local standard-page URLs through `StateCodec` v3. Restore v2 selected tabs once per owning standard window; deduplicate invalid entries and exclude scratch/private state. `StateFile` keeps its bytes-only contract.

Prove with reducer tests for same-tab dual selection, independent navigation and title observations, per-window split focus, shared logical closure, local window closure, archive exclusion, private hidden opener, profile replacement, and v2 migration. The StubEngine must emit old-document and old-incarnation observations on demand so stale rejection is observable. Require one native test with both windows interactively using the same logical tab after integration. The candidate's two-browser feasibility probe is evidence about CEF capacity, not proof of that future reducer migration.

## Unit 2: attach and route by actual owner

One owner changes `BrkApp/{AppStore,KeyRouter,WindowController,LittleWindowController}.swift`, `BrkContent/{ContentAreaView,WindowRootView}.swift`, `BrkCEF/{CEFEngine,ChromePage,EmbeddedSurface,HostWindows}.swift`, and the control-protocol page addressing.

Delete `AppStore.window(showing:)`, the KeyRouter first-claimant routing, and the sorted-standard-window fallback for a known browser opener. Use the slot's window identity, with native attachment validation for physical keyboard events. A scratch owner remains valid while hidden. Controllers render only their own slot surfaces. Preserve weak per-window focus, readiness replay, native-editor protection, generation-aware close handling, borrowed-view restoration, and never-key CEF hosts.

Prove with the existing NativeFocusLifecycle tests plus native same-tab typing, switching activation, Cmd+L, split selection, Peek overlay focus, source-window closure, and reload with another window's editor active. Preserve N1/N2, W2-4, W2-P1/P1C/P2/P2C, and profile isolation. A passing dictionary assertion cannot replace actual NSView attachment and responder facts.

## Unit 3: make transfers independent of live-page observations

One owner changes `BrkBase` transfer vocabulary, `BrkEngine` operation protocol, `BrkCEF/Transfers.swift` plus browser/context lifetime integration, CefKit's download bridge, `BrkDomain/Rules/Library.swift`, download persistence, and Downloads UI state. Establish this owner after Unit 2 lands so both workers do not edit engine ownership concurrently.

Delete `PageEvent.download`, `ChromePage.destinations`, page-addressed `decideDownload`, fallback-to-default policy lookup in KeyRouter, and ledger-only `cancelDownload`. Replace the test that permits cancelled-to-finished with an explicit completion-versus-cancel race test. `DownloadFiles.reserved` becomes private transfer-owned destination allocation; NativeDestinations owns only panel presentation. CEF item snapshots retain validity, in-progress, cancelled, complete, interrupted, and interruption reason separately.

The engine owns browser records through presented, retained-for-transfers, and closing states. No hidden second browser map can bypass shutdown. Context disposal includes retained records, pending decisions, and context-loader readiness callbacks. Browser records protect page observations; transfer records accept legitimate updates independently. No weakening of existing stale-page guards is needed.

Prove actual server byte cessation and file results for cancel, complete, source close, cancel after presentation close, profile reassignment, profile deletion, private expiry, duplicate filename, pending-panel cancellation/reentrancy, interruption, and immediate quit. Test two transfers in one browser, two profiles at one URL, retired/recreated slots, terminal duplicates, and late completed events. Persistent output includes original profile, not the tab's current profile. Private output never enters `StateCodec`.

## Unit 4: document operations and native sheets

One owner changes CefKit's find/print/DevTools adapter and `BrkCEF/DocumentOperations.swift`; a native-UI owner then consumes the frozen interfaces in `BrkApp/NativeDestinations.swift`, `BrkApp/NativePrinting.swift`, `BrkOverlays/FindBar.swift`, `BrkContent/WindowRootView.swift`, and `BrkDomain/Rules/Find.swift`.

Remove the wrapper that always sends `findNext = 0`. Add the find handler and main-frame document identity before enabling menu actions. Replace every `.later(.findInPage)` only as its implemented action becomes usable; do not count open/next as completion of selection or replace. Keep CEF IDs, command names/numbers, CDP JSON, frame IDs, and borrowed C callbacks inside the adapter. A native-UI answer carries the original operation and owner, never a fresh lookup of the current page.

Save, PDF, and Print use native operation states and completed file/print outcomes. Delete disabled save/print action cases only when native destination, cancellation, failure, and teardown are implemented. Keep `ShareExport` separate because it exports link records; repair its ignored write errors in its own unit. Resolve Chrome command IDs through `cef_id_for_command_id_name` if retained for diagnostics, never numeric literals.

Prove search first/next/previous/count/close, rapid query replacement, same-browser navigation before replies, cancellation, renderer death, native bar focus, and split/Peek targeting. Add focused-frame selection/replace tests for input, textarea, contenteditable, iframe, read-only and password exclusions, DOM mutation, IME, and undo. For output, assert PDF parse/page count, MHTML reopening with the origin unavailable, source/window close, unwritable output, duplicate cancellation, and print-sheet cancel/submit callbacks. Printing tests must say whether they submitted to an OS queue or only opened a panel.

## Unit 5: clear data without deleting profiles

One owner changes `BrkBase` scoped-removal types, `BrkCEF/BrowsingData.swift`, domain settings/actions, and the native confirmation/result UI. Rename the remaining profile-removal effect and `WebEngine.forget` to explicit disposal; do not reintroduce them into History clear. Keep the existing profile-deletion marker and last-private-window semantics behind the disposal barrier.

Implement whole-context cookies/cache and Brk history first. Enable host-cookie clearing only after matching host/domain/path cookies are verified. Unsupported scopes/classes fail before mutation. Later origin-storage support stays in A095 until it has origin/profile and restart evidence. Add a completion barrier and document check before reload.

Prove two profiles and two origins at the same time, domain cookies, cache request counters, preservation of localStorage on cookie/cache-only clearing, same-browser navigation before completion, profile deletion during a clear, partial native failure, and cancellation before deletion begins. Preserve C-HISTORY through real restart. No data-removal success is inferred from releasing a request-context pointer.

## Later dependencies remain in scope

Extensions and site permissions consume immutable context and actual owner-window provenance, with their own prompt registries and CEF feasibility checks. Capture, PiP, Cast, and media use document/browser identity and explicit auxiliary-window teardown. Notes and Easels need their own document model while sharing native output UI where useful. Boosts and AI read page content only through a document-scoped permission boundary. Advanced tab/space tools inherit the shared-row versus per-window-state rule. Imports and local-folder sync use StateCodec's saved state contract, excluding native operations, runtime IDs, credentials, and private sessions. This batch does not supply those features or create a generic service to predict them.

## Red-flag review

| Flag | Resolution and remaining cost |
|---|---|
| Shallow module | One operation call owns its callback lifetime, staging, cancellation, and terminal outcome. Native views send intent and render state. The port still has separate families because they have different result/cancellation semantics. |
| Information leakage | Wire IDs, pointers, CDP payloads, file reservations, and Chromium window classes stay in BrkCEF/CefKit. AppKit references remain native-adapter-only. |
| Temporal decomposition | Transfer acceptance, progress, cancellation, and close all belong to the transfer record; no begin/update/finish services with duplicate ownership. |
| Pass-through methods | Existing reducer/effect dispatch remains a policy boundary. Do not add a second forwarding manager between AppStore and the engine. |
| Split ownership | Shared rows, per-window navigation, engine resources, and native sheets each have one writer. The persistent transfer row is an observed result, not a second control owner. |
| Two ways to do one task | Old page download events and old ID-based routing are deleted in the same unit as migration. No legacy compatibility engine is kept. |
| Importable internals | Put CEF adapter records in the BrkCEF target with internal/private visibility. Existing ArchitectureTests reject CefKit imports elsewhere. |
| Hand-synced lists | `ActionID` remains the menu/command-bar source. No second operation inventory is introduced. The parent alone updates canonical completion rows from accepted evidence. |

The interface sketch typechecks and its caller examples match its signatures. It does not establish behavior. Integration must pass the named reducer tests, signed build, and real CEF acceptance before the parent promotes any canonical inventory row.
