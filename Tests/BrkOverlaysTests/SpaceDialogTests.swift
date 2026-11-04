import AppKit
import XCTest

@testable import BrkOverlays
import BrkBase
@testable import BrkDomain
@testable import BrkLayout
import BrkUIKit

// The space dialogs against the 2026-11-03 Arc captures: Create a Space sends the typed name, the picked icon and
// the theme; the theme panel's edits land on both appearances and its pad is Arc's hue wheel; Rename and the delete
// confirmation send their commands; the dialogs are Arc's 450 pt cards centred in the window.

private let editTheme = SpaceTheme(colors: [ThemePresets.brand[3]], wheel: .complementary, texture: .denim, noise: 0.2,
                                   intensity: 0.4, appearance: .light)

@MainActor
final class SpaceCreateDraftTests: XCTestCase {
    func testCreateSpaceNeedsANameAndSendsTheTrimmedNameIconThemeAndProfile() {
        var draft = SpaceCreateDraft()
        XCTAssertFalse(draft.canCreate)
        XCTAssertNil(draft.createCommand, "Arc's Create Space is disabled until a name is typed")
        draft.name = "  流程 "
        draft.icon = .custom(.emoji("📘"))
        draft.profile = ProfileID("work")
        XCTAssertEqual(draft.createCommand, .space(.create(title: "流程", icon: .custom(.emoji("📘")), theme: SpaceCreateDraft.defaultTheme, profile: ProfileID("work"))))
        XCTAssertEqual(SpaceCreateDraft.cancelCommand, .sidebar(.openDialog(nil)))
    }

    func testThePickedPresetIsTheCreatedSpacesTheme() {
        let model = SpaceCreateModel(dispatch: { _ in })
        XCTAssertFalse(model.theme.chosen, "the pad says \"Tap to pick a color for this space\" until a color is picked")
        model.theme.update { $0.setColor(ThemePresets.greyscale[0], at: 0) }
        XCTAssertTrue(model.draft.themeChosen)
        XCTAssertEqual(ThemeDraft(theme: model.draft.theme).colors, [ThemePresets.greyscale[0]], "the first pick is the one color, as Arc's window")
        model.theme.update { $0.addColor() }
        XCTAssertEqual(ThemeDraft(theme: model.draft.theme).colors.count, 2)
        model.draft.name = "流程"
        guard case .space(.create(_, _, let theme, _))? = model.draft.createCommand else { return XCTFail("no create command") }
        XCTAssertEqual(resolveTheme(theme).gradient.first, ThemePresets.greyscale[0])
    }

    func testTheCreateButtonIsArcsBlueUntilAThemeIsPickedThenADeepShadeOfIt() {
        var draft = SpaceCreateDraft()
        let blue = draft.accent(systemScheme: .light)
        XCTAssertEqual(blue.hex, "#1E2CFF")
        draft.themeChosen = true
        draft.theme = SpaceTheme(colors: [ThemePresets.brand[0]], texture: .grain, intensity: 0.25, appearance: .auto)
        let brown = HSL(draft.accent(systemScheme: .light))
        XCTAssertEqual(brown.hue, HSL(ThemePresets.brand[0]).hue, accuracy: 1, "cream gives a brown of its own hue (#725137 in Arc)")
        XCTAssertLessThan(brown.lightness, 0.4)
    }
}

final class ThemeDraftTests: XCTestCase {
    func testEditsLandOnBothAppearancesAndTheLegacyFieldsFollow() {
        var draft = ThemeDraft(theme: editTheme)
        draft.setColor(ThemePresets.pastel[2], at: 0)
        draft.setIntensity(0.9)
        draft.setNoise(0.1)
        XCTAssertEqual(draft.theme.variants?.light.colors.first?.color, ThemePresets.pastel[2])
        XCTAssertEqual(draft.theme.variants?.dark.colors.first?.color, ThemePresets.pastel[2])
        XCTAssertEqual(draft.theme.colors.first, ThemePresets.pastel[2])
        XCTAssertEqual(draft.theme.intensity, 0.9)
        XCTAssertEqual(draft.theme.noise, 0.1)
        XCTAssertEqual(draft.theme.texture, .denim, "the panel has no texture control (P28 d); the stored texture stays")
    }

