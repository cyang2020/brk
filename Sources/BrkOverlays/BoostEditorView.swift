import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// A reducer-owned draft. Typing previews CSS; JavaScript runs only after Save and native confirmation.
@MainActor
public final class BoostEditorView: NSView, NSTextFieldDelegate, NSTextViewDelegate {
    private let dispatch: Dispatch
    private var editor: BoostEditor?
    private let heading = NSTextField(labelWithString: "Edit the Internet with Boosts")
    private let name = NSTextField()
    private let scope = NSPopUpButton()
    private let address = NSTextField()
    private let enabled = NSButton(checkboxWithTitle: "Enable Boost", target: nil, action: nil)
    private let privateAllowed = NSButton(checkboxWithTitle: "Also use in private windows", target: nil, action: nil)
    private let cssLabel = NSTextField(labelWithString: "CSS · live preview")
    private let jsLabel = NSTextField(labelWithString: "JavaScript · confirmation required on Save")
    private let css = NSTextView()
    private let javascript = NSTextView()
    private let cssScroll = NSScrollView()
    private let jsScroll = NSScrollView()
    private let feedback = NSTextField(wrappingLabelWithString: "")
    private let zap = NSButton(title: "Zap an element", target: nil, action: nil)
    private let save = NSButton(title: "Save Boost", target: nil, action: nil)
    private let cancel = NSButton(title: "Cancel", target: nil, action: nil)
    private var syncing = false

