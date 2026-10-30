// Boundary sketch. Extend existing WebEngine/DownloadID/BrowsingContext in production.
import BrkBase
import Foundation

struct PrivateSessionID: Hashable, Sendable { let raw: UUID }
enum ScopedContext: Hashable, Sendable {
    case profile(ProfileID)
    case incognito(PrivateSessionID)
}
struct ContextEpoch: Hashable, Sendable { let context: ScopedContext; let generation: UInt64 }
enum DownloadPolicy: Sendable { case directory(URL), ask(startingAt: URL) }
struct DownloadOwner: Sendable {
    let browser: BrowserToken
    let context: ContextEpoch
    let policy: DownloadPolicy
    var window: WindowID { browser.page.window }
}
struct DownloadDetails: Sendable { let url: URL; let suggestedName: String }
struct TransferProgress: Sendable { let received: Int64; let total: Int64? }
struct FileReceipt: Sendable { let url: URL; let bytes: Int64 }
enum PartialFile: Sendable { case absent, removed, retained(URL, reason: String), unknown }
enum DownloadEnd: Sendable {
    case completed(FileReceipt)
    case cancelled(PartialFile)
    case interrupted(reason: String, PartialFile)
    case failed(reason: String, PartialFile)
}
enum DownloadStage: Sendable {
    case choosingDestination
    case receiving(TransferProgress)
    case cancelling(TransferProgress)
    case terminal(DownloadEnd)
}
struct DownloadUpdate: Sendable {
    let id: DownloadID
    let owner: DownloadOwner
    let details: DownloadDetails
    let revision: UInt64
    let stage: DownloadStage
}
struct DestinationTicket: Hashable, Sendable { let download: DownloadID; let generation: UInt64 }
struct DownloadDestinationPrompt: Sendable {
    let ticket: DestinationTicket
    let window: WindowID
    let directory: URL
    let suggestedName: String
}
enum DestinationAnswer: Sendable { case accepted(URL), cancelled, ownerGone }
struct DisposalID: Hashable, Sendable { let raw: UUID }
struct ContextDisposal: Sendable { let id: DisposalID; let context: ScopedContext }
enum DataDisposition: Sendable { case memoryReleased, deletionScheduledForNextLaunch }
enum ContextDisposalResult: Sendable {
    case completed(DisposalID, ScopedContext, DataDisposition)
    case failed(DisposalID, ScopedContext, reason: String)
}

@MainActor protocol TransferEnginePort: AnyObject {
    func cancelDownload(_ id: DownloadID)
    // Revocation is synchronous; only the final cleanup result is asynchronous.
    func disposeContext(_ request: ContextDisposal)
}
@MainActor protocol TransferEventSink: AnyObject {
    func download(_ update: DownloadUpdate)
    func destination(_ prompt: DownloadDestinationPrompt, reply: @escaping @MainActor (DestinationAnswer) -> Void)
    func dismissDestination(_ ticket: DestinationTicket)
    func contextDisposed(_ result: ContextDisposalResult)
}

@MainActor func libraryCancel(_ engine: any TransferEnginePort, id: DownloadID) {
    engine.cancelDownload(id)
}
@MainActor func revokeBeforeReconcile(_ engine: any TransferEnginePort, request: ContextDisposal) {
    engine.disposeContext(request)
}
