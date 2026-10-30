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

    public override init(frame: NSRect) {
        renderer = ThemeRenderer(device: MTLCreateSystemDefaultDevice())
        super.init(frame: frame)
        wantsLayer = true
        // TODO(W5): layer = renderer?.layer (CAMetalLayer, pixelFormat .bgra8Unorm, framebufferOnly, isOpaque);
        // with no Metal device fall back to a CAGradientLayer of the stops (no texture).
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("not used") }

    public override var isFlipped: Bool { true }

    /// Shows `theme`. `animated` crossfades gradient and texture over Metrics.motion.themeCrossfade (Arc's background
    /// configuration is `single` or `transitioning`); otherwise it switches at once (launch, restore).
    public func show(_ theme: ResolvedTheme, animated: Bool) {
        guard theme != current else { return }
        // TODO(W5): renderer.transition(from: current, to: theme, duration: animated ? crossfade : 0); drive frames
        // with a CADisplayLink (NSView.displayLink(target:selector:), macOS 14) only while transitioning; otherwise
        // redraw once on change and on resize/backing-scale change.
        current = theme
        fatalError("not implemented")
    }

    public override func layout() {
        super.layout()
        // TODO(W5): drawableSize = bounds.size x backingScaleFactor; redraw.
    }
}
