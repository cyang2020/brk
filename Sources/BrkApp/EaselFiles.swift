import AppKit
import BrkBase
import BrkContent
import BrkDomain
import Foundation
import UniformTypeIdentifiers

/// Easels' pictures on disk: `<data directory>/Easels/<easel id>/<element id>.<ext>`. The boards themselves are in
/// state.json (`Doc.easels`); this owns only the copied files. Never reads application state.
actor EaselFiles {
    let root: URL
    init(root: URL) { self.root = root.appendingPathComponent("Easels", isDirectory: true) }

    private func valid(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 100 && id.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
    }

    func directory(_ easel: EaselID) -> URL { root.appendingPathComponent(easel.rawValue, isDirectory: true) }

    /// Copies `source` in and reads its size in points. Refuses what is not a readable picture.
    func importImage(_ source: URL, easel: EaselID, element: String) throws -> (URL, CGSize) {
        guard valid(easel.rawValue), valid(element), source.isFileURL else { throw CocoaError(.fileWriteNoPermission) }
        let attributes = try FileManager.default.attributesOfItem(atPath: source.path)
        guard let bytes = attributes[.size] as? Int, bytes > 0, bytes < 60_000_000 else { throw CocoaError(.fileReadTooLarge) }
        let data = try Data(contentsOf: source)
        guard let image = NSImage(data: data), let rep = image.representations.first, rep.pixelsWide > 0, rep.pixelsHigh > 0 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        // Points: a 144 dpi picture counts half its pixels, like the Finder's preview.
        let size = image.size.width > 0 && image.size.height > 0 ? image.size : CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
        let dir = directory(easel)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let file = dir.appendingPathComponent(element + "." + ext)
        try data.write(to: file, options: .atomic)
        return (file, size)
    }

    func delete(_ easel: EaselID) throws {
        guard valid(easel.rawValue) else { return }
        let dir = directory(easel)
        if FileManager.default.fileExists(atPath: dir.path) { try FileManager.default.removeItem(at: dir) }
    }
}

extension AppStore {
    func runEasel(_ effect: EaselEffect) {
        switch effect {
        case .chooseImage(let window, let easel, let point):
            guard let owner = captureWindow(window), owner.isVisible, owner.attachedSheet == nil else { return }
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.image]
            panel.allowsMultipleSelection = false
            panel.canChooseDirectories = false
            panel.prompt = "Insert"
            panel.message = "Choose a picture to put on the Easel."
            panel.beginSheetModal(for: owner) { [weak self, weak owner] response in
                guard let self, response == .OK, let url = panel.url, owner?.isVisible == true else { return }
                self.dispatch(.user(window, .easel(.importImage(easel, from: url, at: point))))
            }
        case .importImage(let window, let easel, let source, let point, let element):
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    let (file, size) = try await self.easelFiles.importImage(source, easel: easel, element: element)
                    self.dispatch(.system(.easel(.imageImported(window, easel, element: element, file: file, size: size, at: point))))
                } catch {
                    self.dispatch(.system(.easel(.failed(window, easel, "Could not add the picture: " + error.localizedDescription))))
                }
            }
        case .share(let window, var card):
            guard let owner = captureWindow(window), owner.isVisible, owner.attachedSheet == nil else { return }
            // A title typed but not yet committed (the click on Share did not end its editing) is the Easel's title.
            if let typed = windowController(window)?.root.commitEaselTitle(card.id) { card.title = typed }
            guard let png = EaselExport.png(card) else {
                dispatch(.system(.easel(.failed(window, card.id, "Could not draw the Easel."))))
                return
            }
            let panel = NSSavePanel()
            panel.allowedContentTypes = [.png]
            panel.title = "Share Easel"
            panel.prompt = "Save"
            panel.nameFieldStringValue = String(card.title.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").prefix(100)) + ".png"
            SidebarPanelControl.configureTestDirectory(panel)
            panel.beginSheetModal(for: owner) { [weak self] response in
                guard let self, response == .OK, let url = panel.url else { return }
                do {
                    try png.write(to: url, options: .atomic)
                    self.dispatch(.system(.easel(.shared(window, card.id, url))))
                } catch {
                    self.dispatch(.system(.easel(.failed(window, card.id, "Share failed: " + error.localizedDescription))))
                }
            }
        case .deleteFiles(let easel):
            Task { [easelFiles] in try? await easelFiles.delete(easel) }
        }
    }
}
