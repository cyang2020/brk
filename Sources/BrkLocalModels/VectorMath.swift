import Accelerate
import Foundation

public enum VectorMath {
    public static func dot(_ a: [Float], _ b: [Float]) -> Float {
        precondition(a.count == b.count)
        return vDSP.dot(a, b)
    }

    public static func normalized(_ v: [Float]) -> [Float] {
        let length = sqrt(vDSP.sumOfSquares(v))
        return length > 0 ? vDSP.divide(v, length) : v
    }

    /// The first `count` values, renormalised (Matryoshka truncation).
    public static func truncated(_ v: [Float], to count: Int) -> [Float] {
        normalized(count < v.count ? Array(v.prefix(count)) : v)
    }

    /// The middle value (the mean of the two middle values for an even count); 0 for none.
    public static func median(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2
    }

    /// The normalised mean of unit vectors: a group's direction.
    public static func centroid(_ vectors: [[Float]]) -> [Float] {
        guard let first = vectors.first else { return [] }
        var sum = [Float](repeating: 0, count: first.count)
        for v in vectors { vDSP.add(sum, v, result: &sum) }
        return normalized(sum)
    }
}

/// Grouping by the search model's vectors, for the features that call it: Tidy's first cut, the closest groups for a
/// new tab before the decision model picks one, and near-duplicate candidates.
public enum EmbeddingGroups {
    /// Average-linkage clustering with two checks: two clusters merge only while their average similarity is at least
    /// `threshold` and, with every vector first moved off the list's mean (centred), still at least `centred`. The first
    /// check is slice B's (0.70 on 3 labelled lists of 33 tabs); alone it put every tab of one broad subject together
    /// (the README's 8 developer tabs in one group of 7), because all their pairs sit above it. Centring removes what the
    /// whole list shares, so the second check asks whether two clusters are more alike than the list as a whole. Measured
    /// on 8 labelled lists, 2 of them held out (~/brk-evidence/local-models-quality): adjusted Rand index 0.40 to 0.57 on
    /// the six used for choosing, 0.32 to 0.63 on the two held out; the README list 0.23 to 0.90. The pair with the
    /// most room above both checks merges first. Returns clusters of indices, biggest first, each in input order.
    public static func clusters(_ vectors: [[Float]], threshold: Float = 0.68, centred: Float = 0) -> [[Int]] {
        var clusters = vectors.indices.map { [$0] }
        guard clusters.count > 1 else { return clusters }
        let n = vectors.count
        let mean = (0..<vectors[0].count).map { d in vectors.reduce(Float(0)) { $0 + $1[d] } / Float(n) }
        let moved = vectors.map { VectorMath.normalized(zip($0, mean).map { $0 - $1 }) }
        var raw = [[Float]](repeating: [Float](repeating: 0, count: n), count: n)
        var off = raw
        for i in 0..<n {
            for j in i..<n {
                let a = VectorMath.dot(vectors[i], vectors[j]), b = VectorMath.dot(moved[i], moved[j])
                raw[i][j] = a; raw[j][i] = a; off[i][j] = b; off[j][i] = b
            }
        }
        // Sums of pairwise similarities between clusters, kept up to date as they merge.
        while clusters.count > 1 {
            var best: Float = -.infinity, pair = (0, 0)
            for i in 0..<clusters.count {
                for j in (i + 1)..<clusters.count {
                    let size = Float(clusters[i].count * clusters[j].count)
                    let room = min(raw[i][j] / size - threshold, off[i][j] / size - centred)
                    if room > best { best = room; pair = (i, j) }
                }
            }
            guard best >= 0 else { break }
            let (i, j) = pair
            for k in 0..<clusters.count where k != i && k != j {
                raw[i][k] += raw[j][k]; raw[k][i] = raw[i][k]
                off[i][k] += off[j][k]; off[k][i] = off[i][k]
            }
            clusters[i] += clusters[j]
            clusters.remove(at: j)
            raw.remove(at: j); off.remove(at: j)
            for k in raw.indices { raw[k].remove(at: j); off[k].remove(at: j) }
        }
        return clusters.map { $0.sorted() }.sorted { $0.count != $1.count ? $0.count > $1.count : $0[0] < $1[0] }
    }

    /// The `limit` groups whose centroid is closest to `vector`, closest first, with their similarity.
    public static func nearest(_ vector: [Float], groups: [(id: String, vectors: [[Float]])], limit: Int = 5) -> [(id: String, similarity: Float)] {
        groups.filter { !$0.vectors.isEmpty }
            .map { ($0.id, VectorMath.dot(vector, VectorMath.centroid($0.vectors))) }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { (id: $0.0, similarity: $0.1) }
    }

    /// Pairs at least `threshold` similar: candidates only. Measured: every duplicate pair scored 0.92 or more, but so
    /// did 6 of 18 different pages on the same site (Sony XM5 against XM6: 0.977), so a candidate needs the address
    /// rule or the decision model before Brk calls it a duplicate.
    public static func duplicateCandidates(_ vectors: [[Float]], threshold: Float = 0.92) -> [(Int, Int, Float)] {
        var out: [(Int, Int, Float)] = []
        for i in vectors.indices {
            for j in (i + 1)..<vectors.count {
                let s = VectorMath.dot(vectors[i], vectors[j])
                if s >= threshold { out.append((i, j, s)) }
            }
        }
        return out.sorted { $0.2 > $1.2 }
    }
}
