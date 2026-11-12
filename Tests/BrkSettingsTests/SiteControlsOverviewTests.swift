import AppKit
import BrkBase
@testable import BrkDomain
@testable import BrkSettings
import XCTest

/// P36-a: Arc's site control center is 237 pt wide; a web page adds the security row under Developer Mode.
@MainActor
final class SiteControlsOverviewTests: XCTestCase {
    /// The second page's connection note names the reason for Insecure: plain HTTP, the certificate, insecure content,
    /// or a plain HTTP form.
    func testConnectionNoteNamesTheReason() throws {
        let document = DocumentToken(browser: BrowserToken(page: PageID(window: WindowID("w"), item: ItemID("i")), generation: 1), sequence: 1)
        func target(_ url: String) -> SiteTarget { SiteTarget(document: document, context: .profile(.default), origin: SiteOrigin(URL(string: url)!)!) }
        func report(certificate: Bool = false, content: Bool = false, form: Bool = false) -> PageSecurity {
            PageSecurity(document: document, secureConnection: true, certificateError: certificate, insecureContent: content, insecureForm: form)
        }
        let https = target("https://127.0.0.1:8781")
        XCTAssertEqual(SiteControlsHost.connectionNote(target("http://127.0.0.1:8764"), secure: false, security: nil),
                       "Connection is not secure: this site uses plain HTTP.")
        XCTAssertEqual(SiteControlsHost.connectionNote(https, secure: true, security: report()), "Connection is secure (HTTPS).")
        XCTAssertEqual(SiteControlsHost.connectionNote(https, secure: false, security: report(certificate: true, form: true)),
                       "Connection is not secure: the site's certificate is not valid.")
        XCTAssertEqual(SiteControlsHost.connectionNote(https, secure: false, security: report(form: true)),
                       "Connection is not secure: a form on this page sends information over plain HTTP.")
        XCTAssertEqual(SiteControlsHost.connectionNote(https, secure: false, security: report(content: true, form: true)),
                       "Connection is not secure: this page loaded content over plain HTTP.")
    }

    private func snapshot(_ url: String?, secure: Bool = false) -> SiteControlSnapshot {
        let page = PageID(window: WindowID("window"), item: ItemID("item"))
        let target = url.flatMap(URL.init(string:)).flatMap(SiteOrigin.init).map {
            SiteTarget(document: DocumentToken(browser: BrowserToken(page: page, generation: 1), sequence: 1), context: .profile(.default), origin: $0)
        }
        return SiteControlSnapshot(context: .profile(.default), applied: nil, rulesVersion: 1, rulesError: nil, extensionsLoaded: true,
                                   extensions: [], pinnedExtensions: [], extensionError: nil, target: target, profileName: "Default",
                                   rule: SiteRule(), appearance: .automatic, clearing: false, result: nil, secure: secure)
    }

    /// While the page still loads the Clear buttons are off, and a line above them says why.
    func testClearNoteShowsOnlyWhileThePageLoads() {
        var value = snapshot("https://example.com/")
        XCTAssertEqual(SiteControlsHost.clearNote(value), "Clearing works once the page has finished loading.")
        value.ready = true
        XCTAssertNil(SiteControlsHost.clearNote(value))
        XCTAssertNil(SiteControlsHost.clearNote(snapshot(nil)), "no web page, no note")
    }

    private func chip(in view: NSView) -> SecurityChip? {
        for child in view.subviews {
            if let chip = child as? SecurityChip { return chip }
            if let found = chip(in: child) { return found }
        }
        return nil
    }

    func testSecurityRowShowsOnlyForWebPagesWithArcsHeights() throws {
        let host = SiteControlsHost(frame: .zero)
        host.render(snapshot(nil)) { _ in }
        XCTAssertEqual(host.preferredSize, CGSize(width: 237, height: 199.5))
        XCTAssertEqual(try XCTUnwrap(chip(in: host)).isHidden, true)

        var resized: CGSize?
        host.onResize = { resized = $0 }
        host.render(snapshot("http://127.0.0.1:8764/home.html")) { _ in }
        // P36-a: the body spans y 182 to 689 px (253.5 pt) in Arc's capture.
        XCTAssertEqual(host.preferredSize, CGSize(width: 237, height: 254))
        XCTAssertEqual(resized, host.preferredSize, "the popover grows with the security row")
        let insecure = try XCTUnwrap(chip(in: host))
        XCTAssertFalse(insecure.isHidden)
        XCTAssertEqual(insecure.accessibilityLabel(), "Insecure")

        host.render(snapshot("https://example.com/", secure: true)) { _ in }
        XCTAssertEqual(try XCTUnwrap(chip(in: host)).accessibilityLabel(), "Secure")
        // An https page with a certificate error or insecure content (the snapshot's verdict) is the red Insecure.
        host.render(snapshot("https://self-signed.example/", secure: false)) { _ in }
        XCTAssertEqual(try XCTUnwrap(chip(in: host)).accessibilityLabel(), "Insecure")
    }
}
