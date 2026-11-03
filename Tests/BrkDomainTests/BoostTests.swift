import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

final class BoostTests: XCTestCase {
    private func readyDriver() -> Driver {
        let d = Driver()
        let page = d.snapshot.pages[0].id
        let browser = d.state.session.live[page]!.browser!
        let document = DocumentToken(browser: browser, sequence: 1)
        d.page(page.item, .documentChanged(.loading(document)))
        d.page(page.item, .documentChanged(.ready(document)))
        return d
    }
    private func boost(_ scope: BoostScope = .allSites) -> Boost {
        Boost(id: "fixture-boost", name: "Fixture", scope: scope, css: "body { color: red; }", javascript: "document.body.dataset.boost='yes'", allowPrivate: true, javascriptApproved: true)
    }
    func testScopesAreExactAndOnlyHTTP() {
        let origin = SiteOrigin(URL(string: "https://EXAMPLE.test:443/path?q=x")!)!
        XCTAssertTrue(BoostScope.origin(origin).matches(URL(string: "https://example.test/other")!))
        XCTAssertFalse(BoostScope.origin(origin).matches(URL(string: "http://example.test/")!))
        XCTAssertFalse(BoostScope.origin(origin).matches(URL(string: "https://example.test:444/")!))
        XCTAssertTrue(BoostScope.host("example.test").matches(URL(string: "http://example.test:8080/")!))
        XCTAssertFalse(BoostScope.host("example.test").matches(URL(string: "https://sub.example.test/")!))
        XCTAssertFalse(BoostScope.host("example.test").matches(URL(string: "https://example.test.evil/")!))
        for value in ["file:///tmp/a", "chrome://settings", "about:blank", "data:text/html,a"] {
            XCTAssertFalse(BoostScope.allSites.matches(URL(string: value)!))
        }
    }
    func testImportAndExportNeverTransferTrust() throws {
        let original = boost()
        let stored = try BoostCodec.decode(BoostCodec.encode(BoostCatalog(boosts: [original])))
        XCTAssertEqual(stored.boosts, [original])
        let exported = try BoostCodec.export(original)
        let decoded = try BoostCodec.decode(exported).boosts[0]
        XCTAssertFalse(decoded.javascriptApproved); XCTAssertFalse(decoded.allowPrivate)
        let imported = try BoostCodec.imported(BoostCodec.encode(BoostCatalog(boosts: [original])), newID: { "imported-id" })[0]
        XCTAssertEqual(imported.id, "imported-id"); XCTAssertFalse(imported.javascriptApproved); XCTAssertFalse(imported.allowPrivate)
        XCTAssertEqual(imported.javascript, original.javascript)
    }
    func testCodecRejectsVersionsDuplicateIDsMalformedScopesAndLimits() throws {
        var catalog = BoostCatalog(boosts: [boost()]); catalog.version = 2
        XCTAssertThrowsError(try BoostCodec.encode(catalog))
        XCTAssertThrowsError(try BoostCodec.encode(BoostCatalog(boosts: [boost(), boost()])))
        for host in ["example.test/path", "example.test:8080", "EXAMPLE.test", "example.test?x", ""] {
            XCTAssertThrowsError(try BoostCodec.encode(BoostCatalog(boosts: [boost(.host(host))])))
        }
        var large = boost(); large.css = String(repeating: "x", count: 500_001)
        XCTAssertThrowsError(try BoostCodec.encode(BoostCatalog(boosts: [large])))
        XCTAssertThrowsError(try BoostCodec.decode(Data("{}".utf8)))
    }
    func testCatalogDoesNotEnterStateCodecV3() throws {
        let d = readyDriver(); d.system(.boost(.loaded(.default, BoostCatalog(boosts: [boost()]), error: nil)))
        XCTAssertEqual(StateCodec.currentVersion, 3)
        XCTAssertFalse(String(decoding: d.savedFile, as: UTF8.self).contains("fixture-boost"))
        XCTAssertEqual(d.snapshot.pages[0].boostPolicy.boosts[0].javascript, boost().javascript)
        XCTAssertTrue(Driver(file: d.savedFile).snapshot.pages[0].boostPolicy.boosts.isEmpty)
    }
    func testDraftPreviewRunsOnlyConfirmedJavaScriptAndCloseKeepsTheEdits() throws {
        let d = readyDriver(); d.system(.boost(.loaded(.default, BoostCatalog(boosts: [boost()]), error: nil)))
        d.user(.boost(.edit("fixture-boost")))
        var draft = try XCTUnwrap(d.view.boostEditor?.draft); draft.css = "body { color: blue }"
        d.user(.boost(.update(draft)))
        XCTAssertEqual(d.snapshot.pages[0].boostPolicy.boosts[0].css, draft.css)
        XCTAssertEqual(d.snapshot.pages[0].boostPolicy.boosts[0].javascript, boost().javascript, "the saved, confirmed program keeps running")
        draft.javascript += ";1"
        d.user(.boost(.update(draft)))
        XCTAssertEqual(d.snapshot.pages[0].boostPolicy.boosts[0].javascript, "", "typing never runs code")
        let editor = try XCTUnwrap(d.view.boostEditor)
        let closed = d.user(.boost(.close))
        guard case .boost(.write(_, _, let catalog, let owner))? = closed.effects.first else { return XCTFail("close did not save") }
        XCTAssertEqual(owner, editor.id); XCTAssertEqual(catalog.boosts[0].css, draft.css); XCTAssertFalse(catalog.boosts[0].javascriptApproved)
        d.system(.boost(.written(d.window, .default, catalog, editor: editor.id)))
        XCTAssertNil(d.view.boostEditor)
        XCTAssertEqual(d.snapshot.pages[0].boostPolicy.boosts[0].css, draft.css)
        XCTAssertEqual(d.snapshot.pages[0].boostPolicy.boosts[0].javascript, "", "changed JavaScript waits for the hammer's confirmation")
    }
    func testDiscardClosesADirtyDraftAtOnceAndAnUnchangedDraftClosesWithoutWriting() throws {
        let d = readyDriver(); d.system(.boost(.loaded(.default, BoostCatalog(boosts: [boost()]), error: nil)))
        d.user(.boost(.edit("fixture-boost")))
        var draft = try XCTUnwrap(d.view.boostEditor?.draft); draft.css = "body { color: blue }"
        d.user(.boost(.update(draft)))
        d.user(.boost(.discard))
        XCTAssertNil(d.view.boostEditor, "Maybe Later and discard drop the draft")
        XCTAssertEqual(d.snapshot.pages[0].boostPolicy.boosts[0].css, boost().css)
        d.user(.boost(.edit("fixture-boost")))
        XCTAssertTrue(d.user(.boost(.close)).effects.isEmpty)
        XCTAssertNil(d.view.boostEditor, "closing an unchanged Boost writes nothing")
    }
    func testTrustCannotBeGrantedByAnEditorUpdateAndConfirmationRejectsChangedDraft() throws {
        let d = readyDriver(); d.user(.boost(.create))
        var draft = try XCTUnwrap(d.view.boostEditor?.draft)
        draft.javascript = "document.title='boost'"; draft.javascriptApproved = true
        d.user(.boost(.update(draft)))
        let editor = try XCTUnwrap(d.view.boostEditor)
        XCTAssertFalse(editor.draft.javascriptApproved)
        XCTAssertEqual(d.user(.boost(.save)).effects, [.boost(.confirm(d.window, editor.id, editor.draft))])
        var edited = editor.draft; edited.javascript += ";1"
        d.user(.boost(.update(edited)))
        XCTAssertTrue(d.system(.boost(.approved(d.window, editor.id, editor.draft))).effects.isEmpty)
        let current = try XCTUnwrap(d.view.boostEditor)
        let effects = d.system(.boost(.approved(d.window, current.id, current.draft))).effects
        guard case .boost(.write(_, _, let catalog, _))? = effects.first else { return XCTFail("approved save did not write") }
        XCTAssertTrue(catalog.boosts[0].javascriptApproved)
        XCTAssertTrue(d.state.session.boosts[.default]?.boosts.isEmpty ?? true, "catalog must await durable write")
        d.system(.boost(.written(d.window, .default, catalog, editor: current.id)))
        XCTAssertNil(d.view.boostEditor)
        XCTAssertEqual(d.state.session.boosts[.default], catalog)
    }
    func testEditingCodeScopeOrPrivatePermissionRevokesApproval() throws {
        for mutation in 0..<3 {
            let d = readyDriver(); d.system(.boost(.loaded(.default, BoostCatalog(boosts: [boost()]), error: nil)))
            d.user(.boost(.edit("fixture-boost")))
            var draft = try XCTUnwrap(d.view.boostEditor?.draft)
            if mutation == 0 { draft.javascript += ";1" }
            if mutation == 1 { draft.scope = .host("example.test") }
            if mutation == 2 { draft.allowPrivate.toggle() }
            d.user(.boost(.update(draft)))
            XCTAssertFalse(try XCTUnwrap(d.view.boostEditor?.draft.javascriptApproved))
        }
    }
    func testWriteFailurePreservesUnsavedDraft() throws {
        let d = readyDriver(); d.user(.boost(.create))
        let draft = try XCTUnwrap(d.view.boostEditor?.draft)
        XCTAssertFalse(d.user(.boost(.save)).effects.isEmpty)
        d.system(.boost(.failed(d.window, "Disk full")))
        XCTAssertEqual(d.view.boostEditor?.draft, draft)
        XCTAssertEqual(d.view.boostEditor?.message, "Disk full")
        XCTAssertNil(d.state.session.boosts[.default])
    }
    func testZapResultIsDocumentAndEditorFenced() throws {
        let d = readyDriver(); d.user(.boost(.create))
        let editor = try XCTUnwrap(d.view.boostEditor), target = try XCTUnwrap(editor.target)
        d.user(.boost(.zap))
        let pickID = try XCTUnwrap(d.view.boostEditor?.pickID)
        d.system(.boost(.picked(d.window, "wrong-editor", target, "#wrong")))
        XCTAssertTrue(try XCTUnwrap(d.view.boostEditor?.picking))
        d.system(.boost(.picked(d.window, pickID, target, "#ad")))
        XCTAssertTrue(try XCTUnwrap(d.view.boostEditor?.draft.css).contains("#ad { display: none !important; }"))
        d.page(target.page.item, .documentChanged(.loading(DocumentToken(browser: target.document.browser, sequence: target.document.sequence + 1))))
        let before = d.view.boostEditor?.draft.css
        d.system(.boost(.picked(d.window, pickID, target, "#stale")))
        XCTAssertEqual(d.view.boostEditor?.draft.css, before)
        XCTAssertTrue(d.snapshot.pages[0].boostPolicy.boosts.isEmpty)
    }
    func testPrivateCreationIsRefusedAndExistingBoostsRequireOptIn() throws {
        let d = readyDriver(); var publicOnly = boost(); publicOnly.allowPrivate = false
        d.system(.boost(.loaded(.default, BoostCatalog(boosts: [publicOnly]), error: nil)))
        d.user(.window(.newIncognito)); let privateWindow = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .incognito }?.id)
        d.user(.commandBar(.submit("https://example.test/")), in: privateWindow)
        for command in [BoostCommand.create, .legacy, .gallery, .edit("fixture-boost"), .importFile, .remove("fixture-boost")] {
            XCTAssertTrue(d.user(.boost(command), in: privateWindow).effects.isEmpty)
            XCTAssertNil(d.view(of: privateWindow).boostEditor)
        }
        XCTAssertTrue(d.snapshot.pages.filter { $0.id.window == privateWindow }.allSatisfy { $0.boostPolicy.boosts.isEmpty })
        publicOnly.allowPrivate = true
        d.system(.boost(.loaded(.default, BoostCatalog(boosts: [publicOnly]), error: nil)))
        XCTAssertTrue(d.snapshot.pages.first { $0.id.window == privateWindow }?.boostPolicy.boosts.count == 1)
    }
    func testProfilesRemainSeparateAndBoostActionsAreResolved() {
        let d = readyDriver(); d.system(.boost(.loaded(.default, BoostCatalog(boosts: [boost()]), error: nil)))
        d.user(.profile(.create(name: "Other", icon: nil)))
        let profile = d.snapshot.settings.profiles.first { $0.profile.name == "Other" }!.profile.id
        d.user(.profile(.assign(.current, to: profile)))
        XCTAssertTrue(d.snapshot.pages.allSatisfy { $0.boostPolicy.boosts.isEmpty })
        for action in [ActionID.newBoost, .editBoost, .newLegacyBoost, .boostGallery] { XCTAssertNil(action.spec.later) }
    }
}

