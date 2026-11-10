import BrkBase
@testable import BrkDomain
import XCTest

/// Arc's toasts as its binary names them (`ToastController`) and the references show them (Q11-b, P15, P33-d), and the
/// + popover's rows (Q11-a). verify/visual-pairs/run-20261103/r4-14/POPUPS.md has the table.
final class ToastCatalogTests: XCTestCase {
    private func toast(_ d: Driver) -> ToastSnapshot? { d.view.tabTools.toast }

    func testCopyURLToastCarriesShareExceptInAPrivateWindow() throws {
        let d = Driver()
        let tab = d.open("example.com/one")
        for format in [CopyURLFormat.plain, .markdown, .quote] {
            d.user(.tabTools(.dismissToast))
            d.user(.page(.copyURL(format)))
            XCTAssertEqual(toast(d)?.text, ToastCopy.copiedCurrentURL, "\(format)")
            XCTAssertEqual(toast(d)?.action?.symbol, "square.and.arrow.up")
            XCTAssertEqual(toast(d)?.action?.command, .app(.export(.items([tab]))))
        }
        d.user(.window(.newIncognito))
        let incognito = try XCTUnwrap(d.state.doc.windows.first { $0.value.kind == .incognito }?.key)
        d.user(.commandBar(.open(.newTab)), in: incognito)
        d.user(.commandBar(.submit("example.com/private")), in: incognito)
        d.user(.page(.copyURL(.plain)), in: incognito)
        XCTAssertEqual(d.view(of: incognito).tabTools.toast?.text, ToastCopy.copiedCurrentURL)
        XCTAssertNil(d.view(of: incognito).tabTools.toast?.action, "a private tab has nothing to share")
    }

    func testPlusMenuInAPrivateWindowKeepsWhatWorksThere() throws {
        let d = Driver()
        d.user(.window(.newIncognito))
        let incognito = try XCTUnwrap(d.state.doc.windows.first { $0.value.kind == .incognito }?.key)
        let enabled = d.view(of: incognito).plusMenu.flatMap { $0 }.filter(\.enabled).map(\.title)
        XCTAssertEqual(enabled, ["New Split", "New Tab"])
    }
}
