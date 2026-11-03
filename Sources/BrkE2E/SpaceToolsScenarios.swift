import BrkBase
import BrkControl
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation

/// Actual native controls, public loopback pages and this scenario's temporary data only.
enum SpaceToolsScenarios {
    static let all = [
        Scenario("SpaceTools-1", "toolbar navigation, full URL, header layout, pointer resize and floating CEF sidebar", cefOnly: "native CEF navigation and focus", shell),
        Scenario("SpaceTools-2", "Create a Space flow with theme preset and profile, live theme panel, rename dialog, icon popover and manager", cefOnly: "native editor and profile browsing", editor),
        Scenario("SpaceTools-3", "dock drag, sidebar swipe cancellation/page ownership and confirmed deletion", cefOnly: "native pointer/trackpad sequences", gestures),
        Scenario("SpaceTools-4", "Space manager local folder panel cancellation and public bookmark files", cefOnly: "native folder selection", export),
    ]

    private static func hover(_ app: AppUnderTest, at point: CGPoint) throws {
        let window = try app.native().windowFrame
        let location = CGPoint(x: window.minX + point.x, y: CGDisplayBounds(CGMainDisplayID()).maxY - window.maxY + point.y)
        let result = CGWarpMouseCursorPosition(location)
        try expect(result == .success, "could not place pointer over owned native window: \(result.rawValue)")
        try app.hover(point)
    }
    private static func point(_ rect: CGRect) -> CGPoint { CGPoint(x: rect.midX, y: rect.midY) }
    private static func finishAnimation(_ app: AppUnderTest) throws {
        let start = uptime()
        try app.waitUntil("native transition to finish before capture", timeout: 2) { uptime() - start >= 0.35 }
    }
    private static func perform(_ app: AppUnderTest, _ op: ControlOp) throws {
        let result = try app.send(op)
        guard case .ok = result else { throw Check(description: "native input failed: \(op), result: \(result)") }
    }
    private static func control(_ app: AppUnderTest, _ name: String) throws -> CGRect {
        try visible(app.native(), .spaceToolsControl(name)).frame
    }
    @Sendable static func shell(_ app: AppUnderTest) throws {
        let originalCursor = CGEvent(source: nil)?.location
        defer { if let originalCursor { CGWarpMouseCursorPosition(originalCursor) } }
        let item = try app.load(app.site.url("identity.html?toolbar"))
        let page = PageID(window: app.window!, item: item)
        try app.waitForPageInput(page, at: app.site.url("identity.html?toolbar"))
        try app.press("cmd+shift+d")
        try app.waitUntil("toolbar is visible") { try app.view().sidebar.toolbarVisible }
        try expect(try visible(app.native(), .toolbar).frame.height == AddressToolbarLayout.height, "toolbar geometry")
        try app.dispatch(.settings(.advanced(.showFullURLInToolbar(true))))
        try expect(try app.view().urlPill.toolbarText == app.site.url("identity.html?toolbar").absoluteString, "full URL setting has no consumer")
        try app.click(.toolbarAddress)
        try app.waitUntil("toolbar editor focused") { try app.native().firstResponder.contains("command-bar-input") }
        try app.press("cmd+a"); try app.type(app.site.url("page2.html?toolbar-next").absoluteString); try app.press("return")
        try app.waitForPageInput(page, at: app.site.url("page2.html?toolbar-next"))
        try app.click(.toolbarButton("back"))
        try app.waitForPageInput(page, at: app.site.url("identity.html?toolbar"))
        try app.click(.toolbarButton("forward"))
        try app.waitForPageInput(page, at: app.site.url("page2.html?toolbar-next"))
        let before = try app.native().computed.sidebar!.tablistViewport
        try app.dispatch(.sidebar(.toggleSpaceHeader))
        let after = try app.native().computed.sidebar!.tablistViewport
        try expect(after.minY == before.minY - Metrics.tablist.spaceHeaderHeight.value, "hidden header kept its gap")
        for width in [500.0, 164, 228] {
            let native = try app.native(), handle = try visible(native, .resizeHandle).frame
            let source = point(handle), target = CGPoint(x: source.x + width - (try app.view().sidebar.width), y: source.y)
            try perform(app, .pointerDrag(from: source, to: target, cancel: false))
            try expect(try app.view().sidebar.width == width, "pointer resize did not reach \(width)")
        }
        let hideHandle = try visible(app.native(), .resizeHandle).frame
        let hideStart = point(hideHandle)
        try perform(app, .pointerDrag(from: hideStart, to: CGPoint(x: 48, y: hideStart.y), cancel: false))
        try expect(try !app.view().sidebar.visible && app.view().sidebar.width == 164, "drag below 82 did not hide and retain width")
        try app.dispatch(.sidebar(.toggle))
        let restoreHandle = try visible(app.native(), .resizeHandle).frame
        try perform(app, .pointerDrag(from: point(restoreHandle), to: CGPoint(x: 228, y: restoreHandle.midY), cancel: false))
        try app.flush(); try app.restart()
        try expect(try app.view().sidebar.width == 228 && app.view().sidebar.toolbarVisible && !app.view().sidebar.spaceHeaderVisible, "shell preferences did not restore")
        try app.waitForPageInput(page, at: app.site.url("page2.html?toolbar-next"))
        try app.dispatch(.sidebar(.toggleToolbar)); try app.dispatch(.sidebar(.toggle))
        let card = try app.native().computed.contentArea
        try hover(app, at: CGPoint(x: 3, y: card.midY))
        try app.waitUntil("real tracking reveals floating sidebar") { try app.view().sidebar.peek }
        try expect(near(try app.native().computed.contentArea, card), "floating sidebar moved content")
        try finishAnimation(app)
        try app.screenshot("floating-over-cef")
        guard case .menuItems(let menu) = try app.send(.captureContextMenu(window: app.window, point: point(card))) else { throw Check(description: "floating menu capture missing") }
        try expect(!menu.isEmpty && app.view().sidebar.peek, "native menu dismissed the floating sidebar")
        try app.dispatch(.item(.beginRename(.item(item))))
        try app.waitUntil("floating rename editor focused") { try app.native().firstResponder.contains("rename-field") }
        try app.type("Discarded rename")
        try hover(app, at: CGPoint(x: card.maxX - 20, y: card.midY))
        try expect(try app.view().sidebar.peek, "leaving dismissed an active floating rename")
        try app.press("escape")
        try app.waitUntil("rename cancelled") { try app.view().renaming == nil }
        try hover(app, at: CGPoint(x: card.maxX - 20, y: card.midY))
        try app.waitUntil("leaving floating sidebar dismisses it") { try !app.view().sidebar.peek }
        try app.recordWindows("shell-final")
    }

