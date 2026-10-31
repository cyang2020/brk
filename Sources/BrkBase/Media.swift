import Foundation

/// Extension-isolated element identity plus Chromium's exact frame document identity.
public struct MediaPlayerID: Hashable, Sendable, Codable {
    public let document: String
    public let frame: Int
    public let element: String
    public init(document: String, frame: Int, element: String) { self.document = document; self.frame = frame; self.element = element }
}
public enum MediaKind: String, Hashable, Sendable, Codable { case audio, video }
public struct MediaPlayer: Hashable, Sendable, Codable {
    public let id: MediaPlayerID
    public let kind: MediaKind
    public let paused: Bool
    public let ended: Bool
    public let pictureInPicture: Bool
    public init(id: MediaPlayerID, kind: MediaKind, paused: Bool, ended: Bool, pictureInPicture: Bool = false) {
        self.id = id; self.kind = kind; self.paused = paused; self.ended = ended; self.pictureInPicture = pictureInPicture
    }
}
public enum MediaOperation: String, Hashable, Sendable, Codable { case play, pause, enterPictureInPicture, exitPictureInPicture }
public struct MediaControl: Hashable, Sendable, Codable {
    public let document: DocumentToken
    public let player: MediaPlayerID
    public let userInitiated: Bool
    public let operation: MediaOperation
    public init(document: DocumentToken, player: MediaPlayerID, operation: MediaOperation, userInitiated: Bool = true) { self.document = document; self.player = player; self.operation = operation; self.userInitiated = userInitiated }
}

public enum PictureInPictureIntent: String, Hashable, Sendable, Codable { case video, document, close }
public struct DocumentPiPControl: Hashable, Sendable, Codable {
    public let document: DocumentToken
    public let enter: Bool
    public let userInitiated: Bool
    public init(document: DocumentToken, enter: Bool, userInitiated: Bool = true) { self.document = document; self.enter = enter; self.userInitiated = userInitiated }
}
