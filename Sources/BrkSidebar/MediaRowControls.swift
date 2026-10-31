import AppKit
import BrkBase
import BrkDomain
import BrkUIKit

/// A row controls one concrete player. The context menu exposes each player's own state.
@MainActor
final class MediaRowControls: HoverView {
    private let dispatch: Dispatch
    private let button = NSButton()
    private var row: TabRow?
    private var primary: MediaPlayer? {
        row?.mediaPlayers.first(where: { !$0.paused && !$0.ended }) ?? row?.mediaPlayers.first
    }
    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        button.isBordered = false
        button.target = self; button.action = #selector(toggle)
        addSubview(button)
        isHidden = true
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    func render(_ row: TabRow) {
        self.row = row
        isHidden = row.mediaPlayers.isEmpty
        guard let player = primary else { return }
        let paused = player.paused || player.ended
        button.image = NSImage(systemSymbolName: paused ? "play.fill" : "pause.fill", accessibilityDescription: paused ? "Play" : "Pause")
        button.toolTip = row.mediaError ?? (paused ? "Play Media" : "Pause Media")
        button.identify(.tabTool("media-" + row.id.rawValue))
        button.setAccessibilityLabel(paused ? "Play Media" : "Pause Media")
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, frame.contains(point) else { return nil }
        return self
    }
    override func mouseDown(with event: NSEvent) { isPressed = true }
    override func mouseUp(with event: NSEvent) {
        isPressed = false
        if bounds.contains(convert(event.locationInWindow, from: nil)) { toggle() }
    }
    override func layout() { super.layout(); button.frame = bounds }
    @objc private func toggle() {
        guard let row, let player = primary else { return }
        dispatch(.page(.media(.item(row.id), player.id, player.paused || player.ended ? .play : .pause)))
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let row else { return nil }
        let menu = NSMenu()
        for (index, player) in row.mediaPlayers.enumerated() {
            let verb = player.paused || player.ended ? "Play" : "Pause"
            let item = NSMenuItem(title: "\(verb) \(player.kind.rawValue) \(index + 1) · frame \(player.id.frame)", action: #selector(choose(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = player; menu.addItem(item)
        }
        return menu
    }
    @objc private func choose(_ item: NSMenuItem) {
        guard let row, let chosen = item.representedObject as? MediaPlayer,
              let player = row.mediaPlayers.first(where: { $0.id == chosen.id }) else { return }
        dispatch(.page(.media(.item(row.id), player.id, chosen.paused || chosen.ended ? .play : .pause)))
    }
}
