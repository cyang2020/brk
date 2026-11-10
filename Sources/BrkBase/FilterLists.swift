import Foundation

// EasyList / EasyPrivacy (Adblock Plus filter syntax): parsing, an indexed request matcher and element hiding.
// Pure values; the engine runs `FilterLists.match` on CEF's IO thread and `hiddenSelectors` when it styles a page.
// b97ba26463:verify/visual-pairs/run-20261103/r3-8/FILTERS.md lists what is supported and what is skipped.

/// Request kinds as the filter type options name them.
public enum FilterResourceType: String, Hashable, Sendable, Codable, CaseIterable {
    case document, subdocument, stylesheet, script, image, font, object, xmlhttprequest, media, ping, websocket, other
    var bit: UInt16 { 1 << UInt16(Self.allCases.firstIndex(of: self)!) }
    /// Filters without a type option apply to every kind but top-level documents.
    static let defaultMask: UInt16 = allMask & ~FilterResourceType.document.bit
    static let allMask: UInt16 = allCases.reduce(0) { $0 | $1.bit }
}

/// Page-wide exceptions (`@@…$document`, `$elemhide`, `$generichide`, `$genericblock`) that hold for one document.
public struct FilterPageFlags: OptionSet, Hashable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }
    /// Nothing is blocked or hidden on the page.
    public static let document = FilterPageFlags(rawValue: 1)
    /// No element hiding on the page.
    public static let elemhide = FilterPageFlags(rawValue: 2)
    /// Only domain-specific element hiding on the page.
    public static let generichide = FilterPageFlags(rawValue: 4)
    /// Only domain-specific request filters on the page.
    public static let genericblock = FilterPageFlags(rawValue: 8)
}

public enum FilterMatch: Hashable, Sendable {
    case none
    case blocked(filter: String)
    /// A blocking filter matched and an exception filter allowed the request.
    case allowed(filter: String, exception: String)
    public var blocks: Bool { if case .blocked = self { true } else { false } }
}

/// What one list contributed and what it could not use, by reason.
public struct FilterListSummary: Hashable, Sendable, Codable {
    public var title: String?
    public var version: String?
    /// `! Expires:` in hours; nil when the list does not say.
    public var expiresHours: Int?
    public var networkFilters = 0
    public var exceptionFilters = 0
    public var hidingRules = 0
    public var skipped = 0
    /// Skipped lines by reason, for example `option:csp` or `cosmetic:snippet`.
    public var skippedReasons: [String: Int] = [:]
    public var usable: Int { networkFilters + exceptionFilters + hidingRules }
    public init() {}
}

public enum FilterListError: Error, Hashable, Sendable, CustomStringConvertible {
    case tooLarge, notText, noRules
    public var description: String {
        switch self {
        case .tooLarge: "The filter list is larger than 10 MB."
        case .notText: "The filter list is not UTF-8 text."
        case .noRules: "The file contains no filter rules Brk can use."
        }
    }
}

/// One parsed and indexed list. Immutable, shared between threads.
public final class CompiledFilterList: @unchecked Sendable {
    public static let maximumBytes = 10 * 1_048_576
    public let summary: FilterListSummary
    let blocking: FilterIndex
    let exceptions: FilterIndex
    /// Exceptions that set page flags, checked against the document address.
    let pageExceptions: [NetworkFilter]
    let genericHiding: [String]
    /// Generic hiding filters with excluded domains only (`~example.com##.ad`).
    let genericHidingExcluding: [(selector: String, excluded: [String])]
    let specificHiding: [(selector: String, included: [String], excluded: [String])]
    let hidingExceptions: [(selector: String, included: [String])]

    init(summary: FilterListSummary, blocking: [NetworkFilter], exceptions: [NetworkFilter], pageExceptions: [NetworkFilter], generic: [String],
         genericExcluding: [(String, [String])], specific: [(String, [String], [String])], hidingExceptions: [(String, [String])]) {
        self.summary = summary
        self.blocking = FilterIndex(blocking); self.exceptions = FilterIndex(exceptions); self.pageExceptions = pageExceptions
        self.genericHiding = generic
        self.genericHidingExcluding = genericExcluding.map { (selector: $0.0, excluded: $0.1) }
        self.specificHiding = specific.map { (selector: $0.0, included: $0.1, excluded: $0.2) }
        self.hidingExceptions = hidingExceptions.map { (selector: $0.0, included: $0.1) }
    }

