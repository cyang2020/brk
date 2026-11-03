import AppKit
import BrkBase
@testable import BrkDomain
@testable import BrkSettings
import XCTest

/// P36-a: Arc's site control center is 237 pt wide; a web page adds the security row under Developer Mode.
@MainActor
final class SiteControlsOverviewTests: XCTestCase {
    private func snapshot(_ url: String?, secure: Bool = false) -> SiteControlSnapshot {
        let page = PageID(window: WindowID("window"), item: ItemID("item"))
        let target = url.flatMap(URL.init(string:)).flatMap(SiteOrigin.init).map {
            SiteTarget(document: DocumentToken(browser: BrowserToken(page: page, generation: 1), sequence: 1), context: .profile(.default), origin: $0)
        }
        return SiteControlSnapshot(context: .profile(.default), applied: nil, rulesVersion: 1, rulesError: nil, extensionsLoaded: true,
                                   extensions: [], pinnedExtensions: [], extensionError: nil, target: target, profileName: "Default",
                                   rule: SiteRule(), appearance: .automatic, clearing: false, result: nil, secure: secure)
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
        XCTAssertEqual(host.preferredSize, CGSize(width: 237, height: 202))
        XCTAssertEqual(try XCTUnwrap(chip(in: host)).isHidden, true)

        var resized: CGSize?
        host.onResize = { resized = $0 }
        host.render(snapshot("http://127.0.0.1:8764/home.html")) { _ in }
        XCTAssertEqual(host.preferredSize, CGSize(width: 237, height: 255))
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
