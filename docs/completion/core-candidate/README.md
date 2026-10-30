# Window-owned pages and retained transfers

Start with the caller. A menu sends `store.send(.find(.open), from: window)`. The find bar sends query changes through the same store. A Downloads row sends `cancelTransfer(id)` and remains visibly cancelling until the engine confirms the transfer ended. Save Page sends one intent and receives either a completed local file, cancellation, or an error. Callers never choose a CEF browser ID or retain a native callback.

[Interface.swift](Interface.swift) starts with compilable menu and view call sites, followed by the derived types and signatures. Bodies are explicitly unimplemented. [Ownership.md](Ownership.md) defines the semantics, [Migration.md](Migration.md) assigns implementation units, [the ownership diagram](ownership.html) shows the recommended shape, and [the evidence report](../../../verify/completion/core-candidate/REPORT.md) separates measurements from remaining questions. Prototype changes are confined to the reproducible probe package and are not proposed implementation.

## Problem

Two standard windows can select one shared tab, but today's `PageID(ItemID)` produces only one NSView. Download events require that same page to remain live even though the file operation has a different lifetime. New find and output operations also need to identify a document that can change without replacing its browser. The existing focus, scratch-container privacy, profile readiness, incarnation rejection, and ordered shutdown repairs remain constraints.

## Usage and shape

Use a `PageSlot(window, tab)` for each window's live realization of a shared logical row. `BrowserToken(slot, generation)` identifies one immutable-context browser; `DocumentToken(browser, sequence)` identifies one committed document. Each identity exists because its lifetime differs. A native NSWindow remains an adapter-owned weak reference, not persisted domain state.

The reducer owns shared tabs and window-specific navigation state. Projection derives page demand. The engine owns one browser record per incarnation and one transfer record per accepted download. A transfer retains its initiating browser when presentation demand disappears; ordinary page events remain rejected. Profiles and private sessions are never re-derived from a later tab location.

`BrowserOperations` hides CEF references, request-context readiness, native command resolution, find correlation, file staging, and shutdown ordering. Callers supply one typed operation rather than coordinating its stages. Native destination and print adapters answer through one-shot operation callbacks. Their windows are selected from the initiating `WindowID`. This follows boundary-discipline, separate-before-serializing-shared-state, and minimize-reader-load without adding a general-purpose job framework.

## Synthesis decision

This is one independent candidate. The parent selects the base and records synthesis. No other candidate or private rubric informed this design.

## Tradeoffs accepted

- We accept a browser per loaded window/tab pair in exchange for two simultaneously usable windows with independent back stacks and form state. Shared cookies still follow the profile.
- We accept keeping an initiating browser alive during a public download in exchange for completing the original transfer with its original request and context.
- We accept explicit private-expiry and profile-deletion cancellation in exchange for bounded context lifetime.
- We accept MHTML as the initial offline-page format. Full HTML-with-assets export remains a separate format implementation, not a renamed link export.

## Alternative whole shape

An exclusive-host design retains today's one browser per tab. A pure host-allocation table assigns each visible page to the last explicitly activated claimant. Other claimants render a named “Open in this window” placeholder or a noninteractive snapshot. Activation transfers the view, releases the previous window's focus intent, reattaches, then restores input only if that window has no native editor. Browser-origin events route through the allocation record; hidden scratch pages retain their container owner.

This alternative hides browser creation and preserves one back stack, DOM, and audio stream. It exposes ownership transfer to every content card, split, Peek, and activation path. More importantly, it cannot provide two simultaneously usable interactive views. It is viable only if the product explicitly accepts exclusive interactive ownership. No authenticated Arc reference establishes that policy. The recommended shape satisfies simultaneous usability directly and removes the attachment arbitration rule entirely.

A transfer-only worker browser is a different operations design. It would reconstruct requests in a separate browser or URLSession task. That loses unrecorded POST bodies, blob URLs, authentication state, request headers, and service-worker behavior. No supported download handoff was established. Callback-only retention was measured and failed to preserve the transfer after source destruction. Explicit source-close cancellation is viable and cheaper, but gives a less useful public-download behavior than the proven retained-browser path.

## Risks and next step

The native evidence report lists the remaining print, selection/editing, data-scope, and lifetime tests. None is converted into a support promise by the type sketch. Start implementation with the window/tab page key and its native same-tab acceptance test, then introduce transfers as a separate event stream.
