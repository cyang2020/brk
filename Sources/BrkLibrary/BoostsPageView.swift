import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

@MainActor
final class BoostsPageView: NSView {
    private let dispatch: Dispatch
    private let heading = NSTextField(labelWithString: "Boosts")
    private let feedback = NSTextField(wrappingLabelWithString: "")
    private let scroll = NSScrollView()
    private let list = BoostList()
    private let create = NSButton(title: "New Boost", target: nil, action: nil)
    private let install = NSButton(title: "Install from File…", target: nil, action: nil)
    private var actions: [NSButton: Command] = [:]
    private var snapshot: LibrarySnapshot?
    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        wantsLayer = true; layer?.cornerRadius = Metrics.content.cornerRadius.value
        identify(.boostControl("library")); heading.font = .systemFont(ofSize: 26, weight: .bold)
        feedback.font = .systemFont(ofSize: 12); feedback.textColor = .secondaryLabelColor
        create.target = self; create.action = #selector(newBoost); create.bezelStyle = .rounded; create.identify(.boostControl("new"))
        install.target = self; install.action = #selector(importBoost); install.bezelStyle = .rounded; install.identify(.boostControl("import"))
        scroll.hasVerticalScroller = true; scroll.drawsBackground = false; scroll.documentView = list
        for view in [heading, feedback, create, install, scroll] { addSubview(view) }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    func show(_ value: LibrarySnapshot, in rect: CGRect, scheme: Scheme) {
        isHidden = false; frame = rect
        appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        layer?.backgroundColor = LibraryColors.of(scheme).page.cgColor
        create.isEnabled = value.canManageBoosts; install.isEnabled = value.canManageBoosts
        feedback.stringValue = !value.canManageBoosts ? "Manage Boosts from a public window. Existing Boosts need explicit private-window permission." : value.boostMessage ?? "Edit the Internet with Boosts. CSS previews live; JavaScript asks for permission."
        if snapshot?.boosts != value.boosts || snapshot?.canManageBoosts != value.canManageBoosts { rebuild(value) }
        snapshot = value; needsLayout = true
    }
    func hide() { isHidden = true }
    private func button(_ title: String, id: String, command: Command, y: CGFloat, x: CGFloat, width: CGFloat) {
        let button = NSButton(title: title, target: self, action: #selector(commandClicked(_:)))
        button.bezelStyle = .rounded; button.identify(.boostControl(id)); button.frame = CGRect(x: x, y: y, width: width, height: 28)
        actions[button] = command; list.addSubview(button)
    }
    private func label(_ text: String, y: CGFloat, bold: Bool = false) {
        let label = NSTextField(labelWithString: text); label.font = .systemFont(ofSize: bold ? 16 : 12, weight: bold ? .semibold : .regular)
        label.frame = CGRect(x: 8, y: y, width: max(100, bounds.width - 80), height: 24); label.lineBreakMode = .byTruncatingTail
        list.addSubview(label)
    }
    private func rebuild(_ value: LibrarySnapshot) {
        list.subviews.forEach { $0.removeFromSuperview() }; actions = [:]
        var y: CGFloat = 0
        if value.boosts.isEmpty { label("Nothing Boosted Yet!", y: y, bold: true); y += 42 }
        for boost in value.boosts {
            label(boost.name + (boost.enabled ? "" : " · disabled"), y: y, bold: true)
            label(boost.scope.label + (!boost.javascript.isEmpty && !boost.javascriptApproved ? " · JavaScript needs approval" : ""), y: y + 26)
            let id = boost.id
            for (title, suffix, command, x, width) in [
                ("Edit…", "edit", Command.boost(.edit(id)), 4.0, 70.0),
                (boost.enabled ? "Disable" : "Enable", "toggle", .boost(.enable(id, !boost.enabled)), 82, 80),
                ("Export…", "export", .boost(.export(id)), 170, 80),
                ("Remove", "remove", .boost(.remove(id)), 258, 80)] {
                button(title, id: suffix + "-" + id, command: command, y: y + 54, x: x, width: width)
            }
            y += 104
        }
        if value.canManageBoosts {
            label("Local Boost Gallery", y: y, bold: true); y += 36
            for preset in BoostPresets.all {
                button(preset.name, id: "preset-" + preset.id, command: .boost(.preset(preset.id)), y: y, x: 4, width: 240); y += 38
            }
        }
        list.frame.size = NSSize(width: max(0, bounds.width - 48), height: y + 16)
    }
    override func layout() {
        super.layout()
        heading.frame = CGRect(x: 24, y: 22, width: bounds.width - 48, height: 34)
        create.frame = CGRect(x: 20, y: 64, width: 120, height: 30)
        install.frame = CGRect(x: 146, y: 64, width: 170, height: 30)
        feedback.frame = CGRect(x: 24, y: 106, width: bounds.width - 48, height: 40)
        scroll.frame = CGRect(x: 24, y: 156, width: max(0, bounds.width - 48), height: max(0, bounds.height - 176))
        list.frame.size.width = scroll.contentSize.width
    }
    @objc private func commandClicked(_ sender: NSButton) { if let command = actions[sender] { dispatch(command) } }
    @objc private func newBoost() { dispatch(.boost(.create)) }
    @objc private func importBoost() { dispatch(.boost(.importFile)) }
}

private final class BoostList: NSView { override var isFlipped: Bool { true } }
