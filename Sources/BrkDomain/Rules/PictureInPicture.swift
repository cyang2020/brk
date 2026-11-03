import BrkBase
import Foundation

extension Work {
    mutating func pictureInPicture(_ intent: PictureInPictureIntent, in window: WindowID) {
        guard let tab = state.resolveTab(.focused,in:window), let live = state.session.live[PageID(window:window,item:tab)], case .ready(let document) = live.document else { return }
        switch intent {
        case .document: effects.append(.page(document.browser.page,.documentPictureInPicture(DocumentPiPControl(document:document,enter:true))))
        case .video:
            guard let player = live.mediaPlayers.first(where:{$0.kind == .video && !$0.paused && !$0.ended}) ?? live.mediaPlayers.first(where:{$0.kind == .video}) else { toast("This page has no ready video",in:window);return }
            effects.append(.page(document.browser.page,.media(MediaControl(document:document,player:player.id,operation:.enterPictureInPicture))))
        case .close:
            effects.append(.page(document.browser.page,.documentPictureInPicture(DocumentPiPControl(document:document,enter:false))))
            for player in live.mediaPlayers where player.pictureInPicture { effects.append(.page(document.browser.page,.media(MediaControl(document:document,player:player.id,operation:.exitPictureInPicture)))) }
        }
    }
    mutating func reconcilePictureInPicture(from before: AppState) {
        let visible = state.visiblePages(), previous = before.visiblePages()
        for page in previous.subtracting(visible) where state.resolveTab(.focused,in:page.window) != page.item {
            if let live = state.session.live[page], case .ready(let document) = live.document { state.session.automaticPiPCandidates[page] = document }
        }
        for page in Array(state.session.automaticPiPCandidates.keys) {
            guard !visible.contains(page), let live = state.session.live[page], live.document.token == state.session.automaticPiPCandidates[page], permitsAutomaticPiP(page) else { state.session.automaticPiPCandidates[page] = nil;continue }
            guard case .ready(let document) = live.document, live.automaticPiPPlayer == nil,
                  let player = live.mediaPlayers.first(where:{$0.kind == .video && !$0.paused && !$0.ended && !$0.pictureInPicture}) else { continue }
            state.session.automaticPiPCandidates[page] = nil
            state.session.live[page]?.automaticPiPPlayer = player.id
            effects.append(.page(page,.media(MediaControl(document:document,player:player.id,operation:.enterPictureInPicture,userInitiated:false))))
        }
        for (page,live) in state.session.live where visible.contains(page) || !permitsAutomaticPiP(page) {
            guard let player = live.automaticPiPPlayer, case .ready(let document) = live.document else { continue }
            state.session.live[page]?.automaticPiPPlayer = nil
            effects.append(.page(page,.media(MediaControl(document:document,player:player,operation:.exitPictureInPicture,userInitiated:false))))
        }
    }
    /// A page in document fullscreen that leaves the screen (another tab, Space, or its tab closed) leaves
    /// fullscreen, and its window returns to how it was before the page asked, as Chrome does when a fullscreen tab
    /// is deactivated. Without this the window stayed fullscreen around another tab and the hidden page kept its
    /// fullscreen element.
    mutating func reconcileFullscreen(from before: AppState) {
        let visible = state.visiblePages()
        for page in before.visiblePages().subtracting(visible) where before.session.live[page]?.fullscreen == true {
            if state.session.live[page] != nil {
                state.session.live[page]?.fullscreen = false
                effects.append(.page(page, .exitFullscreen))
            }
            if state.doc.windows[page.window] != nil { effects.append(.window(page.window, .pageFullScreen(false))) }
        }
    }
    private func permitsAutomaticPiP(_ page: PageID) -> Bool {
        guard state.doc.settings.advanced.autoPictureInPicture, case .profile = state.session.live[page]?.requestContext,
              let url = state.address(of:page.item,in:page.window,for:.savedDocument), let origin = SiteOrigin(url) else { return false }
        return state.sitePreferences(state.browsingContext(of:page.item)).rule(for:origin).pictureInPictureExempt != true
    }
}