    public static func compile(_ data: Data) throws(FilterListError) -> CompiledFilterList {
        guard data.count <= maximumBytes else { throw .tooLarge }
        guard let text = String(data: data, encoding: .utf8) else { throw .notText }
        return try compile(text)
    }

    public static func compile(_ text: String) throws(FilterListError) -> CompiledFilterList {
        guard text.utf8.count <= maximumBytes else { throw .tooLarge }
        var parser = FilterParser()
        for line in text.split(whereSeparator: \.isNewline) { parser.line(String(line)) }
        guard parser.summary.usable > 0 else { throw .noRules }
        return parser.compiled()
    }
}

public enum FilterLists {
    /// The page-wide exceptions for a document.
    public static func pageFlags(_ lists: [CompiledFilterList], documentURL: URL?) -> FilterPageFlags {
        guard let documentURL, let request = FilterRequestText(documentURL, type: .document, document: documentURL) else { return [] }
        var flags: FilterPageFlags = []
        for list in lists {
            for filter in list.pageExceptions where !flags.contains(filter.pageFlags) && filter.matches(request) { flags.formUnion(filter.pageFlags) }
        }
        return flags
    }

    /// Whether a request is blocked. `documentURL` is the top-level page (the request itself for a document).
    public static func match(_ lists: [CompiledFilterList], url: URL, type: FilterResourceType, documentURL: URL?, pageFlags: FilterPageFlags = []) -> FilterMatch {
        guard !lists.isEmpty, !pageFlags.contains(.document),
              let request = FilterRequestText(url, type: type, document: type == .document ? url : documentURL) else { return .none }
        var block: NetworkFilter?
        for list in lists {
            list.blocking.each(request) { filter in
                guard !(pageFlags.contains(.genericblock) && filter.generic), filter.matches(request) else { return false }
                if block == nil || filter.important && !(block?.important ?? false) { block = filter }
                return filter.important || !list.blocking.hasImportant
            }
            if let found = block, found.important { return .blocked(filter: found.text) }
        }
        guard let block else { return .none }
        for list in lists {
            var exception: NetworkFilter?
            list.exceptions.each(request) { filter in
                guard filter.matches(request) else { return false }
                exception = filter; return true
            }
            if let exception { return .allowed(filter: block.text, exception: exception.text) }
        }
        return .blocked(filter: block.text)
    }

    /// The selectors to hide on a document, in list order, without duplicates.
    public static func hiddenSelectors(_ lists: [CompiledFilterList], documentURL: URL?, pageFlags: FilterPageFlags) -> [String] {
        guard !lists.isEmpty, !pageFlags.contains(.document), !pageFlags.contains(.elemhide) else { return [] }
        let host = documentURL?.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) ?? ""
        var excepted = Set<String>()
        for list in lists {
            for exception in list.hidingExceptions where exception.included.isEmpty || exception.included.contains(where: { domainMatches(host, $0) }) {
                excepted.insert(exception.selector)
            }
        }
        var seen = Set<String>(), out: [String] = []
        func add(_ selector: String) { if !excepted.contains(selector), seen.insert(selector).inserted { out.append(selector) } }
        for list in lists {
            if !pageFlags.contains(.generichide) {
                list.genericHiding.forEach(add)
                for rule in list.genericHidingExcluding where !rule.excluded.contains(where: { domainMatches(host, $0) }) { add(rule.selector) }
            }
            for rule in list.specificHiding where rule.included.contains(where: { domainMatches(host, $0) }) && !rule.excluded.contains(where: { domainMatches(host, $0) }) {
                add(rule.selector)
            }
        }
        return out
    }

    /// `example.com` matches itself and its subdomains; `example.*` matches example under any top-level suffix.
    static func domainMatches(_ host: String, _ domain: String) -> Bool {
        if domain.hasSuffix(".*") {
            let base = String(domain.dropLast(2))
            return host == base || host.hasPrefix(base + ".") || host.contains("." + base + ".")
        }
        return host == domain || host.hasSuffix("." + domain)
    }

    /// The registrable part of a host, approximately: the last two labels, three under a two-letter country code with a
    /// generic second level (example.co.uk), the whole address for IP literals.
    static func baseDomain(_ host: String) -> String {
        if host.contains(":") || host.split(separator: ".").allSatisfy({ $0.allSatisfy(\.isNumber) }) { return host }
        let labels = host.split(separator: ".")
        guard labels.count > 2 else { return host }
        let generic: Set<Substring> = ["co", "com", "net", "org", "gov", "edu", "ac", "or", "ne", "go", "gob", "mil", "nic", "ltd", "plc"]
        let count = labels.last!.count == 2 && generic.contains(labels[labels.count - 2]) ? 3 : 2
        return labels.suffix(count).joined(separator: ".")
    }
}

