// Contract sketch only. The implementation extends existing PageID and WebEngine.
// Typecheck against the current BrkBase module; no bodies implement product behavior.
import AppKit
import BrkBase
import Foundation

// Caller intent includes the window; callers never select an owner from matching snapshots.
@MainActor func reloadSelection(_ pages: any OwnedPagePort, window: WindowID, tab: ItemID) {
    pages.perform(.reload(ignoringCache: false), on: PageSlot(window: window, tab: tab))
}
@MainActor func showBlankPane(_ pages: any OwnedPagePort, window: WindowID, tab: ItemID, context: BrowsingContext) {
    pages.reconcile([OwnedPageDemand(slot: PageSlot(window: window, tab: tab), initialURL: nil, context: context)])
}

// In production this is the existing PageID with its item-only initializer removed.
struct PageSlot: Hashable, Sendable, Codable {
    let window: WindowID
    let tab: ItemID
}
struct BrowserToken: Hashable, Sendable {
    let slot: PageSlot
    let generation: UInt64
}
struct DocumentToken: Hashable, Sendable {
    let browser: BrowserToken
    let sequence: UInt64
}
enum DocumentAvailability: Hashable, Sendable {
    case loading(DocumentToken)
    case ready(DocumentToken)
    case unavailable
}
struct OwnedPageDemand: Hashable, Sendable {
    let slot: PageSlot
    let initialURL: URL?
    let context: BrowsingContext
}

// Persist only these values for standard windows. Dictionary absence means never selected.
enum SavedSelection: Hashable, Sendable, Codable {
    case empty
    case item(ItemID)
}
struct SavedSlot: Hashable, Sendable, Codable {
    var committedURL: URL?
    var observedTitle: String?
}
// Loaded demand, requested addresses and generation/document tokens stay outside saved state.
struct LiveSlot: Sendable {
    var loaded: Bool
    var requestedURL: URL?
    var browser: BrowserToken?
    var document: DocumentAvailability
}

enum OwnedPageReport: Sendable {
    case created(BrowserToken, BrowsingContext, DocumentAvailability)
    // Reuse the complete current PageEvent vocabulary; do not substitute A's shortened list.
    // The implementation adds a document-availability notification to that event stream.
    case observed(BrowserToken, DocumentAvailability, PageEvent)
}

// Shape of the changed existing WebEngine calls; unchanged diagnostics/shutdown calls stay.
// This protocol is a design check, not a second production engine or compatibility route.
@MainActor protocol OwnedPagePort: AnyObject {
    func reconcile(_ demand: [OwnedPageDemand])
    func surface(for slot: PageSlot) -> NSView?
    func perform(_ action: PageAction, on slot: PageSlot)
    func focus(_ slot: PageSlot?, in window: NSWindow)
}
@MainActor protocol OwnedPageSink: AnyObject {
    func receive(_ report: OwnedPageReport)
    // The engine validates current generation and actual native attachment before key delivery.
    func key(_ key: KeyPress, stage: KeyStage, press: PressID, from browser: BrowserToken) -> Bool
}
