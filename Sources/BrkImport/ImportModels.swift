import BrkBase
import BrkDomain
import Foundation

/// A saved login read from another browser, password decrypted, in memory only. Times are Chromium's: microseconds
/// since 1601-01-01 UTC, the unit Login Data stores.
public struct SourceLogin: Sendable, Equatable {
    public var originURL: String
    public var actionURL: String = ""
    public var usernameElement: String = ""
    public var usernameValue: String
    public var passwordElement: String = ""
    public var password: String
    public var submitElement: String = ""
    public var signonRealm: String
    public var dateCreated: Int64
    public var blocklisted = false
    /// Chromium's PasswordForm::Scheme: 0 HTML, 1 basic, 2 digest, 3 other, 4 username only.
    public var scheme: Int64 = 0
    public var timesUsed: Int64 = 0
    public var dateLastUsed: Int64 = 0
    public var datePasswordModified: Int64 = 0

    public init(originURL: String, usernameValue: String, password: String, signonRealm: String, dateCreated: Int64) {
        self.originURL = originURL; self.usernameValue = usernameValue; self.password = password
        self.signonRealm = signonRealm; self.dateCreated = dateCreated
    }

    /// A login from a CSV export (Safari, Firefox, Chrome): what Chrome's own CSV importer makes of one row.
    public init?(csvURL url: URL, username: String, password: String, now: Instant) {
        guard let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme), let host = url.host?.lowercased() else { return nil }
        let port = url.port.map { ":\($0)" } ?? ""
        let realm = "\(scheme)://\(host)\(port)/"
        var origin = URLComponents(url: url, resolvingAgainstBaseURL: false)
        origin?.query = nil; origin?.fragment = nil; origin?.user = nil; origin?.password = nil
        if origin?.path.isEmpty ?? true { origin?.path = "/" }
        self.init(originURL: origin?.string ?? realm, usernameValue: username, password: password, signonRealm: realm,
                  dateCreated: Chromium.time(now))
    }
}

/// A cookie read from another browser, value decrypted. Times are Chromium's (microseconds since 1601); 0 is unset.
public struct SourceCookie: Sendable, Equatable {
    public var host: String
    public var name: String
    public var value: String
    public var path: String
    public var expires: Int64
    public var creation: Int64
    public var lastAccess: Int64
    public var secure: Bool
    public var httpOnly: Bool
    /// Chromium's CookieSameSite: -1 unspecified, 0 none, 1 lax, 2 strict.
    public var sameSite: Int
    public var priority: Int
    public init(host: String, name: String, value: String, path: String, expires: Int64, creation: Int64, lastAccess: Int64,
                secure: Bool, httpOnly: Bool, sameSite: Int, priority: Int) {
        self.host = host; self.name = name; self.value = value; self.path = path; self.expires = expires
        self.creation = creation; self.lastAccess = lastAccess; self.secure = secure; self.httpOnly = httpOnly
        self.sameSite = sameSite; self.priority = priority
    }
}

/// A site the source browser visits often, for the Favorites step.
public struct SourceTopSite: Hashable, Sendable {
    public var title: String
    public var url: URL
    public var score: Int
    public init(title: String, url: URL, score: Int) { self.title = title; self.url = url; self.score = score }
}

/// Everything read from one source profile. Reading never throws as a whole: a part that fails adds a line to
/// `failures` and the rest still comes through (Dia's "Some import steps failed").
public struct ProfileRead: Sendable {
    public var bookmarks: [ImportNode] = []
    public var visits: [ImportedVisit] = []
    /// Visit counts by address, for the bookmark step's stars.
    public var visitCounts: [URL: Int] = [:]
    public var topSites: [SourceTopSite] = []
    public var logins: [SourceLogin] = []
    public var cookies: [SourceCookie] = []
    /// Arc only: its Spaces and each Arc profile's Favorites.
    public var spaces: [ImportedSpace] = []
    public var favorites: [ImportNode] = []
    public var failures: [String] = []
    public init() {}
}

public enum ImportPart: String, Sendable, CaseIterable {
    case bookmarks = "Bookmarks", history = "History", passwords = "Passwords", cookies = "Cookies", spaces = "Spaces"
}

public enum Chromium {
    /// Seconds from 1601-01-01 to 1970-01-01.
    static let epochOffset: Int64 = 11_644_473_600

    /// An instant as Chromium stores time.
    public static func time(_ instant: Instant) -> Int64 { (instant.milliseconds / 1000 + epochOffset) * 1_000_000 + (instant.milliseconds % 1000) * 1000 }

    /// Chromium time as an instant; nil for 0 or a value outside what the state file holds.
    public static func instant(_ micros: Int64) -> Instant? {
        guard micros > 0 else { return nil }
        let instant = Instant(milliseconds: micros / 1000 - epochOffset * 1000)
        return Instant.supported.contains(instant) ? instant : nil
    }
}

/// How much history an import brings: the last 90 days (the state file keeps every visit; user decision 4), capped so
/// one import cannot make it unreasonably large.
public enum HistoryWindow {
    public static let days = 90
    public static let maximumVisits = 20_000
    public static func start(_ now: Instant) -> Instant { now.advanced(by: .seconds(-Int64(days) * 86_400)) }
}

extension ImportNode {
    /// Every address below, for deduplication and stars.
    public var urls: [URL] {
        switch self {
        case .tab(_, let url): [url]
        case .folder(_, let children): children.flatMap(\.urls)
        case .split(_, let panes): panes.flatMap(\.urls)
        }
    }
}
