import BrkBase
import BrkDomain
import Foundation

/// The overlay textures, generated procedurally (Arc's asset files are not copied). Pure and seeded, so the same
/// kind, size and seed give the same bytes on every run and machine.
///
/// Every feature is laid out in points of Arc's tile (`tileSize`): lattice counts and stripe frequencies are whole
/// numbers per tile, so the pattern wraps at the edges. `size` is the pixel size; `tileSize x backing scale` draws
/// the same pattern sharper on a 2x display, like Arc's @2x assets.
public enum TexturePixels {
    /// Arc's tile size for `kind`, in px at 1x (visual-and-copy.md, "Gradient and grain assets").
    public static func tileSize(_ kind: Texture) -> Int {
        switch kind {
        case .grain: Metrics.theme.grainTile.value
        case .sand: Metrics.theme.sandTile.value
        case .denim: Metrics.theme.denimTile.value
        case .tweed: Metrics.theme.tweedTile.value
        }
    }

    /// `size x size` pixels, two bytes each (luminance, alpha), rows from the top. Grain varies its alpha (Arc's
    /// grain is ARGB with transparency); sand, denim and tweed are opaque grayscale like Arc's.
    /// - grain: fine monochrome noise, one grain per point.
    /// - sand: soft speckle: 3 pt blobs with fine noise and scattered dark and light grains.
    /// - denim: steep right-hand twill (wales along 2x + y) over soft vertical warp streaks.
    /// - tweed: coarse fibres crossed at +-45 degrees, in two yarn tones, with flecks.
    public static func generate(_ kind: Texture, size: Int, seed: UInt64) -> [UInt8] {
        precondition(size > 0, "texture size must be positive")
        let tile = tileSize(kind)
        let pixel: (Double, Double) -> (luminance: Double, alpha: Double)
        switch kind {
        case .grain:
            let tone = Lattice(tile, tile, seed: seed, salt: 1), cover = Lattice(tile, tile, seed: seed, salt: 2)
            pixel = { u, v in (tone.sample(u, v), 0.15 + 0.4 * cover.sample(u, v)) }
        case .sand:
            let blobs = Lattice(tile / 3, tile / 3, seed: seed, salt: 1), fine = Lattice(tile, tile, seed: seed, salt: 2)
            let grains = Lattice(tile, tile, seed: seed, salt: 3)
            pixel = { u, v in
                var l = 0.55 + 1.1 * (0.6 * (blobs.sample(u, v) - 0.5) + 0.4 * (fine.sample(u, v) - 0.5))
                let g = grains.sample(u, v)
                if g < 0.08 { l -= 0.3 } else if g > 0.94 { l += 0.2 }
                return (l, 1)
            }
        case .denim:
            let wales = Double(tile / 6)   // 50 per 300 pt tile: 3 pt apart along a row
            let streaks = Lattice(tile / 2, 10, seed: seed, salt: 1), fine = Lattice(tile, tile, seed: seed, salt: 2)
            pixel = { u, v in
                let ridge = pow(0.5 + 0.5 * sin(2 * Double.pi * (2 * u + v) * wales), 1.5)
                return (0.34 + 0.42 * ridge + 0.12 * streaks.sample(u, v) + 0.1 * fine.sample(u, v), 1)
            }
        case .tweed:
            // Fibres along both diagonals: lattices in a = u + v and b = u - v, which wrap whenever u or v does.
            // 16 cells per unit of a is about 6 pt along a fibre, 64 per unit of b about 1.4 pt across it.
            let rising = Lattice(16, 64, seed: seed, salt: 1), falling = Lattice(64, 16, seed: seed, salt: 2)
            let flecks = Lattice(tile, tile, seed: seed, salt: 3)
            pixel = { u, v in
                let a = u + v, b = u - v
                let fibre = max(rising.sample(a, b), falling.sample(a, b))
                // Two yarn tones with a short blend between them.
                let t = min(max((fibre - 0.55) / 0.12, 0), 1)
                var l = 0.42 + 0.4 * t * t * (3 - 2 * t)
                let f = flecks.sample(u, v)
                if f > 0.95 { l += 0.15 } else if f < 0.04 { l -= 0.15 }
                return (l, 1)
            }
        }
        var out = [UInt8](repeating: 0, count: size * size * 2)
        for y in 0..<size {
            let v = (Double(y) + 0.5) / Double(size)
            for x in 0..<size {
                let p = pixel((Double(x) + 0.5) / Double(size), v)
                out[(y * size + x) * 2] = byte(p.luminance)
                out[(y * size + x) * 2 + 1] = byte(p.alpha)
            }
        }
        return out
    }

    private static func byte(_ v: Double) -> UInt8 { UInt8((min(max(v, 0), 1) * 255).rounded()) }
}

/// Periodic value noise: `cols x rows` random values on a lattice that wraps, sampled with smoothstep
/// interpolation. Lattice points sit on pixel centres at 1x, so one cell per pixel is plain white noise.
private struct Lattice {
    let cols: Int, rows: Int
    private let values: [Double]

    init(_ cols: Int, _ rows: Int, seed: UInt64, salt: UInt64) {
        self.cols = cols
        self.rows = rows
        var values = [Double](repeating: 0, count: cols * rows)
        for j in 0..<rows {
            for i in 0..<cols {
                var h = seed &+ salt &* 0xD1B5_4A32_D192_ED03
                h ^= UInt64(i) &* 0x9E37_79B9_7F4A_7C15
                h ^= UInt64(j) &* 0xC2B2_AE3D_27D4_EB4F
                values[j * cols + i] = Double(splitMix(h) >> 11) / Double(1 << 53)
            }
        }
        self.values = values
    }

    func value(_ i: Int, _ j: Int) -> Double {
        values[((j % rows) + rows) % rows * cols + ((i % cols) + cols) % cols]
    }

    /// `u`, `v` in tile units (0..<1 covers the tile once).
    func sample(_ u: Double, _ v: Double) -> Double {
        let gx = u * Double(cols) - 0.5, gy = v * Double(rows) - 0.5
        let i = Int(gx.rounded(.down)), j = Int(gy.rounded(.down))
        let fx = smooth(gx - Double(i)), fy = smooth(gy - Double(j))
        let top = value(i, j) + (value(i + 1, j) - value(i, j)) * fx
        let bottom = value(i, j + 1) + (value(i + 1, j + 1) - value(i, j + 1)) * fx
        return top + (bottom - top) * fy
    }

    private func smooth(_ t: Double) -> Double { t * t * (3 - 2 * t) }
}

/// SplitMix64's output function: a well-mixed 64-bit value from any input.
private func splitMix(_ x: UInt64) -> UInt64 {
    var z = x &+ 0x9E37_79B9_7F4A_7C15
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
}
