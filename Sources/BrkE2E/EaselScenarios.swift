import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import Foundation
import ImageIO

/// Easels on the real app (Q09 a, Q09 c, P32 c): File > New Easel and its board, drawing with the toolbar through
/// real pointer events, selecting, moving and deleting, pictures, the board after a restart, the Library's cards and
/// the delete confirmation.
enum EaselScenarios {
    static let all = [
        Scenario("EaselNew", "File > New Easel and Ctrl+Shift+E: a Pinned row, the board with its title selected for typing, Share in the pill", newEasel),
        Scenario("EaselDraw", "toolbar shapes, arrow, freehand and text through pointer events; select, move, delete, duplicate; a picture through the panel's import", draw),
        Scenario("EaselReopen", "a drawn board and its picture are the same after quitting and relaunching", reopen),
        Scenario("EaselLibrary", "the Library's Easels page lists a card per Easel; a card opens its Easel", library),
        Scenario("EaselDelete", "a card's menu asks first (Q09 c); Cancel keeps it, Delete removes the board, its row and its pictures", delete),
        Scenario("EaselResize", "a selected shape's corner handle resizes it through pointer events; the opposite corner stays", resize),
        Scenario("EaselCapture", "a Media capture's Insert in Easel puts the screenshot on the shown board as a picture", insertCapture),
        Scenario("EaselExport", "the pill's Share saves the board as a PNG through the save panel", export),
    ]

    /// A two-colour 160 x 100 PNG (left blue #3478F6, right red #F25E6B).
    static let picture = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAKAAAABkCAIAAACO1KzYAAAA9klEQVR42u3RMQ0AMAgAMERNDwZmYLp3cGODhCZ10DivVvl5VwnBggULFixYsGDBggULFixYsGDBggULFixYsGDBggULFixYsGDBggULFixYsGDBggULFixYsGDBggULFixYsGDBggULFixYsGDBggULFixYsGDBggULFixYsGDBggULFixYsGDBggULFixYsGDBggULFixYsGDBggULFixYsGDBggULFixYsGDBggULFixYsGDBggULFixYsGDBggULFixYsGDBggULFixYsGDBggULFixYsGDBggULFixYsGDBggULFixYsGDBggULFixYsOB5GvsDIGjjKq89AAAAAElFTkSuQmCC")!

    // MARK: Helpers

    /// Makes an Easel through File > New Easel and returns its id and row.
    @discardableResult
    static func make(_ app: AppUnderTest) throws -> (EaselID, ItemID) {
        let before = try app.view().space.pinned.rows.count
        try app.perform(.menuAction(ActionID.newEasel.rawValue))
        try app.waitUntil("File > New Easel adds a row and shows its board") {
            let v = try app.view()
            return v.space.pinned.rows.count == before + 1 && !v.easels.isEmpty
        }
        guard case .tab(let row)? = try app.view().space.pinned.rows.last, let id = EaselPage.id(of: row.url) else {
            throw Check(description: "the new row is not an Easel's")
        }
        try app.waitUntil("the board is on screen") { isShown(try app.native(), .easelBoard) }
        return (id, row.id)
    }

    static func board(_ app: AppUnderTest) throws -> EaselSnapshot {
        guard let board = try app.view().easels.first else { throw Check(description: "no board is shown") }
        return board
    }

    /// Board point -> window point: the board's x 0 is the card's centre, its y 0 the card's top.
    static func point(_ app: AppUnderTest, _ p: CGPoint) throws -> CGPoint {
        let card = try visible(app.native(), .easelBoard).frame
        return CGPoint(x: card.midX + p.x, y: card.minY + p.y)
    }

    /// Real pointer events: down, every intermediate point dragged, up.
    static func stroke(_ app: AppUnderTest, _ points: [CGPoint]) throws {
        let window = try points.map { try point(app, $0) }
        try app.perform(.pointer(window: app.window, phase: .down, point: window[0]))
        for p in window.dropFirst() { try app.perform(.pointer(window: app.window, phase: .dragged, point: p)) }
        try app.perform(.pointer(window: app.window, phase: .up, point: window[window.count - 1]))
    }

