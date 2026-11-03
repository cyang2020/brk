import CefKit
import XCTest

/// The site controls' Secure / Insecure reads Chromium's SSL status of the visible entry (CEF's `cef_sslstatus_t`).
/// These are the bits Chromium's own indicator counts: a certificate error except the minor revocation-check ones,
/// and displayed or run insecure content.
final class SSLStatusTests: XCTestCase {
    func testCertificateErrorsAreTheErrorBitsWithoutTheMinorRevocationOnes() {
        let clean = CefSSLStatus(isSecureConnection: true, certStatus: 0, contentStatus: 0)
        XCTAssertFalse(clean.hasCertificateError)
        XCTAssertFalse(clean.hasInsecureContent)
        for bit: UInt32 in [1 << 0, 1 << 1, 1 << 2, 1 << 6, 1 << 7, 1 << 8, 1 << 14, 1 << 15] {
            XCTAssertTrue(CefSSLStatus(isSecureConnection: true, certStatus: bit, contentStatus: 0).hasCertificateError, "bit \(bit)")
        }
        // NO_REVOCATION_MECHANISM, UNABLE_TO_CHECK_REVOCATION; IS_EV, REV_CHECKING_ENABLED, SHA1_SIGNATURE_PRESENT.
        for bit: UInt32 in [1 << 4, 1 << 5, 1 << 16, 1 << 17, 1 << 19] {
            XCTAssertFalse(CefSSLStatus(isSecureConnection: true, certStatus: bit, contentStatus: 0).hasCertificateError, "bit \(bit)")
        }
    }

    func testDisplayedOrRunInsecureContentCounts() {
        XCTAssertTrue(CefSSLStatus(isSecureConnection: true, certStatus: 0, contentStatus: 1).hasInsecureContent)
        XCTAssertTrue(CefSSLStatus(isSecureConnection: true, certStatus: 0, contentStatus: 2).hasInsecureContent)
    }

    /// Content's flags arrive unchanged: content with certificate errors (bits 3 and 4) is insecure content, and bit 6
    /// is a form posting to plain HTTP (what the https fixture's mixed.html reports, as 0x40).
    func testCertificateErrorContentAndInsecureFormActionsCount() {
        for bit: UInt32 in [1 << 3, 1 << 4] {
            let status = CefSSLStatus(isSecureConnection: true, certStatus: 0, contentStatus: bit)
            XCTAssertTrue(status.hasInsecureContent, "bit \(bit)")
            XCTAssertFalse(status.hasInsecureFormAction, "bit \(bit)")
        }
        let form = CefSSLStatus(isSecureConnection: true, certStatus: 0, contentStatus: 0x40)
        XCTAssertTrue(form.hasInsecureFormAction)
        XCTAssertFalse(form.hasInsecureContent)
        XCTAssertFalse(CefSSLStatus(isSecureConnection: true, certStatus: 0, contentStatus: 1 << 2).hasInsecureFormAction)
    }
}
