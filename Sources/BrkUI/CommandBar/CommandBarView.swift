import AppKit
import BrkBase
import BrkDomain
import BrkLayout

/// Owner: W4. The command bar: input row, then up to 5 results (switch to tab, open what you typed, history,
/// actions). The typed query and the highlighted row are view state; the snapshot's `openID` resets them.
/// Return dispatches the highlighted result's command (`Suggestion.command`), Esc `.commandBar(.dismiss)`.
/// Opening plays Arc's bounce (scale 0.95 -> 1, no fade).
@MainActor
public final class CommandBarView: NSView, NSTextFieldDelegate {
    let dispatch: Dispatch
    let input = NSTextField()
    private var openID: Int?
    private var query = ""
    private var snapshot: CommandBarSnapshot?

    init(dispatch: @escaping Dispatch) {
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

    func render(_ bar: CommandBarSnapshot?, frames: WindowFrames, palette: Palette) {
        // TODO(W4): nil -> hide. Else frame = frames.commandBar; if bar.openID != openID { query = initialQuery,
        // select all, bounce }; results = Suggest.rank(query:, bar:, appName: Product.name); result rows identify
        // (.commandBarResult(i)); row height Metrics.commandBar.suggestionRowHeight.
        fatalError("not implemented")
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        // TODO(W4): insertNewline -> dispatch(highlighted suggestion's command); cancelOperation ->
        // dispatch(.commandBar(.dismiss)); moveUp/moveDown -> highlight.
        fatalError("not implemented")
    }
}
