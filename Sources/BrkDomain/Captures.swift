import BrkBase
import Foundation

public enum CaptureCommand: Hashable, Sendable, Codable {
    case begin(CaptureMode), select(CaptureRegion), cancel
    case preview(String), export(String), remove(String), insertInEasel(String)
}
public enum CaptureEvent: Sendable, Equatable {
    case loaded(ProfileID, [CaptureRecord], [String: URL], error: String?)
    case rendered(CaptureRequest, CaptureImage)
    case stored(CaptureRequest, CaptureRecord, URL)
    case removed(ProfileID, String)
    case failed(WindowID, String, String)
    case exported(WindowID, String)
}
public enum CaptureEffect: Hashable, Sendable {
    case load(ProfileID), render(CaptureRequest), store(CaptureRequest, CaptureImage)
    case remove(CaptureRecord), export(CaptureRecord, WindowID), insertInEasel(CaptureRecord, WindowID)
    case forget(ProfileID)
}
public struct CaptureSnapshot: Hashable, Sendable, Codable {
    public var request: CaptureRequest
    public var rendering: Bool = false
    public var image: CaptureImage? = nil
    public init(request: CaptureRequest) { self.request = request }
}
struct CaptureLibrary: Sendable, Equatable {
    var records: [CaptureRecord] = []
    var files: [String: URL] = [:]
    var loaded: Set<ProfileID> = []
}
