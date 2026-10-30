import Foundation

/// A typed identifier. The raw value is an opaque string so ids survive the state file and the control socket
/// unchanged; the phantom `Tag` makes a space id unusable where an item id is expected.
///
/// Encodes as a bare JSON string, and as an object key when used in a dictionary (`CodingKeyRepresentable`),
/// so `[ItemID: Item]` becomes `{ "id": {...} }` in the state file, not an array of pairs.
public struct ID<Tag>: Hashable, Comparable, Sendable, Codable, CodingKeyRepresentable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) { self.rawValue = rawValue }

    public var description: String { rawValue }
    public static func < (a: ID, b: ID) -> Bool { a.rawValue < b.rawValue }

    public init(from decoder: any Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }

    public var codingKey: any CodingKey { Key(stringValue: rawValue) }
    public init?<T: CodingKey>(codingKey: T) { self.rawValue = codingKey.stringValue }

    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}

public enum ItemTag {}
public enum SpaceTag {}
public enum WindowTag {}
public enum ArchiveTag {}
public enum ProfileTag {}
public enum DownloadTag {}
public enum LinkRouteTag {}
public enum SearchEngineTag {}
public enum AIRequestTag {}

/// A sidebar item: tab, folder, split, or section root (Arc: `Identifier<SidebarItem>`).
public typealias ItemID = ID<ItemTag>
/// Arc: `Identifier<SpaceModel>`.
public typealias SpaceID = ID<SpaceTag>
/// Arc: `ADKModels.WindowID`.
public typealias WindowID = ID<WindowTag>
/// One archive entry. Distinct from the archived tab's own ItemID, which restore reuses.
public typealias ArchiveID = ID<ArchiveTag>
/// Arc: `ADKModels.Profile`. Spaces, favorites roots, settings and pages carry one; `Doc.profiles` lists them.
public typealias ProfileID = ID<ProfileTag>
/// One file download (Arc: `StorableDownloadMetadata`). Minted by the engine as "<browser id>-<CEF download id>".
public typealias DownloadID = ID<DownloadTag>
/// One Air Traffic Control route (Arc: `StorableLinkRouting`).
public typealias LinkRouteID = ID<LinkRouteTag>
/// A search engine record (Arc: `SearchEngine.keyword`); built-ins use their keyword ("google", "duckduckgo").
public typealias SearchEngineID = ID<SearchEngineTag>
/// One request to the local AI provider (`Effect.ai` -> `SystemEvent.aiResult`).
public typealias AIRequestID = ID<AIRequestTag>

extension ID where Tag == ProfileTag {
    /// Arc stores its initial profile as "default".
    public static let `default` = ProfileID("default")
}

/// A point in time from the injected clock, in milliseconds since 1970. Only BrkApp/Clock.swift reads the real
/// clock; the domain receives `Instant`s in its context, the views receive `now` in their snapshot.
public struct Instant: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    public let milliseconds: Int64

    public init(milliseconds: Int64) { self.milliseconds = milliseconds }

    /// What the clock can read and the state file may hold: the Unix epoch through the last millisecond of 9999 UTC.
    /// Restore replaces a saved instant outside it (`StateCodec`); the test clock refuses to leave it.
    public static let supported = Instant(milliseconds: 0)...Instant(milliseconds: 253_402_300_799_999)

    public static func < (a: Instant, b: Instant) -> Bool { a.milliseconds < b.milliseconds }

    public func advanced(by duration: Duration) -> Instant {
        let (seconds, attoseconds) = duration.components
        return Instant(milliseconds: milliseconds + seconds * 1000 + attoseconds / 1_000_000_000_000_000)
    }

    /// `self - earlier`, as a `Duration`. Exact for any two instants: the difference is taken in `Duration`'s
    /// 128-bit range, where the Int64 subtraction could overflow.
    public func since(_ earlier: Instant) -> Duration { .milliseconds(milliseconds) - .milliseconds(earlier.milliseconds) }

    public var description: String { "\(milliseconds)ms" }

    public init(from decoder: any Decoder) throws {
        milliseconds = try decoder.singleValueContainer().decode(Int64.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(milliseconds)
    }
}