    static func tool(_ app: AppUnderTest, _ name: String) throws { try app.click(.easelControl("tool-" + name)) }

    static func waitForElements(_ app: AppUnderTest, _ count: Int, _ what: String) throws {
        try app.waitUntil(what) { try board(app).elements.count == count }
    }

    /// Writes the fixture picture into the data directory and puts it on the board as the image tool's panel would.
    static func addPicture(_ app: AppUnderTest, _ id: EaselID, at p: CGPoint) throws -> EaselElement {
        let source = app.dataDirectory.appendingPathComponent("fixture-picture.png")
        try picture.write(to: source)
        let before = try board(app).elements.count
        try app.dispatch(.easel(.importImage(id, from: source, at: p)))
        try waitForElements(app, before + 1, "the picture is copied and placed")
        guard let element = try board(app).elements.last, element.shape == .image, let file = element.image else {
            throw Check(description: "the last element is not a picture")
        }
        try expect(file.path.hasPrefix(app.dataDirectory.appendingPathComponent("Easels/\(id.rawValue)").path), "the picture was not copied into the data directory: \(file.path)")
        try expect(try Data(contentsOf: file) == picture, "the copied picture differs from the source")
        return element
    }

    // MARK: Scenarios

    @Sendable static func newEasel(_ app: AppUnderTest) throws {
        let (id, row) = try make(app)
        let v = try app.view()
        guard case .tab(let tab)? = v.space.pinned.rows.last else { throw Check(description: "no row") }
        try expect(tab.title == "Untitled Easel" && tab.status == .current, "the row is \(tab.title) \(tab.status)")
        try expect(tab.favicon == EaselPage.favicon, "the row has no Easel icon")
        try expect(v.urlPill.share == id && v.urlPill.host == "Share", "the pill shows \(v.urlPill.host ?? "nil")")
        try expect(try board(app).editingTitle, "the new Easel's title is not selected")
        try expect(!(try app.native().pages.keys.contains { $0.item == row }), "a browser was made for the board")
        let n = try app.native()
        let card = try visible(n, .card(0)).frame
        let shown = try visible(n, .easelBoard)
        try expect(near(shown.frame, card, tolerance: 1), "the board \(shown.frame) is not on the card \(card)")
        // Q09 a: the title box at the top centre with the + Aa − card left of it, the toolbar bottom left, the person button bottom right.
        let title = try visible(n, .easelControl("title")).frame
        try expect(abs(title.midX - card.midX) < 1 && abs(title.minY - (card.minY + 37.5)) < 2, "the title is at \(title) in \(card)")
        let font = try visible(n, .easelControl("font-tool")).frame
        try expect(font.maxX < title.minX && abs(font.width - 36) < 0.5, "the + Aa − card is at \(font)")
        let toolbar = try visible(n, .easelControl("toolbar")).frame
        try expect(abs(toolbar.minX - (card.minX + 12)) < 1 && abs(toolbar.maxY - (card.maxY - 12)) < 1 && abs(toolbar.height - 44) < 0.5,
                   "the toolbar is at \(toolbar)")
        for name in ["select", "image", "text", "ellipse", "rectangle", "arrow", "pen"] { _ = try visible(n, .easelControl("tool-" + name)) }
        _ = try visible(n, .easelControl("duplicate"))
        let person = try visible(n, .easelControl("person")).frame
        try expect(abs(person.maxX - (card.maxX - 12)) < 1 && abs(person.maxY - (card.maxY - 12)) < 1, "the person button is at \(person)")
        try app.waitUntil("the title takes the keyboard") { try app.native().firstResponder.contains("easel-title") }
        _ = try app.screenshot("easel-new")
        // Typing replaces the selected title; Return keeps it and the row follows.
        try app.type("Trip plan")
        try app.press("return")
        try app.waitUntil("the typed title is saved") { try board(app).title == "Trip plan" }
        try app.waitUntil("the row is renamed") {
            guard case .tab(let renamed)? = try app.view().space.pinned.rows.last else { return false }
            return renamed.title == "Trip plan"
        }
        // The key equivalent makes another (Ctrl+Shift+E).
        let rows = try app.view().space.pinned.rows.count
        try app.press("ctrl+shift+e")
        try app.waitUntil("Ctrl+Shift+E adds a second Easel") { try app.view().space.pinned.rows.count == rows + 1 && board(app).title == "Untitled Easel" }
        _ = try app.screenshot("easel-new-second")
    }

