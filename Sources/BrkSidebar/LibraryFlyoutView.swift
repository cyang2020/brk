import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

// Owner: W3. The Library button's flyout and badge (Arc: `HomeBadging.HomeButton`, `HomeButtonHoverRegionTracker`,
// `HomeBadgingCell`; verify/library-hover-preview/README.md has every number's probe).
//
// The pointer resting `openDwell` on the dock's Library button opens a list of the profile's newest Library items over
// the bottom of the sidebar, newest at the bottom next to the button. While it is open the pointer may travel anywhere
// in the sidebar-wide area `regionHeight` tall above the button's bottom; leaving it closes the list at once, and resting
// `dockCollapse` on the strip right of the button (the Space dots) closes it too. The rows above the list fade out
// behind it. A row's click previews the item, its right click is Arc's menu, and it can be dragged out as a file.
// Whether the list is open is view state; the app hears only that it opened (`LibraryFlyoutCommand.expanded`).

/// What a row asks the sidebar to do beyond a command: a preview, or the file's own actions.
@MainActor
protocol LibraryFlyoutHost: AnyObject {
    func flyoutOpen(_ item: LibraryFlyoutItem)
}

@MainActor
final class LibraryFlyoutView: NSView {
    private let dispatch: Dispatch
    weak var host: LibraryFlyoutHost?
    /// The views whose rows fade behind the open list (the tab list's clip, the mini players).
    var faded: [NSView] = []
    private var rows: [LibraryFlyoutRowView] = []
    private(set) var snapshot: LibraryFlyoutSnapshot?
    private var palette: Palette?
    /// The Library button, the strip right of it and the open list's area, in this view's superview (the sidebar).
    private var button: CGRect = .zero
    private var sidebarWidth = 0.0
    private(set) var isExpanded = false
    private var enabled = true
    private var dwell: Timer?
    private var dockTimer: Timer?
    private var tracking: NSTrackingArea?
    private weak var trackedIn: NSView?
    private let tracker = Tracker()
    /// The snapshot's time and the uptime it arrived at: the subtitles' "2 minutes ago" moves on between snapshots.
    private var clock: (now: Instant, uptime: TimeInterval) = (Instant(milliseconds: 0), 0)
    private var ticker: Timer?
    /// Bytes and uptime the first time a running download was seen, for its remaining time.
    private var rates: [DownloadID: (received: Int64, uptime: TimeInterval)] = [:]
    /// The badge over the button's corner; lives in the dock (above the button).
    let badge = LibraryBadgeView()

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        wantsLayer = true
        alphaValue = 0
        isHidden = true
        identify(.tabTool("library-flyout"))
        tracker.owner = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }
    /// Only the rows take the pointer: the button and the Space dots under the open area stay clickable.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isExpanded, let hit = super.hitTest(point), hit !== self else { return nil }
        return hit
    }

    // MARK: Render

    /// `button` is the Library button in the sidebar's coordinates; `enabled` is false while the Library is open or the
    /// dock is replaced (Create a Space), when the button does not offer the list.
    func render(_ snapshot: LibraryFlyoutSnapshot?, button: CGRect, sidebarWidth: Double, palette: Palette, now: Instant, enabled: Bool, in sidebar: NSView) {
        self.button = button
        self.sidebarWidth = sidebarWidth
        self.palette = palette
        self.enabled = enabled && snapshot != nil
        clock = (now, ProcessInfo.processInfo.systemUptime)
        let changed = snapshot != self.snapshot
        self.snapshot = snapshot
        installTracking(in: sidebar)
        let region = regionRect
        frame = region
        badge.render(snapshot?.badge, palette: palette, hidden: isExpanded)
        if !self.enabled || (snapshot?.items.isEmpty ?? true) { collapse(animated: isExpanded); if !self.enabled { cancelTimers() } }
        if changed || rows.count != (snapshot?.items.count ?? 0) { rebuildRows() } else { layoutRows() }
        if isExpanded { applyFade(animated: false) }
    }

    /// The open list's hover area: the sidebar's width, `regionHeight` tall up from the button's bottom.
    private var regionRect: CGRect {
        let height = Metrics.libraryFlyout.regionHeight.value
        return CGRect(x: 0, y: button.maxY - height, width: sidebarWidth, height: height)
    }

    /// The strip right of the button, as tall as the button (Arc: `HomeDockRegion`).
    private var dockStrip: CGRect {
        CGRect(x: button.maxX, y: button.minY, width: max(0, sidebarWidth - button.maxX), height: button.height)
    }

    private func rebuildRows() {
        let items = snapshot?.items ?? []
        while rows.count > items.count { rows.removeLast().removeFromSuperview() }
        while rows.count < items.count {
            let row = LibraryFlyoutRowView(dispatch: dispatch)
            row.onOpen = { [weak self] item in self?.host?.flyoutOpen(item) }
            rows.append(row)
            addSubview(row)
        }
        let running = Set(items.compactMap { item -> DownloadID? in
            if case .download(let row) = item.content, row.state == .inProgress { return row.id } else { return nil }
        })
        rates = rates.filter { running.contains($0.key) }
        for item in items {
            if case .download(let row) = item.content, row.state == .inProgress, rates[row.id] == nil {
                rates[row.id] = (row.received, clock.uptime)
            }
        }
        layoutRows()
    }

    private func layoutRows() {
        guard let palette, let snapshot else { return }
        let m = Metrics.libraryFlyout
        let count = snapshot.items.count
        let buttonTop = button.minY - frame.minY
        for (index, row) in rows.enumerated() where index < count {
            let fromBottom = Double(count - 1 - index)
            let bottom = buttonTop - m.rowBottomGap.value - fromBottom * m.rowPitch.value
            row.frame = CGRect(x: m.rowLeading.value, y: bottom - m.rowHeight.value, width: max(0, sidebarWidth - m.rowWidthInset.value), height: m.rowHeight.value)
            row.identify(.tabTool("library-flyout-row-\(index)"))
            row.render(snapshot.items[index], subtitle: subtitle(for: snapshot.items[index]), palette: palette)
        }
    }

    // MARK: Subtitles

    private var now: Instant {
        clock.now.advanced(by: .milliseconds(Int64((ProcessInfo.processInfo.systemUptime - clock.uptime) * 1000)))
    }

    /// "2 minutes ago" (Arc's relative date); a running download's "2.8/8.4 MB · 29s".
    private func subtitle(for item: LibraryFlyoutItem) -> String {
        if case .download(let row) = item.content, row.state.isActive {
            return LibraryFlyoutCopy.progress(received: row.received, total: row.total, remaining: remaining(row))
        }
        return LibraryFlyoutCopy.relative(item.date, now: now)
    }

    private func remaining(_ row: DownloadRow) -> TimeInterval? {
        guard let total = row.total, let first = rates[row.id] else { return nil }
        let elapsed = ProcessInfo.processInfo.systemUptime - first.uptime
        let rate = Double(row.received - first.received) / elapsed
        guard elapsed >= 1, rate > 0 else { return nil }
        return Double(total - row.received) / rate
    }

    // MARK: Hover (Arc: `HomeButtonHoverRegionTracker`)

    private func installTracking(in sidebar: NSView) {
        let rect = regionRect.union(button).union(dockStrip)
        if let tracking, trackedIn === sidebar, tracking.rect == rect { return }
        if let tracking { trackedIn?.removeTrackingArea(tracking) }
        // `.activeInActiveApp`: with another app in front Arc lights the button but never opens the list.
        let area = NSTrackingArea(rect: rect, options: [.mouseEnteredAndExited, .mouseMoved, .activeInActiveApp, .enabledDuringMouseDrag],
                                  owner: tracker, userInfo: nil)
        sidebar.addTrackingArea(area)
        tracking = area
        trackedIn = sidebar
    }

    /// The pointer moved to `point` (the sidebar's coordinates), or left the tracked area (nil).
    fileprivate func pointer(at point: CGPoint?) {
        guard enabled, let point else {
            cancelTimers()
            collapse(animated: true)
            return
        }
        if isExpanded {
            if !regionRect.contains(point) { collapse(animated: true); return }
            if dockStrip.contains(point) {
                if dockTimer == nil {
                    dockTimer = Timer.scheduledTimer(withTimeInterval: Metrics.libraryFlyout.dockCollapse.value, repeats: false) { [weak self] _ in
                        MainActor.assumeIsolated { self?.dockTimer = nil; self?.collapse(animated: true) }
                    }
                }
            } else {
                dockTimer?.invalidate(); dockTimer = nil
            }
            return
        }
        guard button.contains(point) else { dwell?.invalidate(); dwell = nil; return }
        guard dwell == nil else { return }
        dispatch(.library(.flyout(.hovered)))
        dwell = Timer.scheduledTimer(withTimeInterval: Metrics.libraryFlyout.openDwell.value, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.dwellEnded() }
        }
    }

    private func dwellEnded() {
        dwell = nil
        guard enabled, NSApp.isActive, let sidebar = trackedIn, let window = sidebar.window,
              button.contains(sidebar.convert(window.mouseLocationOutsideOfEventStream, from: nil)),
              !(snapshot?.items.isEmpty ?? true) else { return }
        expand()
    }

    private func cancelTimers() {
        dwell?.invalidate(); dwell = nil
        dockTimer?.invalidate(); dockTimer = nil
    }

    /// Closes the list now (a click on the Library button, the Library opening).
    func dismiss() {
        cancelTimers()
        collapse(animated: false)
    }

    private func expand() {
        guard !isExpanded else { return }
        isExpanded = true
        isHidden = false
        layoutRows()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Metrics.libraryFlyout.fadeIn.value
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
        }
        applyFade(animated: true)
        badge.render(snapshot?.badge, palette: palette, hidden: true)
        startTicker()
        dispatch(.library(.flyout(.expanded)))
    }

    private func collapse(animated: Bool) {
        dockTimer?.invalidate(); dockTimer = nil
        guard isExpanded else { return }
        isExpanded = false
        ticker?.invalidate(); ticker = nil
        for row in rows { row.pointerLeft() }
        let duration = animated ? Metrics.libraryFlyout.fadeOut.value : 0
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, !self.isExpanded else { return }
                self.isHidden = true
            }
        })
        removeFade(animated: animated)
        badge.render(snapshot?.badge, palette: palette, hidden: false)
    }

    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.layoutRows() }
        }
    }

    // MARK: The rows above fade (the measured backdrop)

    private func fadeColors(height: Double, in view: NSView) -> (colors: [CGColor], locations: [NSNumber]) {
        let m = Metrics.libraryFlyout
        let count = Double(snapshot?.items.count ?? 0)
        // The list's top in the sidebar: n rows of `rowPitch` and the button over the button's bottom.
        let listTop = button.maxY - count * m.rowPitch.value - m.buttonRegion.value
        let stops = stride(from: 0, to: m.backdropFade.value.count, by: 2).map { (m.backdropFade.value[$0], m.backdropFade.value[$0 + 1]) }
        var colors: [CGColor] = [NSColor.black.cgColor]
        var locations: [NSNumber] = [0]
        let origin = view.convert(CGPoint.zero, to: superview).y
        for (above, opacity) in stops {
            let y = (listTop - above) - origin
            guard height > 0 else { break }
            locations.append(NSNumber(value: min(1, max(0, y / height))))
            colors.append(NSColor.black.withAlphaComponent(1 - opacity).cgColor)
        }
        locations.append(1); colors.append(NSColor.black.withAlphaComponent(0).cgColor)
        return (colors, locations)
    }

    private func applyFade(animated: Bool) {
        for view in faded {
            guard let layer = view.layer else { continue }
            let mask = (layer.mask as? CAGradientLayer) ?? CAGradientLayer()
            let fade = fadeColors(height: view.bounds.height, in: view)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            mask.frame = view.bounds
            // The view is flipped: gradient locations run from its top.
            mask.startPoint = CGPoint(x: 0.5, y: view.isFlipped ? 0 : 1)
            mask.endPoint = CGPoint(x: 0.5, y: view.isFlipped ? 1 : 0)
            mask.locations = fade.locations
            if layer.mask !== mask {
                mask.colors = fade.colors.map { _ in NSColor.black.cgColor }
                layer.mask = mask
            }
            CATransaction.commit()
            if animated {
                let animation = CABasicAnimation(keyPath: "colors")
                animation.fromValue = mask.presentation()?.colors ?? mask.colors
                animation.toValue = fade.colors
                animation.duration = Metrics.libraryFlyout.fadeIn.value
                animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
                mask.add(animation, forKey: "fade")
            }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            mask.colors = fade.colors
            CATransaction.commit()
        }
    }

    private func removeFade(animated: Bool) {
        for view in faded {
            guard let mask = view.layer?.mask as? CAGradientLayer else { continue }
            guard animated else { view.layer?.mask = nil; continue }
            let opaque = (mask.colors ?? []).map { _ in NSColor.black.cgColor }
            CATransaction.begin()
            CATransaction.setCompletionBlock { [weak self, weak view] in
                MainActor.assumeIsolated {
                    guard let self, let view, !self.isExpanded else { return }
                    view.layer?.mask = nil
                }
            }
            let animation = CABasicAnimation(keyPath: "colors")
            animation.fromValue = mask.presentation()?.colors ?? mask.colors
            animation.toValue = opaque
            animation.duration = Metrics.libraryFlyout.fadeOut.value
            mask.add(animation, forKey: "unfade")
            CATransaction.setDisableActions(true)
            mask.colors = opaque
            CATransaction.commit()
        }
    }

    // MARK: Tracking area owner

    /// The tracking area's owner: an NSResponder of its own, so the sidebar's own hover tracking stays as it is.
    @MainActor
    private final class Tracker: NSResponder {
        weak var owner: LibraryFlyoutView?
        override func mouseEntered(with event: NSEvent) { moved(event) }
        override func mouseMoved(with event: NSEvent) { moved(event) }
        override func mouseDragged(with event: NSEvent) { moved(event) }
        override func mouseExited(with event: NSEvent) { owner?.pointer(at: nil) }
        private func moved(_ event: NSEvent) {
            guard let owner, let sidebar = owner.trackedIn else { return }
            owner.pointer(at: sidebar.convert(event.locationInWindow, from: nil))
        }
    }
}

