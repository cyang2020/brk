import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

@MainActor
public final class FindBarView: NSView, NSTextFieldDelegate {
    private let dispatch: Dispatch
    private let query = NSTextField(), replacement = NSTextField(), status = NSTextField(labelWithString: "")
    private let previous = NSButton(title: "↑", target: nil, action: nil)
    private let next = NSButton(title: "↓", target: nil, action: nil)
    private let close = NSButton(title: "×", target: nil, action: nil)
    private let replace = NSButton(title: "Replace", target: nil, action: nil)
    private let all = NSButton(title: "Replace All", target: nil, action: nil)
    private let capture = NSButton(title: "Capture Field", target: nil, action: nil)
    private var last: FindSnapshot?

    public init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        wantsLayer = true; identify(.findBar); isHidden = true
        query.identify(.findQuery); replacement.identify(.findReplacement); status.identify(.findStatus)
        query.placeholderString = "Find in Page"; replacement.placeholderString = "Replace with"
        query.delegate = self; replacement.delegate = self
        for field in [query, replacement] { field.font = .systemFont(ofSize: NSFont.smallSystemFontSize) }
        for (button, id, selector) in [
            (previous, ViewID.findPrevious, #selector(back)), (next, .findNext, #selector(forward)), (close, .findClose, #selector(dismiss)),
            (replace, .findReplace, #selector(replaceOne)), (all, .findReplaceAll, #selector(replaceAll)), (capture, .findCapture, #selector(captureField))
        ] { button.identify(id); button.target = self; button.action = selector; button.bezelStyle = .rounded; button.controlSize = .small }
        previous.toolTip = "Previous Match"; next.toolTip = "Next Match"; close.toolTip = "Close Find"
        status.font = .systemFont(ofSize: NSFont.smallSystemFontSize); status.lineBreakMode = .byTruncatingTail
        for view in [query,replacement,status,previous,next,close,replace,all,capture] as [NSView] { addSubview(view) }
    }
    @available(*, unavailable) public required init?(coder: NSCoder) { fatalError("not used") }
    public override var isFlipped: Bool { true }
    public func focusInput() -> Bool { guard !isHidden, let window else { return false }; return window.makeFirstResponder(query) }
    public func render(_ snapshot: FindSnapshot?, frames: FindFrames?, palette: Palette) {
        guard let snapshot, let frames else { isHidden = true; last = nil; query.stringValue = ""; replacement.stringValue = ""; return }
        if last?.page != snapshot.page { replacement.stringValue = "" }
        isHidden = false; frame = frames.bar; appearance = .of(palette.scheme); layer?.backgroundColor = OverlayColors.of(palette.scheme).popover.cgColor
        layer?.cornerRadius = Metrics.content.cornerRadius.value
        if query.stringValue != snapshot.query.text { query.stringValue = snapshot.query.text }
        query.frame = frames.query; status.frame = frames.status; previous.frame = frames.previous; next.frame = frames.next; close.frame = frames.close
        replacement.frame = frames.replacement; replace.frame = frames.replace; all.frame = frames.replaceAll; capture.frame = frames.capture
        for view in [replacement,replace,all,capture] as [NSView] { view.isHidden = !snapshot.replacement }
        replace.isEnabled = snapshot.canReplace; all.isEnabled = snapshot.canReplace
        let count: String
        if snapshot.query.text.isEmpty { count = "" }
        else if snapshot.searching { count = "Searching…" }
        else if let n = snapshot.count { count = snapshot.ordinal.map { "\($0) of \(n)" } ?? (n == 0 ? "No matches" : "\(n) matches") }
        else { count = "" }
        status.stringValue = snapshot.message.isEmpty ? [snapshot.scope,count].filter { !$0.isEmpty }.joined(separator: " · ") : snapshot.message
        status.toolTip = status.stringValue
        last = snapshot
    }
    public func controlTextDidChange(_ notification: Notification) {
        guard notification.object as? NSTextField === query else { return }
        dispatch(.find(.query(FindQuery(text: query.stringValue, caseSensitive: last?.query.caseSensitive ?? false))))
    }
    public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.insertNewline(_:)) { dispatch(.find(.step(NSApp.currentEvent?.modifierFlags.contains(.shift) == true ? .previous : .next))); return true }
        if selector == #selector(NSResponder.cancelOperation(_:)) { dismiss(); return true }
        return false
    }
    @objc private func back() { dispatch(.find(.step(.previous))) }
    @objc private func forward() { dispatch(.find(.step(.next))) }
    @objc private func dismiss() { dispatch(.find(.close)) }
    @objc private func replaceOne() { dispatch(.find(.replaceCurrent(replacement.stringValue))) }
    @objc private func replaceAll() { dispatch(.find(.replaceAll(replacement.stringValue))) }
    @objc private func captureField() { dispatch(.find(.captureScope)) }
}
