import AppKit
import XCTest

@testable import BrkOverlays
import BrkBase
@testable import BrkDomain

// Ported from electron-v1:src/renderer/sidebar/SpaceDialog.test.tsx, against the Swift commands: Save sends the
// name, the picked icon and the theme with the picked preset as its primary color; Cancel closes without changes.

private let editTheme = SpaceTheme(colors: [ThemePresets.brand[3]], wheel: .complementary, texture: .denim, noise: 0.2,
                                   intensity: 0.4, appearance: .light)

final class SpaceDraftTests: XCTestCase {
    func testSaveOnANewSpaceSendsTheTrimmedNameThePickedIconAndThePickedPreset() {
        var draft = SpaceDraft(.newSpace)
        draft.title = "  Work "
        draft.icon = .custom(.named(.briefcase))
        draft.pickColor(ThemePresets.drab[8])
        var expected = SpaceTheme.default
        expected.colors = [ThemePresets.drab[8]]
        XCTAssertEqual(draft.saveCommand, .space(.create(title: "Work", icon: .custom(.named(.briefcase)), theme: expected)))
        XCTAssertTrue(draft.isPicked(ThemePresets.drab[8]))
        XCTAssertFalse(draft.isPicked(SpaceTheme.default.colors[0]))
    }

    func testEditingStartsFromTheSpaceAndSaveUpdatesIt() {
        var draft = SpaceDraft(.editSpace(id: SpaceID("s2"), title: "Work", icon: .custom(.named(.briefcase)), theme: editTheme))
        XCTAssertEqual(draft.title, "Work")
        XCTAssertTrue(draft.isPicked(ThemePresets.brand[3]))
        draft.icon = SpaceIcon.none
        XCTAssertEqual(draft.saveCommand, .space(.update(SpaceID("s2"), title: "Work", icon: SpaceIcon.none, theme: editTheme)))
        // A preset keeps the editor's other settings: only the primary color changes.
        draft.pickColor(ThemePresets.pastel[0])
        var picked = editTheme
        picked.colors = [ThemePresets.pastel[0]]
        XCTAssertEqual(draft.theme, picked)
    }

    func testTheLastEmojiTypedBecomesTheIconAndClearingItGoesBackToNone() {
        var draft = SpaceDraft(.newSpace)
        draft.setEmoji("🚀")
        XCTAssertEqual(draft.icon, .custom(.emoji("🚀")))
        draft.setEmoji("🚀👨‍👩‍👧")
        XCTAssertEqual(draft.icon, .custom(.emoji("👨‍👩‍👧")), "one emoji, even when it is several code points")
        XCTAssertEqual(draft.emoji, "👨‍👩‍👧")
        draft.setEmoji("")
        XCTAssertEqual(draft.icon, SpaceIcon.none)
        draft.icon = .custom(.named(.star))
        draft.setEmoji("")
        XCTAssertEqual(draft.icon, .custom(.named(.star)), "an empty emoji field leaves a named icon alone")
    }

    func testCancelClosesTheDialogWithoutChangingAnything() {
        XCTAssertEqual(SpaceDraft.cancelCommand, .sidebar(.openDialog(nil)))
    }

    func testTheFourPresetSetsOfNineInEditorOrder() {
        XCTAssertEqual(presetSets.map(\.name), ["Brand", "Drab", "Greyscale", "Pastel"])
        XCTAssertEqual(presetSets.map(\.colors.count), [9, 9, 9, 9])
        XCTAssertEqual(presetSets[1].colors.map(\.hex).last, "#2D4468")
    }
}

/// The form as a user drives it: real mouse and key events through `NSApp.sendEvent` into a window that holds it.
@MainActor
final class SpaceDialogHostTests: XCTestCase {
    private var sent: [Command] = []

