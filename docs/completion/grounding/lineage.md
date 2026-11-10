# Ownership decisions and constraints for the core designs

## The question

Why do logical pages, native views, window routing, downloads, and request contexts have their current ownership, and which decisions constrain the next interfaces?

## The code in question

The current source is `ddc2854c4f57e8c3ed18ca4e8fe18cf5d0199b3b`. Core page/engine contracts remain unchanged from grounding commit `6d2d6d5`; `ddc2854` separates History removal from profile disposal. File citations below are repository-relative. Commit citations refer to local git objects, available through `git show <hash>`.

## What we found

- **Direct. Stable views were deliberate.** Landing commit `b8b808a` defines `PageID` as the tab's live form and promises one stable NSView per page lifetime, movable between windows. This predates the focus repairs. The recorded selection rationale prefers fewer lifecycle decisions through complete page demand, engine reconciliation, stable views, and pure geometry. It does not justify simultaneous claims from two windows. Sources: `Sources/BrkBase/Page.swift:8`, `Sources/BrkEngine/WebEngine.swift:29`, `docs/design/swift/rationale.md:275`.
- **Direct. Window lookup intentionally derives from snapshots.** `KeyRouter` explicitly avoids a second map and states that a shown page determines its window. `3d6f4d6` extended lookup to Peek. Later `2fe891e` rejects visibility as a private-context selector: hidden scratch openers route through their owning window, and private modifier links cannot promote into persistent Little Brk. Sources: `Sources/BrkApp/KeyRouter.swift:23`, `Sources/BrkApp/AppStore.swift:98`, `Sources/BrkDomain/Rules/Tabs.swift:170`.
- **Direct implementation history, unknown product intent.** Wave-2 commit `bb62819` expresses downloads as `PageEvent.download` and page-addressed settings decisions. `e26d5d4` adds destination reservations and launch/browser/download identity. The limitation is explicit: CefKit discards cancellation callbacks. No inspected rationale says whether a transfer should end with its source tab. Sources: `docs/design/swift/wave2.md:9`, `Sources/BrkCEF/ChromePage.swift:151`, `Vendor/CefSwift/Sources/CefKit/BrowserClient.swift:333`.
- **Direct. Context replacement and readiness repair concrete failures.** `82821ae` replaces a browser when its context changes. The source comment states that Chromium binds a browser to its context for life. `fa8f496` records browser ID -1 and absent `OnBeforeClose` when creation preceded context initialization; readiness now gates creation and replays current demand. Sources: local commit messages, `Sources/BrkCEF/CEFEngine.swift:105`, `Sources/BrkCEF/CEFProfiles.swift:91`.
- **Direct. Focus and teardown rules are corrective requirements.** `a943c22` adds generation-aware closure. `b9ec646` restores borrowed views before closing browsers after repeated quit crashes. `b1d919a` closes surviving auxiliary widgets before CEF shutdown after an observer assertion and AppKit crash. `6a4ef2d` replaces global focus memory with weak per-window requests, protects editors and moved views, and removes window activation from focus repair. Sources: `Sources/BrkEngine/PageLedger.swift`, `Sources/BrkCEF/EmbeddedSurface.swift:86`, `Sources/BrkCEF/CEFEngine.swift:148`, `b1d919a4de:verify/swift/f5-resume/REPORT.md`.
- **Direct. History clearing is now history-only.** `ddc2854` removes profile disposal and changes the label. Before/after evidence demonstrates the custom-profile localStorage regression. This establishes no scoped data-clear API. Source: `ae96ea121a:verify/completion/history-safety/REPORT.md`.

## What we can reasonably infer

**Inferred.** Given stable global page demand and snapshot-derived routing, the design appears to assume one relevant native claimant per page. Avoiding duplicate bookkeeping is consistent with the KeyRouter comment. No inspected source establishes a multi-window ownership rule or a performance rationale.

## Competing hypotheses

A stable view could support intentional exclusive-host transfer, or represent an unfinished multi-window contract. Page-owned download events could reflect intended source-bound transfers, or the first available callback vocabulary. The historical record does not select either interpretation. The AppKit/StubEngine probe establishes conflicting current claims, not authenticated Arc behavior or a real-CEF policy. Source: `a3966b7375:verify/completion/native-grounding/probe-output.txt`.

## Constraints for both candidates

| Constraint | Required consequence |
| --- | --- |
| Preserve | Generation rejection, immutable context per browser, readiness replay, per-window focus without activation, native-editor protection, scratch-owner routing, private metadata omission, and ordered view/browser/widget/runtime teardown. |
| Change | Make hosting and actual event origin explicit. Freeze initiating context and operation ownership instead of re-deriving them from a tab's later profile or visibility. Correlate document-sensitive results across navigation. |
| Avoid | Weakening page guards to admit downloads, ledger-only cancellation, focus repair that activates windows, disposal masquerading as data clearing, or assuming raw Chrome UI works in the reparented host. |
| Risk | Private Chromium view/widget names, save-panel reentrancy, early download updates, callback retention after close, and new auxiliary windows. Probe the pinned runtime before freezing APIs. |

## What we don't know

Transfer survival and retained-control usability after source destruction, last private-window close, or context release remain runtime unknowns. Actual same-tab Arc behavior and authenticated visual references remain unavailable. Historical intent cannot settle those choices. No manager, registry, or page-instance strategy is selected here.

## Sources consulted

Git history, comments, local design documents, completion grounding, canonical audit, and local failure artifacts were searched. `ae96ea121a:verify/completion/lineage/source.md` records the detailed history pass. GitHub issue/PR access returned 404/422, so discussions were unavailable, not empty; see `ae96ea121a:verify/completion/lineage/issues.md`. T3 parent handoff, user decisions, and canonical audit are the supplied conversation record. Tool discovery identified no relevant external real-time team chat, deployed observability, exception tracking, or analytics tool for this local project. Those external sources were not searched or verified empty. Runtime failure evidence used here is repository-local.

## Confidence summary

Recorded contracts and corrective motivations have direct evidence. The unique-claimant premise is inferred. Multi-window product semantics and operation survival remain open design and runtime questions.
