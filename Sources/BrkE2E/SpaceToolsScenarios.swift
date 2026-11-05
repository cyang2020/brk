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
        Scenario("R56-SwipeReal", "two-finger swipes posted to the window server over the tab list switch Spaces (clean, slanted start, wobbly, flick with inertia, slow while moving), one whose fingers stop short of the middle does not, vertical ones scroll the list, and a swipe still works after the list scrolled", cefOnly: "real scroll events through the window server", realSwipes),
        Scenario("R57-SwipeFollows", "mid-swipe the column follows the fingers at half their travel with the next Space's rows beside it, Favorites and the pill stay, the colors go between the two themes, it settles on Arc's spring; past the last Space it presses and a full ring opens Create a Space; before the first it brings the Library in", cefOnly: "real scroll events through the window server", swipeFollows),
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

    /// A control in a popover or the theme panel (its own window) once it is on screen and settled.
    static func clickWhenShown(_ app: AppUnderTest, _ name: String) throws {
        let start = uptime()
        try app.waitUntil("\(name) settled") { uptime() - start >= 0.6 }
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
        try clickWhenShown(app, "theme-preset-6")
        try clickWhenShown(app, "theme-add")
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
        // The panel opens on the page of the space's color (Pastel); the next page is Drab.
        try clickWhenShown(app, "theme-presets-next")
        try clickWhenShown(app, "theme-preset-8")
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
        try app.type("blue book")
        try clickWhenShown(app, "icon-result-0")
        try app.waitUntil("icon picked") { try app.view().space.icon == .custom(.emoji("📘")) && app.view().dialog == nil }
        try app.flush(); try app.restart()
        try expect(try app.view().theme.scheme == .dark, "dark appearance not restored")
        try expect(try app.view().space.id == created && app.view().space.title == "Native Work Edited" && app.view().space.icon == .custom(.emoji("📘")),
                   "name and icon did not restore")
        try app.dispatch(.library(.open(.spaces)))
        try expect(isShown(try app.native(), .spaceToolsControl("manager")), "Spaces destination missing")
        try finishAnimation(app)
        try app.screenshot("library-spaces")
        // Arc's Space manager has no search: every space has its card, with its name.
        try expect(isShown(try app.native(), .spaceToolsControl("manager-open-\(created)")), "the created space has no card")
        guard case .library(let manager)? = try app.view().overlay else { throw Check(description: "Space manager closed") }
        try expect(manager.spaces.contains { $0.id == created && $0.title == "Native Work Edited" }, "the card lost the edited name")
        // The card's Edit Theme Color… (its … menu, P30-c) and its pencil open the theme panel beside the Library.
        try managerMenu(app, created, choose: "Edit Theme Color…")
        try app.waitUntil("Edit Theme Color… opened the theme panel") { if case .theme(created, _)? = try app.view().dialog { return true } else { return false } }
        try clickWhenShown(app, "theme-appearance-light")
        // The space's Drab navy under the light button: a light window that keeps the light ink over a white wash (r5-6).
        try app.waitUntil("the panel edits the card's space") {
            let v = try app.view()
            if case .theme(created, let t)? = v.dialog { return t.appearance == .light && v.theme.wash.red == 1 } else { return false }
        }
        guard case .library? = try app.view().overlay else { throw Check(description: "the theme panel closed the Library") }
        try app.press("escape")
        try app.waitUntil("Esc closed the card's theme panel and kept the Library") {
            let v = try app.view()
            if case .library? = v.overlay { return v.dialog == nil } else { return false }
        }
        try app.click(.spaceToolsControl("manager-edit-\(created)"))
        try app.waitUntil("the pencil opened the theme panel") { if case .theme(created, _)? = try app.view().dialog { return true } else { return false } }
        try app.press("escape")
        try app.waitUntil("Esc closed the pencil's theme panel") { try app.view().dialog == nil }
        try app.click(.spaceToolsControl("manager-new"))
        try app.waitUntil("the Create a Space flow from the manager") { try app.view().dialog == .newSpace }
        try app.type("Cancelled Space")
        try app.click(.spaceToolsControl("cancel"))
        try expect(try app.view().dock.count == before + 1, "cancelled creation changed saved Spaces")
        try app.recordWindows("editor-final")
    }

    /// The user's report of 2026-11-05: the Space swipe was almost never recognised. With events injected in-process
    /// it always passed; on the real path the list's scroll view took every gesture after its first event.
    @Sendable static func realSwipes(_ app: AppUnderTest) throws {
        let first = try app.view().space.id
        var tabs: [ItemID] = []
        for n in 1...6 {
            let url = app.site.url("page2.html?swipe=\(n)")
            let item = try app.load(url)
            try app.waitForPageInput(PageID(window: app.window!, item: item), at: url)
            tabs.append(item)
        }
        let second = try createSpace(app, title: "Second")
        try app.dispatch(.settings(.advanced(.hapticsOnReorder(false))))
        try app.click(.dockSpace(first))
        try app.waitUntil("back on the first Space") { try app.view().space.id == first }
        // A short window, so the six rows overflow the list.
        let frame = try app.native().windowFrame
        try app.setWindowFrame(CGRect(x: frame.minX, y: frame.minY, width: frame.width, height: 420))
        defer { try? app.setWindowFrame(frame) }
        try finishAnimation(app)
        let window = app.window!
        func list() throws -> CGPoint { point(try app.native().computed.sidebar!.tablistViewport) }
        func rowY() throws -> Double { Double(try app.native().actual[ViewID.row(tabs[0]).identifier]!.frame.minY) }
        func swipe(_ steps: [(Double, Double)], inertia: [(Double, Double)] = []) throws {
            try PhysicalPointer.swipe(app, at: try list(), steps: steps, inertia: inertia, window: window)
        }
        func expectSwitch(_ name: String, to space: SpaceID, _ steps: [(Double, Double)], inertia: [(Double, Double)] = []) throws {
            try swipe(steps, inertia: inertia)
            try app.waitUntil("\(name) switched Spaces") { try app.view().space.id == space }
            try finishAnimation(app)
        }
        let left = Array(repeating: (-15.0, 0.0), count: 10), right = Array(repeating: (15.0, 0.0), count: 10)
        // Fingers to the left: the next Space; to the right: back.
        try expectSwitch("a clean swipe left", to: second, left)
        try expectSwitch("a clean swipe right", to: first, right)
        // The fingers land moving slightly down before going sideways.
        try expectSwitch("a swipe with a slanted start", to: second, [(-1, 2), (-3, 1)] + Array(repeating: (-15.0, 0.0), count: 9))
        try expectSwitch("a wobbly swipe right", to: first, [(8, 1), (10, -1), (12, 2), (14, -1), (14, 1), (14, 0), (14, 0), (14, 0)])
        // 40 points with the fingers down, the rest is inertia.
        try expectSwitch("a flick left", to: second, [(-10, 0), (-14, 0), (-16, 0)], inertia: [(-14, 0), (-10, 0), (-7, 0), (-4, 0), (-2, 0)])
        try expectSwitch("a flick right", to: first, [(10, 0), (14, 0), (16, 0)], inertia: [(14, 0), (10, 0), (7, 0), (4, 0), (2, 0)])
        // 60 points, slowly, and the fingers stop before lifting: short of the middle it goes back (Arc, Q19).
        try PhysicalPointer.swipe(app, at: try list(), steps: Array(repeating: (-4.0, 0.0), count: 15), pause: 0.25, window: window)
        app.sleep(0.6)
        try expect(try app.view().space.id == first, "a slow 60 pt swipe that stopped switched Spaces")
        // The same lifted while still moving goes on, however short (Arc: 5 points a second is enough).
        try expectSwitch("a slow swipe lifted while moving", to: second, Array(repeating: (-4.0, 0.0), count: 15))
        try expectSwitch("and back", to: first, Array(repeating: (4.0, 0.0), count: 15))
        // Vertical gestures belong to the list: it scrolls, the Space stays.
        let rest = try rowY()
        try swipe(Array(repeating: (0.0, -14.0), count: 6))
        try app.waitUntil("the list scrolled under a vertical gesture") { try rowY() < rest - 20 }
        try expect(try app.view().space.id == first, "a vertical gesture switched Spaces")
        _ = try app.screenshot("list-scrolled")
        // Twenty steps: the scroll view adds its own travel at the end of the first gesture, more or less (58 pt short with twelve, r5-7).
        try swipe([(1, -2), (-1, -5)] + Array(repeating: (0.0, 14.0), count: 20))
        let top = rest
        do { try app.waitUntil("the list scrolled back") { try abs(rowY() - top) < 1 } }
        catch { throw Check(description: "the list did not scroll back: row at \(try rowY()), was \(top)") }
        // And a swipe right after the list scrolled is still a swipe.
        try swipe(Array(repeating: (0.0, -14.0), count: 3))
        try expectSwitch("a swipe after the list scrolled", to: second, left)
        _ = try app.screenshot("second-space")
        try expectSwitch("the swipe back", to: first, right)
        // On the page the same gesture is the page's.
        let pageArea = try app.native().computed.contentArea
        try PhysicalPointer.swipe(app, at: point(pageArea), steps: left, window: window)
        app.sleep(0.6)
        try expect(try app.view().space.id == first, "a swipe on the page switched Spaces")
    }

    /// How much of `rect` (window points) in a screenshot differs from its own first pixel (the sidebar), 0...1.
    private static func inkShare(_ url: URL, in rect: CGRect, windowWidth: Double) throws -> Double {
        guard let provider = CGDataProvider(url: url as CFURL), let space = CGColorSpace(name: CGColorSpace.sRGB),
              let image = CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else {
            throw Check(description: "cannot read \(url.path)")
        }
        let scale = Double(image.width) / windowWidth
        guard let crop = image.cropping(to: CGRect(x: rect.minX * scale, y: rect.minY * scale, width: rect.width * scale, height: rect.height * scale)) else { return 0 }
        let bytesPerRow = crop.width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * crop.height)
        bytes.withUnsafeMutableBytes { raw in
            let context = CGContext(data: raw.baseAddress, width: crop.width, height: crop.height, bitsPerComponent: 8, bytesPerRow: bytesPerRow, space: space,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(crop, in: CGRect(x: 0, y: 0, width: crop.width, height: crop.height))
        }
        guard !bytes.isEmpty else { return 0 }
        let background = bytes.prefix(4).map(Int.init)
        let differs = stride(from: 0, to: bytes.count, by: 4).filter { i in (0..<3).map { abs(Int(bytes[i + $0]) - background[$0]) }.reduce(0, +) > 9 }.count
        return Double(differs) / Double(bytes.count / 4)
    }

    /// What R5-7 is for: the column moves with the fingers as Arc's does. Every number here was seen on real Arc (Q19/).
    @Sendable static func swipeFollows(_ app: AppUnderTest) throws {
        let first = try app.view().space.id
        let url = app.site.url("page2.html?follow=first")
        let inFirst = try app.load(url)
        try app.waitForPageInput(PageID(window: app.window!, item: inFirst), at: url)
        let second = try createSpace(app, title: "Second")
        let inSecond = try app.load(app.site.url("page2.html?follow=second"))
        try app.dispatch(.settings(.advanced(.hapticsOnReorder(false))))
        try finishAnimation(app)
        let window = app.window!
        let width = try app.view().sidebar.width
        func listPoint() throws -> CGPoint { point(try app.native().computed.sidebar!.tablistViewport) }
        func rowX(_ item: ItemID) throws -> Double { Double(try app.native().actual[ViewID.row(item).identifier]?.frame.minX ?? -9999) }
        let restX = try rowX(inSecond)
        let pill = try app.native().actual[ViewID.urlPill.identifier]?.frame
        let right = { (n: Int) in Array(repeating: (15.0, 0.0), count: n) }, left = { (n: Int) in Array(repeating: (-15.0, 0.0), count: n) }

        // Fingers 150 to the right, held: the column 75 to the right, the Space before beside it; the pill stays.
        try PhysicalPointer.swipe(app, at: try listPoint(), first: (4, 0), steps: right(10), held: {
            let moved = try rowX(inSecond)
            try expect(abs(moved - (restX + 75)) < 1, "the column moved \(moved - restX), fingers 150")
            let beside = try rowX(inFirst)
            try expect(abs(beside - (restX + 75 - width)) < 1, "the neighbour's row is at \(beside), expected \(restX + 75 - width)")
            try expect(try app.native().actual[ViewID.urlPill.identifier]?.frame == pill, "the pill moved")
            try expect(try app.view().space.id == second, "the Space changed before the fingers lifted")
            // What reached the screen, not only where the views are: the neighbour's current row (a white card) in the 75 points it shows.
            let shot = try app.screenshot("mid-swipe-150")
            let row = try visible(app.native(), .row(inFirst)).frame
            let shown = CGRect(x: 0, y: row.minY - 4, width: max(row.maxX, 0) - 4, height: row.height + 4)
            let ink = try inkShare(shot.url, in: shown, windowWidth: try app.native().windowFrame.width)
            try expect(ink > 0.5, "the neighbouring row is not on screen: \(ink) of \(shown) differs from the sidebar")
        }, then: left(10), pause: 0.25, window: window)
        try app.waitUntil("the column back in place") { abs(try rowX(inSecond) - restX) < 0.5 }
        try expect(try app.view().space.id == second, "back and stopped must stay")

        // Past the middle, stopped: goes on, and the column ends in place.
        try PhysicalPointer.swipe(app, at: try listPoint(), first: (4, 0), steps: right(20), pause: 0.3, window: window)
        try app.waitUntil("past the middle goes on") { try app.view().space.id == first }
        try finishAnimation(app)
        let placed = try rowX(inFirst)
        try expect(abs(placed - restX) < 0.5, "the new page is not in place: \(placed)")
        // The next one back, a quick short one.
        try PhysicalPointer.swipe(app, at: try listPoint(), first: (-3, 0), steps: [(-3, 0), (-3, 0), (-3, 0)], window: window)
        try app.waitUntil("a quick short swipe goes on") { try app.view().space.id == second }
        try finishAnimation(app)

        // Past the last Space: pressed, the ring filling; back and stopped, nothing.
        try PhysicalPointer.swipe(app, at: try listPoint(), first: (-4, 0), steps: left(14), held: {
            let pressed = restX - (try rowX(inSecond))
            try expect(abs(pressed - 14.84) < 1, "fingers 210 past the last Space pressed the column \(pressed)")
            try expect(isShown(try app.native(), .tabTool("space-edge-feedback")), "no edge feedback past the last Space")
            _ = try app.screenshot("past-the-last")
        }, then: right(14), pause: 0.3, window: window)
        try finishAnimation(app)
        try expect(try app.view().dialog == nil, "a ring that was not full opened Create a Space")
        // Full and held: Create a Space.
        try PhysicalPointer.swipe(app, at: try listPoint(), first: (-4, 0), steps: left(27), held: { app.sleep(0.2) }, window: window)
        try app.waitUntil("a full ring opens Create a Space") { try app.view().dialog == .newSpace }
        try finishAnimation(app)
        _ = try app.screenshot("create-a-space")
        try app.dispatch(.sidebar(.openDialog(nil)))
        try app.waitUntil("Create a Space cancelled") { try app.view().dialog == nil }
        try finishAnimation(app)
        try app.dispatch(.space(.focus(first)))
        try finishAnimation(app)

        // Before the first Space the Library comes in with the position, one to one.
        let closedCard = try app.native().computed.contentArea
        try PhysicalPointer.swipe(app, at: try listPoint(), first: (4, 0), steps: right(20), held: {
            guard case .library? = try app.view().overlay else { throw Check(description: "the Library is not there mid-swipe") }
            _ = try app.screenshot("toward-the-library")
        }, then: left(20), pause: 0.3, window: window)
        try app.waitUntil("back and stopped closes the Library") {
            if case .library? = try app.view().overlay { return false }
            return true
        }
        try finishAnimation(app)
        try expect(try app.native().computed.contentArea == closedCard, "the card did not come back")
        try PhysicalPointer.swipe(app, at: try listPoint(), first: (4, 0), steps: right(6), window: window)
        try app.waitUntil("a flick opens the Library") { if case .library? = try app.view().overlay { return true }; return false }
        try finishAnimation(app)
        // With the Library open the gesture is the column's anywhere: a flick back closes it.
        try PhysicalPointer.swipe(app, at: point(try app.native().computed.contentArea), first: (-4, 0), steps: left(6), window: window)
        try app.waitUntil("a flick back closes the Library") {
            if case .library? = try app.view().overlay { return false }
            return true
        }
        try expect(try app.view().space.id == first, "out of the Library: the first Space")
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
        try managerMenu(app, second, choose: "Delete Space")
        try expect(try app.view().pendingSpaceDeletion?.id == second, "Delete did not ask for confirmation")
        try app.click(.spaceToolsControl("alert-cancel"))
        try app.waitUntil("cancel preserved the space") { try app.view().pendingSpaceDeletion == nil }
        try expect(try app.view().dock.contains { $0.id == second }, "Cancel deleted the space")
        try managerMenu(app, second, choose: "Delete Space")
        try app.waitUntil("the delete dialog focused") { try app.native().firstResponder.contains("SpaceAlert") || app.native().firstResponder.contains("ArcDialog") }
        try app.press("return")
        try app.waitUntil("confirmed deletion removed the space") { try !app.view().dock.contains { $0.id == second } }
        try expect(try app.view().tabTools.toast?.text.hasPrefix("Space deleted!") == true, "no undo toast after the deletion")
        try app.flush(); try app.restart()
        try expect(try app.view().dock.map(\.id) == [third, first], "dock order did not persist")
        try app.screenshot("reordered-spaces")
        try app.recordWindows("gestures-final")
    }

    /// Chooses `item` from a Space card's … menu (Arc's space menu, P30-c; "Submenu › Row" for a submenu's row),
    /// through the native menu.
    private static func managerMenu(_ app: AppUnderTest, _ space: SpaceID, choose item: String) throws {
        // The Library slides in and its cards are built on the first renders: the button is read once it has stopped
        // moving (read at once, the menu was asked for at a spot the button had already left and came back empty).
        var last: CGRect?
        try app.waitUntil("the card's … button at rest") {
            let n = try app.native()
            guard isShown(n, .spaceToolsControl("manager-more-\(space)")) else { last = nil; return false }
            let now = try visible(n, .spaceToolsControl("manager-more-\(space)")).frame
            defer { last = now }
            return last == now
        }
        let more = try visible(app.native(), .spaceToolsControl("manager-more-\(space)")).frame
        guard case .menuItems(let titles) = try app.send(.captureContextMenu(window: app.window, point: CGPoint(x: more.midX, y: more.midY), choose: item)) else {
            throw Check(description: "the card's … menu did not open")
        }
        try expect(titles.contains(item.components(separatedBy: " › ")[0]), "the card's menu has \(titles), not \(item)")
    }

    @Sendable static func export(_ app: AppUnderTest) throws {
        let item = try app.load(app.site.url("page2.html?space-export"))
        try app.waitForPageInput(PageID(window: app.window!, item: item), at: app.site.url("page2.html?space-export"))
        let space = try app.view().space.id
        let exportRow = "Export “\(try app.view().dock.first { $0.id == space }?.title ?? "")” into Folder › Bookmarks Folder on Disk…"
        try app.dispatch(.library(.open(.spaces)))
        try managerMenu(app, space, choose: exportRow)
        try perform(app, .sheetButton(title: "Cancel"))
        try app.waitUntil("export cancellation settled") {
            guard case .library(let library)? = try app.view().overlay else { return false }
            return !library.spaceExportInProgress && library.spaceExportMessage == nil
        }
        let destination = app.dataDirectory.appendingPathComponent("owned-export", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try perform(app, .selectSheetDirectory(path: destination.path))
        try managerMenu(app, space, choose: exportRow)
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
