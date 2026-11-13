import AppKit
import BrkBase
import BrkDomain
import Metal
import QuartzCore

/// The window background: the system material, and over it the theme (a blended gradient with a tiled texture) drawn
/// by us with Metal, part see-through, crossfading on space switch. Sits at the bottom of every window; the sidebar's
/// translucent tokens and the content cards draw above it. Arc does the same: an NSVisualEffectView
/// (`WindowBackgroundTranslucencyViewAppKit`) under its WindowThemeUI Metal layer, which is not opaque
/// (gradientFragment, overlayFragment, renderFragment; anatomy, "Space theme system";
/// docs/checks/2026-11-13-window-translucency.md).
///
/// The material is Arc's: `.light` behind the window, emphasized, following the window's active state. So while the
/// window is key or main the blurred windows and desktop behind it show through the theme, and while it is not the
/// material turns flat and the texture fades to Metrics.theme.inactiveTextureFactor (Arc's overlay alpha x 0.25). The
/// system takes care of full screen (the desktop picture behind) and of Reduce Transparency (an opaque material).
///
/// Usage (BrkContent/WindowRootView): `background.show(snapshot.theme, animated: themeChanged)` on every render.
/// Equal themes are a no-op, so calling it on every snapshot is fine.
///
/// Frames are drawn only when something changes: once per `show` without animation, on resize (in step with the
/// window, the layer presents with the Core Animation transaction), on a backing-scale change and when the window
/// turns active or inactive; a display link runs only while a crossfade is running. With no Metal device the canvas
/// shows a small image of the theme and the window's own background color (`ResolvedTheme.windowColor`) shows first.
@MainActor
public final class ThemeBackgroundView: NSView {
    private let material = NSVisualEffectView()
    private let canvas = ThemeCanvasView(frame: .zero)
    /// Observers of the window's key and main state (Arc's `WindowActiveStateTracker`). Block observers stay registered
    /// until removed: leaving the window and `deinit` remove them.
    nonisolated(unsafe) private var activeObservers: [NSObjectProtocol] = []

    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        autoresizingMask = [.width, .height]
        // `.light` (raw value 1) is deprecated in the SDK but is the material Arc's window uses; the semantic materials
        // read differently over the same backdrop.
        material.material = NSVisualEffectView.Material(rawValue: 1) ?? .underWindowBackground
        material.blendingMode = .behindWindow
        material.state = .followsWindowActiveState
        material.isEmphasized = true
        for view in [material, canvas] as [NSView] {
            view.frame = bounds
            view.autoresizingMask = [.width, .height]
            addSubview(view)
        }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("not used") }

    deinit { activeObservers.forEach(NotificationCenter.default.removeObserver) }

    public override var isFlipped: Bool { true }

    /// The background takes the point as one view, as before it had parts.
    public override func hitTest(_ point: NSPoint) -> NSView? { super.hitTest(point) == nil ? nil : self }

    /// Shows `theme`. `animated` crossfades gradient and texture over Metrics.motion.themeCrossfade (Arc's background
    /// configuration is `single` or `transitioning`); otherwise it switches at once (launch, restore). A new theme
    /// during a crossfade fades on from what is on screen.
    public func show(_ theme: ResolvedTheme, animated: Bool) {
        material.isHidden = theme.material == .opaque
        canvas.show(theme, animated: animated)
    }

    /// Mixes two themes at `progress` (0: `base`, 1: `theme`) while a Space's page follows the fingers or settles (Arc's
    /// colors follow the page position, linearly). `show` afterwards ends it. Without Metal it shows the nearer one.
    public func scrub(from base: ResolvedTheme, to theme: ResolvedTheme, progress: Double) {
        material.isHidden = base.material == .opaque && theme.material == .opaque
        canvas.scrub(from: base, to: theme, progress: progress)
    }

    /// The no-Metal path preserves the positioned gradient and wash. Procedural texture remains a GPU approximation.
    static func fallbackImage(_ theme: ResolvedTheme) -> CGImage? { ThemeCanvasView.fallbackImage(theme) }

    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        activeObservers.forEach(NotificationCenter.default.removeObserver)
        activeObservers = []
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard let window else { return }
        let names: [Notification.Name] = [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                                          NSWindow.didBecomeMainNotification, NSWindow.didResignMainNotification]
        activeObservers = names.map { name in
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.activeChanged() }
            }
        }
        activeChanged()
    }

    /// Arc counts the window active when it, or a window it is a child of, is key or main.
    private func activeChanged() {
        var current = window
        var active = false
        while let w = current, !active {
            active = w.isKeyWindow || w.isMainWindow
            current = w.parent
        }
        canvas.setActive(active)
    }
}

/// The theme drawn with Metal into a layer that is not opaque, premultiplied (ThemeRenderer).
@MainActor
final class ThemeCanvasView: NSView {
    private let renderer: ThemeRenderer?
    private var link: CADisplayLink?
    private var fallbackTheme: ResolvedTheme?

    override init(frame: NSRect) {
        renderer = ThemeRenderer(device: MTLCreateSystemDefaultDevice())
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
        renderer?.prewarm()
        renderer?.onTileReady = { [weak self] kind in self?.tileArrived(kind) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func makeBackingLayer() -> CALayer {
        guard let renderer else { return super.makeBackingLayer() }
        let layer = CAMetalLayer()
        layer.device = renderer.device
        layer.pixelFormat = ThemeRenderer.drawableFormat
        layer.colorspace = CGColorSpace(name: CGColorSpace.sRGB)
        layer.framebufferOnly = true
        layer.isOpaque = false
        layer.presentsWithTransaction = true
        return layer
    }

    func show(_ theme: ResolvedTheme, animated: Bool) {
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
        let scrubbed = renderer.isScrubbing
        guard theme != renderer.target || scrubbed else { return }
        let duration = animated ? Metrics.motion.themeCrossfade.value : 0
        renderer.transition(to: theme, duration: duration, at: CACurrentMediaTime())
        if duration > 0 { animate() } else if scrubbed { _ = draw(at: CACurrentMediaTime()) } else { needsDisplay = true }
    }

    func scrub(from base: ResolvedTheme, to theme: ResolvedTheme, progress: Double) {
        guard let renderer else { return show(progress < 0.5 ? base : theme, animated: false) }
        renderer.scrub(from: base, to: theme, progress: progress)
        _ = draw(at: CACurrentMediaTime())
    }

    /// The texture at full strength while the window is active, at Metrics.theme.inactiveTextureFactor while not.
    func setActive(_ active: Bool) {
        let scale = active ? 1 : Metrics.theme.inactiveTextureFactor.value
        guard let renderer, renderer.textureScale != scale else { return }
        renderer.textureScale = scale
        if link == nil { needsDisplay = true }
    }

    /// The theme as a small image, for a Mac without Metal: the stand-in wash keeps it opaque.
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

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        if draw(at: CACurrentMediaTime()) { animate() }
    }

    override func setFrameSize(_ newSize: NSSize) {
        let changed = newSize != frame.size
        super.setFrameSize(newSize)
        if changed { needsDisplay = true }
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

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
