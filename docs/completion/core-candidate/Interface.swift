// Proposed contract only. No prototype code is used by this file.
// swiftc -swift-version 6 -typecheck docs/completion/core-candidate/Interface.swift
import AppKit
import Foundation

// Caller first. These functions are typechecked but never run.
@MainActor func menuFind(_ store: CoreStore, window: WindowID) {
    store.send(.find(.open), from: window)
}
@MainActor func findBarEdited(_ store: CoreStore, window: WindowID, text: String) {
    store.send(.find(.replaceQuery(text, caseSensitive: false)), from: window)
    // Store publishes FindView.searching, then only a matching operation/document result.
}
@MainActor func downloadsCancel(_ store: CoreStore, window: WindowID, id: TransferID) {
    store.send(.cancelTransfer(id), from: window)
    // The row says "Cancelling" until CEF confirms termination and file cleanup finishes.
}
@MainActor func saveMenu(_ store: CoreStore, window: WindowID) {
    store.send(.output(.savePage(.mhtml)), from: window)
    // Native sheet, snapshot, atomic file commit, then OutputResult.saved, or a truthful failure.
}
@MainActor func clearCookiesMenu(_ store: CoreStore, window: WindowID) {
    store.send(.clearAndReload(.cookiesForCurrentHost), from: window)
    // The reducer captures context+document now. Reload happens only after removal completion.
}

// Existing BrkBase.ID<Tag> and existing WindowID/ItemID/ProfileID are reused in implementation.
struct ID<Tag>: Hashable, Sendable { let rawValue: UUID }
enum WindowTag {}; typealias WindowID = ID<WindowTag>
enum TabTag {}; typealias TabID = ID<TabTag>
enum ProfileTag {}; typealias ProfileID = ID<ProfileTag>
enum PrivateTag {}; typealias PrivateSessionID = ID<PrivateTag>
enum OperationTag {}; typealias OperationID = ID<OperationTag>
enum TransferTag {}; typealias TransferID = ID<TransferTag>
enum SelectionTag {}; typealias SelectionID = ID<SelectionTag>

// A realization exists for one tab in one window, including hidden tabs and Peek's scratch tab.
// There is no independently mutable ownerWindow map.
struct PageSlot: Hashable, Sendable { let window: WindowID; let tab: TabID }
struct BrowserToken: Hashable, Sendable { let slot: PageSlot; let generation: UInt64 }
struct DocumentToken: Hashable, Sendable { let browser: BrowserToken; let sequence: UInt64 }
enum Context: Hashable, Sendable {
    case profile(ProfileID)
    case privateSession(PrivateSessionID)
}
// Internal engine context generation distinguishes a deleted/recreated or expired context.
struct ContextToken: Hashable, Sendable { let context: Context; let generation: UInt64 }
struct Origin: Sendable { let scheme: String; let host: String; let port: Int? }

// Doc stores shared logical rows; per-window standard-window URLs are saved by StateCodec.
struct LogicalTab: Sendable { let id: TabID; var launchURL: URL; var pinnedURL: URL?; var customTitle: String? }
struct WindowTabState: Sendable { var currentURL: URL; var observedTitle: String; var loaded: Bool }
struct PageDemand: Sendable {
    let slot: PageSlot
    let context: Context
    let initialURL: URL
    let downloads: DownloadSettings // captured at acceptance, never re-read through TabID
}
struct DownloadSettings: Sendable { let destination: DestinationPolicy }
enum DestinationPolicy: Sendable { case directory(URL); case ask(startingAt: URL) }

// The reducer validates caller targets. Views need no browser tokens, CEF IDs, or native callback handles.
enum CoreCommand: Sendable {
    case select(TabID)
    case find(FindCommand)
    case output(OutputIntent)
    case cancelOutput(OperationID)
    case cancelTransfer(TransferID)
    case clearAndReload(QuickClear)
    case clearData(DataRemoval)
    case cancelClear(OperationID)
}
enum FindCommand: Sendable {
    case open
    case replaceQuery(String, caseSensitive: Bool)
    case next, previous, close
    case useSelection, jumpToSelection
    case replaceSelection(String), replaceAll(String)
}
enum QuickClear: Sendable { case cookiesForCurrentHost, contextHTTPCache }
enum PageAction: Sendable { case navigate(URL), back, forward, reload(ignoringCache: Bool), stop }
enum PageFormat: Sendable { case mhtml }
enum OutputIntent: Sendable { case savePage(PageFormat), pdf(PDFOptions), print }
struct PDFOptions: Sendable { let landscape: Bool; let backgrounds: Bool }

