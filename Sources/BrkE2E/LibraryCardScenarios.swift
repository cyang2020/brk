import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation

/// Owner: F5. The Library's Spaces cards (Arc 1.170's … menu, P30-c; reordering by the move handle), Boosts'
/// Install from File… through the real open panel, and the Downloads row's cancel button against a real transfer.
/// Actual native controls, loopback fixture pages and this scenario's temporary data only.
enum LibraryCardScenarios {
    static let all = [
        Scenario("LibraryDownload-Cancel", "the Library Downloads row's cancel button stops the real transfer at the server", downloadCancel),
    ]

    static let arcRows = ["Change Space Icon…", "Rename Space…", "Edit Theme Color…", "Set Profile", "New Folder", "Live Folders",
                          "Share Space…", "Export “%@” into Folder", "Delete Space"]

    private static func library(_ app: AppUnderTest) throws -> LibrarySnapshot? {
        if case .library(let library)? = try app.view().overlay { return library }
        return nil
    }
    private static func card(_ app: AppUnderTest, _ space: SpaceID) throws -> SpaceManagerRow? { try library(app)?.spaces.first { $0.id == space } }
    private static func center(_ rect: CGRect) -> CGPoint { CGPoint(x: rect.midX, y: rect.midY) }

    /// The rows of `space`'s card menu, opened from its … button through the native menu; chooses `item` ("Submenu ›
    /// Row" for a submenu's row) when given.
    @discardableResult
    private static func cardMenu(_ app: AppUnderTest, _ space: SpaceID, choose item: String? = nil) throws -> [String] {
        let more = try visible(app.native(), .spaceToolsControl("manager-more-\(space)")).frame
        guard case .menuItems(let titles) = try app.send(.captureContextMenu(window: app.window, point: center(more), choose: item)) else {
            throw Check(description: "the card's … menu did not open")
        }
        if let item { try expect(titles.contains(item.components(separatedBy: " › ")[0]), "the card's menu has \(titles), not \(item)") }
        return titles
    }

    private static func createSpace(_ app: AppUnderTest, _ title: String) throws -> SpaceID {
        let before = Set(try app.view().dock.map(\.id))
        try app.dispatch(.space(.create(title: title, icon: .none, theme: SpaceTheme(colors: [ThemePresets.pastel[2]], texture: .grain, intensity: 0.4, appearance: .light))))
        guard let created = try app.view().dock.map(\.id).first(where: { !before.contains($0) }) else { throw Check(description: "\(title) was not created") }
        return created
    }

    @Sendable static func menu(_ app: AppUnderTest) throws {
        let first = try app.view().space.id
        let two = try createSpace(app, "Card Two"), three = try createSpace(app, "Card Three")
        try app.dispatch(.space(.focus(first)))
        try app.dispatch(.library(.open(.spaces)))
        try app.waitUntil("the Spaces page with three cards") { isShown(try app.native(), .spaceToolsControl("manager-more-\(three)")) }
        let rows = try cardMenu(app, two)
        try expect(rows == arcRows.map { $0.replacingOccurrences(of: "%@", with: "Card Two") }, "the card menu is not Arc's nine rows: \(rows)")
        try expect(try library(app) != nil, "opening the card's menu closed the Library")
        try app.screenshot("spaces-cards")
        // New Folder in a space the window does not show: the card shows it, the window stays.
        try cardMenu(app, two, choose: "New Folder")
        try app.waitUntil("New Folder on Card Two's card") {
            if case .folder(let folder)? = try card(app, two)?.pinned.first { return folder.title == "New Folder" }
            return false
        }
        try expect(try app.view().space.id == first && library(app) != nil, "New Folder switched spaces or closed the Library")
        // Rename Space…: Arc's centred dialog over the Library.
        try cardMenu(app, two, choose: "Rename Space…")
        try app.waitUntil("the rename field focused") { try app.native().firstResponder.contains("space-rename-field") }
        try app.press("cmd+a"); try app.type("Card Renamed"); try app.press("return")
        try app.waitUntil("the card renamed") { try card(app, two)?.title == "Card Renamed" && app.view().dialog == nil }
        // Change Space Icon…: the Emoji / Icon popover, pointing at the card while the Library covers the sidebar.
        try cardMenu(app, two, choose: "Change Space Icon…")
        try SpaceToolsScenarios.clickWhenShown(app, "icon-picker-search")
        try app.screenshot("icon-popover-on-card")
        try app.type("blue book")
        try SpaceToolsScenarios.clickWhenShown(app, "icon-result-0")
        try app.waitUntil("the card's icon picked") { try card(app, two)?.icon == .custom(.emoji("📘")) && app.view().dialog == nil }
        // The move handle: dragging the first card one slot right puts its space second.
        let handle = try visible(app.native(), .spaceToolsControl("manager-move-\(first)")).frame
        let pitch = Metrics.library.spacesCardWidth.value + Metrics.library.spacesCardGap.value
        let result = try app.send(.pointerDrag(from: center(handle), to: CGPoint(x: handle.midX + pitch, y: handle.midY), cancel: false))
        guard case .ok = result else { throw Check(description: "pointer drag failed: \(result)") }
        try app.waitUntil("the handle drag reordered the spaces") { try app.view().dock.map(\.id) == [two, first, three] }
        try expect(try library(app)?.spaces.map(\.id) == [two, first, three], "the cards did not follow the new order")
        // Delete Space asks with Arc's dialog (P27); Return confirms.
        try cardMenu(app, three, choose: "Delete Space")
        try app.waitUntil("the delete confirmation") { try app.view().pendingSpaceDeletion?.id == three }
        try app.waitUntil("the delete dialog focused") { try app.native().firstResponder.contains("SpaceAlert") || app.native().firstResponder.contains("ArcDialog") }
        try app.screenshot("delete-confirmation")
        try app.press("return")
        try app.waitUntil("the confirmed deletion removed the space and its card") {
            try !app.view().dock.contains { $0.id == three } && card(app, three) == nil
        }
        try expect(try library(app) != nil, "deleting from a card closed the Library")
        try app.flush(); try app.restart()
        try expect(try app.view().dock.map(\.id) == [two, first], "order or deletion did not persist")
        try expect(try app.view().dock.first { $0.id == two }?.title == "Card Renamed", "the rename did not persist")
        try app.recordWindows("library-card-menu-final")
    }