extension BoostTests {
    func testGalleryLegacyCurrentSiteAndFileCommandsAreRealEffects() throws {
        let d = readyDriver(); let original = boost()
        d.system(.boost(.loaded(.default, BoostCatalog(boosts: [original]), error: nil)))
        d.user(.boost(.gallery))
        guard case .library(let library)? = d.view.overlay else { return XCTFail("gallery missing") }
        XCTAssertEqual(library.boosts.count, 1)
        d.user(.boost(.preset("reader")))
        XCTAssertEqual(d.view.boostEditor?.draft.name, "Comfortable reading")
        d.user(.boost(.legacy)); XCTAssertNotNil(d.view.boostEditor)
        d.user(.boost(.editCurrent)); XCTAssertEqual(d.view.boostEditor?.draft.id, original.id)
        d.user(.boost(.close))
        let file = URL(fileURLWithPath: "/tmp/owned-boost.json")
        XCTAssertEqual(d.user(.boost(.importSelected(file))).effects, [.boost(.importFile(d.window, .default, file))])
        XCTAssertEqual(d.user(.boost(.exportSelected(original.id, file))).effects, [.boost(.exportFile(d.window, original, file))])
        XCTAssertEqual(d.user(.boost(.export(original.id))).effects, [.boost(.exportFile(d.window, original, nil))])
        XCTAssertEqual(d.user(.boost(.importFile)).effects, [.boost(.importFile(d.window, .default, nil))])
        guard case .boost(.write(_, _, let disabled, _))? = d.user(.boost(.enable(original.id, false))).effects.first else { return XCTFail("disable missing") }
        XCTAssertFalse(disabled.boosts[0].enabled)
        guard case .boost(.write(_, _, let removed, _))? = d.user(.boost(.remove(original.id))).effects.first else { return XCTFail("remove missing") }
        XCTAssertTrue(removed.boosts.isEmpty)
    }
    func testInjectionErrorsAreDocumentFencedAndVisibleInLibrary() throws {
        let d = readyDriver()
        // Use this driver's identity, rather than accepting an unrelated document.
        let own = try XCTUnwrap(d.state.siteTarget(in: d.window))
        d.page(own.page.item, .boostFailed(own.document, "Syntax error in Boost"))
        d.user(.library(.open(.boosts)))
        guard case .library(let library)? = d.view.overlay else { return XCTFail("missing Library") }
        XCTAssertEqual(library.boostMessage, "Syntax error in Boost")
        let stale = DocumentToken(browser: own.document.browser, sequence: 999)
        d.page(own.page.item, .boostFailed(stale, "stale"))
        XCTAssertEqual(d.state.session.windows[d.window]?.boostMessage, "Syntax error in Boost")
    }
}

