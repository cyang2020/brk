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

    func testPillIndicatesOnlyAnEnabledBoostMatchingItsSite() {
        let d = readyDriver()
        XCTAssertFalse(d.view.urlPill.hasActiveBoost)
        d.system(.boost(.loaded(.default, BoostCatalog(boosts: [boost()]), error: nil)))
        XCTAssertTrue(d.view.urlPill.hasActiveBoost)
        var disabled = boost(); disabled.enabled = false
        d.system(.boost(.loaded(.default, BoostCatalog(boosts: [disabled]), error: nil)))
        XCTAssertFalse(d.view.urlPill.hasActiveBoost)
        d.system(.boost(.loaded(.default, BoostCatalog(boosts: [boost(.host("other.example"))]), error: nil)))
        XCTAssertFalse(d.view.urlPill.hasActiveBoost)
    }
    /// Review F8 and #21: a typed internationalised host or IPv6 address is stored as committed URLs report it, so the
    /// scope matches and the file validates.
    func testTypedHostsAreStoredAsCommittedURLsReportThem() throws {
        XCTAssertEqual(BoostScope.host(typed: " Bücher.Example "), "xn--bcher-kva.example")
        XCTAssertEqual(BoostScope.host(typed: "[::1]"), "::1")
        XCTAssertEqual(BoostScope.host(typed: "::1"), "::1")
        XCTAssertEqual(BoostScope.host(typed: "example.test:8080"), "example.test")
        for bad in ["", "a b", "example.test/path"] { XCTAssertNil(BoostScope.host(typed: bad), bad) }
        XCTAssertTrue(BoostScope.host("xn--bcher-kva.example").matches(URL(string: "https://bücher.example/")!))
        XCTAssertTrue(BoostScope.host("::1").matches(URL(string: "http://[::1]:8080/a")!))
        for host in ["xn--bcher-kva.example", "::1"] { XCTAssertNoThrow(try BoostCodec.encode(BoostCatalog(boosts: [boost(.host(host))])), host) }
    }

    /// Review #18: a reload of the editor's page keeps the preview on the new document of the same origin.
    func testTheEditorFollowsItsPageThroughAReload() throws {
        let d = readyDriver(); d.system(.boost(.loaded(.default, BoostCatalog(boosts: [boost()]), error: nil)))
        d.user(.boost(.edit("fixture-boost")))
        var draft = try XCTUnwrap(d.view.boostEditor?.draft); draft.css = "body { color: blue }"
        d.user(.boost(.update(draft)))
        XCTAssertEqual(d.snapshot.pages[0].boostPolicy.boosts.first?.css, draft.css)
        let page = d.snapshot.pages[0].id
        let browser = d.state.session.live[page]!.browser!
        let reloaded = DocumentToken(browser: browser, sequence: 2)
        d.page(page.item, .documentChanged(.loading(reloaded)))
        d.page(page.item, .documentChanged(.ready(reloaded)))
        XCTAssertEqual(d.snapshot.pages[0].boostPolicy.boosts.first?.css, draft.css, "the preview ended with the reload")
        let editor = try XCTUnwrap(d.view.boostEditor)
        XCTAssertEqual(d.state.boostEditorTarget(editor)?.document, reloaded)
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
}