    /// The centre of the pixels of `color` in a capture of `window` (by window id, as the control socket's
    /// screenshot does), in window coordinates from the top-left.
    private func centre(of color: RGBA, in window: NSWindow) -> CGPoint? {
        guard let image = CGWindowListCreateImage(.null, .optionIncludingWindow, CGWindowID(window.windowNumber), [.boundsIgnoreFraming]),
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let data = context.data?.assumingMemoryBound(to: UInt8.self) else { return nil }
        let target = [color.red, color.green, color.blue].map { Int(($0 * 255).rounded()) }
        var sumX = 0, sumY = 0, count = 0
        for y in 0..<image.height {
            for x in 0..<image.width {
                let p = (y * image.width + x) * 4
                if abs(Int(data[p]) - target[0]) <= 3, abs(Int(data[p + 1]) - target[1]) <= 3, abs(Int(data[p + 2]) - target[2]) <= 3 {
                    sumX += x
                    sumY += y
                    count += 1
                }
            }
        }
        guard count > 0 else { return nil }
        // The bitmap context's first row is the image's top row.
        let scale = CGFloat(image.width) / window.frame.width
        return CGPoint(x: CGFloat(sumX) / CGFloat(count) / scale, y: CGFloat(sumY) / CGFloat(count) / scale)
    }

    /// A click at a window point measured from the top-left.
    private func click(_ point: CGPoint, in window: NSWindow) {
        let location = CGPoint(x: point.x, y: window.frame.height - point.y)
        func event(_ type: NSEvent.EventType) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                               windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        NSApp.postEvent(event(.leftMouseUp), atStart: false)
        NSApp.sendEvent(event(.leftMouseDown))
        if let up = NSApp.nextEvent(matching: .leftMouseUp, until: .distantPast, inMode: .default, dequeue: true) { NSApp.sendEvent(up) }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
    }

    private func press(_ key: UInt16, _ characters: String, in window: NSWindow) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                         windowNumber: window.windowNumber, context: nil, characters: characters,
                                         charactersIgnoringModifiers: characters, isARepeat: false, keyCode: key)!
            NSApp.sendEvent(event)
        }
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
    }

    func testClickingASwatchThenReturnCreatesTheSpaceWithThatPresetAndEscapeCancels() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1280, height: 776), styleMask: [.titled, .fullSizeContentView],
                              backing: .buffered, defer: false)
        let root = FlippedView(frame: CGRect(x: 0, y: 0, width: 1280, height: 776))
        window.contentView = root
        let host = SpaceDialogHost(dispatch: { [unowned self] in self.sent.append($0) })
        root.addSubview(host)
        let area = CGRect(x: 238, y: 10, width: 1032, height: 756)
        host.show(.newSpace, in: area, scheme: .light)
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        host.layoutSubtreeIfNeeded()

        // Centred in the content area, Arc-popover wide, as tall as the form (no titlebar inset).
        XCTAssertEqual(host.frame.width, 420)
        XCTAssertEqual(host.frame.midX, area.midX, accuracy: 1)
        XCTAssertEqual(host.frame.midY, area.midY, accuracy: 1)
        XCTAssertEqual(host.accessibilityIdentifier(), "space-dialog")
        XCTAssertTrue(host.focusForm(), "the name field takes keyboard focus")

        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
        let drab9 = try XCTUnwrap(centre(of: ThemePresets.drab[8], in: window), "the Drab 9 swatch is drawn")
        click(drab9, in: window)
        press(36, "\r", in: window)
        var drab = SpaceTheme.default
        drab.colors = [ThemePresets.drab[8]]
        XCTAssertEqual(sent, [.space(.create(title: "", icon: SpaceIcon.none, theme: drab))])

        press(53, "\u{1b}", in: window)
        XCTAssertEqual(sent.last, .sidebar(.openDialog(nil)))
    }

    func testTheSameDialogKeepsTheFormAndAnotherOneStartsFresh() throws {
        let host = SpaceDialogHost(dispatch: { _ in })
        let area = CGRect(x: 238, y: 10, width: 1032, height: 756)
        host.show(.newSpace, in: area, scheme: .light)
        let first = try XCTUnwrap(host.hosting)
        host.show(.newSpace, in: area, scheme: .dark)
        XCTAssertTrue(host.hosting === first, "a re-render of the same dialog keeps what was typed")
        host.show(.editSpace(id: SpaceID("s2"), title: "Work", icon: .none, theme: editTheme), in: area, scheme: .dark)
        XCTAssertFalse(host.hosting === first)
        XCTAssertFalse(host.isHidden)
    }
}