/// A request reduced to what matching reads.
struct FilterRequestText {
    let url: [UInt8]
    let lowered: [UInt8]
    /// Where the host starts and ends in `url`.
    let hostRange: Range<Int>
    let host: String
    let documentHost: String
    let thirdParty: Bool
    let type: FilterResourceType

    init?(_ url: URL, type: FilterResourceType, document: URL?) {
        let string = url.absoluteString
        guard let scheme = url.scheme?.lowercased(), ["http", "https", "ws", "wss"].contains(scheme), let host = url.host?.lowercased(), !host.isEmpty else { return nil }
        self.url = Array(string.utf8); lowered = Array(string.lowercased().utf8)
        // scheme://[user@]host[:port]
        let afterScheme = min(scheme.utf8.count + 3, lowered.count)
        let authorityEnd = lowered[afterScheme...].firstIndex { [UInt8(ascii: "/"), UInt8(ascii: "?"), UInt8(ascii: "#")].contains($0) } ?? lowered.count
        let start = lowered[afterScheme..<authorityEnd].lastIndex(of: UInt8(ascii: "@")).map { $0 + 1 } ?? afterScheme
        var end = start
        if start < authorityEnd, lowered[start] == UInt8(ascii: "[") {
            end = (lowered[start..<authorityEnd].firstIndex(of: UInt8(ascii: "]")) ?? authorityEnd - 1) + 1
        } else {
            end = lowered[start..<authorityEnd].firstIndex(of: UInt8(ascii: ":")) ?? authorityEnd
        }
        hostRange = start..<end
        self.host = host.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        documentHost = document?.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) ?? ""
        thirdParty = !documentHost.isEmpty && FilterLists.baseDomain(self.host) != FilterLists.baseDomain(documentHost)
        self.type = type
    }
}

/// One network filter, its pattern compiled to tokens.
struct NetworkFilter: @unchecked Sendable {
    enum Token: Equatable { case byte(UInt8), separator, wildcard }
    let text: String
    let tokens: [Token]
    let regex: NSRegularExpression?
    let hostAnchor: Bool, startAnchor: Bool, endAnchor: Bool
    let matchCase: Bool
    let important: Bool
    let types: UInt16
    /// nil: either party; true: third-party only; false: first-party only.
    let thirdParty: Bool?
    let included: [String], excluded: [String]
    let pageFlags: FilterPageFlags
    /// The index key: a literal run every matching address contains as a whole token.
    let key: String?
    var generic: Bool { included.isEmpty }

