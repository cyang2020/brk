import BrkBase
import BrkDomain
import Foundation

/// The overlay textures, generated procedurally (Arc's asset files are not copied). Pure and seeded, so the same
/// kind, size and seed give the same bytes on every run and machine.
///
/// Arc's Metal renderer draws `grain_metal`, `sand_metal`, `denim_metal` and `tweed_metal` one texel per device pixel
/// (docs/checks/2026-11-13-window-translucency.md, round 2), so the tiles are made at those pixel sizes (`tileSize`) and
/// then scaled to the grey mean and spread of Arc's tiles (`textureTone`): a texture at a given noise darkens a color
/// by as much as Arc's. Lattice counts and stripe frequencies are whole numbers per tile, so the pattern wraps.
public enum TexturePixels {
    /// The tile's size in device pixels (Metrics.theme.*Tile).
    public static func tileSize(_ kind: Texture) -> Int {
        switch kind {
        case .grain: Metrics.theme.grainTile.value
        case .sand: Metrics.theme.sandTile.value
        case .denim: Metrics.theme.denimTile.value
        case .tweed: Metrics.theme.tweedTile.value
        }
    }

    /// `size x size` pixels, two bytes each (grey, alpha), rows from the top. Grain is grey noise at Arc's constant alpha;
    /// sand, denim and tweed are opaque like Arc's.
    /// - grain: fine noise, a grain about 1.5 px across (Arc's neighbouring pixels correlate 0.39).
    /// - sand: soft 3 px speckle with fine noise and scattered dark and light grains.
    /// - denim: right-hand twill 2 px apart along a row (Arc's neighbours alternate, -0.56) over soft vertical streaks.
    /// - tweed: coarse fibres crossed at +-45 degrees, in two yarn tones, with flecks.
    public static func generate(_ kind: Texture, size: Int, seed: UInt64) -> [UInt8] {
        precondition(size > 0, "texture size must be positive")
        let tile = tileSize(kind)
        let pixel: (Double, Double) -> Double
        switch kind {
        case .grain:
            let tone = Lattice(tile * 2 / 3, tile * 2 / 3, seed: seed, salt: 1)
            pixel = { u, v in tone.sample(u, v) }
        case .sand:
            let blobs = Lattice(tile / 3, tile / 3, seed: seed, salt: 1), fine = Lattice(tile, tile, seed: seed, salt: 2)
            let grains = Lattice(tile, tile, seed: seed, salt: 3)
            pixel = { u, v in
                var l = 0.6 * (blobs.sample(u, v) - 0.5) + 0.4 * (fine.sample(u, v) - 0.5)
                let g = grains.sample(u, v)
                if g < 0.08 { l -= 0.3 } else if g > 0.94 { l += 0.2 }
                return l
            }
        case .denim:
            let wales = Double(tile / 4)   // 25 per 100 px tile: 2 px apart along a row
            let streaks = Lattice(tile / 2, 10, seed: seed, salt: 1), fine = Lattice(tile, tile, seed: seed, salt: 2)
            pixel = { u, v in
                let ridge = pow(0.5 + 0.5 * sin(2 * Double.pi * (2 * u + v) * wales), 1.5)
                return 0.42 * ridge + 0.12 * streaks.sample(u, v) + 0.1 * fine.sample(u, v)
            }
        case .tweed:
            // Fibres along both diagonals: lattices in a = u + v and b = u - v, which wrap whenever u or v does.
            let rising = Lattice(16, 64, seed: seed, salt: 1), falling = Lattice(64, 16, seed: seed, salt: 2)
            let flecks = Lattice(tile, tile, seed: seed, salt: 3)
            pixel = { u, v in
                let a = u + v, b = u - v
                let fibre = max(rising.sample(a, b), falling.sample(a, b))
                let t = min(max((fibre - 0.55) / 0.12, 0), 1)
                var l = 0.4 * t * t * (3 - 2 * t)
                let f = flecks.sample(u, v)
                if f > 0.95 { l += 0.15 } else if f < 0.04 { l -= 0.15 }
                return l
            }
        }
        var raw = [Double](repeating: 0, count: size * size)
        for y in 0..<size {
            let v = (Double(y) + 0.5) / Double(size)
            for x in 0..<size { raw[y * size + x] = pixel((Double(x) + 0.5) / Double(size), v) }
        }
        // Scaled to Arc's tile: the same grey mean and spread.
        let tone = textureTone(kind)
        let mean = raw.reduce(0, +) / Double(raw.count)
        let spread = (raw.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(raw.count)).squareRoot()
        let gain = spread > 0 ? tone.spread / spread : 0
        var out = [UInt8](repeating: 0, count: size * size * 2)
        for i in 0..<raw.count {
            out[i * 2] = byte(tone.mean + (raw[i] - mean) * gain)
            out[i * 2 + 1] = byte(tone.alpha)
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
