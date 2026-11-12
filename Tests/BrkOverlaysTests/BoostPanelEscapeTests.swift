import AppKit
import XCTest

@testable import BrkOverlays
import BrkBase
@testable import BrkDomain
import BrkLayout

/// Escape in the Boost panel closes and saves it as × does. Not while an input method is composing (Escape then cancels
/// the composition), and never past a scope the settings card could not read (× refuses that with a note).
@MainActor
final class BoostPanelEscapeTests: XCTestCase {
    /// Takes every command the field editor sends, so Escape does not open the text view's completion list.
    private final class Swallow: NSObject, NSTextFieldDelegate {
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool { true }
    }

    private func escape(in window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 1, windowNumber: window.windowNumber, context: nil,
                         characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: Key.escape.code)!
    }

    func testEscapeLeavesComposingTextAloneAndRefusesAnUnreadableScope() throws {
        _ = NSApplication.shared
        // Case A: an input method's underlined text in a field of the panel takes Escape.
        let panel = BoostPanelWindow(contentRect: CGRect(x: 0, y: 0, width: 200, height: 80), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer { panel.close() }
        let content = NSView(frame: CGRect(x: 0, y: 0, width: 200, height: 80))
        let field = NSTextField(frame: CGRect(x: 10, y: 10, width: 160, height: 22))
        let swallow = Swallow()
        field.delegate = swallow
        content.addSubview(field)
        panel.contentView = content
        var escapes = 0
        panel.onEscape = { escapes += 1 }
        XCTAssertTrue(panel.makeFirstResponder(field))
        let editor = try XCTUnwrap(field.currentEditor() as? NSTextView)
        editor.setMarkedText("ni", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        panel.sendEvent(escape(in: panel))
        XCTAssertEqual(escapes, 0, "Escape went to the input method")
        editor.unmarkText()
        panel.sendEvent(escape(in: panel))
        XCTAssertEqual(escapes, 1, "with nothing composing Escape is the panel's")

        // Case B: a scope the card cannot read; Escape refuses it as × does.
        var sent: [Command] = []
        let view = BoostEditorView(dispatch: { sent.append($0) })
        let origin = try XCTUnwrap(SiteOrigin(URL(string: "https://example.com")!))
        view.render(BoostEditor(id: "e1", profile: .default, target: nil,
                                draft: Boost(id: "b1", name: "Mine", scope: .origin(origin), css: "p { color: red }")))
        func find(_ name: String) -> NSView? {
            func walk(_ v: NSView) -> NSView? {
                if v.accessibilityIdentifier() == ViewID.boostControl(name).identifier { return v }
                for child in v.subviews { if let found = walk(child) { return found } }
                return nil
            }
            return walk(view)
        }
        let scope = try XCTUnwrap(find("scope-value") as? NSTextField)
        scope.stringValue = "exa mple"
        scope.delegate?.controlTextDidChange?(Notification(name: NSControl.textDidChangeNotification, object: scope))
        XCTAssertEqual(sent, [], "the card did not take the text")
        view.exit()
        XCTAssertEqual(sent, [], "Escape does not close and save with the last scope the card could read")
        XCTAssertEqual((find("message") as? NSTextField)?.stringValue, BoostEditorView.scopeRefusal)
    }
}