    @Sendable static func draw(_ app: AppUnderTest) throws {
        let (id, _) = try make(app)
        // Rectangle, ellipse and arrow by dragging; each returns to the select tool.
        try tool(app, "rectangle")
        try stroke(app, [CGPoint(x: -300, y: 200), CGPoint(x: -250, y: 240), CGPoint(x: -160, y: 290)])
        try waitForElements(app, 1, "a rectangle")
        let rectangle = try board(app).elements[0]
        try expect(rectangle.shape == .rectangle && near(rectangle.frame, CGRect(x: -300, y: 200, width: 140, height: 90), tolerance: 1),
                   "the rectangle is \(rectangle.shape) \(rectangle.frame)")
        try app.waitUntil("the new shape is selected") { isShown(try app.native(), .easelControl("selection")) }
        try tool(app, "ellipse")
        try stroke(app, [CGPoint(x: -100, y: 200), CGPoint(x: 0, y: 300)])
        try waitForElements(app, 2, "an ellipse")
        try tool(app, "arrow")
        try stroke(app, [CGPoint(x: 60, y: 300), CGPoint(x: 120, y: 260), CGPoint(x: 200, y: 210)])
        try waitForElements(app, 3, "an arrow")
        let arrow = try board(app).elements[2]
        try expect(arrow.shape == .arrow && arrow.points.count == 2 && abs(arrow.points[1].x - 200) < 1, "the arrow is \(arrow)")
        // Freehand keeps every point of the stroke.
        try tool(app, "pen")
        let wave = (0...24).map { CGPoint(x: -300 + Double($0) * 12, y: 400 + sin(Double($0) / 2) * 24) }
        try stroke(app, wave)
        try waitForElements(app, 4, "a freehand stroke")
        let ink = try board(app).elements[3]
        try expect(ink.shape == .ink && ink.points.count >= 20, "the stroke kept \(ink.points.count) points")
        // Text: click, type, Return.
        try tool(app, "text")
        try app.click(at: try point(app, CGPoint(x: 80, y: 420)))
        try app.waitUntil("the text field takes the keyboard") { try app.native().firstResponder.contains("easel-text-editor") }
        try app.type("Hello board")
        try app.press("return")
        try waitForElements(app, 5, "a text box")
        let typed = try board(app).elements[4].text
        try expect(typed == "Hello board", "the text box reads \(typed)")
        let picture = try addPicture(app, id, at: CGPoint(x: 300, y: 400))
        _ = try app.screenshot("easel-drawn")

        // Select the rectangle with a click, move it by dragging, then delete it with the Delete key.
        try tool(app, "select")
        try app.click(at: try point(app, CGPoint(x: -230, y: 245)))
        // The selection frame is the rectangle's box 6 pt out: 152 x 102 (the text box was selected before).
        try app.waitUntil("a click selects the rectangle") {
            let n = try app.native()
            guard isShown(n, .easelControl("selection")), let frame = n.actual[ViewID.easelControl("selection").identifier]?.frame else { return false }
            return abs(frame.width - 152) < 1 && abs(frame.height - 102) < 1
        }
        let before = try visible(app.native(), .easelControl("selection")).frame
        try stroke(app, [CGPoint(x: -230, y: 245), CGPoint(x: -210, y: 260), CGPoint(x: -190, y: 275)])
        try app.waitUntil("the rectangle moved by the drag") {
            guard let moved = try board(app).elements.first(where: { $0.id == rectangle.id }) else { return false }
            return near(moved.frame, rectangle.frame.offsetBy(dx: 40, dy: 30), tolerance: 1)
        }
        var after = before
        do {
            try app.waitUntil("the selection follows the rectangle") {
                after = try visible(app.native(), .easelControl("selection")).frame
                return abs(after.minX - before.minX - 40) < 1 && abs(after.minY - before.minY - 30) < 1
            }
        } catch { throw Check(description: "the selection did not follow: \(before) -> \(after)") }
        _ = try app.screenshot("easel-moved")
        try app.click(.easelControl("duplicate"))
        try waitForElements(app, 7, "duplicate copies the selection")
        try app.waitUntil("the board has the keyboard") { try app.native().firstResponder.contains("easel-board") }
        try app.type("\u{7F}")
        try waitForElements(app, 6, "Delete removes the selected copy")
        try app.click(at: try point(app, CGPoint(x: -190, y: 275)))
        try app.waitUntil("the original is selected again") { isShown(try app.native(), .easelControl("selection")) }
        try app.type("\u{7F}")
        try waitForElements(app, 5, "Delete removes the rectangle")
        try expect(!(try board(app).elements.contains { $0.id == rectangle.id }), "the rectangle is still there")
        try expect(try board(app).elements.contains { $0.id == picture.id }, "deleting the rectangle took the picture")
        // The image tool opens a picture panel on the window; Esc puts it away and adds nothing.
        try tool(app, "image")
        try app.waitUntil("the picture panel is open") { if case .menuItems = try? app.send(.sidebarPanel(window: app.window, action: .inspect)) { true } else { false } }
        _ = try app.screenshotSheet("easel-image-panel")
        try app.perform(.answerSavePanel(window: app.window, path: nil))
        app.sleep(0.8)
        try expect(try board(app).elements.count == 5, "cancelling the panel changed the board")
        _ = try app.screenshot("easel-after-delete")
    }

