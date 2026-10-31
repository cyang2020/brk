import Foundation

public enum CaptureMode: String, Hashable, Sendable, Codable { case area, fullPage, portrait }
/// Fractions of the visible CSS viewport. Page offsets and zoom are resolved by the engine at capture time.
public struct CaptureRegion: Hashable, Sendable, Codable {
    public let x: Double, y: Double, width: Double, height: Double
    public init(x: Double, y: Double, width: Double, height: Double) { self.x = x; self.y = y; self.width = width; self.height = height }
    public var valid: Bool { [x,y,width,height].allSatisfy(\.isFinite) && x >= 0 && y >= 0 && width > 0 && height > 0 && x + width <= 1.000001 && y + height <= 1.000001 }
}
public struct CaptureRequest: Hashable, Sendable, Codable {
    public let id: String
    public let document: DocumentToken
    public let context: BrowsingContext
    public let mode: CaptureMode
    public let title: String
    public let url: URL
    public let createdAt: Instant
    public var region: CaptureRegion?
    public init(id: String, document: DocumentToken, context: BrowsingContext, mode: CaptureMode, title: String, url: URL, createdAt: Instant, region: CaptureRegion? = nil) {
        self.id = id; self.document = document; self.context = context; self.mode = mode; self.title = title; self.url = url; self.createdAt = createdAt; self.region = region
    }
}
public struct CaptureImage: Hashable, Sendable, Codable {
    public let png: Data
    public let width: Int, height: Int
    public let scale: Double
    public init(png: Data, width: Int, height: Int, scale: Double) { self.png = png; self.width = width; self.height = height; self.scale = scale }
}
public struct CaptureRecord: Hashable, Sendable, Codable {
    public let id: String
    public let profile: ProfileID
    public let title: String
    public let url: URL
    public let createdAt: Instant
    public let mode: CaptureMode
    public let width: Int, height: Int
    public let scale: Double
    public init(request: CaptureRequest, profile: ProfileID, image: CaptureImage) {
        id = request.id; self.profile = profile; title = request.title; url = request.url; createdAt = request.createdAt; mode = request.mode
        width = image.width; height = image.height; scale = image.scale
    }
}
/// The Easel owner can consume this value without knowing the storage layout or CEF.
public struct EaselCaptureInsertion: Hashable, Sendable, Codable {
    public let capture: CaptureRecord
    public let png: Data
    public init(capture: CaptureRecord, png: Data) { self.capture = capture; self.png = png }
}
