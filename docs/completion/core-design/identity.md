# Window-owned page implementation contract

This freezes A Units 1 and 2 after review C1. Deliver one integrated change that makes a single logical tab usable in two standard windows, routes each page's input to its owner, and restores each window's committed address. No destination, download-control, find, printing or data-clear implementation is included in this unit. Their existing behavior and known limitations remain visible in the inventory.

## Identity and ownership

Extend the existing `PageID` to contain a `WindowID` and an `ItemID`. The design's `PageSlot` means this composite PageID; do not keep a parallel ID or the old item-only initializer. Migrate every production, test, diagnostic and control-protocol caller. Use unambiguous composite Codable/coding-key encoding that round-trips every accepted underlying ID, and reject malformed live-control IDs. Persistence migration belongs in `StateCodec`, not a fallback that guesses an owner window.

The reducer owns window-specific loaded demand and live observations. Projection creates at most one page demand for each window/tab pair, including hidden pages. The engine owns one browser per demanded pair and an increasing incarnation generation. A browser's context and slot owner never change. Profile reassignment replaces the browser while retaining the logical slot. All page observations, shortcuts and open requests carry that origin; delete first-claimant and sorted-claimant window lookup.

Keep all existing PageAction and PageEvent behavior: navigation, reload/stop, zoom, DevTools, renderer recovery, loading/back/forward, favicon, focus, popup/navigation and current download events. This unit changes their addressing, not their feature coverage. Hidden scratch openers retain their container/window owner. Only physical page input requires a live visible surface actually attached to that owner's native window. Do not apply that visibility condition to background popups.

## Browser and document observations

Use the engine's existing incarnation generation as the one authoritative browser generation; move its vocabulary to BrkBase if domain-facing callbacks need it. Announce a new browser token before its observations. The reducer accepts it only for a currently demanded slot and rejects superseded generations. Native callbacks must also pass the engine's existing live-incarnation check.

Expose document availability with the browser observation stream, so future callers can obtain a document token without querying native handles. A main-frame cross-document load starts a fresh sequence and makes it loading; a same-document fragment/history update keeps the sequence. The ready notification makes the token usable. Renderer loss makes it unavailable. Tokens from before a failed or replaced navigation are never resurrected by guessing from a URL. A failure without a confirmed usable document leaves document operations unavailable; the page can still reload/recover. A newly created blank browser has an explicit initial document state. An empty pane with nil URL has no browser and no document token.

The first implementation can add a document-state observation to the existing PageEvent vocabulary. Preserve the single event stream and all existing events rather than copying the candidate's shortened enum. Add adapter hooks for main-frame lifecycle where existing callbacks lack that distinction. Find/output interfaces remain unfrozen; this unit only establishes truthful identity and availability.

## Empty panes and selection

Logical seeds, saved slot URLs and initial page demand permit nil. Nil means an empty tab/split pane that waits for input, and must not create a browser. Native content and command-bar behavior for blank panes remains functional.

Represent an explicit empty selection separately from a space that has never had a selection. Normalize must preserve the explicit empty state. A page-initiated close unloads only its originating global slot and selects another eligible row in that window, or explicitly selects nothing. It does not delete a shared row or recreate the closed slot during the same normalization. Explicitly selecting that row later creates a new incarnation. Closing a scratch page follows its existing single-window close policy and never archives private content.

User Today Close/Archive still removes the shared logical row and its realizations. Pinned Close and Keep retains the row and unloads its realizations, preserving the existing shared close policy. Closing a native window removes only that window's page demand. Split membership, orientation and proportions remain shared; focused pane becomes window-specific. A repeated same-tab selection must remain usable without depending on a changed revision or another window surrendering its view.

## Address, title and restoration rules

Each standard window stores the last committed document URL for its slots. Loaded state, provisional/requested navigation, browser/document generations, native hosts and callbacks stay transient. Titles observed by one slot affect only that window's projection; user-defined titles remain shared. Preserve an explicit saved nil URL rather than replacing it with a shared requested address during restoration.

Keep user navigation intent separate from the committed restoration URL. The engine may load a newly requested address, but a failed/uncommitted navigation or attachment response must not become an automatic recreation seed. On profile reassignment or restart, use the slot's last committed document, or remain blank. Never automatically replay a known download response. Add a throttled-download request-count regression around reassignment/restoration. No transfer-lifetime promise is added here.

The shared row keeps a safe committed fallback seed for a first explicit selection in a new window; it never navigates other live slots. When its last slot is retired, preserve that slot's last committed address as the fallback. A row with no committed address has a nil seed. Keep a pinned home/reset address distinct from current navigation. An explicit Open In/new-window command passes its source address rather than guessing the shared seed.

Every window-targeted Copy URL, Markdown/quote copy, duplicate, archive, Open In, pin/reset and local export resolves addresses through one domain helper: use that initiating window's committed/current visible slot as the action requires, then the safe shared seed. Navigation-intent display can show a requested URL, but archive/export/restoration never manufacture a committed document from it. A global/background action with no initiating window chooses the safe shared seed, then the first valid saved standard-window slot in sorted WindowID order. If no URL exists, the action follows the existing empty-tab behavior. The helper must be explicit about whether it needs the visible address or a safe saved document.

Archive takes its initiating window's committed URL and observed title before removing the shared row. Restore seeds the new row and restoring window from that archive record. Container archive reconstruction remains a separate unfinished feature. File export traverses the requested shared structure but resolves each tab through the initiating window and deterministic fallback. It does not serialize browser tokens or private state.

`StateCodec` v3 saves standard-window slot URLs and split focus, with explicit empty selection. Read v1 and v2 through their existing repair rules, then seed each restored selected slot from its old tab address and split focus. Remove references to missing windows/items or foreign scratch containers. Nonselected rows remain lazy; saved URLs do not imply loaded demand. Continue to exclude incognito, Peek, Little Brk scratch data and operation tokens from persistence.

## Native boundaries and acceptance

Each card requests only its window's composite page. Keep per-window weak focus requests, native-editor precedence, context readiness, PageLedger rejection, never-key CEF hosts and ordered view/browser/widget/runtime teardown. Do not copy either probe's browser-parking or retained-transfer implementation. Existing downloads remain on their current channel until the next unit replaces that channel.

Before integration, demonstrate the same logical tab in two native windows with distinct browser IDs and attached views. Type different values, navigate to different documents, switch activation, and invoke Cmd+L from each; the other window's document, editor and overlay must remain unchanged. Restart and recover each window's URL. Cover blank/new split panes, per-window split focus, Peek, local page-initiated close without immediate recreation, global archive/restore, profile reassignment and hidden private popups. Check composite ID round-trips and v1/v2/v3 restore fixtures.

Run the signed build and all existing native scenarios, including N1/N2, W2-4, profile/private routing, immediate-download quit and C-HISTORY. Add real assertions for the new behavior rather than changing the old defect reproduction to a nominal PASS. No feature row is promoted solely because this contract or its sketch typechecks.
