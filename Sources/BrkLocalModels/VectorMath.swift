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
    /// Average-linkage clustering on cosine similarity: clusters merge while some pair is at least `threshold` similar
    /// on average. Measured on 3 labelled Today lists of 33 tabs (verify/ai-native/b-local-models): with titles embedded
    /// as `.document(title: nil, text: title)`, 0.70 gave the best shared adjusted Rand index (0.62, 0.54, 0.55).
    /// Returns clusters of indices, biggest first, each in input order.
    public static func clusters(_ vectors: [[Float]], threshold: Float = 0.70) -> [[Int]] {
        var clusters = vectors.indices.map { [$0] }
        guard clusters.count > 1 else { return clusters }
        let n = vectors.count
        var similarity = [[Float]](repeating: [Float](repeating: 0, count: n), count: n)
        for i in 0..<n { for j in i..<n { let s = VectorMath.dot(vectors[i], vectors[j]); similarity[i][j] = s; similarity[j][i] = s } }
        // Sum of pairwise similarities between clusters, kept up to date as they merge.
        var link = similarity
        while clusters.count > 1 {
            var best: Float = -.infinity, pair = (0, 0)
            for i in 0..<clusters.count {
                for j in (i + 1)..<clusters.count {
                    let average = link[i][j] / Float(clusters[i].count * clusters[j].count)
                    if average > best { best = average; pair = (i, j) }
                }
            }
            guard best >= threshold else { break }
            let (i, j) = pair
            for k in 0..<clusters.count where k != i && k != j {
                link[i][k] += link[j][k]
                link[k][i] = link[i][k]
            }
            clusters[i] += clusters[j]
            clusters.remove(at: j)
            link.remove(at: j)
            for k in link.indices { link[k].remove(at: j) }
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
