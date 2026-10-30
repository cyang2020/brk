import Foundation

public enum PrivateSessionTag {}
public enum DisposalTag {}
public typealias PrivateSessionID = ID<PrivateSessionTag>
public typealias DisposalID = ID<DisposalTag>

public struct ContextEpoch: Hashable, Sendable, Codable {
    public let context: BrowsingContext
    public let generation: UInt64
    public init(context: BrowsingContext, generation: UInt64) { self.context = context; self.generation = generation }
}

public enum DownloadPolicy: Hashable, Sendable, Codable {
    case directory(URL)
    case ask(startingAt: URL)
    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
    }
    public static var `default`: Self { .directory(defaultDirectory) }
}
public struct DownloadOwner: Hashable, Sendable, Codable {
    public let browser: BrowserToken
    public let context: ContextEpoch
    public let policy: DownloadPolicy
    public var window: WindowID { browser.page.window }
    public init(browser: BrowserToken, context: ContextEpoch, policy: DownloadPolicy) {
        self.browser = browser; self.context = context; self.policy = policy
    }
}
public struct DownloadDetails: Hashable, Sendable, Codable {
    public let url: URL
    public let suggestedName: String
    public init(url: URL, suggestedName: String) { self.url = url; self.suggestedName = suggestedName }
}
public struct TransferProgress: Hashable, Sendable, Codable {
    public let received: Int64
    public let total: Int64?
    public init(received: Int64, total: Int64?) { self.received = received; self.total = total }
}
public struct FileReceipt: Hashable, Sendable, Codable {
    public let url: URL
    public let bytes: Int64
    public init(url: URL, bytes: Int64) { self.url = url; self.bytes = bytes }
}
public enum PartialFile: Hashable, Sendable, Codable {
    case absent, removed, retained(URL, reason: String), unknown
}
public enum DownloadEnd: Hashable, Sendable, Codable {
    case completed(FileReceipt)
    case cancelled(PartialFile)
    case interrupted(reason: String, PartialFile)
    case failed(reason: String, PartialFile)
}
public enum DownloadStage: Hashable, Sendable, Codable {
    case choosingDestination
    case receiving(TransferProgress)
    case cancelling(TransferProgress)
    case terminal(DownloadEnd)
}
public struct DownloadUpdate: Hashable, Sendable, Codable {
    public let id: DownloadID
    public let owner: DownloadOwner
    public let details: DownloadDetails
    public let revision: UInt64
    public let stage: DownloadStage
    public init(id: DownloadID, owner: DownloadOwner, details: DownloadDetails, revision: UInt64, stage: DownloadStage) {
        self.id = id; self.owner = owner; self.details = details; self.revision = revision; self.stage = stage
    }
}
public struct DestinationTicket: Hashable, Sendable {
    public let download: DownloadID
    public let generation: UInt64
    public init(download: DownloadID, generation: UInt64) { self.download = download; self.generation = generation }
}
public struct DownloadDestinationPrompt: Sendable {
    public let ticket: DestinationTicket
    public let window: WindowID
    public let directory: URL
    public let suggestedName: String
    public init(ticket: DestinationTicket, window: WindowID, directory: URL, suggestedName: String) {
        self.ticket = ticket; self.window = window; self.directory = directory; self.suggestedName = suggestedName
    }
}
public enum DestinationAnswer: Sendable { case accepted(URL), cancelled, ownerGone }
public struct ContextDisposal: Hashable, Sendable {
    public let id: DisposalID
    public let context: BrowsingContext
    public init(id: DisposalID, context: BrowsingContext) { self.id = id; self.context = context }
}
public enum DataDisposition: Hashable, Sendable, Codable { case memoryReleased, deletionScheduledForNextLaunch }
public enum ContextDisposalResult: Hashable, Sendable {
    case completed(DisposalID, BrowsingContext, DataDisposition)
    case failed(DisposalID, BrowsingContext, reason: String)
}