    /// A control in a popover or the theme panel (its own window) once it is on screen.
    private static func clickWhenShown(_ app: AppUnderTest, _ name: String) throws {
        try app.waitUntil("\(name) on screen") { (try? app.click(.spaceToolsControl(name))) != nil }
    }

    @Sendable static func editor(_ app: AppUnderTest) throws {
        try app.dispatch(.profile(.create(name: "Space Fixture", icon: nil)))
        guard case .settings(let settings) = try app.send(.settings),
              settings.profiles.contains(where: { $0.profile.name == "Space Fixture" }) else { throw Check(description: "fixture profile missing") }
        let before = try app.view().dock.count
        // Arc's Create a Space flow in the sidebar: name, Choose a Theme (the theme panel as a popover; a preset
        // shows on the window at once), the Profile menu, Create Space.
        try app.dispatch(.sidebar(.openDialog(.newSpace)))
        try app.waitUntil("the Create a Space flow") { let n = try app.native(); return isShown(n, .spaceDialog) && !isShown(n, .urlPill) }
        try app.type("Native Work")
        try app.click(.spaceToolsControl("theme"))
        try clickWhenShown(app, "theme-presets-next")
        try app.click(.spaceToolsControl("theme-preset-6"))
        try app.click(.spaceToolsControl("theme-add"))
        try finishAnimation(app)
        try app.screenshot("theme-stage")
        let pill = try control(app, "profile")
        guard case .menuItems(let menu) = try app.send(.captureContextMenu(window: app.window, point: point(pill), choose: "Space Fixture")) else {
            throw Check(description: "profile menu capture missing")
        }
        try expect(menu.contains("Space Fixture") && menu.contains("New Profile…"), "profile menu rows: \(menu)")
        try app.click(.spaceToolsControl("save"))
        try app.waitUntil("created space saved its profile") { try app.view().dock.count == before + 1 && app.view().urlPill.profile?.name == "Space Fixture" }
        let created = try app.view().space.id
        try expect(try app.view().space.title == "Native Work", "name not saved")
        try expect(try app.view().dialog == nil && isShown(try app.native(), .urlPill), "the flow did not give the sidebar back")
        guard case .theme(_, let theme)? = { () -> SpaceDialogSnapshot? in try? app.dispatch(.sidebar(.openDialog(.theme(.current)))); return try? app.view().dialog }() else {
            throw Check(description: "theme panel missing")
        }
        try expect(theme.variants?.light.colors.first?.color == ThemePresets.pastel[6], "the picked preset was not the created theme")
        try expect(theme.variants?.light.colors.count == 2 && theme.variants?.dark.colors.count == 2, "add-color change not saved on both appearances")
        // Edit Theme…: every edit is saved while the panel stays open; Esc closes it.
        try clickWhenShown(app, "theme-appearance-dark")
        try app.waitUntil("dark appearance applied with the panel open") {
            let v = try app.view()
            if case .theme? = v.dialog { return v.theme.scheme == .dark } else { return false }
        }
        try app.click(.spaceToolsControl("theme-presets-next")); try app.click(.spaceToolsControl("theme-presets-next"))
        try app.click(.spaceToolsControl("theme-preset-8"))
        try app.waitUntil("the Drab preset applied") {
            guard case .theme(_, let t)? = try app.view().dialog else { return false }
            return t.variants?.dark.colors.first?.color == ThemePresets.drab[8]
        }
        try app.screenshot("theme-editor")
        try app.press("escape")
        try app.waitUntil("Esc closed the theme panel") { try app.view().dialog == nil }
        // Rename Space: the centred dialog with the name selected.
        try app.dispatch(.sidebar(.openDialog(.rename(.current))))
        try app.waitUntil("rename field focused") { try app.native().firstResponder.contains("space-rename-field") }
        try app.type("Native Work Edited"); try app.press("return")
        try app.waitUntil("renamed") { try app.view().space.title == "Native Work Edited" && app.view().dialog == nil }
        // Change Space Icon…: the Emoji / Icon popover.
        try app.dispatch(.sidebar(.openDialog(.icon(.current))))
        try clickWhenShown(app, "icon-picker-search")
        try app.type("crescent moon")
        try clickWhenShown(app, "icon-result-0")
        try app.waitUntil("icon picked") { try app.view().space.icon == .custom(.emoji("🌙")) && app.view().dialog == nil }
        try app.flush(); try app.restart()
        try expect(try app.view().theme.scheme == .dark, "dark appearance not restored")
        try expect(try app.view().space.id == created && app.view().space.title == "Native Work Edited" && app.view().space.icon == .custom(.emoji("🌙")),
                   "name and icon did not restore")
        try app.dispatch(.library(.open(.spaces)))
        try expect(isShown(try app.native(), .spaceToolsControl("manager")), "Spaces destination missing")
        try finishAnimation(app)
        try app.screenshot("library-spaces")
        try app.click(.spaceToolsControl("manager-search"))
        try app.type("No such fixture space")
        try expect(!isShown(try app.native(), .spaceToolsControl("manager-open-\(created)")), "manager search did not filter cards")
        try app.press("cmd+a"); try app.type("Native Work Edited")
        try expect(isShown(try app.native(), .spaceToolsControl("manager-open-\(created)")), "manager did not restore the matching card")
        try app.click(.spaceToolsControl("manager-new"))
        try app.waitUntil("the Create a Space flow from the manager") { try app.view().dialog == .newSpace }
        try app.type("Cancelled Space")
        try app.click(.spaceToolsControl("cancel"))
        try expect(try app.view().dock.count == before + 1, "cancelled creation changed saved Spaces")
        try app.recordWindows("editor-final")
    }

