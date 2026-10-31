import BrkBase
import Foundation

public enum BoostCodec {
    public static func validate(_ catalog: BoostCatalog) throws {
        guard catalog.version == 1, catalog.boosts.count <= 200, Set(catalog.boosts.map(\.id)).count == catalog.boosts.count else {
            throw invalid("Unsupported Boost version, duplicate IDs or too many Boosts.")
        }
        for boost in catalog.boosts {
            guard !boost.id.isEmpty, boost.id.count <= 160, boost.id.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0) || $0 == 45 }), !boost.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  boost.name.count <= 200, boost.css.utf8.count <= 500_000, boost.javascript.utf8.count <= 500_000 else {
                throw invalid("Boosts need a name and at most 500 KB each of CSS and JavaScript.")
            }
            if case .host(let host) = boost.scope {
                guard let url = URL(string: "https://" + host), let origin = SiteOrigin(url), origin.url.host == host,
                      origin.value == "https://" + host else { throw invalid("Use an exact lowercase hostname without a path or port.") }
            }
        }
    }
    public static func encode(_ catalog: BoostCatalog) throws -> Data {
        try validate(catalog)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(catalog)
        guard data.count <= 10_000_000 else { throw invalid("Boost file exceeds 10 MB.") }
        return data
    }
    public static func decode(_ data: Data) throws -> BoostCatalog {
        guard data.count <= 10_000_000 else { throw invalid("Boost file exceeds 10 MB.") }
        let value = try JSONDecoder().decode(BoostCatalog.self, from: data); try validate(value); return value
    }
    public static func export(_ boost: Boost) throws -> Data {
        var value = boost; value.javascriptApproved = false; value.allowPrivate = false
        return try encode(BoostCatalog(boosts: [value]))
    }
    public static func imported(_ data: Data, newID: () -> String) throws -> [Boost] {
        try decode(data).boosts.map { boost in
            var value = boost; value.id = newID(); value.javascriptApproved = false; value.allowPrivate = false; return value
        }
    }
    private static func invalid(_ message: String) -> NSError { NSError(domain: "BrkBoosts", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
}
