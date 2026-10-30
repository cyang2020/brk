import BrkBase
import BrkDomain
import Foundation
import Metal
import QuartzCore

/// Metal pipeline for the themed background, in three passes like Arc's shader library:
/// 1. gradient: render the gradient stops into a small texture (Metrics.theme.gradientTexturePerFactor x factor px)
///    with a soft multi-point blend; during a transition, blend the from/to gradients by `progress`.
/// 2. overlay: pick the texture tile(s) (from/to during a transition) with their opacities.
/// 3. render: draw the gradient texture scaled to the drawable, multiply the tiled overlay texture over it
///    (`overlayRepetitions` = drawable size / tile size, normal blend when opacity is 0), then the wash.
///
/// Shaders are compiled at run time from `ThemeRenderer.shaderSource` with `makeLibrary(source:options:)`, because
/// SwiftPM does not compile .metal files; the compile happens once at launch (a few ms).
@MainActor
final class ThemeRenderer {
    let device: any MTLDevice
    let layer: CAMetalLayer
    private let textures: TextureCache

    init?(device: (any MTLDevice)?) {
        guard let device else { return nil }
        self.device = device
        layer = CAMetalLayer()
        textures = TextureCache(device: device)
        // TODO(W5): build the three pipeline states from shaderSource; command queue.
    }

    /// Starts (or replaces) a transition. `duration` 0 switches at once.
    func transition(from: ResolvedTheme?, to: ResolvedTheme, duration: Double) {
        fatalError("not implemented")
    }

    /// Draws one frame at `time`; returns false when no transition is running (the display link can stop).
    func draw(at time: CFTimeInterval) -> Bool {
        fatalError("not implemented")
    }

    static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;
    // TODO(W5): vertex shader for a full-screen triangle; fragment gradientFragment(stops, count, progress),
    // overlayFragment(fromTile, toTile, fromAlpha, toAlpha, progress), renderFragment(gradientTexture,
    // overlayTexture, repetitions, wash).
    """
}

/// Procedural, tileable textures, generated once per kind at the tile sizes of Arc's own assets
/// (Metrics.theme.*Tile) and uploaded as MTLTextures. Arc's asset files are not copied.
@MainActor
final class TextureCache {
    let device: any MTLDevice
    private var cache: [Texture: any MTLTexture] = [:]

    init(device: any MTLDevice) { self.device = device }

    func texture(_ kind: Texture) -> any MTLTexture {
        fatalError("not implemented")
    }
}
