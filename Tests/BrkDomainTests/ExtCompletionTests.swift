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
    func testExtensionAndBrkPriorityMatrixUsesOneResolvedTable() throws {
        let extensionChord = KeyChord([.command, .shift], .u)
        for stage in [KeyStage.beforePage, .afterPage, .menu] {
            let d = Driver()
            XCTAssertFalse(d.key(extensionChord, stage: stage, pressID: 1).keyHandled, "Unbound extension chord is left to Chromium/native editor")
        }
        for priority in [KeyPriority.app, .page, .pageThenApp] {
            for stage in [KeyStage.beforePage, .afterPage, .menu] {
                let d = Driver()
                d.user(.settings(.shortcuts(.setChord(.newTab, extensionChord))))
                d.user(.settings(.shortcuts(.setPriority(.newTab, priority))))
                let handled = d.key(extensionChord, stage: stage, pressID: 2).keyHandled
                XCTAssertEqual(handled, priority == .app || stage != .beforePage, "\(priority) at \(stage)")
            }
        }
        let error = ExtensionShortcuts.error(for: extensionChord, extensionID: "fixture", command: "run", catalog: [fixture()],
            overrides: [.newTab: KeyOverride(chord: extensionChord, priority: .page)])
        XCTAssertNotNil(error, "A page-first Brk remap is still reserved against extension assignment")
        for key in [Key.a, .c, .v, .x, .z] {
            XCTAssertNotNil(ExtensionShortcuts.error(for: KeyChord(.command, key), extensionID: "fixture", command: "run", catalog: [], overrides: [:]))
        }
    }

    func testEasyListImportIsAtomicAndReportsUnsupportedLines() throws {
        let source = "[Adblock Plus 2.0]\n! selected local rules\n||ads.example^\n|https://fixture.test/blocked/\n##.advert\n"
        guard case .loaded(let rules) = StateCodec.decodeEasyListRules(Data(source.utf8)) else { return XCTFail("valid subset rejected") }
        XCTAssertEqual(rules.blockedHosts, ["ads.example"])
        XCTAssertEqual(rules.blockedURLPrefixes, ["https://fixture.test/blocked/"])
        XCTAssertEqual(rules.cosmeticSelectors, [".advert"])
        for line in ["@@||ads.example^", "||ads.example^$third-party", "example.com##.advert", "/ad[0-9]/", "##div > span", "|https://fixture.test/*"] {
            guard case .failed = StateCodec.decodeEasyListRules(Data((source + line).utf8)) else { XCTFail("unsupported rule accepted: " + line); continue }
        }
        let d = Driver(); let context = BrowsingContext.profile(.default)
        d.system(.websiteRulesLoaded(context, .loaded(rules)))
        d.system(.websiteRulesLoaded(context, .failed("line 4")))
        XCTAssertEqual(d.state.doc.sitePreferences[.default]?.blockingRules, rules)
        XCTAssertEqual(Driver(file: d.savedFile).state.doc.sitePreferences[.default]?.blockingRules, rules)
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

    func testBundledRulesUseTheDocumentedResource() {
        XCTAssertEqual(WebsiteBlockingRules.builtIn.version, 1)
        XCTAssertTrue(WebsiteBlockingRules.builtIn.blockedHosts.contains("doubleclick.net"))
        XCTAssertTrue(WebsiteBlockingRules.builtIn.blockedPathPrefixes.contains("/brk-blocked-tracker/"))
    }
}
