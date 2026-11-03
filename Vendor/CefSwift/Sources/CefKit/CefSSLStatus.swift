import CCef
import Foundation

/// The SSL status of a browser's visible navigation entry, the input of Chromium's own security indicator.
public struct CefSSLStatus: Sendable, Equatable {
    /// The entry's document came over TLS.
    public var isSecureConnection: Bool
    /// `cef_cert_status_t` bits.
    public var certStatus: UInt32
    /// `cef_ssl_content_status_t` bits.
    public var contentStatus: UInt32

    public init(isSecureConnection: Bool, certStatus: UInt32, contentStatus: UInt32) {
        self.isSecureConnection = isSecureConnection
        self.certStatus = certStatus
        self.contentStatus = contentStatus
    }

    /// A certificate error Chromium holds against the page: any error bit (net's CERT_STATUS_ALL_ERRORS, 0xFF00FFFF)
    /// except the two minor revocation-check statuses, as net::IsCertStatusError and IsCertStatusMinorError decide.
    public var hasCertificateError: Bool {
        let minor = CERT_STATUS_NO_REVOCATION_MECHANISM.rawValue | CERT_STATUS_UNABLE_TO_CHECK_REVOCATION.rawValue
        return certStatus & 0xFF00_FFFF & ~UInt32(minor) != 0
    }

    /// The page displayed or ran content that came over plain HTTP, or with a certificate error. Content's
    /// `SSLStatus::ContentStatusFlags` reach CEF unchanged; CEF's enum names only the first two bits.
    public var hasInsecureContent: Bool {
        let insecure = SSL_CONTENT_DISPLAYED_INSECURE_CONTENT.rawValue | SSL_CONTENT_RAN_INSECURE_CONTENT.rawValue
        return contentStatus & (UInt32(insecure) | Self.displayedContentWithCertErrors | Self.ranContentWithCertErrors) != 0
    }

    /// A form on the page submits to a plain HTTP address. Since Chromium upgrades plain HTTP images and media and blocks
    /// other plain HTTP subresources, this is what an https page with plain HTTP parts usually reports.
    public var hasInsecureFormAction: Bool { contentStatus & Self.displayedFormWithInsecureAction != 0 }

    static let displayedContentWithCertErrors: UInt32 = 1 << 3
    static let ranContentWithCertErrors: UInt32 = 1 << 4
    static let displayedFormWithInsecureAction: UInt32 = 1 << 6
}

extension CefBrowser {
    /// The visible navigation entry's SSL status; nil while the browser has no valid entry.
    public func visibleSSLStatus() -> CefSSLStatus? {
        var result: CefSSLStatus?
        withHostInternal { host in
            guard let entry = host.pointee.get_visible_navigation_entry?(host) else { return }
            defer { cefRelease(UnsafeMutableRawPointer(entry)) }
            guard entry.pointee.is_valid?(entry) != 0, let status = entry.pointee.get_sslstatus?(entry) else { return }
            defer { cefRelease(UnsafeMutableRawPointer(status)) }
            result = CefSSLStatus(
                isSecureConnection: status.pointee.is_secure_connection?(status) != 0,
                certStatus: UInt32(status.pointee.get_cert_status?(status).rawValue ?? 0),
                contentStatus: UInt32(status.pointee.get_content_status?(status).rawValue ?? 0)
            )
        }
        return result
    }
}
