import Accelerate
import Foundation

/// Something the index can find: an open tab, a history address or an archived tab, by its title, its site and the
/// page's own short description when Brk read one this session (the page's meta description, else its first paragraph,
/// `PageDescription`), a saved conversation by its title and the user's own messages, or a file on this Mac by its name
/// and the start of its text (the file index, one per Mac). Nothing of a private window. The index file keeps only
/// vectors and hashes, never the text.
public struct IndexEntry: Hashable, Sendable {
    public enum Kind: String, Hashable, Sendable, CaseIterable { case tab, history, archive, conversation, file }

    /// Stable per thing: "tab:<item id>", "history:<url>", "archive:<archive id>", "conversation:<id>", "file:<path>".
    public var key: String
    public var kind: Kind
    public var title: String
    public var url: String
    /// The page's short description or the start of a file's text, nil when not read (an entry embedded with one keeps it).
    public var description: String?
    /// Part of the fingerprint besides the title and address: a file's size and modification time.
    public var version: String

    public init(kind: Kind, id: String, title: String, url: String, description: String? = nil, version: String = "") {
        self.key = "\(kind.rawValue):\(id)"
        self.kind = kind
        self.title = title
        self.url = url
        self.description = description?.isEmpty == true ? nil : description
        self.version = version
    }

    /// The text the model reads: the title and the host, then the description. Measured on 32 paraphrased queries over
    /// 40 real pages (~/brk-evidence/local-models-quality): the right page in the first two 22 times with the title and
    /// host, 28 with the description added. Titles alone often never say what a page is about ("Perseverance (rover)").
    public var text: EmbeddingText {
        let host = URL(string: url)?.host() ?? ""
        let head = host.isEmpty ? title : "\(title) (\(host))"
        return .document(title: nil, text: description.map { "\(head). \($0)" } ?? head)
    }

    /// Changes when the title, address or version changes; a stored vector with another value is embedded again.
    var fingerprint: UInt64 { Self.hash(version.isEmpty ? "\(title)\u{1F}\(url)" : "\(title)\u{1F}\(url)\u{1F}\(version)") }
    /// 0 without a description. A stored vector is embedded again when a different description arrives, and kept when
    /// none is known (after a relaunch the page is not read until it loads again).
    var descriptionPrint: UInt64 { description.map(Self.hash) ?? 0 }

