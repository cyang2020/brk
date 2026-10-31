import BrkBase
import Foundation

extension Work {
    mutating func pictureInPicture(_ intent: PictureInPictureIntent, in window: WindowID) {
        guard let tab = state.resolveTab(.focused, in: window), let live = state.session.live[PageID(window: window, item: tab)],
              case .ready(let document) = live.document else { return }
        switch intent {
        case .document: effects.append(.page(document.browser.page, .documentPictureInPicture(DocumentPiPControl(document: document, enter: true))))
        case .video:
            guard let player = live.mediaPlayers.first(where: { $0.kind == .video && !$0.paused && !$0.ended }) ?? live.mediaPlayers.first(where: { $0.kind == .video }) else { toast("This page has no ready video", in: window); return }
            effects.append(.page(document.browser.page, .media(MediaControl(document: document, player: player.id, operation: .enterPictureInPicture))))
        case .close:
            effects.append(.page(document.browser.page, .documentPictureInPicture(DocumentPiPControl(document: document, enter: false))))
            for player in live.mediaPlayers where player.pictureInPicture { effects.append(.page(document.browser.page, .media(MediaControl(document: document, player: player.id, operation: .exitPictureInPicture)))) }
        }
    }
    mutating func reconcilePictureInPicture(from before: AppState) {
        let visible = state.visiblePages(), previous = before.visiblePages()
        for page in previous.subtracting(visible).sorted() {
            guard state.resolveTab(.focused, in: page.window) != page.item, state.doc.settings.advanced.autoPictureInPicture, let live = state.session.live[page],
                  case .ready(let document) = live.document, case .profile = live.requestContext,
                  let url = state.address(of: page.item, in: page.window, for: .savedDocument), let origin = SiteOrigin(url),
                  !state.sitePreferences(state.browsingContext(of: page.item)).rule(for: origin).pictureInPictureExempt.orFalse,
                  let player = live.mediaPlayers.first(where: { $0.kind == .video && !$0.paused && !$0.ended && !$0.pictureInPicture }) else { continue }
            state.session.live[page]?.automaticPiPPlayer = player.id
            effects.append(.page(page, .media(MediaControl(document: document, player: player.id, operation: .enterPictureInPicture, userInitiated: false))))
        }
        for page in visible.sorted() {
            guard let live = state.session.live[page], let player = live.automaticPiPPlayer, case .ready(let document) = live.document else { continue }
            state.session.live[page]?.automaticPiPPlayer = nil
            effects.append(.page(page, .media(MediaControl(document: document, player: player, operation: .exitPictureInPicture, userInitiated: false))))
        }
    }
}
private extension Optional where Wrapped == Bool { var orFalse: Bool { self ?? false } }
