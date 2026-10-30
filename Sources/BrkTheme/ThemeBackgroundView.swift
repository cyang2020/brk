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
/// Usage (BrkUI/WindowRootView): `background.show(snapshot.theme, animated: themeChanged)` on every render. Equal
/// themes are a no-op, so calling it on every snapshot is fine.
@MainActor
public final class ThemeBackgroundView: NSView {
    private let renderer: ThemeRenderer?
    private var current: ResolvedTheme?
    /// First-pass drawing until the Metal renderer is written: a gradient layer of the stops plus the wash, cross-
    /// faded by swapping layers. Stays as the fallback for a Mac with no Metal device.
    private let gradient = CAGradientLayer()
    private let wash = CALayer()

    public override init(frame: NSRect) {
        renderer = ThemeRenderer(device: MTLCreateSystemDefaultDevice())
        super.init(frame: frame)
        wantsLayer = true
        layer?.addSublayer(gradient)
        layer?.addSublayer(wash)
        gradient.startPoint = CGPoint(x: 0, y: 1)
        gradient.endPoint = CGPoint(x: 1, y: 0)
        // TODO(W5): layer = renderer?.layer (CAMetalLayer, pixelFormat .bgra8Unorm, framebufferOnly, isOpaque) with
        // the three-pass shader and the procedural texture; the gradient layer below becomes the no-Metal fallback.
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("not used") }

    public override var isFlipped: Bool { true }

    /// Shows `theme`. `animated` crossfades gradient and texture over Metrics.motion.themeCrossfade (Arc's background
    /// configuration is `single` or `transitioning`); otherwise it switches at once (launch, restore).
    public func show(_ theme: ResolvedTheme, animated: Bool) {
        guard theme != current else { return }
        current = theme
        // TODO(W5): renderer.transition(from: current, to: theme, duration: animated ? crossfade : 0); drive frames
        // with a CADisplayLink (NSView.displayLink(target:selector:), macOS 14) only while transitioning; otherwise
        // redraw once on change and on resize/backing-scale change. Until then, Core Animation crossfades the layers.
        CATransaction.begin()
        CATransaction.setAnimationDuration(animated ? Metrics.motion.themeCrossfade.value : 0)
        gradient.colors = theme.gradient.map { NSColor(srgbRed: $0.red, green: $0.green, blue: $0.blue, alpha: $0.alpha).cgColor }
        wash.backgroundColor = NSColor(srgbRed: theme.wash.red, green: theme.wash.green, blue: theme.wash.blue, alpha: theme.wash.alpha).cgColor
        CATransaction.commit()
    }

    public override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        wash.frame = bounds
        CATransaction.commit()
        // TODO(W5): drawableSize = bounds.size x backingScaleFactor; redraw.
    }
}