    func matches(_ request: FilterRequestText) -> Bool {
        guard types & request.type.bit != 0 || !pageFlags.isEmpty && request.type == .document else { return false }
        if let thirdParty, thirdParty != request.thirdParty { return false }
        if !included.isEmpty || !excluded.isEmpty {
            let context = request.documentHost
            if !included.isEmpty, !included.contains(where: { FilterLists.domainMatches(context, $0) }) { return false }
            if excluded.contains(where: { FilterLists.domainMatches(context, $0) }) { return false }
        }
        let subject = matchCase ? request.url : request.lowered
        if let regex {
            let string = String(decoding: subject, as: UTF8.self)
            return regex.firstMatch(in: string, range: NSRange(location: 0, length: (string as NSString).length)) != nil
        }
        if hostAnchor {
            // At the host's start or after any dot in it.
            var position = request.hostRange.lowerBound
            while position < request.hostRange.upperBound {
                if Self.match(tokens, 0, subject, position, endAnchor) { return true }
                guard let dot = subject[position..<request.hostRange.upperBound].firstIndex(of: UInt8(ascii: ".")) else { return false }
                position = dot + 1
            }
            return false
        }
        if startAnchor { return Self.match(tokens, 0, subject, 0, endAnchor) }
        for start in 0...subject.count where Self.match(tokens, 0, subject, start, endAnchor) { return true }
        return false
    }

    static func isSeparator(_ byte: UInt8) -> Bool {
        !(byte >= 0x30 && byte <= 0x39 || byte >= 0x41 && byte <= 0x5A || byte >= 0x61 && byte <= 0x7A || byte >= 0x80)
            && byte != UInt8(ascii: "_") && byte != UInt8(ascii: "-") && byte != UInt8(ascii: ".") && byte != UInt8(ascii: "%")
    }

    /// Backtracking glob match of `tokens[t...]` against `subject[s...]`.
    static func match(_ tokens: [Token], _ t: Int, _ subject: [UInt8], _ s: Int, _ end: Bool) -> Bool {
        var t = t, s = s
        while t < tokens.count {
            switch tokens[t] {
            case .byte(let byte):
                guard s < subject.count, subject[s] == byte else { return false }
                t += 1; s += 1
            case .separator:
                if s == subject.count {
                    // `^` also matches the end of the address; only more `^` or `*` may follow it then.
                    return tokens[(t + 1)...].allSatisfy { $0 == .separator || $0 == .wildcard }
                }
                guard isSeparator(subject[s]) else { return false }
                t += 1; s += 1
            case .wildcard:
                while t < tokens.count, tokens[t] == .wildcard { t += 1 }
                if t == tokens.count { return true }
                for next in s...subject.count where match(tokens, t, subject, next, end) { return true }
                return false
            }
        }
        return !end || s == subject.count
    }
}

/// Filters by key token; the ones without a key are checked for every request.
struct FilterIndex {
    private let keyed: [String: [Int]]
    private let unkeyed: [Int]
    private let filters: [NetworkFilter]
    let hasImportant: Bool
    init(_ filters: [NetworkFilter]) {
        self.filters = filters
        hasImportant = filters.contains(where: \.important)
        var keyed: [String: [Int]] = [:], unkeyed: [Int] = []
        for (index, filter) in filters.enumerated() {
            if let key = filter.key { keyed[key, default: []].append(index) } else { unkeyed.append(index) }
        }
        self.keyed = keyed; self.unkeyed = unkeyed
    }
    var count: Int { filters.count }
    /// Calls `body` with each candidate until it returns true.
    func each(_ request: FilterRequestText, _ body: (NetworkFilter) -> Bool) {
        for index in unkeyed where body(filters[index]) { return }
        var start: Int?
        var seen = Set<String>()
        let bytes = request.lowered
        for position in 0...bytes.count {
            if position < bytes.count, FilterParser.isTokenByte(bytes[position]) { if start == nil { start = position }; continue }
            guard let from = start else { continue }
            start = nil
            let token = String(decoding: request.lowered[from..<position], as: UTF8.self)
            guard seen.insert(token).inserted, let candidates = keyed[token] else { continue }
            for index in candidates where body(filters[index]) { return }
        }
    }
}

struct FilterParser {
    var summary = FilterListSummary()
    private var blocking: [NetworkFilter] = [], exceptions: [NetworkFilter] = [], pageExceptions: [NetworkFilter] = []
    private var generic: [String] = [], genericExcluding: [(String, [String])] = [], specific: [(String, [String], [String])] = []
    private var hidingExceptions: [(String, [String])] = []
    private var lines = 0
    static let maximumLines = 400_000