    func testPlusAddsTheComplementAndMinusNeverRemovesTheLastColor() {
        var draft = ThemeDraft(theme: SpaceTheme(colors: [ThemePresets.brand[0]], texture: .grain, intensity: 0.25, appearance: .auto))
        draft.addColor()
        XCTAssertEqual(draft.colors.count, 2)
        XCTAssertEqual(HSL(draft.colors[1]).hue, (HSL(draft.colors[0]).hue + 180).truncatingRemainder(dividingBy: 360), accuracy: 1)
        draft.addColor(); draft.addColor()
        XCTAssertEqual(draft.colors.count, 3)
        draft.removeColor(at: 0); draft.removeColor(at: 0); draft.removeColor(at: 0)
        XCTAssertEqual(draft.colors.count, 1)
    }

    func testTheAppearanceButtonsSetTheSelection() {
        var draft = ThemeDraft(theme: SpaceTheme(colors: [ThemePresets.brand[0]], texture: .grain, intensity: 0.25, appearance: .auto), systemScheme: .light)
        XCTAssertEqual(draft.appearance, .auto)
        draft.setAppearance(.dark)
        XCTAssertEqual(draft.theme.variants?.selection, .dark)
        XCTAssertEqual(draft.resolved.scheme, .dark)
    }

    func testThePadIsArcsHueWheel() {
        // P28 a: the cream preset sits 29° below the right-hand axis at 0.82 of the inscribed radius.
        let cream = ThemePad.point(of: ThemePresets.brand[0])
        let angle = atan2(cream.y - 0.5, cream.x - 0.5) * 180 / .pi
        XCTAssertEqual(angle, HSL(ThemePresets.brand[0]).hue, accuracy: 0.5)
        XCTAssertEqual(hypot(cream.x - 0.5, cream.y - 0.5) / 0.5, 0.82, accuracy: 0.02)
        // P28 a: the Greyscale page's white sits on the left-hand axis at the pad's edge; a grey has no hue.
        let white = ThemePad.point(of: ThemePresets.greyscale[0])
        XCTAssertEqual(white.y, 0.5, accuracy: 0.001)
        XCTAssertLessThan(white.x, 0.05)
        XCTAssertLessThan(ThemePad.point(of: ThemePresets.greyscale[4]).x, 0.5, "mid grey left of the centre")
        // Round trip: a dot dragged to where a color sits picks that color.
        for color in [ThemePresets.brand[3], ThemePresets.drab[7], ThemePresets.pastel[4]] {
            let back = ThemePad.color(at: ThemePad.point(of: color), saturation: HSL(color).saturation)
            XCTAssertEqual(back.hex, color.hex)
        }
    }

    func testThePresetPagesAreInArcsOrder() {
        XCTAssertEqual(ThemePresets.pages.map(\.name), ["Brand", "Pastel", "Drab", "Greyscale"])
        XCTAssertEqual(ThemePresets.pages.map(\.colors.count), [9, 9, 9, 9])
    }
}

final class EmojiCatalogTests: XCTestCase {
    func testTheEmojiSearchUsesUnicodeNames() {
        XCTAssertTrue(EmojiCatalog.matching("blue book").contains("📘"))
        XCTAssertEqual(EmojiCatalog.matching("cactus").first, "🌵", "SidebarToolsIcons picks the space icon by this search")
        XCTAssertEqual(EmojiCatalog.categories.first?.emoji.prefix(8).joined(), "😀😃😄😁😆😅🤣😂", "P10 c's first row")
        XCTAssertEqual(EmojiCatalog.categories.count, 8)
    }
}

final class SpaceAlertKindTests: XCTestCase {
    func testRenameSendsTheTrimmedNameAndRefusesABlankOne() {
        let rename = SpaceAlertKind.rename(id: SpaceID("s"), title: "对照")
        XCTAssertEqual(rename.confirmCommand(name: " 新名 "), .space(.update(SpaceID("s"), title: "新名", icon: nil, theme: nil)))
        XCTAssertNil(rename.confirmCommand(name: "  "))
        XCTAssertEqual(rename.cancelCommand, .sidebar(.openDialog(nil)))
    }

    func testDeleteConfirmsOrCancelsWithItsToken() {
        let request = SpaceDeletionRequest(id: SpaceID("s"), title: "对照", token: "t1")
        XCTAssertEqual(SpaceAlertKind.delete(request).confirmCommand(name: ""), .space(.confirmDelete(SpaceID("s"), token: "t1", confirmed: true)))
        XCTAssertEqual(SpaceAlertKind.delete(request).cancelCommand, .space(.confirmDelete(SpaceID("s"), token: "t1", confirmed: false)))
    }
}