    public init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        wantsLayer = true; layer?.cornerRadius = Metrics.content.cornerRadius.value
        identify(.boostControl("editor"))
        heading.font = .systemFont(ofSize: 18, weight: .bold)
        name.placeholderString = "Boost name"; name.delegate = self; name.identify(.boostControl("name"))
        address.placeholderString = "https://example.com or example.com"; address.delegate = self; address.identify(.boostControl("scope-value"))
        scope.addItems(withTitles: ["This origin", "This host", "All websites"])
        scope.target = self; scope.action = #selector(scopeChanged); scope.identify(.boostControl("scope"))
        for (button, action, id) in [(enabled, #selector(changed), "enabled"), (privateAllowed, #selector(changed), "private"),
                                     (zap, #selector(beginZap), "zap"), (save, #selector(saveBoost), "save"), (cancel, #selector(cancelBoost), "cancel")] {
            button.target = self; button.action = action; button.identify(.boostControl(id)); button.bezelStyle = .rounded
        }
        for (text, scroll, id) in [(css, cssScroll, "css"), (javascript, jsScroll, "javascript")] {
            text.isRichText = false; text.isAutomaticQuoteSubstitutionEnabled = false; text.isAutomaticDashSubstitutionEnabled = false
            text.isAutomaticTextReplacementEnabled = false; text.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
            text.delegate = self; text.identify(.boostControl(id)); text.textContainerInset = NSSize(width: 6, height: 6)
            text.isVerticallyResizable = true; text.isHorizontallyResizable = false; text.autoresizingMask = [.width]
            text.textContainer?.widthTracksTextView = true
            scroll.hasVerticalScroller = true; scroll.borderType = .bezelBorder; scroll.documentView = text
        }
        cssLabel.font = .systemFont(ofSize: 12, weight: .semibold); jsLabel.font = cssLabel.font
        feedback.font = .systemFont(ofSize: 11); feedback.textColor = .secondaryLabelColor
        for view in [heading, name, scope, address, enabled, privateAllowed, cssLabel, cssScroll, jsLabel, jsScroll, feedback, zap, cancel, save] { addSubview(view) }
        isHidden = true
    }
    @available(*, unavailable) public required init?(coder: NSCoder) { fatalError("not used") }
    public override var isFlipped: Bool { true }
    public func render(_ value: BoostEditor?, in rect: CGRect, scheme: Scheme) {
        let opening = editor?.id != value?.id
        editor = value
        guard let value else { isHidden = true; return }
        isHidden = value.picking
        frame = CGRect(x: max(rect.minX, rect.maxX - 420), y: rect.minY, width: min(420, rect.width), height: rect.height)
        appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        syncing = true
        if name.stringValue != value.draft.name { name.stringValue = value.draft.name }
        if css.string != value.draft.css { css.string = value.draft.css }
        if javascript.string != value.draft.javascript { javascript.string = value.draft.javascript }
        let index: Int
        switch value.draft.scope { case .origin: index = 0; case .host: index = 1; case .allSites: index = 2 }
        scope.selectItem(at: index)
        if window?.firstResponder !== address.currentEditor(), address.stringValue != value.draft.scope.label { address.stringValue = value.draft.scope.label }
        address.isEnabled = index != 2
        enabled.state = value.draft.enabled ? .on : .off; privateAllowed.state = value.draft.allowPrivate ? .on : .off
        zap.isEnabled = value.target != nil
        feedback.stringValue = value.message ?? "CSS previews on the captured page. Save applies to matching sites. Reload to undo JavaScript effects."
        syncing = false
        needsLayout = true
        if opening && !value.picking { window?.makeFirstResponder(name) }
    }
    public override func layout() {
        super.layout()
        let width = max(0, bounds.width - 32), h = bounds.height
        heading.frame = CGRect(x: 16, y: 16, width: width, height: 26)
        name.frame = CGRect(x: 16, y: 52, width: width, height: 26)
        scope.frame = CGRect(x: 16, y: 88, width: width, height: 26)
        address.frame = CGRect(x: 16, y: 122, width: width, height: 26)
        enabled.frame = CGRect(x: 16, y: 158, width: width, height: 22)
        privateAllowed.frame = CGRect(x: 16, y: 184, width: width, height: 22)
        let editorHeight = max(60, (h - 372) / 2)
        cssLabel.frame = CGRect(x: 16, y: 216, width: width, height: 20)
        cssScroll.frame = CGRect(x: 16, y: 240, width: width, height: editorHeight)
        jsLabel.frame = CGRect(x: 16, y: 248 + editorHeight, width: width, height: 20)
        jsScroll.frame = CGRect(x: 16, y: 272 + editorHeight, width: width, height: editorHeight)
        feedback.frame = CGRect(x: 16, y: h - 92, width: width, height: 44)
        zap.frame = CGRect(x: 12, y: h - 40, width: 136, height: 30)
        cancel.frame = CGRect(x: bounds.width - 204, y: h - 40, width: 80, height: 30)
        save.frame = CGRect(x: bounds.width - 124, y: h - 40, width: 112, height: 30)
        for (text, scroll) in [(css, cssScroll), (javascript, jsScroll)] { text.setFrameSize(NSSize(width: scroll.contentSize.width, height: max(text.frame.height, scroll.contentSize.height))) }
    }
    public func controlTextDidChange(_ obj: Notification) { updateDraft() }
    public func textDidChange(_ notification: Notification) { updateDraft() }
    @objc private func changed() { updateDraft() }
    @objc private func scopeChanged() {
        if let origin = editor?.target?.origin {
            address.stringValue = scope.indexOfSelectedItem == 1 ? origin.url.host ?? "" : origin.value
        }
        updateDraft()
    }
    @discardableResult private func updateDraft() -> Bool {
        guard !syncing, var draft = editor?.draft else { return false }
        draft.name = name.stringValue; draft.css = css.string; draft.javascript = javascript.string
        draft.enabled = enabled.state == .on; draft.allowPrivate = privateAllowed.state == .on
        switch scope.indexOfSelectedItem {
        case 0:
            guard let url = URL(string: address.stringValue), let origin = SiteOrigin(url) else { feedback.stringValue = "Enter an HTTP(S) origin."; return false }
            draft.scope = .origin(origin)
        case 1: draft.scope = .host(address.stringValue.lowercased())
        default: draft.scope = .allSites
        }
        dispatch(.boost(.update(draft)))
        return true
    }
    @objc private func beginZap() { dispatch(.boost(.zap)) }
    @objc private func saveBoost() { if updateDraft() { dispatch(.boost(.save)) } }
    @objc private func cancelBoost() { dispatch(.boost(.cancel)) }
}

@MainActor
public final class BoostZapOverlayView: NSView {
    private let label = NSTextField(labelWithString: "Zap · Click an element to hide it. Escape cancels.")
    private let cancel = NSButton(title: "Cancel Zap", target: nil, action: nil)
    private let dispatch: Dispatch
    public init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        wantsLayer = true; layer?.cornerRadius = Metrics.content.cornerRadius.value
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        cancel.target = self; cancel.action = #selector(cancelPick); cancel.bezelStyle = .rounded
        cancel.identify(.boostControl("cancel-zap"))
        addSubview(label); addSubview(cancel); isHidden = true
    }
    @available(*, unavailable) public required init?(coder: NSCoder) { fatalError("not used") }
    public func render(_ editor: BoostEditor?, in rect: CGRect) {
        isHidden = editor?.picking != true
        frame = CGRect(x: rect.minX + 12, y: rect.minY + 12, width: min(560, rect.width - 24), height: 42)
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        label.frame = CGRect(x: 12, y: 10, width: max(0, bounds.width - 124), height: 24)
        cancel.frame = CGRect(x: bounds.width - 110, y: 6, width: 104, height: 30)
    }
    @objc private func cancelPick() { dispatch(.boost(.zap)) }
}
