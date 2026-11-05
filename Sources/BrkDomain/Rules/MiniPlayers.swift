import BrkBase
import Foundation

// Owner: W1. Arc's mini players (`MediaControlsFeature`). What a card does was tried on Arc 1.170 and read from its
// binary (verify/visual-pairs/run-20261103/r5-5/REPORT.md); the rules here are that list.

extension LivePage {
    /// Something in the page is making sound or would be if the tab were not muted. A player the page itself keeps silent
    /// does not count, nor one the Picture in Picture window shows: Arc opens that window instead of a card (Q18-media-w).
    var playsThroughMiniPlayer: Bool {
        mediaPlayers.contains { !$0.paused && !$0.ended && !$0.silent } && !showsPictureInPicture
    }

    var showsPictureInPicture: Bool { documentPictureInPicture || (automaticPiPPlayer != nil && mediaError == nil) || mediaPlayers.contains(where: \.pictureInPicture) }
}

/// A window's cards follow its pages, whatever moved them:
/// - a tab that is playing and not on screen gets a card, unless its × closed it since the tab was last shown;
/// - the card stays when the sound pauses behind it (its button then reads Play), but a tab paused before it left the
///   screen gets none;
/// - it goes when the tab is shown again, when the page stops having players (it navigated or closed) or moves to a
///   Picture in Picture window.
func repairMiniPlayers(_ state: inout AppState) {
    for window in state.session.windows.keys {
        guard var session = state.session.windows[window] else { continue }
        let shown = Set(state.shownItem(in: window).map { state.panes(of: $0) } ?? [])
        func live(_ tab: ItemID) -> LivePage? { state.session.live[PageID(window: window, item: tab)] }
        var players = session.miniPlayers.filter { tab in
            guard !shown.contains(tab), let page = live(tab) else { return false }
            return !page.mediaPlayers.isEmpty && !page.showsPictureInPicture
        }
        let closed = session.closedMiniPlayers.subtracting(shown).filter { live($0) != nil }
        let playing = state.session.live.compactMap { page, value in page.window == window && value.playsThroughMiniPlayer ? page.item : nil }
        for tab in playing.sorted() where !shown.contains(tab) && !players.contains(tab) && !closed.contains(tab) { players.append(tab) }
        guard players != session.miniPlayers || closed != session.closedMiniPlayers else { continue }
        session.miniPlayers = players
        session.closedMiniPlayers = closed
        state.session.windows[window] = session
    }
}

func projectMiniPlayers(_ state: AppState, window: WindowID) -> [MiniPlayerSnapshot] {
    (state.session.windows[window]?.miniPlayers ?? []).compactMap { tab in
        guard let page = state.session.live[PageID(window: window, item: tab)], let t = state.displayedTab(tab, in: window) else { return nil }
        return MiniPlayerSnapshot(tab: tab, title: t.displayTitle, favicon: t.favicon, icon: t.icon,
                                  playing: page.mediaPlayers.contains { !$0.paused && !$0.ended }, muted: t.muted,
                                  hasNextTrack: page.mediaPlayers.contains(where: \.hasNextTrack),
                                  hasPreviousTrack: page.mediaPlayers.contains(where: \.hasPreviousTrack), volume: page.mediaVolume)
    }
}

extension Work {
    private func readyPage(_ ref: ItemRef, in window: WindowID) -> (page: PageID, document: DocumentToken, live: LivePage)? {
        guard let tab = state.resolveTab(ref, in: window) else { return nil }
        let page = PageID(window: window, item: tab)
        guard let live = state.session.live[page], case .ready(let document) = live.document else { return nil }
        return (page, document, live)
    }

    /// The card's Pause stops everything playing in the tab and its Play starts those again; with none noted (the page
    /// paused itself) the first player. A muted tab's buttons do nothing (Q18-media-g: the glyph is dimmed).
    mutating func mediaSession(_ ref: ItemRef, _ operation: MediaSessionOperation, in window: WindowID) {
        guard let (page, document, live) = readyPage(ref, in: window), state.tab(page.item)?.muted != true else { return }
        func emit(_ player: MediaPlayerID, _ op: MediaOperation) { effects.append(.page(page, .media(MediaControl(document: document, player: player, operation: op)))) }
        switch operation {
        case .pause:
            let playing = live.mediaPlayers.filter { !$0.paused && !$0.ended }.map(\.id)
            state.session.live[page]?.suspendedPlayers = playing
            playing.forEach { emit($0, .pause) }
        case .play:
            let noted = live.suspendedPlayers.filter { id in live.mediaPlayers.contains { $0.id == id } }
            let players = noted.isEmpty ? Array(live.mediaPlayers.prefix(1).map(\.id)) : noted
            state.session.live[page]?.suspendedPlayers = []
            players.forEach { emit($0, .play) }
        case .nextTrack:
            if let player = live.mediaPlayers.first(where: \.hasNextTrack) { emit(player.id, .nextTrack) }
        case .previousTrack:
            if let player = live.mediaPlayers.first(where: \.hasPreviousTrack) { emit(player.id, .previousTrack) }
        }
    }

    mutating func mediaVolume(_ ref: ItemRef, _ volume: Double, in window: WindowID) {
        guard let (page, document, live) = readyPage(ref, in: window), volume.isFinite else { return }
        let level = min(1, max(0, volume))
        state.session.live[page]?.mediaVolume = level
        for player in live.mediaPlayers {
            effects.append(.page(page, .media(MediaControl(document: document, player: player.id, operation: .setVolume, volume: level))))
        }
    }

    mutating func closeMiniPlayer(_ tab: ItemID, in window: WindowID) {
        guard state.session.windows[window]?.miniPlayers.contains(tab) == true else { return }
        state.session.windows[window]?.miniPlayers.removeAll { $0 == tab }
        state.session.windows[window]?.closedMiniPlayers.insert(tab)
    }
}
