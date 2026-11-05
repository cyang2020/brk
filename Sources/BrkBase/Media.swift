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
    /// The page has muted this element (a news site's autoplaying clip): it makes no sound, so it gets no mini player
    /// (Arc, Q18-media-z1). The tab's own mute is another matter: that tab keeps its card.
    public let silent: Bool
    /// The player's frame has a Media Session handler for the next or previous track (Arc's `MediaSessionState`).
    public let hasNextTrack: Bool
    public let hasPreviousTrack: Bool
    public init(id: MediaPlayerID, kind: MediaKind, paused: Bool, ended: Bool, pictureInPicture: Bool = false, silent: Bool = false,
                hasNextTrack: Bool = false, hasPreviousTrack: Bool = false) {
        self.id = id; self.kind = kind; self.paused = paused; self.ended = ended; self.pictureInPicture = pictureInPicture
        self.silent = silent; self.hasNextTrack = hasNextTrack; self.hasPreviousTrack = hasPreviousTrack
    }
}
public enum MediaOperation: String, Hashable, Sendable, Codable { case play, pause, enterPictureInPicture, exitPictureInPicture, nextTrack, previousTrack, setVolume }
public struct MediaControl: Hashable, Sendable, Codable {
    public let document: DocumentToken
    public let player: MediaPlayerID
    public let userInitiated: Bool
    public let operation: MediaOperation
    /// `setVolume`: the volume, 0 to 1.
    public let volume: Double?
    public init(document: DocumentToken, player: MediaPlayerID, operation: MediaOperation, userInitiated: Bool = true, volume: Double? = nil) { self.document = document; self.player = player; self.operation = operation; self.userInitiated = userInitiated; self.volume = volume }
}
/// What a mini player's transport buttons ask of a tab (Arc: `ADKClient.playMediaSession`, `pauseMediaSession`,
/// `playNextMediaSessionTrack`, `playPreviousMediaSessionTrack`). Unlike `MediaOperation` it names no player.
public enum MediaSessionOperation: String, Hashable, Sendable, Codable { case play, pause, nextTrack, previousTrack }

public enum PictureInPictureIntent: String, Hashable, Sendable, Codable { case video, document, close }
public struct DocumentPiPControl: Hashable, Sendable, Codable {
    public let document: DocumentToken
    public let enter: Bool
    public let userInitiated: Bool
    public init(document: DocumentToken, enter: Bool, userInitiated: Bool = true) { self.document = document; self.enter = enter; self.userInitiated = userInitiated }
}
