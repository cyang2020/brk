import AppKit
import BrkBase
import BrkDomain
import Foundation

/// The Dock icon while Brk runs (`AppSnapshot.dockTile`), as Chrome's and Arc's: the number of downloads in
/// progress as the badge, a progress bar over the bottom of the icon while every one of them knows its size, and the
/// Downloads stack in the Dock bounces once for each download that finishes (the `com.apple.DownloadFileFinished`
/// notification browsers post with the file's path). The icon itself is `NSApp.applicationIconImage` (the Icon
/// pane's choice, AppStore), drawn under the bar.
@MainActor
final class DockTile {
    private var shown: DockTileSnapshot?
    private let tile: NSDockTile
    private let post: (String) -> Void
    private let progressView = DockProgressView()

    init(tile: NSDockTile = NSApp.dockTile, post: @escaping (String) -> Void = DockTile.announceFinished) {
        self.tile = tile
        self.post = post
    }

    /// What the tile shows now (badge text, progress), for the tests and the control socket.
    var badge: String? { tile.badgeLabel }
    var progress: Double? { tile.contentView == nil ? nil : progressView.progress }

    func update(_ snapshot: DockTileSnapshot) {
        guard snapshot != shown else { return }
        let previous = shown
        shown = snapshot
        tile.badgeLabel = snapshot.active > 0 ? "\(snapshot.active)" : nil
        if let progress = snapshot.progress {
            progressView.progress = progress
            progressView.frame = NSRect(origin: .zero, size: tile.size)
            tile.contentView = progressView
        } else {
            tile.contentView = nil
        }
        tile.display()
        // The first snapshot lists downloads finished before launch; only the ones that finish while running bounce.
        guard let previous else { return }
        for (id, path) in snapshot.finished where previous.finished[id] == nil { post(path) }
    }

    /// The Icon pane's choice for the Dock tile plug-in (scripts/dock-tile/BrkDockTilePlugIn.swift), which draws it
    /// while Brk is not running: `<data directory>/dock-tile.json`, and the same JSON as the object of the
    /// distributed notification "<bundle id>.dockTileIcon" for a plug-in the Dock has loaded. Both name the data
    /// directory, so a test instance's choice never reaches the tile of the Brk in Application Support.
    static func publishIcon(_ icon: String, dataDirectory: URL = Product.dataDirectory(), bundleID: String? = Bundle.main.bundleIdentifier,
                            post: (String, String) -> Void = DockTile.postIcon) {
        let object: [String: String] = ["icon": icon, "dataDirectory": dataDirectory.standardizedFileURL.path]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return }
        try? FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        try? data.write(to: dataDirectory.appendingPathComponent("dock-tile.json"), options: .atomic)
        if let bundleID { post(bundleID + ".dockTileIcon", String(decoding: data, as: UTF8.self)) }
    }

    nonisolated static func postIcon(_ name: String, _ object: String) {
        DistributedNotificationCenter.default().postNotificationName(NSNotification.Name(name), object: object, userInfo: nil, deliverImmediately: true)
    }

    nonisolated static func announceFinished(_ path: String) {
        DistributedNotificationCenter.default().postNotificationName(NSNotification.Name("com.apple.DownloadFileFinished"), object: path,
                                                                     userInfo: nil, deliverImmediately: true)
    }
}

/// The app icon with a rounded progress bar across its lower part (Chrome's Dock download bar).
final class DockProgressView: NSView {
    var progress: Double = 0 { didSet { needsDisplay = true } }

    override func draw(_ dirtyRect: NSRect) {
        NSApp.applicationIconImage?.draw(in: bounds)
        let bar = NSRect(x: bounds.width * 0.1, y: bounds.height * 0.12, width: bounds.width * 0.8, height: max(6, bounds.height * 0.1))
        let radius = bar.height / 2
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: bar, xRadius: radius, yRadius: radius).fill()
        let inset = bar.insetBy(dx: 1.5, dy: 1.5)
        let filled = NSRect(x: inset.minX, y: inset.minY, width: max(inset.height, inset.width * CGFloat(min(1, max(0, progress)))), height: inset.height)
        NSColor.controlAccentColor.setFill()
        NSBezierPath(roundedRect: filled, xRadius: inset.height / 2, yRadius: inset.height / 2).fill()
    }
}
