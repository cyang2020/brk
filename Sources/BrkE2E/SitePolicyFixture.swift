import Foundation

enum SitePolicyFixture {
    static func response(_ path: String, request: Data) -> Data? {
        if path == "/site-policy-cookie-seed" {
            let lines = String(decoding: request, as: UTF8.self).components(separatedBy: "\r\n")
            let target = lines[0].split(separator: " ").dropFirst().first.map(String.init) ?? ""
            let raw = URLComponents(string: target)?.queryItems?.first { $0.name == "value" }?.value ?? "fixture"
            let value = String(raw.prefix(128).filter { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
            let domain = lines.contains { $0.lowercased().hasPrefix("host:") && $0.contains(".brk.test") }
                ? "Set-Cookie: domainfixture=\(value); Domain=brk.test; Path=/; Max-Age=3600\r\n" : ""
            return Data("HTTP/1.1 200 OK\r\nContent-Length: 6\r\nSet-Cookie: httponlyfixture=\(value); HttpOnly; Path=/; Max-Age=3600\r\n\(domain)Cache-Control: no-store\r\nConnection: close\r\n\r\nseeded".utf8)
        }
        if path == "/site-policy-cookie-read" {
            let cookie = String(decoding: request, as: UTF8.self).components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("cookie:") }.map { String($0.dropFirst(7)) } ?? ""
            let body = try! JSONSerialization.data(withJSONObject: ["cookie": cookie])
            return Data("HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n".utf8) + body
        }
        if path == "/site-policy-redirect" { return Data("HTTP/1.1 302 Found\r\nLocation: /brk-blocked-tracker/tracker.js\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8) }
        if path == "/site-policy-cache.js" {
            let body = Data("window.cachedFixture=true;".utf8)
            return Data("HTTP/1.1 200 OK\r\nContent-Type: text/javascript\r\nCache-Control: public, max-age=3600\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8) + body
        }
        return nil
    }
}
