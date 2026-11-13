import BrkBase
import BrkDomain
import CoreGraphics
import Foundation
import Metal
import QuartzCore

/// Metal pipeline for the themed background, in three passes like Arc's shader library (gradientFragment,
/// overlayFragment, renderFragment; docs/checks/2026-11-13-window-translucency.md):
/// 1. gradient: Arc's layer color into a small texture (Metrics.theme.gradientTexturePerFactor x backing scale px),
///    premultiplied: the first two colors mixed in OKLab along the 45 degree ramp (`themeRampCorners`), a third mixed in
///    from clear at the top, each at the theme's layer alpha; mixed by `progress` with the gradient last drawn.
/// 2. overlay: the theme's tile, one texel per device pixel, as premultiplied grey and alpha (the tile's alpha x the
///    texture opacity), mixed by `progress` with the overlay last drawn.
/// 3. render: the gradient (scaled to the drawable) over the underlay, then the overlay multiplied over both, as Arc's
///    renderFragment does, into a drawable that is not opaque: the window's material shows through the rest.
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
    /// Bound in place of a tile that is not generated yet (alpha 0: no texture).
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
        blank.replace(region: MTLRegionMake2D(0, 0, 1, 1), mipmapLevel: 0, withBytes: [UInt8(255), UInt8(0)], bytesPerRow: 2)
        self.device = device
        self.queue = queue
        self.blank = blank
        tiles = TileCache(device: device)
    }

    static let drawableFormat = MTLPixelFormat.bgra8Unorm
    private static let gradientFormat = MTLPixelFormat.rgba16Float
    private static let overlayFormat = MTLPixelFormat.rg16Float

    /// The theme shown, or being faded to.
    var target: ResolvedTheme? { theme }

    /// Starts generating every kind of tile in the background, so a space switch never waits for one. The tiles are
    /// one texel per device pixel at any backing scale, as Arc's.
    func prewarm() {
        for kind in Texture.allCases { _ = tiles.tile(kind) }
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

    /// The underlay under the theme's colors, premultiplied (U x u, u): the render pass lays the gradient over it.
    struct Layer: Equatable {
        var under: SIMD4<Float>

        static let clear = Layer(under: .zero)

        init(under: SIMD4<Float>) { self.under = under }

        init(_ theme: ResolvedTheme) {
            let u = Float(theme.underlay.alpha)
            self.init(under: SIMD4<Float>(Float(theme.underlay.red) * u, Float(theme.underlay.green) * u, Float(theme.underlay.blue) * u, u))
        }

        func mixed(_ other: Layer, _ p: Float) -> Layer { Layer(under: under + (other.under - under) * p) }

        var uniforms: [Float] { [under.x, under.y, under.z, under.w] }
    }

    /// The gradient and overlay of `theme` into one side of the texture pairs, mixed over the other side.
    private func layers(of theme: ResolvedTheme, into output: Int, over from: Int, progress p: Float, scale: Int, targets: Targets, commandBuffer: any MTLCommandBuffer) {
        // 1. Gradient: up to three colors as OKLab, the ramp's corner values for the drawable's shape, the layer alpha.
        let colors = theme.gradient.isEmpty ? [RGBA(1, 1, 1)] : Array(theme.gradient.prefix(3))
        var gradient: [Float] = []
        for i in 0..<3 {
            let lab = OKLabColor(colors[min(i, colors.count - 1)])
            gradient += [Float(lab.l), Float(lab.a), Float(lab.b), 1]
        }
        gradient += themeRampCorners(aspect: Double(targets.width) / Double(max(targets.height, 1))).map(Float.init)
        gradient += [Float(colors.count), Float(min(max(theme.layerAlpha, 0), 1)), p, 0]
        pass(commandBuffer, into: targets.gradients[output], gradientPipeline, uniforms: gradient,
             textures: [targets.gradients[from]])

        // 2. Overlay: the tile at its pixel size, alpha = the tile's x the texture opacity.
        let tile = tiles.tile(theme.texture)
        let tilePixels = Float(TexturePixels.tileSize(theme.texture))
        let overlay: [Float] = [tilePixels, tilePixels, tile == nil ? 0 : Float(theme.textureOpacity * textureScale), p]
        pass(commandBuffer, into: targets.overlays[output], overlayPipeline, uniforms: overlay,
             textures: [tile ?? blank, targets.overlays[from]])
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

    struct GradientUniforms { float4 colors[3]; float4 corners; float count; float alpha; float progress; float pad; };

    float3 oklabToLinear(float3 c) {
        float l = c.x + 0.3963377774 * c.y + 0.2158037573 * c.z;
        float m = c.x - 0.1055613458 * c.y - 0.0638541728 * c.z;
        float s = c.x - 0.0894841775 * c.y - 1.2914855480 * c.z;
        l = l * l * l; m = m * m * m; s = s * s * s;
        return float3(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
                      -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
                      -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s);
    }

    float encodeSRGB(float x) {
        float a = fabs(x);
        return a > 0.0031308 ? sign(x) * (1.055 * pow(a, 1.0 / 2.4) - 0.055) : x * 12.92;
    }

    // Arc's layerColor: the first two colors along the 45 degree ramp (the corner values interpolated over the quad's two
    // triangles, full at three quarters), a third from clear at the top (full at three quarters of the height), mixed in
    // OKLab, each at the layer alpha, the third laid over the first in linear light. Premultiplied sRGB out.
    fragment float4 gradientFragment(Varyings in [[stage_in]], constant GradientUniforms& u [[buffer(0)]],
                                     texture2d<float> from [[texture(0)]]) {
        float2 p = in.uv;
        float t = p.x + p.y <= 1 ? u.corners.x + p.x * (u.corners.y - u.corners.x) + p.y * (u.corners.z - u.corners.x)
                                 : u.corners.w + (1 - p.x) * (u.corners.z - u.corners.w) + (1 - p.y) * (u.corners.y - u.corners.w);
        float3 base = u.count > 1.5 ? mix(u.colors[0].xyz, u.colors[1].xyz, clamp(t * 4.0 / 3.0, 0.0, 1.0)) : u.colors[0].xyz;
        float3 rgb = oklabToLinear(base);
        float a = u.alpha;
        if (u.count > 2.5) {
            float ao = clamp(p.y * 4.0 / 3.0, 0.0, 1.0) * u.alpha;
            float aOut = (1 - ao) * a + ao;
            rgb = (oklabToLinear(u.colors[2].xyz) * ao + rgb * a * (1 - ao)) / max(aOut, 1e-6);
            a = aOut;
        }
        float4 to = float4(float3(encodeSRGB(rgb.x), encodeSRGB(rgb.y), encodeSRGB(rgb.z)) * a, a);
        if (u.progress >= 1) { return to; }
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        return mix(from.sample(s, in.uv), to, u.progress);
    }

    struct OverlayUniforms { float2 tilePixels; float opacity; float progress; };

    // Arc's overlayFragment: the tile as premultiplied grey and alpha, alpha = the tile's x the texture opacity.
    fragment float4 overlayFragment(Varyings in [[stage_in]], constant OverlayUniforms& u [[buffer(0)]],
                                    texture2d<float> tile [[texture(0)]], texture2d<float> from [[texture(1)]]) {
        constexpr sampler s(filter::nearest, address::repeat);
        float2 t = tile.sample(s, in.position.xy / u.tilePixels).rg;
        float a = t.y * u.opacity;
        float4 to = float4(t.x * a, a, 0, 1);
        if (u.progress >= 1) { return to; }
        return float4(mix(from.read(uint2(in.position.xy)).rg, to.rg, u.progress), 0, 1);
    }

    struct RenderUniforms { float4 under; };

    // The gradient over the underlay, then Arc's renderFragment: the overlay multiplied over both
    // (o x g + o x (1 - g.a) + g x (1 - o.a)), premultiplied; the layer is not opaque, so the window's material shows through
    // what it leaves. A dither of half a step hides 8-bit banding in the blend.
    fragment float4 renderFragment(Varyings in [[stage_in]], constant RenderUniforms& u [[buffer(0)]],
                                   texture2d<float> gradient [[texture(0)]], texture2d<float> overlay [[texture(1)]]) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        float4 g = gradient.sample(s, in.uv);
        float3 layer = g.rgb + u.under.rgb * (1 - g.a);
        float coverage = g.a + u.under.a * (1 - g.a);
        float2 o = overlay.read(uint2(in.position.xy)).rg;
        float3 color = o.x * layer + o.x * (1 - coverage) + layer * (1 - o.y);
        float alpha = o.y + coverage * (1 - o.y);
        float dither = fract(sin(dot(in.position.xy, float2(12.9898, 78.233))) * 43758.5453) - 0.5;
        return float4(color + dither / 255.0 * alpha, alpha);
    }
    """
}

/// The procedural tiles as Metal textures, one per kind, generated in the background (TexturePixels is pure) and
/// uploaded on the main actor. Arc's asset files are not copied.
@MainActor
final class TileCache {
    let device: any MTLDevice
    var onReady: ((Texture) -> Void)?
    private var tiles: [Texture: any MTLTexture] = [:]
    private var pending: Set<Texture> = []

    init(device: any MTLDevice) { self.device = device }

    /// The tile, or nil while it is being generated (`onReady` fires when it is there).
    func tile(_ kind: Texture) -> (any MTLTexture)? {
        if let tile = tiles[kind] { return tile }
        if pending.insert(kind).inserted {
            let size = TexturePixels.tileSize(kind)
            Task.detached(priority: .userInitiated) { [weak self] in
                let pixels = TexturePixels.generate(kind, size: size, seed: 1)
                await self?.upload(kind, pixels, size: size)
            }
        }
        return nil
    }

    private func upload(_ kind: Texture, _ pixels: [UInt8], size: Int) {
        pending.remove(kind)
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rg8Unorm, width: size, height: size, mipmapped: false)
        descriptor.usage = .shaderRead
        guard let texture = device.makeTexture(descriptor: descriptor) else { return }
        texture.replace(region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0, withBytes: pixels, bytesPerRow: size * 2)
        tiles[kind] = texture
        onReady?(kind)
    }
}