    static func hash(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01B3 }
        return hash == 0 ? 1 : hash
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
/// turning search by meaning off deletes the file. The file holds keys, two hashes and 256 half-precision numbers
/// per entry (about 570 bytes), no titles and no page text.
public actor SemanticIndex {
    public let file: URL
    public let dimensions: Int
    private var keys: [String] = []
    private var kinds: [IndexEntry.Kind] = []
    private var fingerprints: [UInt64] = []
    private var descriptions: [UInt64] = []
    private var vectors: [[Float]] = []
    private var position: [String: Int] = [:]
    private var loaded = false
    /// Every vector in one row-major block, for one matrix-vector product per query (20,000 entries: about 1 ms, against
    /// 29 ms one dot product at a time); rebuilt after a change.
    private var matrix: [Float] = []
    private var matrixRows = -1

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
        let byKey = Dictionary(wanted.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        let keep = keys.indices.filter { index in
            guard let entry = byKey[keys[index]], entry.fingerprint == fingerprints[index] else { return false }
            return entry.description == nil || entry.descriptionPrint == descriptions[index]
        }
        if keep.count != keys.count {
            keys = keep.map { keys[$0] }
            kinds = keep.map { kinds[$0] }
            fingerprints = keep.map { fingerprints[$0] }
            descriptions = keep.map { descriptions[$0] }
            vectors = keep.map { vectors[$0] }
            matrixRows = -1
            reindex()
            try save()
        }
        guard let embedder else { return 0 }
        return try await add(missing(wanted), embedder: embedder, batch: batch)
    }

    /// The wanted entries the index has no vector for (by key; `reconcile` without an embedder first drops changed ones).
    public func missing(_ wanted: [IndexEntry]) -> [IndexEntry] {
        loadIfNeeded()
        var seen = Set(keys)
        return wanted.filter { seen.insert($0.key).inserted }
    }

    /// Embeds and keeps entries the index does not have yet, in batches, writing after each 16th and the last; drops
    /// nothing. Returns how many were embedded.
    @discardableResult
    public func add(_ entries: [IndexEntry], embedder: any TextEmbedding, batch: Int = 64) async throws -> Int {
        loadIfNeeded()
        let missing = entries
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
                descriptions.append(entry.descriptionPrint)
                vectors.append(VectorMath.truncated(vector, to: dimensions))
                matrixRows = -1
            }
            done += slice.count
            start += slice.count
            // A long first indexing keeps its work if Brk quits halfway; a short one writes once.
            if (start / batch) % 16 == 0 || start >= missing.count { try save() }
        }
        return done
    }

    /// The best `limit` entries for a query vector, best first: those at least `minimum` similar and at least `lead`
    /// above the query's median similarity over the whole index (every kind). The median is the query's own baseline:
    /// a vague text ("asdf", "hello") is about as close to every entry, a real one stands out from most of them.
    public func search(_ query: [Float], limit: Int = 8, kinds wanted: Set<IndexEntry.Kind> = Set(IndexEntry.Kind.allCases),
                       minimum: Float = 0, lead: Float = 0) -> [SearchHit] {
        loadIfNeeded()
        let q = VectorMath.truncated(query, to: dimensions)
        let scores = scored(q)
        let floor = max(minimum, lead > 0 ? VectorMath.median(scores) + lead : minimum)
        var hits: [SearchHit] = []
        for index in scores.indices where wanted.contains(kinds[index]) && scores[index] >= floor {
            hits.append(SearchHit(key: keys[index], kind: kinds[index], score: scores[index]))
        }
        return Array(hits.sorted { $0.score > $1.score }.prefix(limit))
    }

    private func scored(_ q: [Float]) -> [Float] {
        guard !vectors.isEmpty, q.count == dimensions else { return [] }
        if matrixRows != vectors.count || matrix.count != vectors.count * dimensions {
            matrix = vectors.flatMap { $0 }
            matrixRows = vectors.count
        }
        var out = [Float](repeating: 0, count: vectors.count)
        vDSP_mmul(matrix, 1, q, 1, &out, 1, vDSP_Length(vectors.count), 1, vDSP_Length(dimensions))
        return out
    }

    public func vector(for key: String) -> [Float]? {
        loadIfNeeded()
        return position[key].map { vectors[$0] }
    }

    /// Deletes every vector and the file.
    public func removeAll() {
        keys = []; kinds = []; fingerprints = []; descriptions = []; vectors = []; position = [:]
        loaded = true
        try? FileManager.default.removeItem(at: file)
    }

    private func reindex() {
        position = Dictionary(keys.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { a, _ in a })
    }

    // MARK: File: "BRKV", version, dimensions, count, then per entry: key length, key, kind, fingerprint, description
    // hash (version 2 on), Float16s. A version 1 file reads as embedded without descriptions.

    private static let magic: [UInt8] = Array("BRKV".utf8)
    private static let version: UInt32 = 2

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        guard let data = try? Data(contentsOf: file), let decoded = Self.decode(data, dimensions: dimensions) else { return }
        (keys, kinds, fingerprints, descriptions, vectors) = decoded
        reindex()
    }

    private func save() throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try Self.encode(keys: keys, kinds: kinds, fingerprints: fingerprints, descriptions: descriptions, vectors: vectors, dimensions: dimensions)
            .write(to: file, options: .atomic)
    }

    static func encode(keys: [String], kinds: [IndexEntry.Kind], fingerprints: [UInt64], descriptions: [UInt64], vectors: [[Float]], dimensions: Int) -> Data {
        var data = Data(magic)
        func put<T: FixedWidthInteger>(_ value: T) { withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) } }
        put(version); put(UInt32(dimensions)); put(UInt32(keys.count))
        for index in keys.indices {
            let key = Array(keys[index].utf8)
            put(UInt16(key.count)); data.append(contentsOf: key)
            put(UInt8(IndexEntry.Kind.allCases.firstIndex(of: kinds[index]) ?? 0))
            put(fingerprints[index])
            put(descriptions[index])
            for value in vectors[index] { put(HalfFloat.bits(value)) }
        }
        return data
    }

    static func decode(_ data: Data, dimensions: Int) -> ([String], [IndexEntry.Kind], [UInt64], [UInt64], [[Float]])? {
        var offset = 0
        func take(_ count: Int) -> Data? {
            guard offset + count <= data.count else { return nil }
            defer { offset += count }
            return data.subdata(in: data.startIndex + offset..<data.startIndex + offset + count)
        }
        func get<T: FixedWidthInteger>(_: T.Type) -> T? {
            take(MemoryLayout<T>.size).map { bytes in T(littleEndian: bytes.withUnsafeBytes { $0.loadUnaligned(as: T.self) }) }
        }
        guard take(4).map(Array.init) == magic, let fileVersion = get(UInt32.self), (1...version).contains(fileVersion),
              get(UInt32.self) == UInt32(dimensions), let count = get(UInt32.self) else { return nil }
        var keys: [String] = [], kinds: [IndexEntry.Kind] = [], prints: [UInt64] = [], described: [UInt64] = [], vectors: [[Float]] = []
        for _ in 0..<count {
            guard let length = get(UInt16.self), let key = take(Int(length)), let kind = get(UInt8.self), let print = get(UInt64.self),
                  IndexEntry.Kind.allCases.indices.contains(Int(kind)) else { return nil }
            let description: UInt64
            if fileVersion >= 2 { guard let value = get(UInt64.self) else { return nil }; description = value } else { description = 0 }
            var vector: [Float] = []
            vector.reserveCapacity(dimensions)
            for _ in 0..<dimensions {
                guard let bits = get(UInt16.self) else { return nil }
                vector.append(HalfFloat.value(bits))
            }
            keys.append(String(decoding: key, as: UTF8.self))
            kinds.append(IndexEntry.Kind.allCases[Int(kind)])
            prints.append(print)
            described.append(description)
            vectors.append(vector)
        }
        return (keys, kinds, prints, described, vectors)
    }
}