    static func isTokenByte(_ byte: UInt8) -> Bool {
        byte >= 0x30 && byte <= 0x39 || byte >= 0x61 && byte <= 0x7A || byte == UInt8(ascii: "%")
    }

    func compiled() -> CompiledFilterList {
        CompiledFilterList(summary: summary, blocking: blocking, exceptions: exceptions, pageExceptions: pageExceptions, generic: generic,
                           genericExcluding: genericExcluding, specific: specific, hidingExceptions: hidingExceptions)
    }

    private mutating func skip(_ reason: String) {
        summary.skipped += 1
        summary.skippedReasons[reason, default: 0] += 1
    }

    mutating func line(_ raw: String) {
        lines += 1
        guard lines <= Self.maximumLines else { if lines == Self.maximumLines + 1 { skip("limit:lines") }; return }
        let line = raw.trimmingCharacters(in: .whitespaces)
        if line.isEmpty || line.hasPrefix("[") && line.hasSuffix("]") { return }
        if line.hasPrefix("!") { comment(line); return }
        guard line.utf8.count <= 8192 else { skip("limit:length"); return }
        if let cosmetic = Self.cosmetic(line) { hiding(domains: cosmetic.domains, kind: cosmetic.kind, body: cosmetic.body); return }
        network(line)
    }

    private mutating func comment(_ line: String) {
        let body = line.dropFirst().trimmingCharacters(in: .whitespaces)
        func value(_ name: String) -> String? {
            guard body.lowercased().hasPrefix(name.lowercased() + ":") else { return nil }
            return body.dropFirst(name.count + 1).trimmingCharacters(in: .whitespaces)
        }
        if let title = value("Title") { summary.title = title }
        if let version = value("Version") { summary.version = version }
        if let expires = value("Expires") {
            let parts = expires.split(separator: " ")
            if let count = parts.first.flatMap({ Int($0) }), count > 0, parts.count > 1 {
                summary.expiresHours = parts[1].lowercased().hasPrefix("hour") ? count : parts[1].lowercased().hasPrefix("day") ? count * 24 : nil
            }
        }
    }

    // MARK: Element hiding

    /// `domains#kind#body`, where kind is "" (hide), "@" (exception), "?" (extended CSS), "$" (snippet) or "%" (script).
    static func cosmetic(_ line: String) -> (domains: String, kind: String, body: String)? {
        guard let hash = line.firstIndex(of: "#") else { return nil }
        let domains = line[..<hash]
        // A `*` only as an entity suffix (`google.*`).
        guard !domains.contains(where: { "/|@\"!".contains($0) }),
              domains.split(separator: ",").allSatisfy({ !$0.dropLast(2).contains("*") && (!$0.contains("*") || $0.hasSuffix(".*")) }) else { return nil }
        var rest = line[line.index(after: hash)...]
        var kind = ""
        if let first = rest.first, "@?$%".contains(first) { kind = String(first); rest = rest.dropFirst() }
        if kind == "@", rest.first == "?" || rest.first == "$" { kind += String(rest.first!); rest = rest.dropFirst() }
        guard rest.first == "#", rest.count > 1 else { return nil }
        return (String(domains), kind, String(rest.dropFirst()))
    }

    private mutating func hiding(domains: String, kind: String, body: String) {
        switch kind {
        case "$", "@$": skip("cosmetic:snippet"); return
        case "%": skip("cosmetic:script"); return
        default: break
        }
        var selector = body
        if kind.hasSuffix("?") { selector = selector.replacingOccurrences(of: ":-abp-has(", with: ":has(") }
        let unsupported = [":-abp-", ":has-text(", ":upward(", ":xpath(", ":style(", ":remove(", ":matches-css", ":min-text-length(", ":watch-attr(",
                           ":matches-path(", ":matches-attr(", ":matches-prop(", ":others(", ":contains(", ":nth-ancestor(", ":remove-attr(", ":remove-class("]
        if selector.hasPrefix("+js(") || selector.hasPrefix("^") { skip("cosmetic:scriptlet-or-html"); return }
        if unsupported.contains(where: { selector.contains($0) }) { skip("cosmetic:procedural"); return }
        guard Self.safeSelector(selector) else { skip("cosmetic:selector"); return }
        var included: [String] = [], excluded: [String] = []
        for part in domains.split(separator: ",") {
            let domain = part.trimmingCharacters(in: .whitespaces).lowercased()
            guard !domain.isEmpty else { continue }
            if domain.hasPrefix("~") { excluded.append(String(domain.dropFirst())) } else { included.append(domain) }
        }
        if kind.hasPrefix("@") {
            hidingExceptions.append((selector, included)); summary.exceptionFilters += 1; return
        }
        if included.isEmpty && excluded.isEmpty { generic.append(selector) }
        else if included.isEmpty { genericExcluding.append((selector, excluded)) }
        else { specific.append((selector, included, excluded)) }
        summary.hidingRules += 1
    }