extension BoostTests {
    func testGlobalPreferenceRemovesAllInjectionAndZapTogglePreservesDraft() throws {
        let d = readyDriver()
        d.system(.boost(.loaded(.default, BoostCatalog(boosts: [boost()]), error: nil)))
        XCTAssertFalse(d.snapshot.pages[0].boostPolicy.boosts.isEmpty)
        d.user(.settings(.advanced(.boostsEnabled(false))))
        XCTAssertTrue(d.snapshot.pages[0].boostPolicy.boosts.isEmpty)
        d.user(.settings(.advanced(.boostsEnabled(true))))
        d.user(.boost(.create))
        let draft = try XCTUnwrap(d.view.boostEditor?.draft)
        d.user(.boost(.zap)); XCTAssertEqual(d.view.boostEditor?.picking, true)
        d.user(.boost(.zap)); XCTAssertEqual(d.view.boostEditor?.picking, false)
        XCTAssertEqual(d.view.boostEditor?.draft, draft)
    }
}

extension BoostTests {
    func testCancelledZapCannotCompleteANewerPickInTheSameEditor() throws {
        let d = readyDriver(); d.user(.boost(.create)); d.user(.boost(.zap))
        let editor = try XCTUnwrap(d.view.boostEditor), oldPick = try XCTUnwrap(editor.pickID), target = try XCTUnwrap(editor.target)
        d.user(.boost(.zap)); d.user(.boost(.zap))
        XCTAssertNotEqual(d.view.boostEditor?.pickID, oldPick)
        d.system(.boost(.picked(d.window, oldPick, target, "#stale")))
        XCTAssertEqual(d.view.boostEditor?.picking, true)
        XCTAssertEqual(d.view.boostEditor?.draft.css, "")
    }
}

