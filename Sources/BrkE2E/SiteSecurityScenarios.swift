import BrkBase
import BrkControl
import BrkDomain
import Foundation

/// The site controls' Secure / Insecure row against real certificates. The https fixture
/// (`Tests/Fixtures/https-fixture`) serves a page on a certificate Brk trusts through its test switch
/// (`BRK_TEST_TRUSTED_SPKI`, set by the harness for these scenarios), one on a certificate nothing trusts, and https
/// pages with plain HTTP parts. Each scenario reads Chromium's report through the snapshot, then what the popover
/// shows: the overview's security button and, on the second page, the connection note.
enum SiteSecurityScenarios {
    static let all = [
        Scenario("SiteSecurity-invalid", "untrusted certificate: Chromium's interstitial, Proceed, then Insecure with the certificate note",
                 cefOnly: "Chromium certificate verification", invalid),
    ]

    static let secureNote = "Connection is secure (HTTPS)."
    static let certificateNote = "Connection is not secure: the site's certificate is not valid."
    static let formNote = "Connection is not secure: a form on this page sends information over plain HTTP."

    @Sendable static func secure(_ app: AppUnderTest) throws {
        let fixture = try HTTPSFixture(app); defer { fixture.stop() }
        let item = try app.load(fixture.url("127.0.0.1", "/secure.html"))
        try waitForTitle(app, item, "Secure fixture")
        try app.dispatch(.site(.controls))
        try app.waitUntil("Chromium reports a clean TLS connection") {
            let value = try SitePolicyScenarios.controls(app)
            return value.security?.secureConnection == true && value.security?.certificateError == false && value.secure
        }
        try showsSecurity(app, secure: true, note: secureNote, shots: "secure")
        app.note("The page came over TLS on the fixture's trusted.pem; Chromium verified it through the test-only SPKI allowance (no keychain or trust-setting change) and reported no certificate error and no insecure content.")
    }

    @Sendable static func invalid(_ app: AppUnderTest) throws {
        let fixture = try HTTPSFixture(app); defer { fixture.stop() }
        let url = fixture.url("untrusted.brk.test", "/invalid.html")
        let item = try app.load(url)
        try waitForTitle(app, item, "Privacy error")
        let page = PageID(window: app.window!, item: item)
        _ = try app.screenshot("interstitial")
        try expect(!fixture.served("/invalid.html"), "the page was served before Proceed")
        // Advanced, then "Proceed to untrusted.brk.test (unsafe)": the interstitial's own buttons.
        try app.perform(.evaluate(page: page, script: "document.getElementById('details-button').click();document.getElementById('proceed-link').click()"))
        try waitForTitle(app, item, "Invalid certificate fixture")
        try expect(fixture.served("/invalid.html"), "Proceed did not load the page from the fixture")
        try app.dispatch(.site(.controls))
        try app.waitUntil("Chromium holds the certificate error against the page") {
            let value = try SitePolicyScenarios.controls(app)
            return value.security?.secureConnection == true && value.security?.certificateError == true && !value.secure
        }
        try showsSecurity(app, secure: false, note: certificateNote, shots: "invalid")
        app.note("untrusted.pem (a self-signed key nothing trusts) produced Chromium's ERR_CERT_AUTHORITY_INVALID interstitial; its Advanced and Proceed buttons loaded the page, and the TLS page then read back as Insecure.")
    }


    /// The popover's overview shows Secure or Insecure; the security button opens the second page with the note.
    static func showsSecurity(_ app: AppUnderTest, secure: Bool, note: String, shots: String, details: Bool = true) throws {
        guard let owner = app.window else { throw Check(description: "site-controls owner missing") }
        let shown = secure ? "Secure" : "Insecure", other = secure ? "Insecure" : "Secure"
        try app.waitUntil("the overview shows \(shown)") {
            let texts = try texts(app, owner)
            return texts.contains(shown) && !texts.contains(other)
        }
        _ = try app.screenshotSiteControls(shots + "-overview")
        guard details else { return }
        try app.perform(.siteControlInput(window: owner, field: "siteSecurity", action: .press))
        try app.waitUntil("the second page explains: \(note)") { try texts(app, owner).contains(note) }
        _ = try app.screenshotSiteControls(shots + "-details")
    }

    static func texts(_ app: AppUnderTest, _ owner: WindowID) throws -> [String] {
        guard case .menuItems(let texts) = try app.send(.siteControlTexts(window: owner)) else { throw Check(description: "site control texts missing") }
        return texts
    }
}

/// One run of `Tests/Fixtures/https-fixture/serve.py` on free ports, owned by the scenario.
final class HTTPSFixture {
    let process = Process()
    let https: Int, http: Int
    let requests: URL

    static func directory(_ app: AppUnderTest) -> URL {
        app.site.root.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Tests/Fixtures/https-fixture")
    }
    /// What the harness passes as `BRK_TEST_TRUSTED_SPKI`.
    static func trustedSPKI(siteRoot: URL) -> String? {
        let file = siteRoot.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Tests/Fixtures/https-fixture/trusted.spki")
        return (try? String(contentsOf: file, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(_ app: AppUnderTest) throws {
        let ready = app.dataDirectory.appendingPathComponent("https-ready.json")
        requests = app.dataDirectory.appendingPathComponent("https-requests.jsonl")
        try? FileManager.default.removeItem(at: ready)
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "-I", Self.directory(app).appendingPathComponent("serve.py").path,
                             "--port", "0", "--http-port", "0", "--ready", ready.path, "--requests", requests.path]
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        let deadline = ProcessInfo.processInfo.systemUptime + 10
        var ports: [String: Int]?
        while ports == nil, ProcessInfo.processInfo.systemUptime < deadline, process.isRunning {
            ports = (try? Data(contentsOf: ready)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Int] }
            if ports == nil { usleep(100_000) }
        }
        guard let ports, let https = ports["https"], let http = ports["http"] else {
            if process.isRunning { process.terminate(); process.waitUntilExit() }
            throw Check(description: "the https fixture did not start")
        }
        self.https = https; self.http = http
        app.note("https fixture: python3 -I Tests/Fixtures/https-fixture/serve.py --port 0 --http-port 0 (https \(https), http \(http)).")
    }

    func url(_ host: String, _ path: String) -> URL { URL(string: "https://\(host):\(https)\(path)")! }

    private func lines() -> [[String: String]] {
        guard let text = try? String(contentsOf: requests, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: String] }
    }
    func served(_ path: String) -> Bool { lines().contains { $0["scheme"] == "https" && $0["path"] == path } }

    func stop() {
        guard process.isRunning else { return }
        process.terminate(); process.waitUntilExit()
    }
}
