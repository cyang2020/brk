import Foundation

public struct UpdateRelease: Equatable, Sendable, Codable {
    public let version: String
    public let build: UInt64
    public let notesURL: URL?

    public init(version: String, build: UInt64, notesURL: URL? = nil) {
        self.version = version
        self.build = build
        self.notesURL = notesURL
    }
}

public enum UpdatePresentation: Equatable, Sendable, Codable {
    case checking
    case available(UpdateRelease)
    case downloading(UpdateRelease, fraction: Double?)
    case preparing(UpdateRelease)
    case ready(UpdateRelease)
    case installing(UpdateRelease)
    case updated(UpdateRelease)
    case failed(message: String)
}