    @Sendable static func gestures(_ app: AppUnderTest) throws {
        let first = try app.view().space.id
        let scrollURL = app.site.url("spaces-scroll.html")
        let scrollItem = try app.load(scrollURL)
        try app.waitForPageInput(PageID(window: app.window!, item: scrollItem), at: scrollURL)
        let second = try createSpace(app, title: "Second")
        let third = try createSpace(app, title: "Third")
        try app.dispatch(.settings(.advanced(.hapticsOnReorder(false))))
        let f = try app.native().computed.sidebar!
        try perform(app, .pointerDrag(from: point(f.dockSpaces[third]!), to: point(f.dockSpaces[first]!), cancel: true))
        try expect(try app.view().dock.map(\.id) == [first, second, third], "cancelled dock drag changed order")
        let g = try app.native().computed.sidebar!
        try perform(app, .pointerDrag(from: point(g.dockSpaces[third]!), to: point(g.dockSpaces[first]!), cancel: false))
        try expect(try app.view().dock.map(\.id) == [third, first, second], "native dock drag did not reorder")
        try app.click(.dockSpace(first))
        let pageArea = try app.native().computed.contentArea
        try perform(app, .scrollGesture(at: point(pageArea), horizontal: -140, vertical: 0, cancel: false))
        try expect(try app.view().space.id == first, "page scrolling switched Spaces")
        try app.waitUntil("horizontal page gesture reaches actual DOM scrolling") {
            try currentTab(app.view())?.title.hasPrefix("page-scroll:") == true
        }
        let sidebar = try app.native().computed.sidebar!.tablistViewport
        try perform(app, .scrollGesture(at: point(sidebar), horizontal: -140, vertical: 0, cancel: true))
        try expect(try app.view().space.id == first, "cancelled sidebar swipe switched Spaces")
        try perform(app, .scrollGesture(at: point(sidebar), horizontal: -140, vertical: 0, cancel: false))
        try app.waitUntil("sidebar gesture switched to next space") { try app.view().space.id == second }
        for _ in 0..<3 {
            try app.press("cmd+alt+left")
            try expect(try app.view().space.id == first && currentTab(app.view())?.id == scrollItem, "keyboard switch did not restore the Space selection")
            try app.press("cmd+alt+right")
            try expect(try app.view().space.id == second, "rapid keyboard switch did not reach the next Space")
        }
        try app.dispatch(.library(.open(.spaces)))
        try app.click(.spaceToolsControl("manager-delete-\(second)"))
        try expect(try app.view().pendingSpaceDeletion?.id == second, "Delete did not ask for confirmation")
        try app.click(.spaceToolsControl("alert-cancel"))
        try app.waitUntil("cancel preserved the space") { try app.view().pendingSpaceDeletion == nil }
        try expect(try app.view().dock.contains { $0.id == second }, "Cancel deleted the space")
        try app.click(.spaceToolsControl("manager-delete-\(second)"))
        try app.waitUntil("the delete dialog focused") { try app.native().firstResponder.contains("SpaceAlert") || app.native().firstResponder.contains("ArcDialog") }
        try app.press("return")
        try app.waitUntil("confirmed deletion removed the space") { try !app.view().dock.contains { $0.id == second } }
        try expect(try app.view().tabTools.toast?.text == "Space deleted!", "no toast after the deletion")
        try app.flush(); try app.restart()
        try expect(try app.view().dock.map(\.id) == [third, first], "dock order did not persist")
        try app.screenshot("reordered-spaces")
        try app.recordWindows("gestures-final")
    }

