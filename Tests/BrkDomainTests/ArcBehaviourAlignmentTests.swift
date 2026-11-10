import BrkBase
import CoreGraphics
import Foundation
import XCTest
@testable import BrkDomain

/// The behaviour half of the 2026-11-03 Arc pairing (verify/visual-pairs/run-20261103/REPORT.md, "留到下一轮的"):
/// the Ctrl+Tab switcher switches on release, Developer Mode shows the whole address, the Library card's Edit Space…
/// is the theme panel, and Secure needs a clean certificate.
final class ArcBehaviourAlignmentTests: XCTestCase {
    /// Makes `tab`'s current page a ready document and returns it.
    private func ready(_ d: Driver, _ tab: ItemID) throws -> DocumentToken {
        let page = PageID(window: d.window, item: tab)
        let browser = try XCTUnwrap(d.state.session.live[page]?.browser)
        let document = DocumentToken(browser: browser, sequence: (d.state.session.live[page]?.documentSequence ?? 0) + 1)
        d.page(tab, .documentChanged(.loading(document)))
        d.page(tab, .documentChanged(.ready(document)))
        return document
    }

    // MARK: Ctrl+Tab

    /// each Tab press while Control is held moves only the switcher's selection; the window and the sidebar keep the
    /// page the walk started from until Control is released, which shows the selection
    func testCtrlTabSwitchesOnlyWhenControlIsReleased() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        let b = d.open("http://127.0.0.1:9/b")
        let c = d.open("http://127.0.0.1:9/c")
        d.system(.window(d.window, .modifiersChanged(held: [.control])))
        d.user(.tab(.cycleRecent(.next)))
        XCTAssertEqual(d.view.tabTools.recent?.items.map(\.id), [c, b, a])
        XCTAssertEqual(d.view.tabTools.recent?.selected, b)
        XCTAssertEqual(d.current?.id, c, "the sidebar still selects the page the walk started from")
        XCTAssertEqual(d.view.content.panes.map(\.tab), [c], "the content still shows it")
        d.user(.tab(.cycleRecent(.next)))
        XCTAssertEqual(d.view.tabTools.recent?.selected, a)
        XCTAssertEqual(d.current?.id, c)
        d.system(.window(d.window, .modifiersChanged(held: [])))
        XCTAssertNil(d.view.tabTools.recent)
        XCTAssertEqual(d.current?.id, a, "releasing Control shows the selection")
        XCTAssertEqual(d.view.content.panes.map(\.tab), [a])
    }

    /// the sweep tick leaves a held walk open; with Control no longer held (its release went missing) it commits
    func testTheClockTickCommitsOnlyAWalkWhoseControlIsNoLongerHeld() throws {
        let d = Driver()
        let a = d.todayIDs[0]
        let b = d.open("http://127.0.0.1:9/b")
        d.system(.window(d.window, .modifiersChanged(held: [.control])))
        d.user(.tab(.cycleRecent(.next)))
        d.system(.clockTick)
        XCTAssertEqual(d.view.tabTools.recent?.selected, a, "Control is still down: the switcher stays")
        XCTAssertEqual(d.current?.id, b)
        let lost = Driver()
        let first = lost.todayIDs[0]
        _ = lost.open("http://127.0.0.1:9/b")
        lost.user(.tab(.cycleRecent(.next)))   // no Control reported down, as after a release delivered elsewhere
        lost.system(.clockTick)
        XCTAssertNil(lost.view.tabTools.recent)
        XCTAssertEqual(lost.current?.id, first)
    }

    // MARK: Developer Mode

    /// with the site's Developer Mode on, the pill shows the whole address (scheme, path, query); off, the host
    func testDeveloperModeShowsTheWholeAddressInThePill() throws {
        let d = Driver()
        let tab = d.open("https://www.example.test/docs/page?x=1")
        _ = try ready(d, tab)
        XCTAssertEqual(d.view.urlPill.host, "example.test")
        let target = try XCTUnwrap(d.state.siteTarget(in: d.window))
        var rule = SiteRule()
        rule.developerMode = true
        d.user(.site(.rule(target, rule)))
        XCTAssertEqual(d.view.urlPill.host, "https://www.example.test/docs/page?x=1")
        d.user(.sidebar(.toggleToolbar))
        XCTAssertEqual(d.view.urlPill.toolbarText, "https://www.example.test/docs/page?x=1", "the toolbar's address follows the pill")
        let other = d.open("https://other.test/a")
        _ = try ready(d, other)
        XCTAssertEqual(d.view.urlPill.host, "other.test", "Developer Mode is per site")
        d.user(.tab(.focus(tab)))
        rule.developerMode = false
        d.user(.site(.rule(try XCTUnwrap(d.state.siteTarget(in: d.window)), rule)))
        XCTAssertEqual(d.view.urlPill.host, "example.test")
    }

    // MARK: Theme panel

    /// Spaces > Edit Theme…, the space's Edit Theme Color… and the Library Space card's Edit Space… all open the theme
    /// panel; from the Library it opens beside it and the Library stays open
    func testEveryEditThemeEntryOpensTheThemePanel() throws {
        let d = Driver()
        let space = d.view.space.id
        d.user(ActionID.editSpaceTheme.spec.command)
        guard case .theme(space, _)? = d.view.dialog else { return XCTFail("Edit Theme… did not open the theme panel") }
        d.user(.sidebar(.openDialog(nil)))
        let menu = try XCTUnwrap(popup(d.user(.sidebar(.popupMenu(.space(space), at: .zero)))))
        d.user(try XCTUnwrap(command(menu, "Edit Theme Color…")))
        guard case .theme(space, _)? = d.view.dialog else { return XCTFail("Edit Theme Color… did not open the theme panel") }
        d.user(.sidebar(.openDialog(nil)))
        d.user(.library(.open(.spaces)))
        d.user(.sidebar(.openDialog(.theme(.space(space)))))   // the card's pencil and its … menu's Edit Space…
        guard case .theme(space, _)? = d.view.dialog else { return XCTFail("Edit Space… did not open the theme panel") }
        guard case .library? = d.view.overlay else { return XCTFail("the Library closed") }
        d.user(.app(.exit))
        XCTAssertNil(d.view.dialog, "Esc closes the theme panel above the Library first")
        guard case .library? = d.view.overlay else { return XCTFail("Esc closed the Library under the theme panel") }
        d.user(.app(.exit))
        XCTAssertNil(d.view.overlay, "the next Esc closes the Library")
    }

    // MARK: Secure / Insecure

    /// Secure needs https and an engine report of a clean certificate and content for the shown document; a report
    /// about an earlier document does not count, and http is never secure
    func testSecureFollowsTheCertificateAndContentNotOnlyTheScheme() throws {
        let d = Driver()
        let tab = d.open("https://example.test/")
        let document = try ready(d, tab)
        d.user(.site(.controls))
        XCTAssertEqual(d.snapshot.sites[d.window]?.secure, true, "https before the engine reports counts as secure")
        d.page(tab, .securityChanged(PageSecurity(document: document, secureConnection: true, certificateError: true, insecureContent: false)))
        XCTAssertEqual(d.snapshot.sites[d.window]?.secure, false, "a certificate error makes https Insecure")
        XCTAssertEqual(d.snapshot.sites[d.window]?.security?.certificateError, true)
        d.page(tab, .securityChanged(PageSecurity(document: document, secureConnection: true, certificateError: false, insecureContent: true)))
        XCTAssertEqual(d.snapshot.sites[d.window]?.secure, false, "insecure content makes https Insecure")
        d.page(tab, .securityChanged(PageSecurity(document: document, secureConnection: true, certificateError: false, insecureContent: false, insecureForm: true)))
        XCTAssertEqual(d.snapshot.sites[d.window]?.secure, false, "a form posting over plain HTTP makes https Insecure")
        XCTAssertEqual(d.snapshot.sites[d.window]?.security?.insecureForm, true)
        d.page(tab, .securityChanged(PageSecurity(document: document, secureConnection: true, certificateError: false, insecureContent: false)))
        XCTAssertEqual(d.snapshot.sites[d.window]?.secure, true)
        // A report for a document that is no longer shown is ignored.
        let stale = PageSecurity(document: DocumentToken(browser: document.browser, sequence: document.sequence + 5), secureConnection: true, certificateError: true, insecureContent: false)
        assertUnchanged(d.state, d.page(tab, .securityChanged(stale)))
        d.page(tab, .securityChanged(PageSecurity(document: document, secureConnection: true, certificateError: true, insecureContent: false)))
        let next = try ready(d, tab)
        XCTAssertNotEqual(next, document)
        XCTAssertEqual(d.snapshot.sites[d.window]?.secure, true, "the next document is not judged by the last one's report")
        let plain = d.open("http://example.test/")
        let plainDocument = try ready(d, plain)
        d.page(plain, .securityChanged(PageSecurity(document: plainDocument, secureConnection: false, certificateError: false, insecureContent: false)))
        XCTAssertEqual(d.snapshot.sites[d.window]?.secure, false, "http is Insecure")
    }
}
