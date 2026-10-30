import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit
import SwiftUI

/// Owner: W4 (dialogs). The new-space and edit-space dialog: name, icon (emoji, named icon or SF Symbol), Arc's
/// preset color pads (Brand, Drab, Greyscale, Pastel), wheel (analogous or complementary), texture, the noise dial,
/// the intensity slider and appearance.
/// SwiftUI inside an `NSHostingView`, the one kind of place SwiftUI is used (as Arc does with
/// `ThemeAwareHostingController`). The form's fields are local SwiftUI state seeded from the snapshot; Save dispatches
/// `.space(.create(...))` or `.space(.update(...))`, Cancel dispatches `.sidebar(.openDialog(nil))`. Edits preview
/// live by dispatching `.space(.update(...))` for the theme (Arc's editor recolors the window as you drag).
@MainActor
public final class SpaceDialogHost: NSView {
    let dispatch: Dispatch
    private var hosting: NSHostingView<SpaceDialogForm>?

    public init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        isHidden = true
        identify(.spaceDialog)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Keyboard focus into the form (its first field). False while hidden or not in a window.
    public func focusForm() -> Bool {
        guard !isHidden, let hosting, let window else { return false }
        return window.makeFirstResponder(hosting)
    }

    public func render(_ dialog: SpaceDialogSnapshot?, frames: WindowFrames, palette: Palette) {
        guard let dialog else {
            isHidden = true
            hosting?.removeFromSuperview()
            hosting = nil
            return
        }
        isHidden = false
        if hosting == nil {
            let view = NSHostingView(rootView: SpaceDialogForm(dialog: dialog, dispatch: dispatch))
            addSubview(view)
            hosting = view
        } else {
            hosting?.rootView = SpaceDialogForm(dialog: dialog, dispatch: dispatch)   // TODO(W4): keep form state for the same dialog
        }
        let size = CGSize(width: Metrics.commandBar.attachedMaxWidth.value / 2, height: Metrics.commandBar.boxHeight.value)
        frame = CGRect(x: frames.contentArea.midX - size.width / 2, y: frames.contentArea.midY - size.height / 2, width: size.width, height: size.height)
        hosting?.frame = bounds
    }
}

struct SpaceDialogForm: View {
    let dialog: SpaceDialogSnapshot
    let dispatch: Dispatch
    @State private var title = ""
    @State private var theme = SpaceTheme.default

    var body: some View {
        // TODO(W4): TextField for the name, icon picker (emoji / NamedIcon grid / SF Symbol), 4 x 9 preset grid from
        // ThemePresets, wheel toggle, texture picker, noise dial, intensity slider, appearance (auto/light/dark),
        // Save and Cancel.
        Text(Copy.urlPlaceholder).hidden()
    }
}
