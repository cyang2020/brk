import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

final class ExtCompletionTests: XCTestCase {
    private func fixture(_ name: String = "run", key: String = "⌘⇧Y") -> BrowserExtension {
        BrowserExtension(id: "fixture", name: "Fixture", version: "1", enabled: true,
            incognitoAllowed: false, canChangeIncognito: true,
            commands: [BrowserExtensionCommand(name: name, description: "Run", keybinding: key, active: true)])
    }
    func testEditsAreChromiumEffectsAndPrivateManagementIsRefused() throws {
        let d = Driver()
        d.system(.extensionsRead(ExtensionCatalog(context: .profile(.default), extensions: [fixture()], error: nil)))
        XCTAssertEqual(d.user(.site(.extensionIncognito("fixture", true))).effects,
                       [.editExtension("fixture", .incognito(true), .profile(.default))])
        XCTAssertEqual(d.user(.site(.extensionShortcut("fixture", "run", "cmd+shift+u"))).effects,
                       [.editExtension("fixture", .shortcut(command: "run", chord: KeyChord([.command, .shift], .u)), .profile(.default))])
        d.user(.window(.newIncognito))
        let window = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .incognito }?.id)
        XCTAssertTrue(d.user(.site(.extensionIncognito("fixture", true)), in: window).effects.isEmpty)
        XCTAssertTrue(d.user(.site(.extensionShortcut("fixture", "run", "cmd+shift+u")), in: window).effects.isEmpty)
    }
    func testDuplicateReservedAndClearedBindings() throws {
        let d = Driver()
        let other = BrowserExtension(id: "other", name: "Other", version: "1", enabled: true,
            commands: [BrowserExtensionCommand(name: "other", description: "Other", keybinding: "⌘⇧U", active: true)])
        d.system(.extensionsRead(ExtensionCatalog(context: .profile(.default), extensions: [fixture(), other], error: nil)))
        d.user(.site(.controls))
        for chord in ["cmd+t", "cmd+shift+u", "cmd+space", "y"] {
            XCTAssertTrue(d.user(.site(.extensionShortcut("fixture", "run", chord))).effects.isEmpty, chord)
            XCTAssertNotNil(d.snapshot.sites[d.window]?.extensionError)
        }
        XCTAssertEqual(d.user(.site(.extensionShortcut("fixture", "run", ""))).effects,
                       [.editExtension("fixture", .shortcut(command: "run", chord: nil), .profile(.default))])
    }

    func testControlsReadSavedChoicesDuringLoadingWithoutEnablingDestructiveOperations() throws {
        let d = Driver()
        let page = d.snapshot.pages[0].id
        let browser = try XCTUnwrap(d.state.session.live[page]?.browser)
        d.page(page.item, .documentChanged(.loading(DocumentToken(browser: browser, sequence: 1))))
        d.page(page.item, .documentChanged(.ready(DocumentToken(browser: browser, sequence: 1))))
        let previous = try XCTUnwrap(d.state.siteTarget(in: d.window))
        d.user(.site(.permission(previous, previous.origin, [.notifications], .deny)))
        let destination = previous.origin.url.appendingPathComponent("loading")
        d.page(previous.page.item, .navigationRequested(destination))
        let document = DocumentToken(browser: previous.document.browser, sequence: previous.document.sequence + 1)
        d.page(previous.page.item, .documentChanged(.loading(document)))
        d.user(.site(.controls))
        XCTAssertNil(d.snapshot.sites[d.window]?.target, "An uncommitted navigation has no readback target")
        d.page(previous.page.item, .committed(destination))
        XCTAssertEqual(d.snapshot.sites[d.window]?.target?.document, document)
        XCTAssertEqual(d.snapshot.sites[d.window]?.rule.permissions[.notifications], .deny)
        XCTAssertNil(d.state.siteTarget(in: d.window), "Clear/export readiness is still strict")
        XCTAssertTrue(d.user(.site(.clear(kinds: [.cookies], scope: .site, reload: true))).effects.isEmpty)
    }

}
