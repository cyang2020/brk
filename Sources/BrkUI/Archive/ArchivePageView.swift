import AppKit
import BrkBase
import BrkDomain
import BrkLayout

/// Owner: W4. The archive page, drawn inside the content area like Arc's archive in the content card, so the
/// sidebar and dock stay clickable around it. Groups by bucket (`ArchiveSnapshot.groups`), each entry with a restore
/// button (`.archive(.restore(id))`), Clear Archive with Arc's confirmation, and the auto-archive threshold picker
/// (`.settings(.autoArchive(t))`).
@MainActor
public final class ArchivePageView: NSView {
    let dispatch: Dispatch

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        isHidden = true
        identify(.archive)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    public override var isFlipped: Bool { true }

    func render(_ archive: ArchiveSnapshot?, frames: WindowFrames, palette: Palette) {
        // TODO(W4): nil -> hide. Else frame = frames.archive, rounded like a card; a scroll view of groups
        // identify(.archiveGroup(bucket)), entries identify(.archiveEntry(id)), buttons identify(.archiveRestore(id)),
        // identify(.archiveClear), identify(.archiveThreshold). Empty state: Copy.archiveEmpty.
        fatalError("not implemented")
    }
}
