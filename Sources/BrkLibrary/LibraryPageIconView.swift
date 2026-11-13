import AppKit

/// A Library page's picture in the navigation column (Arc: `AnimatedPageSidebarItemView`, 28 x 28 pt): the
/// `LibraryPageArt` picture, which plays its short animation once each time its page becomes the open one (also
/// when the Library opens on it) and otherwise holds still. Every frame is worked out from the picture's keyframes
/// up front and handed to Core Animation, so the motion stays smooth while the page it opens is being built.
@MainActor
final class LibraryPageIconView: NSView {
    private struct Layers {
        let clip: CALayer
        let mask: CAShapeLayer?
        let holder: CALayer
        let shape: CAShapeLayer
    }

    /// One frame's worth of every changing value.
    private struct Frames {
        var transforms: [[CATransform3D]]
        var opacities: [[Float]]
        var paths: [[CGPath]?]
        var masks: [[CGPath]?]
    }

    let icon: LibraryPageArt.Icon
    private let board = CALayer()
    private var layers: [Layers] = []
    private var frames: Frames?
    var reduceMotion: () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    /// How many times it has started its animation (read by checks).
    private(set) var plays = 0

    init(icon: LibraryPageArt.Icon) {
        self.icon = icon
        super.init(frame: .zero)
        wantsLayer = true
        board.bounds = CGRect(x: 0, y: 0, width: 128, height: 128)
        layer?.addSublayer(board)
        for (index, part) in icon.parts.enumerated() {
            let clip = CALayer()
            clip.frame = board.bounds
            let mask: CAShapeLayer? = part.hiddenBy.isEmpty ? nil : CAShapeLayer()
            mask?.frame = board.bounds
            clip.mask = mask
            let holder = CALayer()
            holder.bounds = .zero
            holder.position = .zero
            let shape = CAShapeLayer()
            shape.bounds = .zero
            shape.position = .zero
            if let width = part.stroke {
                shape.fillColor = nil
                shape.lineWidth = width
                shape.lineCap = .round
                shape.lineJoin = .round
            } else {
                shape.fillRule = .evenOdd
            }
            holder.addSublayer(shape)
            clip.addSublayer(holder)
            board.addSublayer(clip)
            layers.append(Layers(clip: clip, mask: mask, holder: holder, shape: shape))
            _ = index
        }
        pose(at: icon.last)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let side = min(bounds.width, bounds.height)
        board.position = CGPoint(x: bounds.midX, y: bounds.midY)
        board.transform = CATransform3DMakeScale(side / 128, side / 128, 1)
        CATransaction.commit()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        for l in layers { l.shape.contentsScale = scale; l.mask?.contentsScale = scale }
    }

    /// The outline's colour, and the inside's on the open page (nil leaves the inside out).
    func render(outline: NSColor, inside: NSColor?) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (part, l) in zip(icon.parts, layers) {
            let color = part.ink == .outline ? outline.cgColor : inside?.cgColor
            if part.stroke != nil { l.shape.strokeColor = color } else { l.shape.fillColor = color }
            l.shape.isHidden = color == nil
        }
        CATransaction.commit()
    }

    /// Plays the picture's animation once, from frame 1 to its last.
    func play() {
        guard !reduceMotion() else { return }
        plays += 1
        let f = frames ?? makeFrames()
        frames = f
        let duration = (icon.last - 1) / 60
        let count = f.transforms.first?.count ?? 0
        let times = (0..<count).map { NSNumber(value: Double($0) / Double(max(1, count - 1))) }
        func keyframes(_ keyPath: String, _ values: [Any], discrete: Bool = false) -> CAKeyframeAnimation {
            let animation = CAKeyframeAnimation(keyPath: keyPath)
            animation.values = values
            animation.keyTimes = times
            animation.duration = duration
            animation.calculationMode = discrete ? .discrete : .linear
            return animation
        }
        for (i, l) in layers.enumerated() {
            l.holder.add(keyframes("transform", f.transforms[i].map { NSValue(caTransform3D: $0) }), forKey: "play-transform")
            if Set(f.opacities[i]).count > 1 { l.holder.add(keyframes("opacity", f.opacities[i]), forKey: "play-opacity") }
            if let paths = f.paths[i] { l.shape.add(keyframes("path", paths), forKey: "play-path") }
            if let masks = f.masks[i], let mask = l.mask { mask.add(keyframes("path", masks, discrete: true), forKey: "play-mask") }
        }
        pose(at: icon.last)
    }

    /// Sets every layer to the picture at `frame`, without animation.
    private func pose(at frame: Double) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (i, part) in icon.parts.enumerated() {
            let l = layers[i]
            l.holder.transform = CATransform3DMakeAffineTransform(icon.transform(part.place, at: frame))
            l.holder.opacity = Float(icon.opacity(part.place, at: frame))
            l.shape.path = part.path(frame)
            l.mask?.path = icon.visibleArea(i, at: frame)
        }
        CATransaction.commit()
    }

    private func makeFrames() -> Frames {
        let numbers = Array(stride(from: 1.0, through: icon.last, by: 1))
        var f = Frames(transforms: [], opacities: [], paths: [], masks: [])
        for (i, part) in icon.parts.enumerated() {
            f.transforms.append(numbers.map { CATransform3DMakeAffineTransform(icon.transform(part.place, at: $0)) })
            f.opacities.append(numbers.map { Float(icon.opacity(part.place, at: $0)) })
            let paths = numbers.map { part.path($0) }
            f.paths.append(paths.dropFirst().allSatisfy { $0 == paths[0] } ? nil : paths)
            f.masks.append(part.hiddenBy.isEmpty ? nil : numbers.compactMap { icon.visibleArea(i, at: $0) })
        }
        return f
    }
}