    /// A101: the corner handles do what they show. Drag the bottom-right handle of a selected rectangle: it grows from
    /// its top-left corner, which stays; the board keeps the new size after a restart.
    @Sendable static func resize(_ app: AppUnderTest) throws {
        _ = try make(app)
        try tool(app, "rectangle")
        try stroke(app, [CGPoint(x: -300, y: 200), CGPoint(x: -250, y: 240), CGPoint(x: -160, y: 290)])
        try waitForElements(app, 1, "a rectangle")
        let before = try board(app).elements[0]
        try app.waitUntil("the new shape is selected") { isShown(try app.native(), .easelControl("selection")) }
        let outset = 6.0
        try stroke(app, [CGPoint(x: before.frame.maxX + outset, y: before.frame.maxY + outset), CGPoint(x: before.frame.maxX + 40, y: before.frame.maxY + 30),
                         CGPoint(x: before.frame.maxX + 80, y: before.frame.maxY + 60)])
        try app.waitUntil("the handle resized the rectangle") { try board(app).elements.first.map { abs($0.frame.width - before.frame.width) > 40 } ?? false }
        let after = try board(app).elements[0]
        try expect(abs(after.frame.minX - before.frame.minX) <= 1 && abs(after.frame.minY - before.frame.minY) <= 1, "the top-left corner moved: \(before.frame) -> \(after.frame)")
        try expect(abs(after.frame.maxX - (before.frame.maxX + 80)) <= 2 && abs(after.frame.maxY - (before.frame.maxY + 60)) <= 2, "the corner did not follow the pointer: \(after.frame)")
        _ = try app.screenshot("easel-resized")
        try app.flush(); try app.restart()
        try app.waitUntil("the board is shown after the restart") { !(try app.view().easels.isEmpty) }
        try expect(try near(board(app).elements[0].frame, after.frame, tolerance: 0.5), "the new size did not survive a restart")
    }