    /// A selector that cannot leave its CSS rule: no braces, no comment or markup, balanced quotes and brackets.
    static func safeSelector(_ selector: String) -> Bool {
        guard !selector.isEmpty, selector.utf8.count <= 4096, !selector.contains("{"), !selector.contains("}"), !selector.contains("/*"),
              !selector.contains("<"), !selector.contains("\\"), !selector.contains(";") || selector.contains("\"") || selector.contains("'") else { return false }
        var depth = 0, bracket = 0
        var quote: Character?
        for character in selector {
            if let open = quote { if character == open { quote = nil }; continue }
            switch character {
            case "\"", "'": quote = character
            case "(": depth += 1
            case ")": depth -= 1; if depth < 0 { return false }
            case "[": bracket += 1
            case "]": bracket -= 1; if bracket < 0 { return false }
            case ";": return false
            default: break
            }
        }
        return quote == nil && depth == 0 && bracket == 0
    }

    // MARK: Request filters

    private mutating func network(_ line: String) {
        var pattern = line
        var exception = false
        if pattern.hasPrefix("@@") { exception = true; pattern.removeFirst(2) }
        var optionText: String?
        if let dollar = pattern.lastIndex(of: "$") {
            let tail = pattern[pattern.index(after: dollar)...]
            let regexBody = pattern.hasPrefix("/") && (pattern[..<dollar].lastIndex(of: "/").map { $0 > pattern.startIndex } ?? false)
            if !regexBody || !tail.contains("/") || tail.contains("=") {
                optionText = String(tail); pattern = String(pattern[..<dollar])
            }
        }
        var types: UInt16 = 0, negated: UInt16 = 0
        var thirdParty: Bool?, matchCase = false, important = false
        var included: [String] = [], excluded: [String] = []
        var pageFlags: FilterPageFlags = []
        var sawPopupOnly = false
        if let optionText {
            for raw in optionText.split(separator: ",", omittingEmptySubsequences: false) {
                var option = raw.trimmingCharacters(in: .whitespaces).lowercased()
                let negative = option.hasPrefix("~")
                if negative { option.removeFirst() }
                let name = option.split(separator: "=", maxSplits: 1).first.map(String.init) ?? option
                let value = option.contains("=") ? String(option.split(separator: "=", maxSplits: 1)[1]) : nil
                let aliases: [String: FilterResourceType] = [
                    "script": .script, "image": .image, "stylesheet": .stylesheet, "css": .stylesheet, "object": .object, "object-subrequest": .object,
                    "xmlhttprequest": .xmlhttprequest, "xhr": .xmlhttprequest, "subdocument": .subdocument, "frame": .subdocument,
                    "ping": .ping, "beacon": .ping, "media": .media, "font": .font, "websocket": .websocket, "other": .other,
                    "document": .document, "doc": .document,
                ]
                if let type = aliases[name] {
                    if type == .document && exception && !negative { pageFlags.insert(.document); continue }
                    if negative { negated |= type.bit } else { types |= type.bit }
                    continue
                }
                switch name {
                case "third-party", "3p": thirdParty = !negative
                case "first-party", "1p": thirdParty = negative
                case "match-case": matchCase = !negative
                case "important": important = true
                case "all": types |= FilterResourceType.allMask
                case "domain", "from":
                    for part in (value ?? "").split(separator: "|") {
                        let domain = String(part).lowercased()
                        if domain.hasPrefix("~") { excluded.append(String(domain.dropFirst())) } else if !domain.isEmpty { included.append(domain) }
                    }
                case "elemhide", "ehide":
                    guard exception else { skip("option:elemhide"); return }
                    pageFlags.insert(.elemhide)
                case "generichide", "ghide":
                    guard exception else { skip("option:generichide"); return }
                    pageFlags.insert(.generichide)
                case "genericblock":
                    guard exception else { skip("option:genericblock"); return }
                    pageFlags.insert(.genericblock)
                case "popup", "webrtc", "popunder": sawPopupOnly = true
                case "": continue
                default: skip("option:" + name); return
                }
            }
        }
        if sawPopupOnly && types == 0 && negated == 0 { skip("option:popup"); return }
        let mask: UInt16
        if types != 0 { mask = types & ~negated }
        else if negated != 0 { mask = FilterResourceType.defaultMask & ~negated }
        else { mask = pageFlags.isEmpty ? FilterResourceType.defaultMask : 0 }
        guard mask != 0 || !pageFlags.isEmpty else { skip("option:type"); return }

        var regex: NSRegularExpression?
        var hostAnchor = false, startAnchor = false, endAnchor = false
        var body = pattern
        if body.count > 2, body.hasPrefix("/"), body.hasSuffix("/") {
            let source = String(body.dropFirst().dropLast())
            guard let compiled = try? NSRegularExpression(pattern: source, options: matchCase ? [] : [.caseInsensitive]) else { skip("syntax:regex"); return }
            regex = compiled
        } else {
            if body.hasPrefix("||") { hostAnchor = true; body.removeFirst(2) }
            else if body.hasPrefix("|") { startAnchor = true; body.removeFirst() }
            if body.hasSuffix("|") { endAnchor = true; body.removeLast() }
        }
        let source = matchCase ? body : body.lowercased()
        var tokens: [NetworkFilter.Token] = []
        if regex == nil {
            for byte in source.utf8 {
                switch byte {
                case UInt8(ascii: "*"): if tokens.last != .wildcard { tokens.append(.wildcard) }
                case UInt8(ascii: "^"): tokens.append(.separator)
                default: tokens.append(.byte(byte))
                }
            }
            if !hostAnchor && !startAnchor && tokens.first == .wildcard { tokens.removeFirst() }
            if !endAnchor && tokens.last == .wildcard { tokens.removeLast() }
            if tokens.isEmpty && types == 0 && negated == 0 && thirdParty == nil && included.isEmpty && pageFlags.isEmpty { skip("syntax:matches-everything"); return }
        }
        let filter = NetworkFilter(text: line, tokens: tokens, regex: regex, hostAnchor: hostAnchor, startAnchor: startAnchor, endAnchor: endAnchor,
                                   matchCase: matchCase, important: important && !exception, types: mask, thirdParty: thirdParty,
                                   included: included, excluded: excluded, pageFlags: pageFlags,
                                   key: regex == nil && !matchCase ? Self.key(tokens, anchoredStart: hostAnchor || startAnchor, anchoredEnd: endAnchor) : nil)
        if !pageFlags.isEmpty { pageExceptions.append(filter); summary.exceptionFilters += 1 }
        if exception && mask != 0 { exceptions.append(filter); if pageFlags.isEmpty { summary.exceptionFilters += 1 } }
        else if !exception { blocking.append(filter); summary.networkFilters += 1 }
    }

