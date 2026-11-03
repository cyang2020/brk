import BrkBase
import Foundation

public enum CaptureCommand: Hashable, Sendable, Codable {
    case begin(CaptureMode), select(CaptureRegion), cancel
    /// A row of the menu card that opens beside a finished selection (P33-c), or the copied toast's Save.
    case act(CaptureAction)
    case open(String), preview(String), export(String), remove(String), insertInEasel(String)
}
/// Arc's capture menu: Save to Library, Copy, Save…, Edit, Retake (Send via iMessage and New Easel are not offered).
public enum CaptureAction: String, Hashable, Sendable, Codable { case library, copy, file, edit, retake }
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
    case copy(CaptureImage), saveFile(CaptureRequest, CaptureImage, WindowID)
    case open(CaptureRecord, WindowID), remove(CaptureRecord), export(CaptureRecord, WindowID), insertInEasel(CaptureRecord, WindowID)
    case forget(ProfileID)
}
public struct CaptureSnapshot: Hashable, Sendable, Codable {
    public var request: CaptureRequest
    public var rendering: Bool = false
    public var image: CaptureImage? = nil
    /// The menu row being carried out (a Library write in flight), so the menu closes while it runs.
    public var action: CaptureAction? = nil
    public init(request: CaptureRequest, image: CaptureImage? = nil) { self.request = request; self.image = image }
    public var canSaveToLibrary: Bool { if case .profile = request.context { true } else { false } }
}
struct CaptureLibrary: Sendable, Equatable {
    var records: [CaptureRecord] = []
    var files: [String: URL] = [:]
    var errors: [ProfileID: String] = [:]
    var loaded: Set<ProfileID> = []
}

extension AppState {
    /// Whether a Library write for `request` is still wanted: its selection menu or its copied toast is still up.
    public func captureAwaitsStore(_ request: CaptureRequest) -> Bool {
        let session = self.session.windows[request.document.browser.page.window]
        return session?.capture?.request == request || session?.copiedCapture?.request == request
    }
}
