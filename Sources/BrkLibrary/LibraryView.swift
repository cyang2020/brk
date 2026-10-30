import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// Owner: F5. The Library host inside the content card (Arc: `HomeButton`, `BaseHomeComponents`): a page strip
/// along the top (one cell per `LibraryPage`, Arc's Lottie icons later), a close button, and the page area under it.
/// The archive page keeps its own view (BrkOverlays/ArchivePageView.swift, moving here in F5) and is placed in
/// `frames.library.page` by the window root; this view draws the strip and the other pages.
///
/// Public surface (what BrkContent's root may call): `init(dispatch:)`, `render`.
/// First pass: strip cells as plain buttons, a placeholder label for every page but the archive. TODO(F5):
/// Downloads (rows with progress, `DownloadMenu`), History (rows, search), Media, Easels & Notes, Boosts, Spaces.
@MainActor
public final class LibraryView: NSView {
    private let dispatch: Dispatch
    private var cells: [LibraryPage: NSButton] = [:]
    private let close = NSButton(title: LibraryCopy.close, target: nil, action: nil)
    private let placeholder = NSTextField(labelWithString: "")
    private var last: (LibrarySnapshot, LibraryFrames, Palette)?

    public init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        wantsLayer = true
        identify(.library)
        for page in LibraryPage.allCases {
            let button = NSButton(title: LibraryCopy.title(page), target: self, action: #selector(pageClicked(_:)))
            button.bezelStyle = .inline
            button.identify(.libraryPage(page))
            button.tag = LibraryPage.allCases.firstIndex(of: page)!
            cells[page] = button
            addSubview(button)
        }
        close.bezelStyle = .inline
        close.target = self
        close.action = #selector(closeClicked)
        close.identify(.libraryClose)
        addSubview(close)
        placeholder.alignment = .center
        placeholder.textColor = .secondaryLabelColor
        placeholder.font = .systemFont(ofSize: NSFont.systemFontSize)
        addSubview(placeholder)
        isHidden = true
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("not used") }

    public override var isFlipped: Bool { true }

    /// Idempotent: the same slice, frames and palette change nothing.
    public func render(_ library: LibrarySnapshot?, frames: WindowFrames, palette: Palette) {
        guard let library, let f = frames.library else {
            isHidden = true
            last = nil
            return
        }
        if let last, last.0 == library, last.1 == f, last.2 == palette { return }
        last = (library, f, palette)
        isHidden = false
        frame = f.frame
        layer?.backgroundColor = palette.color(palette.tokens.itemBackground).cgColor
        let local = { (r: CGRect) in r.offsetBy(dx: -f.frame.minX, dy: -f.frame.minY) }
        for (page, button) in cells {
            if let cell = f.pageCells[page] { button.frame = local(cell).insetBy(dx: 2, dy: 6) }
            button.state = page == library.page ? .on : .off
        }
        let closeSize = CGSize(width: 60, height: f.strip.height - 12)
        close.frame = CGRect(x: f.frame.width - closeSize.width - 8, y: 6, width: closeSize.width, height: closeSize.height)
        close.isHidden = true   // TODO(F5): Arc closes the Library from its own button; Esc works today.
        placeholder.frame = local(f.page)
        placeholder.isHidden = library.page == .archive
        placeholder.stringValue = LibraryCopy.placeholder(library)
    }

    @objc private func pageClicked(_ sender: NSButton) {
        guard LibraryPage.allCases.indices.contains(sender.tag) else { return }
        dispatch(.library(.open(LibraryPage.allCases[sender.tag])))
    }

    @objc private func closeClicked() { dispatch(.library(.close)) }
}

/// Arc's Library copy (visual-and-copy.md "Settings page labels", menu rows 170 to 174).
public enum LibraryCopy {
    public static let close = "Close"

    public static func title(_ page: LibraryPage) -> String {
        switch page {
        case .downloads: "Downloads"
        case .history: "History"
        case .archive: "Archive"
        case .media: "Media"
        case .easelsAndNotes: "Easels & Notes"
        case .boosts: "Boosts"
        case .spaces: "Spaces"
        }
    }

    /// First-pass page bodies. TODO(F5): the real pages.
    static func placeholder(_ library: LibrarySnapshot) -> String {
        switch library.page {
        case .downloads: library.downloads.isEmpty ? "No downloads yet." : library.downloads.map(\.filename).joined(separator: "\n")
        case .history: library.history.isEmpty ? "No history yet." : library.history.prefix(50).map { $0.title.isEmpty ? $0.url.absoluteString : $0.title }.joined(separator: "\n")
        case .archive: ""
        case .media: "Captures and media arrive with a later wave."
        case .easelsAndNotes: "Easels and Notes arrive with a later wave."
        case .boosts: "Boosts arrive with a later wave."
        case .spaces: "The space manager arrives with a later wave."
        }
    }
}