extension BoostTests {
    func testExitCancelsZapBeforeClosingTheUnsavedEditor() throws {
        let d = readyDriver(); d.user(.boost(.create)); d.user(.boost(.zap))
        let draft = try XCTUnwrap(d.view.boostEditor?.draft)
        d.user(.app(.exit))
        XCTAssertEqual(d.view.boostEditor?.picking, false)
        XCTAssertNil(d.view.boostEditor?.pickID)
        XCTAssertEqual(d.view.boostEditor?.draft, draft)
        XCTAssertTrue(d.user(.app(.exit)).effects.isEmpty, "a blank never-saved Boost is not written")
        XCTAssertNil(d.view.boostEditor)
    }
    func testZapRefusesAnEditorWhoseCapturedPageIsNoLongerVisible() throws {
        let d = readyDriver(); d.user(.boost(.create))
        _ = d.open("https://other.example/")
        XCTAssertTrue(d.user(.boost(.zap)).effects.isEmpty)
        XCTAssertEqual(d.view.boostEditor?.picking, false)
    }
}

extension BoostTests {
    func testLibraryCoverCancelsZapAndRejectsTheLateSelection() throws {
        let d = readyDriver(); d.user(.boost(.create)); d.user(.boost(.zap))
        let editor = try XCTUnwrap(d.view.boostEditor), pick = try XCTUnwrap(editor.pickID), target = try XCTUnwrap(editor.target)
        d.user(.library(.open(.boosts)))
        XCTAssertEqual(d.view.boostEditor?.picking, false)
        XCTAssertNil(d.view.boostEditor?.pickID)
        XCTAssertTrue(d.user(.boost(.zap)).effects.isEmpty)
        d.system(.boost(.picked(d.window, pick, target, "#hidden")))
        XCTAssertEqual(d.view.boostEditor?.draft.css, "")
    }
    func testNavigationAwayCancelsAnActiveZapWithoutLosingItsDraft() throws {
        let d = readyDriver(); d.user(.boost(.create)); d.user(.boost(.zap))
        let draft = try XCTUnwrap(d.view.boostEditor?.draft)
        _ = d.open("https://another.example/")
        XCTAssertEqual(d.view.boostEditor?.picking, false)
        XCTAssertNil(d.view.boostEditor?.pickID)
        XCTAssertEqual(d.view.boostEditor?.draft, draft)
    }
}

