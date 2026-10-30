import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// Owner: W4. The command bar: input row, then up to 5 results (switch to tab, open what you typed, history,
/// actions). The typed query and the highlighted row are view state; the snapshot's `openID` resets them.
/// Return dispatches the highlighted result's command (`Suggestion.command`), Esc `.commandBar(.dismiss)`.
/// Opening plays Arc's bounce (scale 0.95 -> 1, no fade).
///
/// Public surface: `init(dispatch:)`, `render`, `focusInput`. The text field itself stays internal: the window
/// controller asks for focus, it does not reach into the bar.
@MainActor
public final class CommandBarView: NSView, NSTextFieldDelegate {
    let dispatch: Dispatch
    let input = NSTextField()
    private var openID: Int?
    private var query = ""
    private var snapshot: CommandBarSnapshot?

    public init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        isHidden = true
        identify(.commandBar)
        input.identify(.commandBarInput)
        input.placeholderString = Copy.urlPlaceholder
        input.delegate = self
        addSubview(input)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    public override var isFlipped: Bool { true }

    /// Makes the input first responder. False while the bar is hidden or not in a window.
    public func focusInput() -> Bool {
        guard !isHidden, let window else { return false }
        return window.makeFirstResponder(input)
    }

    public func render(_ bar: CommandBarSnapshot?, frames: WindowFrames, palette: Palette) {
        guard let bar, let frame = frames.commandBar else {
            isHidden = true
            snapshot = nil
            return
        }
        self.frame = frame
        isHidden = false
        wantsLayer = true
        layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        layer?.cornerCurve = .continuous
        let m = Metrics.commandBar
        input.frame = CGRect(x: m.contentInset.value, y: m.contentInset.value, width: bounds.width - 2 * m.contentInset.value,
                             height: m.inputRowHeight.value - m.contentInset.value)
        if bar.openID != openID {
            openID = bar.openID
            query = bar.initialQuery
            input.stringValue = query
            input.currentEditor()?.selectAll(nil)
            // TODO(W4): Arc's opening bounce (scale Metrics.commandBar.openBounceFrom -> 1, no fade).
        }
        snapshot = bar
        // TODO(W4): results = Suggest.rank(query: query, bar: bar, appName: Product.name); one row view per result,
        // identify(.commandBarResult(i)), row height Metrics.commandBar.suggestionRowHeight, highlight moves with
        // moveUp/moveDown, Return dispatches the highlighted result's command.
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            // TODO(W4): the highlighted suggestion's command instead of the raw text.
            dispatch(.commandBar(.submit(input.stringValue)))
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            dispatch(.commandBar(.dismiss))
            return true
        case #selector(NSResponder.moveUp(_:)), #selector(NSResponder.moveDown(_:)):
            // TODO(W4): move the highlight.
            return true
        default:
            return false
        }
    }

    public func controlTextDidChange(_ notification: Notification) {
        query = input.stringValue
        // TODO(W4): re-rank and re-render the result rows.
    }
}