    @Sendable static func export(_ app: AppUnderTest) throws {
        let item = try app.load(app.site.url("page2.html?space-export"))
        try app.waitForPageInput(PageID(window: app.window!, item: item), at: app.site.url("page2.html?space-export"))
        let space = try app.view().space.id
        try app.dispatch(.library(.open(.spaces)))
        try app.click(.spaceToolsControl("manager-export-\(space)"))
        try perform(app, .sheetButton(title: "Cancel"))
        try app.waitUntil("export cancellation settled") {
            guard case .library(let library)? = try app.view().overlay else { return false }
            return !library.spaceExportInProgress && library.spaceExportMessage == nil
        }
        let destination = app.dataDirectory.appendingPathComponent("owned-export", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try perform(app, .selectSheetDirectory(path: destination.path))
        try app.click(.spaceToolsControl("manager-export-\(space)"))
        try app.waitUntil("folder export sheet is responsive") { try app.view().overlay != nil }
        try app.click(.spaceToolsControl("folder-export-path"))
        try app.press("cmd+a"); try app.type(destination.appendingPathComponent("missing").path)
        try perform(app, .sheetButton(title: "Export Here"))
        try expect(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty, "invalid destination wrote files")
        guard case .library(let pending)? = try app.view().overlay else { throw Check(description: "export manager closed") }
        try expect(pending.spaceExportInProgress, "invalid folder ended the editable confirmation")
        try app.click(.spaceToolsControl("folder-export-path"))
        try app.press("cmd+a"); try app.type(destination.path)
        try app.waitUntil("native export confirmation creates both local bookmark files", timeout: 15) {
            let folders = (try? FileManager.default.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil)) ?? []
            if folders.contains(where: { FileManager.default.fileExists(atPath: $0.appendingPathComponent("bookmarks.json").path) && FileManager.default.fileExists(atPath: $0.appendingPathComponent("bookmarks.html").path) }) { return true }
            _ = try app.send(.sheetButton(title: "Export Here"))
            return false
        }
        let folder = try FileManager.default.contentsOfDirectory(at: destination, includingPropertiesForKeys: nil).first!
        let document = try JSONDecoder().decode(ExportDocument.self, from: Data(contentsOf: folder.appendingPathComponent("bookmarks.json")))
        let html = try String(contentsOf: folder.appendingPathComponent("bookmarks.html"), encoding: .utf8)
        try expect(document.entries.contains { if case .link(_, let url) = $0 { return url == app.site.url("page2.html?space-export") }; return false }, "export did not use the saved public document URL")
        try expect(html.contains("space-export"), "HTML export missing the fixture URL")
        // Preserve actual output after the runner removes its temporary data root.
        let evidence = app.shotsDirectory.deletingLastPathComponent().appendingPathComponent("exports")
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        for name in ["bookmarks.json", "bookmarks.html"] {
            try Data(contentsOf: folder.appendingPathComponent(name)).write(to: evidence.appendingPathComponent(name))
        }
        try app.screenshot("export-complete")
        try app.recordWindows("export-final")
    }
}