    /// A101's "with captures": a full-page capture saved to the Library, then Media's Insert in Easel with an Easel
    /// under the Library puts the capture's PNG on that board.
    @Sendable static func insertCapture(_ app: AppUnderTest) throws {
        let item = try app.load(app.site.url("page2.html"))
        try app.waitForPageInput(PageID(window: app.window!, item: item), at: app.site.url("page2.html"))
        try app.dispatch(.capture(.begin(.fullPage)))
        try app.waitUntil("Screenshot Copied to Clipboard toast", timeout: 20) { try app.view().capture == nil && app.view().tabTools.toast?.text == "Screenshot Copied to Clipboard" }
        try app.dispatch(.capture(.act(.library)))   // the toast's Save
        let (_, _) = try make(app)
        try app.dispatch(.library(.open(.media)))
        var record: String?
        try app.waitUntil("the capture is in Media", timeout: 20) {
            guard case .library(let library)? = try app.view().overlay else { return false }
            record = library.captures.first?.id
            guard let record else { return false }
            return isShown(try app.native(), .tabTool("capture-card-" + record))
        }
        let card = try visible(app.native(), .tabTool("capture-card-" + record!)).frame
        guard case .menuItems(let titles) = try app.send(.captureContextMenu(window: app.window, point: CGPoint(x: card.midX, y: card.midY), choose: "Insert in Easel")) else {
            throw Check(description: "the capture card's menu did not open")
        }
        try expect(titles.contains("Insert in Easel"), "the capture card's menu has \(titles)")
        try app.waitUntil("the capture is on the board", timeout: 15) { try board(app).elements.contains { $0.shape == .image && $0.image != nil } }
        guard let picture = try board(app).elements.first(where: { $0.shape == .image }), let file = picture.image else { throw Check(description: "no picture") }
        try expect(file.path.hasPrefix(app.dataDirectory.appendingPathComponent("Easels").path), "the picture is not in the board's folder: \(file.path)")
        try expect(try Data(contentsOf: file).prefix(8) == Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]), "the picture is not a PNG")
        try app.dispatch(.library(.close))
        _ = try app.screenshot("easel-capture")
    }

    /// A101's "export the result": the pill's Share (🔒 Share) opens the real save panel; Cancel writes nothing; Save,
    /// pressed through Accessibility as `FilePanelScenarios` does (keys posted to this remote panel do not reach it),
    /// writes the board as a PNG that has the drawn ellipse on it.
    @Sendable static func export(_ app: AppUnderTest) throws {
        guard FilePanelScenarios.usesAccessibility else { throw Skipped(description: FilePanelScenarios.gestureGap) }
        _ = try make(app)
        try app.press("escape")
        try tool(app, "ellipse")
        try stroke(app, [CGPoint(x: -100, y: 200), CGPoint(x: 0, y: 300)])
        try waitForElements(app, 1, "an ellipse")
        try app.click(.urlPill)
        try ImportSyncScenarios.waitPanel(app, "Share Easel")
        try ImportSyncScenarios.panel(app, .button("Cancel"))
        try app.waitUntil("Cancel closes the panel") { try app.native().sheetClass == nil }
        try expect(try FileManager.default.contentsOfDirectory(atPath: app.dataDirectory.path).filter { $0.hasSuffix(".png") }.isEmpty, "Cancel wrote a file")
        try app.click(.urlPill)
        try ImportSyncScenarios.waitPanel(app, "Share Easel")
        guard case .menuItems(let controls) = try app.send(.sidebarPanel(window: nil, action: .inspect)) else { throw Check(description: "no panel to read") }
        try expect(controls.last == "name:Untitled Easel.png", "the panel suggests \(controls.last ?? "nothing")")
        let destination = app.dataDirectory.appendingPathComponent("easel-share.png")
        try FilePanelScenarios.selectSave(app, destination)
        try app.waitUntil("Saved toast") { try app.view().tabTools.toast?.text == "Saved easel-share.png" }
        try app.waitUntil("the panel is gone") { try app.native().sheetClass == nil }
        let bytes = try Data(contentsOf: destination)
        guard let source = CGImageSourceCreateWithData(bytes as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              CGImageSourceGetType(source) as String? == "public.png" else { throw Check(description: "the shared file is not a PNG (\(bytes.count) bytes)") }
        let pixels = PixelGrid(image)
        var inked = 0
        for y in stride(from: 0, to: pixels.height, by: 2) { for x in stride(from: 0, to: pixels.width, by: 2) where pixels.isInked(x: x, y: y) { inked += 1 } }
        try expect(inked > 20, "the PNG (\(pixels.width)×\(pixels.height)) has no drawing on it")
        try FilePanelScenarios.retain(app, destination, label: "easel")
        app.note("REAL PANEL: Share opened NSSavePanel; AX Cancel wrote nothing; AX set the name and pressed Save; the PNG is \(pixels.width)×\(pixels.height) with \(inked) inked samples.")
    }

    /// An image's pixels as 8-bit RGBA, for checking that something was drawn on it.
    private struct PixelGrid {
        let width: Int, height: Int, bytes: [UInt8]
        init(_ image: CGImage) {
            let width = image.width, height = image.height
            var data = [UInt8](repeating: 0, count: width * height * 4)
            data.withUnsafeMutableBytes { raw in
                CGContext(data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                          space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?
                    .draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            }
            self.width = width; self.height = height; bytes = data
        }
        /// Darker than the board's near-white background.
        func isInked(x: Int, y: Int) -> Bool {
            let o = (y * width + x) * 4
            return bytes[o + 3] > 0 && min(bytes[o], bytes[o + 1], bytes[o + 2]) < 200
        }
    }

    @Sendable static func reopen(_ app: AppUnderTest) throws {
        let (id, row) = try make(app)
        try app.type("Kept board")
        try app.press("return")
        try app.waitUntil("the title is saved") { try board(app).title == "Kept board" }
        try tool(app, "ellipse")
        try stroke(app, [CGPoint(x: -200, y: 220), CGPoint(x: -80, y: 320)])
        try tool(app, "pen")
        try stroke(app, (0...12).map { CGPoint(x: 0 + Double($0) * 10, y: 300 - Double($0 % 3) * 12) })
        try waitForElements(app, 2, "an ellipse and a stroke")
        let picture = try addPicture(app, id, at: CGPoint(x: 260, y: 300))
        let drawn = try board(app).elements
        _ = try app.screenshot("easel-before-restart")
        try app.flush()
        try app.restart()
        try app.waitUntil("the Easel's row survives the restart") { try app.view().space.pinned.rows.contains { $0.id == row } }
        try app.dispatch(.tab(.focus(row)))
        try app.waitUntil("its board is shown again") { try app.view().easels.first?.id == id && isShown(try app.native(), .easelBoard) }
        let shown = try board(app)
        try expect(shown.title == "Kept board", "the title came back as \(shown.title)")
        try expect(shown.elements == drawn, "the board changed across the restart")
        try expect(FileManager.default.fileExists(atPath: picture.image!.path), "the picture's copy is gone")
        try expect(try app.view().urlPill.share == id, "the pill is not the Share button after the restart")
        _ = try app.screenshot("easel-after-restart")
    }

    @Sendable static func library(_ app: AppUnderTest) throws {
        let (first, firstRow) = try make(app)
        try app.press("return")
        try tool(app, "rectangle")
        try stroke(app, [CGPoint(x: -120, y: 220), CGPoint(x: 120, y: 360)])
        try waitForElements(app, 1, "a rectangle on the first Easel")
        let (second, _) = try make(app)
        try app.dispatch(.library(.open(.easelsAndNotes)))
        try app.waitUntil("the Easels page lists both") {
            guard case .library(let library)? = try app.view().overlay else { return false }
            return Set(library.easels.map(\.id)) == [first, second]
        }
        try app.waitUntil("a card per Easel") { let n = try app.native(); return isShown(n, .easelCard(first)) && isShown(n, .easelCard(second)) }
        let n = try app.native()
        let a = try visible(n, .easelCard(first)).frame, b = try visible(n, .easelCard(second)).frame
        try expect(abs(a.width - 132) < 0.5 && abs(a.height - 132) < 0.5, "a card is \(a.size)")
        try expect(abs(a.minY - b.minY) < 0.5 && abs(abs(a.minX - b.minX) - 148) < 0.5, "two cards to a row, 16 apart: \(b) \(a)")
        try expect(abs(min(a.minX, b.minX) - 124) < 1 && abs(a.minY - 60) < 1, "the first card is at \(min(a.minX, b.minX)), \(a.minY) (P32 c: 124, 60)")
        _ = try app.screenshot("easel-library")
        // A card opens its Easel.
        try app.click(.easelCard(first))
        try app.waitUntil("the card opens the Easel") { let v = try app.view(); return v.overlay == nil && v.easels.first?.id == first }
        try expect(currentTab(try app.view())?.id == firstRow, "the Easel's own row is not the one shown")
    }

    @Sendable static func delete(_ app: AppUnderTest) throws {
        let (id, row) = try make(app)
        try app.press("return")
        try tool(app, "rectangle")
        try stroke(app, [CGPoint(x: -120, y: 220), CGPoint(x: 120, y: 360)])
        let picture = try addPicture(app, id, at: CGPoint(x: 0, y: 460))
        let folder = picture.image!.deletingLastPathComponent()
        try app.dispatch(.library(.open(.easelsAndNotes)))
        try app.waitUntil("the card is listed") { isShown(try app.native(), .easelCard(id)) }
        let card = try visible(app.native(), .easelCard(id)).frame
        func chooseDelete() throws {
            guard case .menuItems(let titles) = try app.send(.captureContextMenu(window: app.window, point: CGPoint(x: card.midX, y: card.midY), choose: "Delete…")) else {
                throw Check(description: "the card's menu did not open")
            }
            try expect(titles == ["Open", "Share…", "Delete…"], "the card's menu is \(titles)")
            try app.waitUntil("Delete asks first") { try app.view().pendingEaselDeletion?.id == id }
        }
        try chooseDelete()
        try app.waitUntil("the confirmation takes the keyboard") { try app.native().firstResponder.contains("SpaceAlert") || app.native().firstResponder.contains("ArcDialog") }
        _ = try visible(app.native(), .spaceDialog)
        _ = try app.screenshot("easel-delete-confirm")
        try app.click(.spaceToolsControl("alert-cancel"))
        try app.waitUntil("Cancel closes the confirmation") { try app.view().pendingEaselDeletion == nil }
        try expect(try app.view().space.pinned.rows.contains { $0.id == row }, "Cancel deleted the Easel")
        try chooseDelete()
        try app.waitUntil("the confirmation takes the keyboard again") { try app.native().firstResponder.contains("SpaceAlert") || app.native().firstResponder.contains("ArcDialog") }
        try app.press("return")
        try app.waitUntil("Delete removes the Easel, its card and its row") {
            let v = try app.view()
            guard case .library(let library)? = v.overlay else { return false }
            return library.easels.isEmpty && !v.space.pinned.rows.contains { $0.id == row }
        }
        try app.waitUntil("its pictures are deleted") { !FileManager.default.fileExists(atPath: folder.path) }
        _ = try app.screenshot("easel-deleted")
        try app.flush()
        try app.restart()
        try expect(!(try app.view().space.pinned.rows.contains { $0.id == row }), "the deleted Easel's row came back")
        try app.dispatch(.library(.open(.easelsAndNotes)))
        try app.waitUntil("the Library shows no Easel after the restart") {
            guard case .library(let library)? = try app.view().overlay else { return false }
            return library.easels.isEmpty
        }
    }
}
