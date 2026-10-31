import AppKit
import BrkBase
import BrkDomain
import Metal
import QuartzCore

/// The window background: a blended gradient with a tiled texture over it, drawn by us with Metal, crossfading on
/// space switch. Sits at the bottom of every window; the sidebar's translucent tokens and the content cards draw
/// above it. Arc does the same with its WindowThemeUI Metal renderer (gradientFragment, overlayFragment,
/// renderFragment; anatomy, "Space theme system").
///
/// Usage (BrkContent/WindowRootView): `background.show(snapshot.theme, animated: themeChanged)` on every render.
/// Equal themes are a no-op, so calling it on every snapshot is fine.
///
/// Frames are drawn only when something changes: once per `show` without animation, on resize (in step with the
/// window, the layer presents with the Core Animation transaction) and on a backing-scale change; a display link
/// runs only while a crossfade is running. With no Metal device the view draws nothing and the window's own
/// background color (`ResolvedTheme.windowColor`) shows.
@MainActor
public final class ThemeBackgroundView: NSView {
    private let renderer: ThemeRenderer?
    private var link: CADisplayLink?
    private var fallbackTheme: ResolvedTheme?

    public override init(frame: NSRect) {
        renderer = ThemeRenderer(device: MTLCreateSystemDefaultDevice())
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
        autoresizingMask = [.width, .height]
        renderer?.prewarm(scale: Int((NSScreen.main?.backingScaleFactor ?? 2).rounded()))
        renderer?.onTileReady = { [weak self] kind in self?.tileArrived(kind) }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("not used") }

    public override var isFlipped: Bool { true }

    public override func makeBackingLayer() -> CALayer {
        guard let renderer else { return super.makeBackingLayer() }
        let layer = CAMetalLayer()
        layer.device = renderer.device
        layer.pixelFormat = ThemeRenderer.drawableFormat
        layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        layer.framebufferOnly = true
        layer.isOpaque = true
        layer.presentsWithTransaction = true
        return layer
    }

    /// Shows `theme`. `animated` crossfades gradient and texture over Metrics.motion.themeCrossfade (Arc's background
    /// configuration is `single` or `transitioning`); otherwise it switches at once (launch, restore). A new theme
    /// during a crossfade fades on from what is on screen.
    public func show(_ theme: ResolvedTheme, animated: Bool) {
        guard let renderer else {
            guard fallbackTheme != theme else { return }
            fallbackTheme = theme
            let image = Self.fallbackImage(theme)
            CATransaction.begin()
            CATransaction.setAnimationDuration(animated ? Metrics.motion.themeCrossfade.value : 0)
            layer?.contents = image
            CATransaction.commit()
            return
        }
        guard theme != renderer.target else { return }
        let duration = animated ? Metrics.motion.themeCrossfade.value : 0
        renderer.transition(to: theme, duration: duration, at: CACurrentMediaTime())
        if duration > 0 { animate() } else { needsDisplay = true }
    }

    /// The no-Metal path preserves the positioned gradient and wash. Procedural texture remains a GPU approximation.
    static func fallbackImage(_ theme: ResolvedTheme) -> CGImage? {
        let side = 64
        var bytes: [UInt8] = []
        bytes.reserveCapacity(side * side * 4)
        for y in 0..<side {
            for x in 0..<side {
                let color = themeSample(theme, at: ThemePoint(x: (Double(x) + 0.5) / Double(side), y: (Double(y) + 0.5) / Double(side)))
                bytes += [UInt8((color.red * 255).rounded()), UInt8((color.green * 255).rounded()), UInt8((color.blue * 255).rounded()), 255]
            }
        }
        guard let provider = CGDataProvider(data: Data(bytes) as CFData) else { return nil }
        return CGImage(width: side, height: side, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: side * 4,
                       space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                       provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent)
    }

    public override var wantsUpdateLayer: Bool { true }

    public override func updateLayer() {
        if draw(at: CACurrentMediaTime()) { animate() }
    }

    public override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed { needsDisplay = true }
    }

    public override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        if let scale = window?.backingScaleFactor { renderer?.prewarm(scale: Int(scale.rounded())) }
        needsDisplay = true
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsDisplay = true
    }

    /// The shown theme's tile finished generating after the theme was first drawn without it: fade it in.
    private func tileArrived(_ kind: Texture) {
        guard let renderer, let theme = renderer.target, theme.texture == kind else { return }
        guard link == nil else { return needsDisplay = true }
        renderer.transition(to: theme, duration: Metrics.motion.themeCrossfade.value, at: CACurrentMediaTime())
        animate()
    }

    private func animate() {
        guard link == nil, window != nil else { return }
        let link = displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    @objc private func step(_ link: CADisplayLink) {
        if !draw(at: link.targetTimestamp) {
            link.invalidate()
            self.link = nil
        }
    }

    /// Draws one frame at the view's pixel size; true while a crossfade is still running.
    private func draw(at time: CFTimeInterval) -> Bool {
        guard let renderer, let layer = layer as? CAMetalLayer, let window, bounds.width > 0, bounds.height > 0 else { return false }
        let scale = window.backingScaleFactor
        let size = CGSize(width: (bounds.width * scale).rounded(), height: (bounds.height * scale).rounded())
        if layer.contentsScale != scale { layer.contentsScale = scale }
        if layer.drawableSize != size { layer.drawableSize = size }
        return renderer.draw(in: layer, scale: Int(scale.rounded()), at: time)
    }
}