    @Sendable static func export(_ app: AppUnderTest) throws {
        let address = app.site.url("page2.html?library-card-export")
        let item = try app.load(address)
        try app.waitForPageInput(PageID(window: app.window!, item: item), at: address)
        let space = try app.view().space.id
        let title = try app.view().dock.first { $0.id == space }?.title ?? ""
        try app.dispatch(.library(.open(.spaces)))
        try app.waitUntil("the Spaces page") { isShown(try app.native(), .spaceToolsControl("manager-more-\(space)")) }
        // Share Space…: the export file (Brk's Share is a file export), through the real save panel.
        try cardMenu(app, space, choose: "Share Space…")
        try ImportSyncScenarios.waitPanel(app, "Export")
        let shared = app.dataDirectory.appendingPathComponent("library-card-share.json")
        try FilePanelScenarios.selectSave(app, shared)
        try app.waitUntil("Share Space… wrote the file") { FileManager.default.fileExists(atPath: shared.path) }
        let document = try SidebarDataCodec.decodeExport(Data(contentsOf: shared))
        try expect(String(decoding: try Data(contentsOf: shared), as: UTF8.self).contains("library-card-export"), "the shared file lacks the space's tab: \(document)")
        try FilePanelScenarios.retain(app, shared, label: "share-space")
        try expect(try library(app) != nil, "Share Space… closed the Library")
        // Export “X” into Folder › Bookmarks Folder on Disk…: Brk's folder sheet writes bookmarks.json and .html.
        let destination = app.dataDirectory.appendingPathComponent("library-card-folder", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try app.perform(.selectSheetDirectory(path: destination.path))
        try cardMenu(app, space, choose: "Export “\(title)” into Folder › Bookmarks Folder on Disk…")
        try app.waitUntil("the folder export sheet") { try library(app)?.spaceExportInProgress == true }
        try app.click(.spaceToolsControl("folder-export-path"))
        try app.press("cmd+a"); try app.type(destination.path)
        try app.waitUntil("the folder export wrote both bookmark files", timeout: 15) {
            let folders = (try? FileManager.default.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil)) ?? []
            if folders.contains(where: { FileManager.default.fileExists(atPath: $0.appendingPathComponent("bookmarks.json").path)
                && FileManager.default.fileExists(atPath: $0.appendingPathComponent("bookmarks.html").path) }) { return true }
            _ = try app.send(.sheetButton(title: "Export Here"))
            return false
        }
        let folder = try FileManager.default.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil).first!
        let bookmarks = try JSONDecoder().decode(ExportDocument.self, from: Data(contentsOf: folder.appendingPathComponent("bookmarks.json")))
        try expect(bookmarks.entries.contains { if case .link(_, let url) = $0 { return url == address }; return false }, "the folder export lacks the tab")
        try FilePanelScenarios.retain(app, folder.appendingPathComponent("bookmarks.json"), label: "export-into-folder")
        try app.screenshot("export-complete")
    }


    @Sendable static func downloadCancel(_ app: AppUnderTest) throws {
        let folder = app.dataDirectory.appendingPathComponent("downloads", isDirectory: true)
        try app.dispatch(.settings(.profile(.default, .downloadsDirectory(folder.path))))
        let page = PageID(window: try app.view().id, item: try app.view().content.panes[0].tab)
        try app.waitForPageInput(page, at: app.site.url("index.html"))
        let encoded = String(data: try JSONEncoder().encode(app.site.url("transfer-library-cancel").absoluteString), encoding: .utf8)!
        try app.evaluate(page, "(()=>{let f=document.createElement('iframe');f.style.display='none';f.src=\(encoded);document.body.append(f)})()")
        try app.dispatch(.library(.open(.downloads)))
        var running: DownloadRow?
        try app.waitUntil("bytes arriving", timeout: 12) {
            running = try library(app)?.downloads.first { $0.filename == "transfer-library-cancel.bin" }
            return running?.state == .inProgress && (running?.received ?? 0) > 0
        }
        let id = running!.id
        try app.screenshot("downloading")
        try app.click(.tabTool("download-cancel-\(id)"))
        try app.waitUntil("the row's cancel ended the download") { try library(app)?.downloads.first { $0.id == id }?.state == .cancelled }
        try app.waitUntil("the server saw the transport stop", timeout: 10) { app.site.requestCount("/transfer-library-cancel-stopped") > 0 }
        let bytes = app.site.requestCount("/transfer-library-cancel-bytes")
        try expect(bytes > 0 && bytes < 16_384 * 256, "the cancelled download received \(bytes) bytes")
        Thread.sleep(forTimeInterval: 0.2)
        try expect(app.site.requestCount("/transfer-library-cancel-bytes") == bytes, "the server kept writing after the cancel")
        app.note("server stopped at \(bytes) of \(16_384 * 256) bytes after the row's cancel button")
        try app.screenshot("cancelled")
    }
}