/// IEEE 754 binary16 conversion for the index file, written out because Swift's `Float16` exists only on Apple silicon
/// and the Intel build reads and writes the same files. Rounds to nearest, ties to even, as `Float16(_:)` does; the
/// tests compare both directions with `Float16` on arm64.
enum HalfFloat {
    static func bits(_ value: Float) -> UInt16 {
        let f = value.bitPattern
        let sign = UInt16(truncatingIfNeeded: (f >> 16) & 0x8000)
        let exponent = Int((f >> 23) & 0xFF)
        let mantissa = f & 0x7F_FFFF
        if exponent == 0xFF { return sign | 0x7C00 | (mantissa == 0 ? 0 : 0x200 | UInt16(truncatingIfNeeded: mantissa >> 13)) }
        let e = exponent - 127 + 15
        if e >= 0x1F { return sign | 0x7C00 }
        if e <= 0 {
            // Below the smallest normal half: a subnormal, value = m * 2^-24, or zero.
            let shift = 14 - e
            guard shift <= 24 else { return sign }
            return sign | UInt16(truncatingIfNeeded: roundedShift(mantissa | 0x80_0000, by: UInt32(shift)))
        }
        // A carry out of the mantissa moves into the exponent, up to infinity at 0x7C00.
        return sign | UInt16(truncatingIfNeeded: (UInt32(e) << 10) + roundedShift(mantissa, by: 13))
    }

    static func value(_ bits: UInt16) -> Float {
        let sign = UInt32(bits & 0x8000) << 16
        let exponent = UInt32((bits >> 10) & 0x1F)
        let mantissa = UInt32(bits & 0x3FF)
        if exponent == 0x1F { return Float(bitPattern: sign | 0x7F80_0000 | (mantissa << 13)) }
        if exponent == 0 {
            let magnitude = Float(mantissa) * 0x1p-24
            return sign == 0 ? magnitude : -magnitude
        }
        return Float(bitPattern: sign | ((exponent + 112) << 23) | (mantissa << 13))
    }

    private static func roundedShift(_ x: UInt32, by shift: UInt32) -> UInt32 {
        let kept = x >> shift
        let dropped = x & ((1 << shift) - 1)
        let half = UInt32(1) << (shift - 1)
        return dropped > half || (dropped == half && kept & 1 == 1) ? kept + 1 : kept
    }
}
