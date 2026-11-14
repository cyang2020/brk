import Foundation

public struct UpdateRelease: Equatable, Sendable, Codable {
    public let version: String
    public let build: UInt64

    public init(version: String, build: UInt64) {
        self.version = version
        self.build = build
    }
}

public enum UpdatePresentation: Equatable, Sendable, Codable {
    case checking
    case available(UpdateRelease)
    case downloading(UpdateRelease, fraction: Double?)
    case preparing(UpdateRelease)
    case ready(UpdateRelease)
    case installing(UpdateRelease)
    case failed(message: String)
}
