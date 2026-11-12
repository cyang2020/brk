import AppKit
import BrkBase
import BrkDomain
import BrkLayout

/// The last look of each shown tab or split, for the Ctrl+Tab switcher's cards (Arc shows the pages, P09-a). A view
/// cannot draw Chromium's pixels itself, so the window's own image is taken (`capture`, BrkApp's window-server call)
/// and cropped to the card: once the window has been still for `settle` (a short look at a tab is enough) with
/// nothing over the content, and once more as the switcher opens, before its first frame (the screen still shows the
/// page it started from).
@MainActor
final class PageThumbnails {
    /// The window's image as the window server shows it; nil when the app gives none (tests).
    var capture: (() -> CGImage?)?
    private(set) var images: [ItemID: NSImage] = [:]
    /// The Space each image belongs to. A window shows one Space's rows at a time, so those rows can only tell which of
    /// that Space's images are of tabs since closed (or moved away).
    private var spaces: [ItemID: SpaceID] = [:]
    /// What the images were last checked against: the shown Space, the items its rows list, and the Spaces in the dock.
    /// They are checked again only when this changes.
    private var checked: Listing?
    private struct Listing: Equatable {
        var space: SpaceID
        var items: Set<ItemID>
        var spaces: Set<SpaceID>
    }
    /// What the last render showed: the item a switcher card stands for and its rect in the window, and the Space.
    private var shown: (item: ItemID, rect: CGRect)?
    private var shownSpace: SpaceID?
    private var pending: Task<Void, Never>?
    private let settle: Duration = .milliseconds(350)
    /// Card images are kept at twice the switcher's 157.5 x 105 pt.
    private let size = CGSize(width: 315, height: 210)

    /// Called at the start of every render with the previous frame still on screen. `opening`: the switcher is about
    /// to appear, so the page it started from is taken now.
    func beforeRender(opening: Bool, in view: NSView) {
        if opening, let shown { take(shown, in: view) }
    }

    /// Called after a render: remembers what is shown and, while nothing covers it, takes it once things settle.
    func afterRender(_ snapshot: WindowSnapshot, frames: WindowFrames, in view: NSView) {
        pending?.cancel()
        shown = Self.shownUnit(snapshot.content, frames: frames)
        shownSpace = snapshot.space.id
        prune(snapshot)
        let covered = snapshot.overlay != nil || snapshot.tabTools.recent != nil || snapshot.tabTools.toast != nil || snapshot.find != nil
            || snapshot.dialog != nil || snapshot.profileDialog != nil || snapshot.pendingSpaceDeletion != nil || snapshot.ai != nil
            || snapshot.boostEditor != nil || snapshot.capture != nil || frames.sidebarFloats
        guard !covered, let target = shown, capture != nil else { return }
        pending = Task { @MainActor [weak self, weak view, settle] in
            try? await Task.sleep(for: settle)
            guard !Task.isCancelled, let self, let view else { return }
            self.take(target, in: view)
        }
    }

    /// Images of tabs the shown Space no longer lists go: the tab closed or was archived. One a neighbouring Space now
    /// lists goes with the tab to that Space instead (the tab moved), as does one of the shown Space's rows with an
    /// image from another Space. Images of a Space that is no longer in the dock go too; other Spaces' images stay for
    /// their own switcher. They used to stay for as long as the window lived, about 265 KB a tab.
    private func prune(_ snapshot: WindowSnapshot) {
        guard !images.isEmpty else { return }
        let space = snapshot.space.id
        var listed = Self.items(snapshot.space, favorites: snapshot.favorites)
        if let scratch = snapshot.scratch { listed.formUnion(Self.items(scratch.rows)) }
        if let split = snapshot.content.split { listed.insert(split) }
        listed.formUnion(snapshot.content.panes.map(\.tab))
        let listing = Listing(space: space, items: listed, spaces: Set(snapshot.dock.map(\.id) + [space]))
        guard listing != checked else { return }
        checked = listing
        let neighbors = [snapshot.neighbors.previous, snapshot.neighbors.next].compactMap { $0 }.map { page in
            (page.space.id, Self.items(page.space, favorites: page.favorites))
        }
        for (item, tagged) in spaces {
            if listed.contains(item) {
                spaces[item] = space
            } else if tagged == space, let moved = neighbors.first(where: { $0.1.contains(item) }) {
                spaces[item] = moved.0
            } else if tagged == space || !listing.spaces.contains(tagged) {
                images[item] = nil
                spaces[item] = nil
            }
        }
    }

    /// Every tab, split and split pane a Space's rows list, folders' contents included, and its Favorites.
    static func items(_ space: SpaceSnapshot, favorites: FavoritesSnapshot) -> Set<ItemID> {
        items(space.pinned.rows + space.today.rows).union(favorites.tiles.map(\.id))
    }

    static func items(_ rows: [Row]) -> Set<ItemID> {
        var found = Set<ItemID>()
        func walk(_ rows: [Row]) {
            for row in rows {
                switch row {
                case .tab(let tab): found.insert(tab.id)
                case .folder(let folder): walk(folder.children)
                case .split(let split): found.insert(split.id); found.formUnion(split.panes.map(\.id))
                }
            }
        }
        walk(rows)
        return found
    }

    /// The switcher's unit: a split is one card (the whole content area), else the single pane's tab.
    static func shownUnit(_ content: ContentSnapshot, frames: WindowFrames) -> (item: ItemID, rect: CGRect)? {
        if let split = content.split { return (split, frames.contentArea) }
        guard let pane = content.presentedPanes.first, case .page = pane.content, let card = frames.cards.first else { return nil }
        return (pane.tab, card.rect)
    }

    private func take(_ target: (item: ItemID, rect: CGRect), in view: NSView) {
        guard let window = view.window, window.isVisible, window.occlusionState.contains(.visible),
              let image = capture?(), let thumbnail = Self.thumbnail(of: image, rect: view.convert(target.rect, to: nil), window: window, size: size) else { return }
        images[target.item] = thumbnail
        spaces[target.item] = shownSpace
    }

    /// `rect` (window coordinates, bottom-left origin) cut from the window's image and scaled to fill `size`, top
    /// aligned like Arc's cards (the top of the page shows).
    static func thumbnail(of image: CGImage, rect: CGRect, window: NSWindow, size: CGSize) -> NSImage? {
        let height = window.frame.height
        let scale = Double(image.width) / max(1, window.frame.width)
        let pixels = CGRect(x: rect.minX * scale, y: (height - rect.maxY) * scale, width: rect.width * scale, height: rect.height * scale).integral
        guard pixels.width > 1, pixels.height > 1, let crop = image.cropping(to: pixels),
              let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let fill = max(size.width / Double(crop.width), size.height / Double(crop.height))
        let drawn = CGSize(width: Double(crop.width) * fill, height: Double(crop.height) * fill)
        context.interpolationQuality = .high
        context.draw(crop, in: CGRect(x: (size.width - drawn.width) / 2, y: size.height - drawn.height, width: drawn.width, height: drawn.height))
        guard let scaled = context.makeImage() else { return nil }
        return NSImage(cgImage: scaled, size: CGSize(width: size.width / 2, height: size.height / 2))
    }
}
