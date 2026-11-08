import Foundation

/// Something the index can find: an open tab, a history address or an archived tab, by its title and site, or a saved
/// conversation by its title and the user's own messages. Only those go into the model, never page text, and nothing of
/// a private window.
public struct IndexEntry: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable, CaseIterable { case tab, history, archive, conversation }

    /// Stable per thing: "tab:<item id>", "history:<url>", "archive:<archive id>", "conversation:<id>".
    public var key: String
    public var kind: Kind
    public var title: String
    public var url: String

    public init(kind: Kind, id: String, title: String, url: String) {
        self.key = "\(kind.rawValue):\(id)"
        self.kind = kind
        self.title = title
        self.url = url
    }

    /// The text the model reads: the title and the host, as measured best for search and placement together.
    public var text: EmbeddingText {
        let host = URL(string: url)?.host() ?? ""
        return .document(title: nil, text: host.isEmpty ? title : "\(title) (\(host))")
    }

    /// Changes when what the model would read changes; a stored vector with another value is embedded again.
    var fingerprint: UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in "\(title)\u{1F}\(url)".utf8 { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
        return hash
    }
}

public struct SearchHit: Hashable, Sendable {
    public var key: String
    public var kind: IndexEntry.Kind
    public var score: Float
}

/// One profile's vectors for search by meaning, in `<data>/Local Models/Index/<profile>.vectors`.
///
/// What it holds is decided by the browser's state, never by the index: `reconcile` is given everything that should be
/// findable now, and anything else is dropped and the file rewritten before any new vector is computed. Clearing
/// history, removing a visit, deleting an archived tab or closing a tab therefore removes its vector at the next
/// reconcile, which BrkApp runs a few seconds after the state changes and at launch. Removing the search model or
/// turning search by meaning off deletes the file. The file holds keys, fingerprints and 256 half-precision numbers
/// per entry (about 560 bytes), no titles and no page text.
public actor SemanticIndex {
    public let file: URL
    public let dimensions: Int
    private var keys: [String] = []
    private var kinds: [IndexEntry.Kind] = []
    private var fingerprints: [UInt64] = []
    private var vectors: [[Float]] = []
    private var position: [String: Int] = [:]
    private var loaded = false

    /// Upper bound on entries; past it the oldest history goes unindexed (the caller orders entries newest first).
    public static let capacity = 50_000

    public init(file: URL, dimensions: Int = 256) {
        self.file = file
        self.dimensions = dimensions
    }

    public var count: Int { vectors.count }

    public func contains(_ key: String) -> Bool { position[key] != nil }

    /// Drops what is no longer wanted (written at once), then embeds what is new or changed, in batches, writing after
    /// each. Without an embedder only the dropping happens. Returns how many entries were embedded.
    @discardableResult
    public func reconcile(_ wanted: [IndexEntry], embedder: (any TextEmbedding)?, batch: Int = 64) async throws -> Int {
        loadIfNeeded()
        let wanted = Array(wanted.prefix(Self.capacity))
        let wantedPrints = Dictionary(wanted.map { ($0.key, $0.fingerprint) }, uniquingKeysWith: { a, _ in a })
        let keep = keys.indices.filter { wantedPrints[keys[$0]] == fingerprints[$0] }
        if keep.count != keys.count {
            keys = keep.map { keys[$0] }
            kinds = keep.map { kinds[$0] }
            fingerprints = keep.map { fingerprints[$0] }
            vectors = keep.map { vectors[$0] }
            reindex()
            try save()
        }
        guard let embedder else { return 0 }
        var seen = Set(keys)
        let missing = wanted.filter { seen.insert($0.key).inserted }
        var done = 0
        var start = 0
        while start < missing.count {
            try Task.checkCancellation()
            let slice = Array(missing[start..<min(start + batch, missing.count)])
            let embedded = try await embedder.embed(slice.map(\.text))
            // The state may have dropped some of these meanwhile; the next reconcile removes them.
            for (entry, vector) in zip(slice, embedded) where position[entry.key] == nil {
                position[entry.key] = keys.count
                keys.append(entry.key)
                kinds.append(entry.kind)
                fingerprints.append(entry.fingerprint)
                vectors.append(VectorMath.truncated(vector, to: dimensions))
            }
            done += slice.count
            start += slice.count
            // A long first indexing keeps its work if Brk quits halfway; a short one writes once.
            if (start / batch) % 16 == 0 || start >= missing.count { try save() }
        }
        return done
    }

    /// The best `limit` entries for a query vector, best first, at least `minimum` similar.
    public func search(_ query: [Float], limit: Int = 8, kinds wanted: Set<IndexEntry.Kind> = Set(IndexEntry.Kind.allCases),
                       minimum: Float = 0) -> [SearchHit] {
        loadIfNeeded()
        let q = VectorMath.truncated(query, to: dimensions)
        var hits: [SearchHit] = []
        for index in vectors.indices where wanted.contains(kinds[index]) {
            let score = VectorMath.dot(q, vectors[index])
            if score >= minimum { hits.append(SearchHit(key: keys[index], kind: kinds[index], score: score)) }
        }
        return Array(hits.sorted { $0.score > $1.score }.prefix(limit))
    }

    public func vector(for key: String) -> [Float]? {
        loadIfNeeded()
        return position[key].map { vectors[$0] }
    }

    /// Deletes every vector and the file.
    public func removeAll() {
        keys = []; kinds = []; fingerprints = []; vectors = []; position = [:]
        loaded = true
        try? FileManager.default.removeItem(at: file)
    }

    private func reindex() {
        position = Dictionary(keys.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: File: "BRKV", version, dimensions, count, then per entry: key length, key, kind, fingerprint, Float16s.

    private static let magic: [UInt8] = Array("BRKV".utf8)
    private static let version: UInt32 = 1

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: file), let decoded = Self.decode(data, dimensions: dimensions) else { return }
        (keys, kinds, fingerprints, vectors) = decoded
        reindex()
    }

    private func save() throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try Self.encode(keys: keys, kinds: kinds, fingerprints: fingerprints, vectors: vectors, dimensions: dimensions)
            .write(to: file, options: .atomic)
    }

    static func encode(keys: [String], kinds: [IndexEntry.Kind], fingerprints: [UInt64], vectors: [[Float]], dimensions: Int) -> Data {
        var data = Data(magic)
        func put<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        put(version); put(UInt32(dimensions)); put(UInt32(keys.count))
        for index in keys.indices {
            let key = Array(keys[index].utf8)
            put(UInt16(key.count)); data.append(contentsOf: key)
            put(UInt8(IndexEntry.Kind.allCases.firstIndex(of: kinds[index]) ?? 0))
            put(fingerprints[index])
            for value in vectors[index] { put(Float16(value).bitPattern) }
        }
        return data
    }

    static func decode(_ data: Data, dimensions: Int) -> ([String], [IndexEntry.Kind], [UInt64], [[Float]])? {
        var offset = 0
        func take(_ count: Int) -> Data? {
            guard offset + count <= data.count else { return nil }
            defer { offset += count }
            return data.subdata(in: data.startIndex + offset..<data.startIndex + offset + count)
        }
        func get<T: FixedWidthInteger>(_: T.Type) -> T? {
            take(MemoryLayout<T>.size).map { bytes in T(littleEndian: bytes.withUnsafeBytes { $0.loadUnaligned(as: T.self) }) }
        }
        guard take(4).map(Array.init) == magic, get(UInt32.self) == version, get(UInt32.self) == UInt32(dimensions),
              let count = get(UInt32.self) else { return nil }
        var keys: [String] = [], kinds: [IndexEntry.Kind] = [], prints: [UInt64] = [], vectors: [[Float]] = []
        for _ in 0..<count {
            guard let length = get(UInt16.self), let key = take(Int(length)), let kind = get(UInt8.self), let print = get(UInt64.self),
                  IndexEntry.Kind.allCases.indices.contains(Int(kind)) else { return nil }
            var vector: [Float] = []
            vector.reserveCapacity(dimensions)
            for _ in 0..<dimensions {
                guard let bits = get(UInt16.self) else { return nil }
                vector.append(Float(Float16(bitPattern: bits)))
            }
            keys.append(String(decoding: key, as: UTF8.self))
            kinds.append(IndexEntry.Kind.allCases[Int(kind)])
            prints.append(print)
            vectors.append(vector)
        }
        return (keys, kinds, prints, vectors)
    }
}
