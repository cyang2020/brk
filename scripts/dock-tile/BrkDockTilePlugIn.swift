// Brk's Dock tile plug-in (A131), the counterpart of Arc's Contents/PlugIns/DockTilePlugIn.plugin: macOS loads it
// into the Dock's helper process for Brk's tile, so a Brk kept in the Dock shows the icon chosen in Settings > Icon
// while Brk is not running (the bundle's .icns is always "The Original"). While Brk runs, the app's own
// `NSApp.applicationIconImage` takes the tile and this plug-in is not drawn.
//
// Brk writes its choice to `<data directory>/dock-tile.json` ({"icon": "neon", "dataDirectory": "<path>"}) at launch
// and on every change, and posts the same JSON as the object of the distributed notification
// "<bundle id>.dockTileIcon". The plug-in shows the file's choice when the Dock hands it the tile, follows the
// notification while it is loaded, and keeps the last choice in its host's user defaults in case the file cannot be
// read from the Dock's process. A notification from another data directory (a test instance) is ignored.
//
// Built by scripts/dock-tile/build-plugin.sh together with Sources/BrkSettings/AppIconArt.swift, so the tile, the
// running Dock icon, the About window and the Icon pane use the same artwork.
import AppKit
import os

@objc(BrkDockTilePlugIn)
final class BrkDockTilePlugIn: NSObject, NSDockTilePlugIn {
    private var tile: NSDockTile?
    private var observer: NSObjectProtocol?
    private let log = Logger(subsystem: "dev.brk.docktile", category: "plugin")

    /// The app bundle this plug-in sits in (Contents/PlugIns/BrkDockTile.plugin).
    private var host: Bundle? {
        Bundle(url: Bundle(for: BrkDockTilePlugIn.self).bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent())
    }
    private var hostID: String { host?.bundleIdentifier ?? "dev.brk.Brk" }
    private var cacheKey: String { "BrkDockTileIcon." + hostID }

    /// Brk's data directory as the app computes it (BrkBase/Product.swift): BRK_DATA_DIR, else Application Support.
    var dataDirectory: URL {
        if let override = ProcessInfo.processInfo.environment["BRK_DATA_DIR"], !override.isEmpty { return URL(fileURLWithPath: override, isDirectory: true) }
        let name = host?.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Brk"
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent(name, isDirectory: true)
    }

    func setDockTile(_ dockTile: NSDockTile?) {
        if let observer { DistributedNotificationCenter.default().removeObserver(observer) }
        observer = nil
        tile = dockTile
        guard let dockTile else { log.notice("tile released for \(self.hostID, privacy: .public)"); return }
        log.notice("tile set for \(self.hostID, privacy: .public)")
        show(Self.choice(fileAt: dataDirectory) ?? UserDefaults.standard.string(forKey: cacheKey), on: dockTile)
        observer = DistributedNotificationCenter.default().addObserver(forName: Notification.Name(hostID + ".dockTileIcon"), object: nil, queue: .main) { [weak self] note in
            guard let self, let text = note.object as? String, let choice = Self.choice(json: Data(text.utf8), dataDirectory: self.dataDirectory),
                  let tile = self.tile else { return }
            self.show(choice, on: tile)
        }
    }

    private func show(_ name: String?, on tile: NSDockTile) {
        let variant = name.flatMap(AppIconArt.Variant.init(rawValue:)) ?? .original
        UserDefaults.standard.set(variant.rawValue, forKey: cacheKey)
        MainActor.assumeIsolated {
            let view = NSImageView(frame: NSRect(origin: .zero, size: tile.size))
            view.imageScaling = .scaleProportionallyUpOrDown
            view.image = AppIconArt.image(variant, side: max(tile.size.width, 128))
            view.identifier = NSUserInterfaceItemIdentifier("brk-dock-tile-" + variant.rawValue)
            tile.contentView = view
            tile.display()
        }
        log.notice("tile shows \(variant.rawValue, privacy: .public) for \(self.hostID, privacy: .public)")
    }

    /// The choice in `<directory>/dock-tile.json`, nil when the file is missing or unreadable.
    static func choice(fileAt directory: URL) -> String? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent("dock-tile.json")) else { return nil }
        return choice(json: data, dataDirectory: directory)
    }

    /// The icon of a dock-tile JSON, nil when it names another data directory than `dataDirectory`.
    static func choice(json: Data, dataDirectory: URL) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: json) as? [String: Any], let icon = object["icon"] as? String else { return nil }
        if let from = object["dataDirectory"] as? String,
           URL(fileURLWithPath: from).standardizedFileURL.path != dataDirectory.standardizedFileURL.path { return nil }
        return icon
    }
}