extension BoostTests {
    func testFirstBoostOpensOnTheIntroCardAndMaybeLaterCreatesNothing() throws {
        let d = readyDriver(); d.user(.boost(.create))
        XCTAssertEqual(d.view.boostEditor?.page, .intro)
        d.user(.boost(.page(.style)))
        XCTAssertEqual(d.view.boostEditor?.page, .style, "Make a Boost")
        d.user(.boost(.discard))
        XCTAssertNil(d.view.boostEditor)
        d.user(.boost(.create))
        XCTAssertTrue(d.user(.boost(.close)).effects.isEmpty, "× on the intro card creates no Boost")
        d.system(.boost(.loaded(.default, BoostCatalog(boosts: [boost()]), error: nil)))
        d.user(.boost(.create))
        XCTAssertEqual(d.view.boostEditor?.page, .style, "the card is for the first Boost only")
        d.user(.boost(.page(.javascript)))
        XCTAssertEqual(d.view.boostEditor?.page, .javascript)
    }
    func testStyleControlsCompileIntoThePagesCSSAndSurviveTheFile() throws {
        let d = readyDriver(); d.user(.boost(.create)); d.user(.boost(.page(.style)))
        var draft = try XCTUnwrap(d.view.boostEditor?.draft)
        draft.style = BoostStyle(tint: BoostPoint(x: 0.6, y: 0.3), text: BoostPoint(x: 0.1, y: 0.9), inverted: true, intensity: 2, font: 8, size: 2, textCase: .upper)
        draft.css = "#own { color: red }"
        d.user(.boost(.update(draft)))
        let css = try XCTUnwrap(d.snapshot.pages.first?.boostPolicy.boosts.first?.css)
        for part in ["mix-blend-mode: multiply", "opacity: 0.56", "invert(1)", "font-family: Georgia", "zoom: 1.3", "uppercase", "#own { color: red }"] {
            XCTAssertTrue(css.contains(part), part)
        }
        XCTAssertLessThan(try XCTUnwrap(css.range(of: "font-family")).lowerBound, try XCTUnwrap(css.range(of: "#own")).lowerBound, "the Code page's CSS comes last and wins")
        let stored = try BoostCodec.decode(BoostCodec.encode(BoostCatalog(boosts: [d.view.boostEditor!.draft])))
        XCTAssertEqual(stored.boosts[0].style, draft.style)
        var invalid = draft; invalid.style?.font = 99
        d.user(.boost(.update(invalid)))
        XCTAssertEqual(d.view.boostEditor?.draft.style?.font, 8, "an out-of-range control value is refused")
        XCTAssertThrowsError(try BoostCodec.encode(BoostCatalog(boosts: [invalid])))
        var cleared = draft; cleared.style = BoostStyle(); cleared.css = ""
        d.user(.boost(.update(cleared)))
        XCTAssertNil(d.view.boostEditor?.draft.style, "the reset button's empty style is no style")
        XCTAssertTrue(d.view.boostEditor?.draft.isBlank == true)
        let legacy = try BoostCodec.decode(Data(#"{"version":1,"boosts":[{"id":"old","name":"Old","scope":{"allSites":{}},"css":"a{}","javascript":"","enabled":true,"allowPrivate":false,"javascriptApproved":false}]}"#.utf8))
        XCTAssertNil(legacy.boosts[0].style, "Boost files from before the visual controls still load")
    }
    func testCloseSavesANewBoostAndABlankOneCreatesNothing() throws {
        let d = readyDriver(); d.user(.boost(.create)); d.user(.boost(.page(.style)))
        XCTAssertTrue(d.user(.boost(.close)).effects.isEmpty)
        XCTAssertNil(d.view.boostEditor)
        d.user(.boost(.create)); d.user(.boost(.page(.style)))
        var draft = try XCTUnwrap(d.view.boostEditor?.draft); draft.style = BoostStyle(font: 3)
        d.user(.boost(.update(draft)))
        let editor = try XCTUnwrap(d.view.boostEditor)
        guard case .boost(.write(_, _, let catalog, let owner))? = d.user(.boost(.close)).effects.first else { return XCTFail("close did not save") }
        XCTAssertEqual(owner, editor.id)
        XCTAssertNotNil(d.view.boostEditor, "the panel waits for the durable write")
        d.system(.boost(.written(d.window, .default, catalog, editor: editor.id)))
        XCTAssertNil(d.view.boostEditor)
        XCTAssertEqual(d.state.session.boosts[.default]?.boosts.first?.style?.font, 3)
    }
    func testZapStaysArmedAfterEachPickAndEscapeOnThePageEndsItQuietly() throws {
        let d = readyDriver(); d.user(.boost(.create)); d.user(.boost(.page(.style)))
        let target = try XCTUnwrap(d.view.boostEditor?.target)
        d.user(.boost(.zap))
        let first = try XCTUnwrap(d.view.boostEditor?.pickID)
        let rearmed = d.system(.boost(.picked(d.window, first, target, "#ad")))
        let second = try XCTUnwrap(d.view.boostEditor?.pickID)
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(rearmed.effects, [.boost(.pick(d.window, second, target))])
        XCTAssertEqual(d.view.boostEditor?.picking, true)
        d.system(.boost(.picked(d.window, second, target, "#ad")))
        let third = try XCTUnwrap(d.view.boostEditor?.pickID)
        d.system(.boost(.picked(d.window, third, target, "main > p:nth-of-type(2)")))
        let css = try XCTUnwrap(d.view.boostEditor?.draft.css)
        XCTAssertEqual(css.components(separatedBy: "#ad { display: none !important; }").count, 2, "a second Zap of the same element adds nothing")
        XCTAssertTrue(css.contains("main > p:nth-of-type(2) { display: none !important; }"))
        let fourth = try XCTUnwrap(d.view.boostEditor?.pickID)
        XCTAssertTrue(d.system(.boost(.picked(d.window, fourth, target, nil))).effects.isEmpty)
        XCTAssertEqual(d.view.boostEditor?.picking, false)
        XCTAssertNil(d.view.boostEditor?.message, "Escape is not an error")
    }
    func testEyedropperInsertsTheSelectorIntoTheOpenCodeSegment() throws {
        let d = readyDriver(); d.user(.boost(.create)); d.user(.boost(.page(.css)))
        let target = try XCTUnwrap(d.view.boostEditor?.target)
        d.user(.boost(.inspect))
        XCTAssertEqual(d.view.boostEditor?.pickPurpose, .selector)
        d.system(.boost(.picked(d.window, try XCTUnwrap(d.view.boostEditor?.pickID), target, "#hero")))
        XCTAssertEqual(d.view.boostEditor?.picking, false, "the eyedropper picks once")
        XCTAssertTrue(try XCTUnwrap(d.view.boostEditor?.draft.css).contains("#hero {\n"))
        d.user(.boost(.page(.javascript)))
        d.user(.boost(.inspect))
        d.system(.boost(.picked(d.window, try XCTUnwrap(d.view.boostEditor?.pickID), target, "#hero")))
        XCTAssertEqual(d.view.boostEditor?.draft.javascript, "document.querySelector(\"#hero\")\n")
        d.user(.boost(.inspect)); XCTAssertEqual(d.view.boostEditor?.picking, true)
        d.user(.boost(.page(.style)))
        XCTAssertEqual(d.view.boostEditor?.picking, false, "leaving the Code page ends its pick")
    }
    func testHammerConfirmsJavaScriptSavesAndKeepsThePanelOpen() throws {
        let d = readyDriver(); d.user(.boost(.create)); d.user(.boost(.page(.javascript)))
        var draft = try XCTUnwrap(d.view.boostEditor?.draft); draft.javascript = "document.title='boost'"
        d.user(.boost(.update(draft)))
        let editor = try XCTUnwrap(d.view.boostEditor)
        XCTAssertEqual(d.user(.boost(.save)).effects, [.boost(.confirm(d.window, editor.id, editor.draft))])
        guard case .boost(.write(_, _, let catalog, let owner))? = d.system(.boost(.approved(d.window, editor.id, editor.draft))).effects.first else { return XCTFail("approval did not write") }
        XCTAssertNil(owner, "the hammer saves without closing")
        XCTAssertEqual(d.view.boostEditor?.draft.javascriptApproved, true)
        XCTAssertEqual(d.snapshot.pages[0].boostPolicy.boosts[0].javascript, "", "nothing runs before the write is durable")
        d.system(.boost(.written(d.window, .default, catalog, editor: nil)))
        XCTAssertNotNil(d.view.boostEditor)
        XCTAssertEqual(d.view.boostEditor?.message, "JavaScript allowed and saved.")
        XCTAssertEqual(d.snapshot.pages[0].boostPolicy.boosts[0].javascript, "document.title='boost'")
    }
}