/// Arc's flyout copy (Swift small strings in HomeBadging, bin:0x10265e000 to 0x1026b6000).
enum LibraryFlyoutCopy {
    static let copyFile = "Copy File"
    static let copyImage = "Copy Image"
    static let sendViaMessages = "Send via iMessage"
    static let airDrop = "AirDrop"
    static func openIn(_ app: String) -> String { "Open in " + app }
    static let showInFinder = "Show in Finder"
    /// Arc's "Hide from Arc", with Brk's name.
    static let hide = "Hide from Brk"
    static let moveToTrash = "Move to Trash"
    static let cancelDownload = "Cancel Download"
    static let delete = "Delete"

    /// "51 seconds ago", "2 minutes ago", "1 day ago" (Arc's rows read exactly these).
    static func relative(_ date: Instant, now: Instant) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        formatter.dateTimeStyle = .numeric
        formatter.locale = Locale(identifier: "en_US")
        let seconds = max(1, Double(now.since(date).components.seconds))
        return formatter.localizedString(fromTimeInterval: -seconds)
    }

    /// "2.8/8.4 MB · 29s" (Arc's running row); "2.8 MB" without a size.
    static func progress(received: Int64, total: Int64?, remaining: TimeInterval?) -> String {
        guard let total, total > 0 else { return ByteCountFormatter.string(fromByteCount: received, countStyle: .file) }
        let whole = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
        let parts = whole.split(separator: " ")
        let unit = parts.count == 2 ? String(parts[1]) : ""
        let scale: Double = switch unit { case "KB": 1e3; case "MB": 1e6; case "GB": 1e9; case "TB": 1e12; default: 1 }
        let done = String(format: scale == 1 ? "%.0f" : "%.1f", Double(received) / scale)
        var text = "\(done)/\(whole)"
        if let remaining, remaining.isFinite {
            let formatter = DateComponentsFormatter()
            formatter.unitsStyle = .abbreviated
            formatter.allowedUnits = remaining >= 3600 ? [.hour, .minute] : remaining >= 60 ? [.minute, .second] : [.second]
            formatter.maximumUnitCount = 2
            if let left = formatter.string(from: max(1, remaining.rounded())) { text += " · " + left }
        }
        return text
    }
}