// Engine inputs are already addressed. Replaying the same OperationID returns its prior state.
struct FindRequest: Sendable { let id: OperationID; let action: FindAction }
enum FindAction: Sendable {
    case query(DocumentToken, text: String, caseSensitive: Bool)
    case step(SearchToken, Direction)
    case stop(SearchToken)
    case useSelection(DocumentToken)
    case jump(SelectionToken)
    case replace(EditableSelection, String)
    case replaceAll(EditableSelection, query: String, replacement: String)
}
struct SelectionToken: Sendable { let document: DocumentToken; let selection: SelectionID }
struct SearchToken: Hashable, Sendable { let operation: OperationID; let document: DocumentToken }
enum Direction: Sendable { case next, previous }
// Only the renderer adapter can create this after checking focused frame/element/document.
struct EditableSelection: Sendable {
    let document: DocumentToken
    let selection: SelectionID
    let kind: EditableKind
    fileprivate init(document: DocumentToken, selection: SelectionID, kind: EditableKind) {
        self.document = document; self.selection = selection; self.kind = kind
    }
}
enum EditableKind: Sendable { case textInput, textArea, contentEditable }
enum FindUpdate: Sendable {
    case pending(SearchToken)
    case matches(SearchToken, count: Int, ordinal: Int?, final: Bool)
    case selection(OperationID, text: String, token: SelectionToken)
    case replaced(OperationID, DocumentToken, count: Int)
    case stopped(OperationID)
    case failed(OperationID, Failure)
}
struct FindView: Sendable { var query: String; var result: FindPresentation }
enum FindPresentation: Sendable { case searching; case matches(count: Int, ordinal: Int?); case failure(Failure); case closed }

// One transfer is independent of the live page-event stream and contains immutable acceptance provenance.
struct TransferOrigin: Sendable {
    let browser: BrowserToken
    let context: ContextToken
    let settings: DownloadSettings
    let url: URL
    let suggestedName: String
}
enum TransferState: Sendable {
    case awaitingDestination
    case receiving(received: Int64, total: Int64?)
    case cancelling(received: Int64)
    case terminal(TransferEnd)
}
enum TransferEnd: Sendable {
    case completed(FileReceipt)
    case cancelled(CancelCause, PartialFileDisposition)
    case interrupted(reason: String, PartialFileDisposition)
    case failed(Failure)
}
enum CancelCause: Sendable { case user, sourceClosedBeforeDecision, ownerWindowClosedBeforeDecision, profileDeleted, privateSessionEnded, applicationQuit }
enum PartialFileDisposition: Sendable { case absent; case removed; case retained(URL, error: String) }
struct FileReceipt: Sendable { let url: URL; let bytes: Int64 }
struct TransferUpdate: Sendable { let id: TransferID; let origin: TransferOrigin; let sequence: UInt64; let state: TransferState }

// Destination is resolved by native UI under the initiating window. It is never a CEF window.
enum NativeOperation: Hashable, Sendable { case transfer(TransferID), output(OperationID) }
struct DestinationPrompt: Sendable {
    let operation: NativeOperation
    let window: WindowID
    let suggestedName: String
    let directory: URL
}
enum DestinationAnswer: Sendable { case accepted(URL), cancelled, ownerGone }
struct PrintPrompt: Sendable { let operation: OperationID; let window: WindowID; let pdf: URL }
enum PrintAnswer: Sendable { case submitted, cancelled, failed(String), ownerGone }
struct OutputRequest: Sendable { let id: OperationID; let document: DocumentToken; let intent: OutputIntent }
enum OutputUpdate: Sendable {
    case choosingDestination(OperationID)
    case rendering(OperationID)
    case presentingPrintPanel(OperationID)
    case finished(OperationID, OutputResult)
}
enum OutputResult: Sendable {
    case saved(FileReceipt)
    case submittedToPrintSystem // never claims physical paper printed
    case cancelled
    case failed(Failure)
}

