import BrkBase
import BrkDomain
import CoreGraphics
import Foundation
import Metal
import QuartzCore

/// Metal pipeline for the themed background, in three passes like Arc's shader library (gradientFragment,
/// overlayFragment, renderFragment; anatomy, "Space theme system"):
/// 1. gradient: the theme's stops blended softly across a small texture (Metrics.theme.gradientTexturePerFactor x
///    backing scale px), mixed by `progress` with the gradient last drawn.
/// 2. overlay: the theme's tile, repeated from the top-left at its size in points, turned into the factor the
///    gradient is multiplied by (1 - opacity x (1 - tile value)), mixed by `progress` with the factor last drawn.
/// 3. render: gradient (scaled to the drawable) x factor at the theme's layer alpha over its underlay, premultiplied,
///    into a drawable that is not opaque: the window's material shows through the rest (Arc's GradientLayer:
///    `underlayColor` and the layer alpha; docs/checks/2026-11-13-window-translucency.md).
///
/// The textures of passes 1 and 2 are kept in pairs: a transition freezes the pair last drawn as its "from" side, so
/// a space switch that interrupts a running crossfade continues from exactly what is on screen.
///
/// Shaders are compiled at run time from `shaderSource` with `makeLibrary(source:options:)`, because SwiftPM does
/// not compile .metal files; the compile happens once per renderer.
@MainActor
final class ThemeRenderer {
    let device: any MTLDevice
    private let queue: any MTLCommandQueue
    private let gradientPipeline: any MTLRenderPipelineState
    private let overlayPipeline: any MTLRenderPipelineState
    private let renderPipeline: any MTLRenderPipelineState
    private let tiles: TileCache
    /// Bound in place of a tile that is not generated yet (factor 1: no texture).
    private let blank: any MTLTexture

    private var theme: ResolvedTheme?
    private var start: CFTimeInterval = 0
    private var duration: Double = 0
    private var fromLayer = Layer.clear
    private var targets: Targets?
    /// Which texture of each pair holds the "from" side; the other one is drawn into.
    private var from = 0
    /// What the last frame drew (index of the pair, its layer values), nil before the first frame.
    private var last: (output: Int, layer: Layer)?
    /// The texture's opacity is multiplied by this: Metrics.theme.inactiveTextureFactor while the window is inactive.
    var textureScale: Double = 1
    /// Two themes mixed at a progress the caller holds (a Space swipe's position), instead of a timed crossfade.
    /// `baseDrawn`: the "from" side of the pair holds `base`.
    private var scrubbing: (base: ResolvedTheme, progress: Double, baseDrawn: Bool)?

    /// Called with the kind of a tile that finished generating in the background.
    var onTileReady: ((Texture) -> Void)? {
        get { tiles.onReady }
        set { tiles.onReady = newValue }
    }

