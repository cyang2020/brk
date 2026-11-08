import BrkBase
import CBrkCore
import Foundation

/// The page's audio and video elements on BrkCore, read by the framework in every frame (brk/browser/brk_media_players.mm), as CEF's Brk reads
/// them with its bundled extension: the same `MediaPlayer` values and the same per-element operations.
extension CorePage {
    func mediaPlayersChanged(_ json: String) {
        guard let data = json.data(using: .utf8), let rows = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else { return }
        let players = rows.compactMap { row -> MediaPlayer? in
            guard let element = row["element"] as? String, let frame = row["frame"] as? Int, let document = row["document"] as? String,
                  let kind = (row["kind"] as? String).flatMap(MediaKind.init(rawValue:)) else { return nil }
            return MediaPlayer(id: MediaPlayerID(document: document, frame: frame, element: element), kind: kind,
                               paused: row["paused"] as? Bool ?? true, ended: row["ended"] as? Bool ?? false,
                               pictureInPicture: row["pictureInPicture"] as? Bool ?? false, silent: row["silent"] as? Bool ?? false)
        }
        let pictureInPicture = mediaPlayers.contains(where: \.pictureInPicture)
        guard players != mediaPlayers, let document = readyDocument else { return }
        mediaPlayers = players
        engine.pageDidEmit(self, .mediaChanged(document, players, error: nil))
        if pictureInPicture != players.contains(where: \.pictureInPicture) { refreshWebsitePolicy() }
    }

    func control(_ request: MediaControl) {
        guard request.document == readyDocument, mediaPlayers.contains(where: { $0.id == request.player }) else { return }
        let done = contents.controlMediaPlayer(inFrame: Int32(request.player.frame), element: request.player.element,
                                               operation: request.operation.rawValue, volume: request.volume ?? 0)
        if !done, let document = readyDocument {
            engine.pageDidEmit(self, .mediaChanged(document, mediaPlayers, error: "The player's frame is gone"))
        }
    }
}