    /// The longest run of token bytes (at least three) that is a whole token of every matching address: bounded on
    /// both sides by a literal non-token byte, a separator, or an anchor.
    /// Tokens nearly every address has; a key from these alone would make the filter a candidate for every request.
    static let commonTokens: Set<String> = ["http", "https", "www", "com", "net", "org", "html", "php", "wss"]

    static func key(_ tokens: [NetworkFilter.Token], anchoredStart: Bool, anchoredEnd: Bool) -> String? {
        var best: [UInt8] = [], common: [UInt8] = [], run: [UInt8] = [], runStart = 0
        func bounded(_ index: Int, atStart: Bool) -> Bool {
            guard index >= 0, index < tokens.count else { return atStart ? anchoredStart : anchoredEnd }
            switch tokens[index] {
            case .wildcard: return false
            case .separator: return true
            case .byte(let byte): return !isTokenByte(byte)
            }
        }
        for index in 0...tokens.count {
            if index < tokens.count, case .byte(let byte) = tokens[index], isTokenByte(byte) {
                if run.isEmpty { runStart = index }
                run.append(byte); continue
            }
            if run.count >= 3, bounded(runStart - 1, atStart: true), bounded(index, atStart: false) {
                if commonTokens.contains(String(decoding: run, as: UTF8.self)) { if common.isEmpty { common = run } }
                else if run.count > best.count { best = run }
            }
            run = []
        }
        let key = best.isEmpty ? common : best
        return key.isEmpty ? nil : String(decoding: key, as: UTF8.self)
    }
}