    init?(device: (any MTLDevice)?) {
        guard let device, let queue = device.makeCommandQueue() else { return nil }
        do {
            let library = try device.makeLibrary(source: Self.shaderSource, options: nil)
            func pipeline(_ fragment: String, _ format: MTLPixelFormat) throws -> any MTLRenderPipelineState {
                let descriptor = MTLRenderPipelineDescriptor()
                descriptor.vertexFunction = library.makeFunction(name: "fullScreen")
                descriptor.fragmentFunction = library.makeFunction(name: fragment)
                descriptor.colorAttachments[0].pixelFormat = format
                return try device.makeRenderPipelineState(descriptor: descriptor)
            }
            gradientPipeline = try pipeline("gradientFragment", Self.gradientFormat)
            overlayPipeline = try pipeline("overlayFragment", Self.overlayFormat)
            renderPipeline = try pipeline("renderFragment", Self.drawableFormat)
        } catch {
            return nil
        }
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rg8Unorm, width: 1, height: 1, mipmapped: false)
        guard let blank = device.makeTexture(descriptor: descriptor) else { return nil }
        blank.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: [UInt8(255), UInt8(255)], bytesPerRow: 2)
        self.device = device
        self.queue = queue
        self.blank = blank
        tiles = TileCache(device: device)
    }

    static let drawableFormat = MTLPixelFormat.bgra8Unorm
    private static let gradientFormat = MTLPixelFormat.rgba16Float
    private static let overlayFormat = MTLPixelFormat.r8Unorm

    /// The theme shown, or being faded to.
    var target: ResolvedTheme? { theme }

    /// Starts generating every kind of tile at `scale` in the background, so a space switch never waits for one.
    func prewarm(scale: Int) {
        for kind in Texture.allCases { _ = tiles.tile(kind, scale: scale) }
    }

    /// Fades from what the last frame showed to `theme` over `duration`; 0 (or no frame drawn yet) switches at once.
    func transition(to theme: ResolvedTheme, duration: Double, at now: CFTimeInterval) {
        scrubbing = nil
        self.theme = theme
        start = now
        if let last, duration > 0 {
            from = last.output
            fromLayer = last.layer
            self.duration = duration
        } else {
            self.duration = 0
        }
    }

    var isScrubbing: Bool { scrubbing != nil }

    /// Mixes `base` and `theme` at `progress` from the next frame on (linear, as Arc's colors follow the page position).
    func scrub(from base: ResolvedTheme, to theme: ResolvedTheme, progress: Double) {
        let drawn = scrubbing.map { $0.base == base && $0.baseDrawn } ?? false
        scrubbing = (base, min(max(progress, 0), 1), drawn)
        self.theme = theme
    }

    /// Progress of the running transition at `time`, 0...1, eased in and out; 1 when none is running.
    func progress(at time: CFTimeInterval) -> Double {
        if let scrubbing { return scrubbing.progress }
        guard duration > 0 else { return 1 }
        let t = min(max((time - start) / duration, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Draws one frame for `time` into `texture` (the drawable's, or any texture of `drawableFormat`) with `scale`
    /// device pixels per point. Returns false when no transition is running any more (the display link can stop).
    @discardableResult
    func encode(into texture: any MTLTexture, scale: Int, at time: CFTimeInterval, commandBuffer: any MTLCommandBuffer) -> Bool {
        guard let theme else { return false }
        let targets = targets(width: texture.width, height: texture.height, scale: scale)
        if let scrub = scrubbing, !scrub.baseDrawn {
            // The base goes into the pair's "from" side, whole; the frames after it mix over it.
            layers(of: scrub.base, into: from, over: 1 - from, progress: 1, scale: scale, targets: targets, commandBuffer: commandBuffer)
            fromLayer = Layer(scrub.base)
            scrubbing?.baseDrawn = true
        }
        let p = Float(progress(at: time))
        let output = 1 - from
        layers(of: theme, into: output, over: from, progress: p, scale: scale, targets: targets, commandBuffer: commandBuffer)

        // 3. Composite over the underlay, premultiplied.
        let to = Layer(theme)
        let layer = p >= 1 ? to : fromLayer.mixed(to, p)
        pass(commandBuffer, into: texture, renderPipeline, uniforms: layer.uniforms,
             textures: [targets.gradients[output], targets.overlays[output]])

        last = (output, layer)
        if scrubbing != nil { return false }
        if p >= 1 { duration = 0 }
        return p < 1
    }

    /// The gradient's alpha and the underlay below it, premultiplied and already scaled by what the gradient leaves
    /// uncovered: output = gradient x alpha + under, coverage = alpha + under.a.
    struct Layer: Equatable {
        var alpha: Float
        var under: SIMD4<Float>

        static let clear = Layer(alpha: 1, under: .zero)

        init(alpha: Float, under: SIMD4<Float>) {
            self.alpha = alpha
            self.under = under
        }

        init(_ theme: ResolvedTheme) {
            let a = min(max(theme.layerAlpha, 0), 1), u = theme.underlay.alpha * (1 - a)
            self.init(alpha: Float(a), under: SIMD4<Float>(Float(theme.underlay.red * u), Float(theme.underlay.green * u),
                                                           Float(theme.underlay.blue * u), Float(u)))
        }

        func mixed(_ other: Layer, _ p: Float) -> Layer {
            Layer(alpha: alpha + (other.alpha - alpha) * p, under: under + (other.under - under) * p)
        }

        var uniforms: [Float] { [under.x, under.y, under.z, under.w, alpha, 0, 0, 0] }
    }

    /// The gradient and overlay of `theme` into one side of the texture pairs, mixed over the other side.
    private func layers(of theme: ResolvedTheme, into output: Int, over from: Int, progress p: Float, scale: Int, targets: Targets, commandBuffer: any MTLCommandBuffer) {
        // 1. Gradient.
        let stops = (theme.gradient + Array(repeating: theme.gradient.last ?? RGBA(0, 0, 0), count: 3)).prefix(3)
        var gradient: [Float] = []
        for stop in stops { gradient += [Float(stop.red), Float(stop.green), Float(stop.blue), 1] }
        for i in 0..<3 {
            let anchor = theme.positions.indices.contains(i) ? theme.positions[i] : ThemePoint.anchors[i]
            gradient += [Float(anchor.x), Float(anchor.y), 0, 0]
        }
        gradient += [Float(min(theme.gradient.count, 3)), p, 0, 0]
        pass(commandBuffer, into: targets.gradients[output], gradientPipeline, uniforms: gradient,
             textures: [targets.gradients[from]])

        // 2. Overlay factor.
        let tile = tiles.tile(theme.texture, scale: scale)
        let tilePixels = Float(TexturePixels.tileSize(theme.texture) * scale)
        let overlay: [Float] = [tilePixels, tilePixels, tile == nil ? 0 : Float(theme.textureOpacity * textureScale),
                                Float(theme.textureContrast), tile?.mean ?? 1, p, 0, 0]
        pass(commandBuffer, into: targets.overlays[output], overlayPipeline, uniforms: overlay,
             textures: [tile?.texture ?? blank, targets.overlays[from]])
    }

    /// Draws one frame into the layer's next drawable and presents it with the current Core Animation transaction
    /// (the layer has `presentsWithTransaction`, so resizes never show a stretched or stale frame).
    @discardableResult
    func draw(in layer: CAMetalLayer, scale: Int, at time: CFTimeInterval) -> Bool {
        guard theme != nil, layer.drawableSize.width > 0, layer.drawableSize.height > 0,
              let drawable = layer.nextDrawable(), let commandBuffer = queue.makeCommandBuffer() else { return false }
        let animating = encode(into: drawable.texture, scale: scale, at: time, commandBuffer: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilScheduled()
        drawable.present()
        return animating
    }

    private func pass(_ commandBuffer: any MTLCommandBuffer, into texture: any MTLTexture, _ pipeline: any MTLRenderPipelineState,
                      uniforms: [Float], textures: [any MTLTexture]) {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = texture
        descriptor.colorAttachments[0].loadAction = .dontCare
        descriptor.colorAttachments[0].storeAction = .store
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: descriptor) else { return }
        encoder.setRenderPipelineState(pipeline)
        encoder.setFragmentBytes(uniforms, length: uniforms.count * MemoryLayout<Float>.stride, index: 0)
        for (i, t) in textures.enumerated() { encoder.setFragmentTexture(t, index: i) }
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        encoder.endEncoding()
    }

    /// The texture pairs, reallocated when the drawable's size or scale changes. A transition running across a
    /// reallocation finishes at once, since its frozen side is gone.
    private func targets(width: Int, height: Int, scale: Int) -> Targets {
        if let targets, targets.width == width, targets.height == height, targets.scale == scale { return targets }
        let side = Int(Metrics.theme.gradientTexturePerFactor.value) * scale
        func texture(_ format: MTLPixelFormat, _ w: Int, _ h: Int) -> any MTLTexture {
            let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: format, width: w, height: h, mipmapped: false)
            descriptor.usage = [.renderTarget, .shaderRead]
            descriptor.storageMode = .private
            return device.makeTexture(descriptor: descriptor)!
        }
        let made = Targets(width: width, height: height, scale: scale,
                           gradients: [texture(Self.gradientFormat, side, side), texture(Self.gradientFormat, side, side)],
                           overlays: [texture(Self.overlayFormat, width, height), texture(Self.overlayFormat, width, height)])
        targets = made
        duration = 0
        last = nil
        scrubbing?.baseDrawn = false
        return made
    }

    private struct Targets {
        let width: Int, height: Int, scale: Int
        let gradients: [any MTLTexture]
        let overlays: [any MTLTexture]
    }

    static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct Varyings { float4 position [[position]]; float2 uv; };

    // One triangle that covers the target; uv (0, 0) is the top-left corner.
    vertex Varyings fullScreen(uint id [[vertex_id]]) {
        float2 uv = float2((id << 1) & 2, id & 2);
        Varyings out;
        out.position = float4(uv.x * 2 - 1, 1 - uv.y * 2, 0, 1);
        out.uv = uv;
        return out;
    }

    struct GradientUniforms { float4 colors[3]; float4 anchors[3]; float count; float progress; };

    // Primary top-left (where the sidebar is), the lighter companion top-right, the darker one at the bottom.
    // Gaussian weights normalised per pixel give one soft blend with no flat spots or edges.
    fragment float4 gradientFragment(Varyings in [[stage_in]], constant GradientUniforms& u [[buffer(0)]],
                                     texture2d<float> from [[texture(0)]]) {
        const float2 anchors[3] = { float2(0.1, 0.15), float2(0.95, 0.25), float2(0.5, 1.0) };
        const float weights[3] = { 1.5, 1.0, 1.0 };
        float3 sum = 0;
        float total = 0;
        for (int i = 0; i < int(u.count); i++) {
            float2 d = in.uv - u.anchors[i].xy;
            float w = weights[i] * exp(-dot(d, d) / (2 * 0.42 * 0.42));
            sum += w * u.colors[i].rgb;
            total += w;
        }
        float3 to = sum / max(total, 1e-6);
        if (u.progress >= 1) { return float4(to, 1); }
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        return float4(mix(from.sample(s, in.uv).rgb, to, u.progress), 1);
    }

    struct OverlayUniforms { float2 tilePixels; float opacity; float contrast; float mean; float progress; };

    // The factor the gradient is multiplied by. The tile (luminance, alpha) is composited over white; noise scales
    // its deviation from the tile's mean, so the noise dial changes the pattern, not the brightness.
    fragment float4 overlayFragment(Varyings in [[stage_in]], constant OverlayUniforms& u [[buffer(0)]],
                                    texture2d<float> tile [[texture(0)]], texture2d<float> from [[texture(1)]]) {
        constexpr sampler s(filter::nearest, address::repeat);
        float2 t = tile.sample(s, in.position.xy / u.tilePixels).rg;
        float value = 1 - t.g * (1 - t.r);
        value = u.mean + (value - u.mean) * u.contrast;
        float to = 1 - u.opacity * (1 - value);
        if (u.progress >= 1) { return float4(to, 0, 0, 1); }
        return float4(mix(from.read(uint2(in.position.xy)).r, to, u.progress), 0, 0, 1);
    }

    struct RenderUniforms { float4 under; float alpha; };

    // Gradient x factor at the layer alpha over the underlay, premultiplied (the layer is not opaque: the window's
    // material shows through what it leaves). A dither of half a step hides 8-bit banding in the blend.
    fragment float4 renderFragment(Varyings in [[stage_in]], constant RenderUniforms& u [[buffer(0)]],
                                   texture2d<float> gradient [[texture(0)]], texture2d<float> overlay [[texture(1)]]) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        float3 color = gradient.sample(s, in.uv).rgb * overlay.read(uint2(in.position.xy)).r;
        float coverage = u.alpha + u.under.a;
        float dither = fract(sin(dot(in.position.xy, float2(12.9898, 78.233))) * 43758.5453) - 0.5;
        return float4(color * u.alpha + u.under.rgb + dither / 255.0 * coverage, coverage);
    }
    """
}

/// The procedural tiles as Metal textures, one per kind and backing scale, generated in the background
/// (TexturePixels is pure) and uploaded on the main actor. Arc's asset files are not copied.
@MainActor
final class TileCache {
    struct Tile {
        let texture: any MTLTexture
        /// Mean of the tile's luminance composited over white: what noise scales the deviation from.
        let mean: Float
    }

    private struct Key: Hashable, Sendable {
        let kind: Texture
        let scale: Int
    }

    let device: any MTLDevice
    var onReady: ((Texture) -> Void)?
    private var tiles: [Key: Tile] = [:]
    private var pending: Set<Key> = []

    init(device: any MTLDevice) { self.device = device }

    /// The tile, or nil while it is being generated (`onReady` fires when it is there).
    func tile(_ kind: Texture, scale: Int) -> Tile? {
        let key = Key(kind: kind, scale: scale)
        if let tile = tiles[key] { return tile }
        if pending.insert(key).inserted {
            let size = TexturePixels.tileSize(kind) * scale
            Task.detached(priority: .userInitiated) { [weak self] in
                let pixels = TexturePixels.generate(kind, size: size, seed: 1)
                await self?.upload(key, pixels, size: size)
            }
        }
        return nil
    }

    private func upload(_ key: Key, _ pixels: [UInt8], size: Int) {
        pending.remove(key)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rg8Unorm, width: size, height: size, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return }
        texture.replace(region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0, withBytes: pixels, bytesPerRow: size * 2)
        var sum = 0.0
        for i in stride(from: 0, to: pixels.count, by: 2) {
            sum += 1 - Double(pixels[i + 1]) / 255 * (1 - Double(pixels[i]) / 255)
        }
        tiles[key] = Tile(texture: texture, mean: Float(sum / Double(size * size)))
        onReady?(key.kind)
    }
}
