import CefKit
import Foundation
import XCTest

final class ExtRequestFilterTests: XCTestCase {
    func testImportedURLPrefixKeepsSchemeHostPortAndPathBoundaries() {
        let filter = CefRequestFilter()
        filter.configure(enabled: true, hosts: [], paths: [], urlPrefixes: ["https://fixture.test:8443/ads/"])
        XCTAssertTrue(filter.blocks(URL(string: "https://fixture.test:8443/ads/ad.js?x=1")!))
        for input in ["https://fixture.test:8443/news", "https://fixture.test:8443/ads-other/", "https://fixture.test.evil:8443/ads/ad.js", "http://fixture.test:8443/ads/ad.js", "https://fixture.test/ads/ad.js"] {
            XCTAssertFalse(filter.blocks(URL(string: input)!), input)
        }
        filter.configure(enabled: false, hosts: [], paths: [], urlPrefixes: ["https://fixture.test:8443/ads/"])
        XCTAssertFalse(filter.blocks(URL(string: "https://fixture.test:8443/ads/ad.js")!))
    }
}