// MARK: Lists a profile keeps

/// One filter list of a profile: a subscription Brk downloads (EasyList, EasyPrivacy) or a file the user chose. The
/// text lives in `FilterListStore` under `key`; the record holds what the site settings show.
public struct FilterListRecord: Hashable, Sendable, Codable, Identifiable {
    public let id: String
    public var title: String
    /// Where updates come from; nil for an imported file.
    public var source: URL?
    public var enabled: Bool
    /// The stored text's `FilterListStore.key`; nil until the first download.
    public var key: String?
    public var summary: FilterListSummary?
    /// The last time new text arrived (download or import).
    public var updated: Instant?
    /// The last download attempt, successful or not.
    public var checked: Instant?
    /// The last attempt failed for a reason other than having no network.
    public var problem: String?
    /// The last attempt found no network. Not an error: the previous copy stays in use and Brk retries.
    public var offline: Bool?
    public init(id: String, title: String, source: URL?, enabled: Bool = true) {
        self.id = id; self.title = title; self.source = source; self.enabled = enabled
    }

    public static let importedID = "imported"
    public static let subscriptions = [
        FilterListRecord(id: "easylist", title: "EasyList", source: URL(string: "https://easylist.to/easylist/easylist.txt")!),
        FilterListRecord(id: "easyprivacy", title: "EasyPrivacy", source: URL(string: "https://easylist.to/easylist/easyprivacy.txt")!),
    ]
    /// When the next automatic download is due after `checked`: the list's own Expires (four days when it gives
    /// none), an hour after a failed or offline attempt.
    public var refreshInterval: Duration {
        if offline == true || problem != nil { return .seconds(3600) }
        let hours = min(max(summary?.expiresHours ?? 96, 1), 14 * 24)
        return .seconds(hours * 3600)
    }
}

/// What a download produced.
public enum FilterListFetch: Hashable, Sendable, Codable {
    case updated(key: String, summary: FilterListSummary)
    case unchanged
    case offline
    case failed(String)
}

/// The downloaded and imported texts, one file per content key under the data directory.
public enum FilterListStore {
    public static var directory: URL { Product.dataDirectory().appendingPathComponent("Filter Lists", isDirectory: true) }
    public static func url(_ key: String) -> URL { directory.appendingPathComponent(key + ".txt") }
    /// FNV-1a 64 of the bytes and their count: equal texts share a file, a changed text gets a new one.
    public static func key(_ data: Data) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
        return String(hash, radix: 16).leftPadded(16) + "-" + String(data.count)
    }
    public static func isKey(_ value: String) -> Bool {
        value.range(of: #"^[0-9a-f]{16}-[0-9]{1,9}$"#, options: .regularExpression) != nil
    }
    public static func write(_ data: Data, key: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = url(key)
        guard !FileManager.default.fileExists(atPath: file.path) else { return }
        try data.write(to: file, options: .atomic)
    }
}

private extension String {
    func leftPadded(_ width: Int) -> String { count >= width ? self : String(repeating: "0", count: width - count) + self }
}