// Data removal is distinct from disposal. Unsupported combinations fail before any deletion.
struct DataRemoval: Sendable {
    let context: ContextToken
    let scope: DataScope
    let classes: Set<DataClass>
}
enum DataScope: Sendable { case entireContext; case host(String); case origin(Origin) }
enum DataClass: Hashable, Sendable { case cookies, httpCache, history, localStorage, indexedDB, serviceWorkers, cacheStorage, passwords }
struct ClearRequest: Sendable {
    let id: OperationID
    let removal: DataRemoval
    let reloadIfUnchanged: DocumentToken?
}
enum ClearResult: Sendable {
    case complete(OperationID, removed: Set<DataClass>)
    case unsupported(OperationID, combinations: [String])
    case partial(OperationID, removed: Set<DataClass>, failed: [String])
    case cancelledBeforeStart(OperationID)
}
enum CancelDisposition: Sendable { case accepted, tooLate, unknownOperation }
enum Disposal: Sendable { case deleteProfile(ProfileID); case endPrivateSession(PrivateSessionID) }
enum DisposalResult: Sendable { case completed; case draining; case failed(Failure) }
enum Failure: Sendable {
    case staleDocument, ownerGone, unsupported(String), engineUnavailable
    case native(String), timeout(String), outputCleanupFailed(URL)
}

// BrkEngine owns this typed port; raw CEF wire values exist only in BrkCEF/CefKit.
@MainActor protocol BrowserOperations: AnyObject {
    var sink: (any BrowserEventSink)? { get set }
    func reconcile(_ demand: [PageDemand])
    func surface(for slot: PageSlot) -> NSView?
    func focus(_ slot: PageSlot?, in window: NSWindow)
    func perform(_ action: PageAction, on slot: PageSlot)
    func find(_ request: FindRequest)
    func output(_ request: OutputRequest)
    func cancelOutput(_ id: OperationID)
    func cancelTransfer(_ id: TransferID, cause: CancelCause)
    func clear(_ request: ClearRequest)
    func cancelClear(_ id: OperationID) -> CancelDisposition
    func dispose(_ request: Disposal) async -> DisposalResult
    func shutdown() async -> ShutdownResult
}
enum ShutdownResult: Sendable { case clean; case timedOut(unclosed: [BrowserToken], incomplete: [OperationID]) }
@MainActor protocol BrowserEventSink: AnyObject {
    func page(_ event: PageObservation, from document: DocumentToken)
    func find(_ event: FindUpdate)
    func transfer(_ event: TransferUpdate)
    func output(_ event: OutputUpdate)
    func cleared(_ result: ClearResult)
    // Input origin is the slot's stable owner. Native key events additionally validate the attached NSWindow.
    func key(_ key: NativeKey, from browser: BrowserToken) -> Bool
    func print(_ prompt: PrintPrompt, answer: @escaping @MainActor (PrintAnswer) -> Void)
    func dismissNativeUI(_ operation: NativeOperation)
    func destination(_ prompt: DestinationPrompt, answer: @escaping @MainActor (DestinationAnswer) -> Void)
}
enum PageObservation: Sendable { case documentBegan(URL), title(String), open(URL, foreground: Bool), closed }
struct NativeKey: Sendable { let keyCode: UInt16; let modifiers: UInt64; let press: UInt64; let stage: KeyStage }
enum KeyStage: Sendable { case beforePage, afterPage }

// Implementation skeletons. These bodies deliberately cannot be mistaken for working behavior.
@MainActor final class CoreStore {
    func send(_ command: CoreCommand, from window: WindowID) { fatalError("not implemented") }
    func receive(_ event: FindUpdate) { fatalError("not implemented") }
    func receive(_ event: TransferUpdate) { fatalError("not implemented") }
}
@MainActor final class NativeDestinations {
    func present(_ prompt: DestinationPrompt, answer: @escaping @MainActor (DestinationAnswer) -> Void) { fatalError("not implemented") }
    func dismiss(_ id: NativeOperation) { fatalError("not implemented") }
}

// BrkCEF private storage shape. Do not export either record from the actual adapter module.
private enum BrowserLife {
    case presented
    case retainedForTransfers(Set<TransferID>)
    case closing
}
private struct BrowserRecord {
    let token: BrowserToken
    let context: ContextToken
    var documentSequence: UInt64
    var document: DocumentToken { DocumentToken(browser: token, sequence: documentSequence) }
    var life: BrowserLife
    // Own ChromePage, its stable surface, callback bridge, and document operations here.
}
private struct TransferRecord {
    let id: TransferID
    let origin: TransferOrigin
    var state: TransferState
    // Own retained CEF decision/update callbacks and destination reservation here.
    // Register on FIRST update or decision; before-download is not guaranteed first.
}