/// The dialogs as a user drives them: real key events through `NSApp.sendEvent` into a window that holds them.
@MainActor
final class SpaceDialogHostTests: XCTestCase {
    private var sent: [Command] = []

    private func press(_ key: UInt16, _ characters: String, in window: NSWindow) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: window.windowNumber, context: nil, characters: characters,
                                         charactersIgnoringModifiers: characters, isARepeat: false, keyCode: key)!
            NSApp.sendEvent(event)
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
    }

    private func type(_ text: String, in window: NSWindow) {
        (window.firstResponder as? NSTextView)?.insertText(text, replacementRange: NSRange(location: NSNotFound, length: 0))
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
    }

    /// A 1280 x 776 window with a 228 pt sidebar (dock 50 at the bottom) and the content area beside it.
    private func harness() -> (NSWindow, SpaceDialogHost, WindowFrames) {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1280, height: 776), styleMask: [.titled, .fullSizeContentView],
                              backing: .buffered, defer: false)
        let root = FlippedView(frame: CGRect(x: 0, y: 0, width: 1280, height: 776))
        window.contentView = root
        let host = SpaceDialogHost(dispatch: { [unowned self] in self.sent.append($0) })
        root.addSubview(host)
        let sidebar = SidebarFrames(frame: CGRect(x: 0, y: 0, width: 228, height: 776), titleRow: CGRect(x: 0, y: 4, width: 228, height: 40),
                                    trafficLightsOrigin: CGPoint(x: 13, y: 17), urlPill: CGRect(x: 8, y: 48, width: 212, height: 36),
                                    favoritesTray: .zero, favoriteTiles: [:], spaceHeader: CGRect(x: 0, y: 140, width: 228, height: 36),
                                    tablistViewport: CGRect(x: 0, y: 176, width: 228, height: 550), rows: [],
                                    dock: CGRect(x: 0, y: 726, width: 228, height: 50), dockSpaces: [:], libraryButton: .zero, plusButton: .zero)
        let frames = WindowFrames(contentSize: CGSize(width: 1280, height: 776), sidebar: sidebar, sidebarFloats: false, resizeHandle: nil,
                                  revealStrip: nil, contentArea: CGRect(x: 238, y: 10, width: 1032, height: 756), cards: [], dividers: [],
                                  commandBar: nil, library: nil, peek: nil)
        window.makeKeyAndOrderFront(nil)
        return (window, host, frames)
    }

    func testRenameIsArcsCentredCardWithTheNameSelectedAndReturnRenames() throws {
        let (window, host, frames) = harness()
        defer { window.orderOut(nil) }
        host.render(.rename(id: SpaceID("s"), title: "对照"), deletion: nil, frames: frames, palette: Palette(resolveTheme(.default)))
        host.layoutSubtreeIfNeeded()
        let alert = try XCTUnwrap(host.alert)
        alert.layoutSubtreeIfNeeded()
        alert.dialog.layoutSubtreeIfNeeded()
        XCTAssertEqual(alert.card.frame.size, CGSize(width: 450, height: 222), "P26 a")
        XCTAssertEqual(alert.card.frame.midX, 640, accuracy: 1)
        XCTAssertEqual(alert.card.frame.midY, 388, accuracy: 1)
        XCTAssertTrue(host.focusForm(), "the name field takes keyboard focus")
        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        XCTAssertEqual(editor.selectedRange(), NSRange(location: 0, length: 2), "the name is selected")
        type("新名", in: window)
        press(36, "\r", in: window)
        XCTAssertEqual(sent.last, .space(.update(SpaceID("s"), title: "新名", icon: nil, theme: nil)))
        alert.cancel.action()
        XCTAssertEqual(sent.last, .sidebar(.openDialog(nil)))
    }

    func testDeleteIsArcsCentredCardAndReturnConfirmsWithTheToken() throws {
        let (window, host, frames) = harness()
        defer { window.orderOut(nil) }
        let request = SpaceDeletionRequest(id: SpaceID("s"), title: "对照", token: "t1")
        host.render(nil, deletion: request, frames: frames, palette: Palette(resolveTheme(.default)))
        let alert = try XCTUnwrap(host.alert)
        host.layoutSubtreeIfNeeded(); alert.layoutSubtreeIfNeeded(); alert.dialog.layoutSubtreeIfNeeded()
        XCTAssertEqual(alert.card.frame.size, CGSize(width: 450, height: 273), "P27 a")
        XCTAssertTrue(host.focusForm())
        press(36, "\r", in: window)
        XCTAssertEqual(sent.last, .space(.confirmDelete(SpaceID("s"), token: "t1", confirmed: true)))
        host.render(nil, deletion: nil, frames: frames, palette: Palette(resolveTheme(.default)))
        XCTAssertNil(host.alert)
        XCTAssertTrue(host.isHidden)
    }

    func testCreateASpaceTakesTheSidebarsPlaceAndReportsItsDraft() throws {
        let (window, host, frames) = harness()
        defer { window.orderOut(nil) }
        var drafts: [(SpaceTheme, SpaceIcon)?] = []
        host.onDraft = { drafts.append($0) }
        host.render(.newSpace, deletion: nil, frames: frames, palette: Palette(resolveTheme(.default)))
        host.layoutSubtreeIfNeeded()
        let flow = try XCTUnwrap(host.subviews.first { $0.accessibilityIdentifier() == "space-dialog" })
        XCTAssertEqual(flow.frame, CGRect(x: 0, y: 44, width: 228, height: 682), "between the title row and the dock")
        XCTAssertEqual(drafts.count, 1)
        XCTAssertTrue(host.focusForm(), "the name field takes keyboard focus")
        type("流程", in: window)
        press(36, "\r", in: window)
        XCTAssertEqual(sent.last, .space(.create(title: "流程", icon: .none, theme: SpaceCreateDraft.defaultTheme, profile: .default)))
        host.render(nil, deletion: nil, frames: frames, palette: Palette(resolveTheme(.default)))
        XCTAssertNil(drafts.last!, "closing the flow clears the draft")
    }

    func testNewProfileIsTwoStepsInArcsCentredCard() throws {
        let (window, host, frames) = harness()
        defer { window.orderOut(nil) }
        ProfileDialogHost.render(.create, over: host, frames: frames, palette: Palette(resolveTheme(.default)))
        let profile = try XCTUnwrap(window.contentView?.subviews.compactMap { $0 as? ProfileDialogHost }.first)
        profile.layoutSubtreeIfNeeded()
        let view = try XCTUnwrap(profile.subviews.first as? ProfileDialogView)
        view.layoutSubtreeIfNeeded(); view.dialog.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.dialog.card.frame.width, 450)
        XCTAssertEqual(view.dialog.card.frame.height, 424, accuracy: 6, "P42 a")
        XCTAssertFalse(view.dialog.confirm.isEnabled, "Next waits for a name")
        XCTAssertTrue(ProfileDialogHost.focus(over: host))
        type("Work", in: window)
        press(36, "\r", in: window)
        XCTAssertTrue(sent.isEmpty, "Next shows the icon step; nothing is created yet")
        press(36, "\r", in: window)
        XCTAssertEqual(sent.last, .profile(.create(name: "Work", icon: nil)))
    }

    func testChangeProfileIsArcsCentredCardNamingTheSpace() throws {
        let (window, host, frames) = harness()
        defer { window.orderOut(nil) }
        let rows = [ProfileRow(id: .default, name: "Default", icon: nil, spaceTitles: ["对照"], isDefault: true),
                    ProfileRow(id: ProfileID("w"), name: "Work", icon: nil, spaceTitles: [], isDefault: false)]
        ProfileDialogHost.render(.change(space: SpaceID("s"), current: .default, profiles: rows), over: host, frames: frames,
                                 palette: Palette(resolveTheme(.default)), spaceNames: [SpaceID("s"): "对照"])
        let profile = try XCTUnwrap(window.contentView?.subviews.compactMap { $0 as? ProfileDialogHost }.first)
        profile.layoutSubtreeIfNeeded()
        let view = try XCTUnwrap(profile.subviews.first as? ProfileDialogView)
        view.layoutSubtreeIfNeeded(); view.dialog.layoutSubtreeIfNeeded()
        XCTAssertEqual(view.dialog.card.frame.width, 450)
        XCTAssertEqual(view.dialog.card.frame.height, 332, accuracy: 6, "Q04 a")
        XCTAssertTrue(ProfileDialogHost.focus(over: host))
        press(36, "\r", in: window)
        XCTAssertEqual(sent.last, .profile(.openDialog(nil)), "confirming the current profile just closes")
    }
}
