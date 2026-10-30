import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import SwiftUI

/// Owner: W5 (theme editor) with W3 (name and icon fields). The new-space and edit-space dialog: name, icon (emoji
/// or SF Symbol), Arc's preset color pads (Brand, Drab, Greyscale, Pastel), texture, intensity and appearance.
/// SwiftUI inside an `NSHostingView`, the one kind of place SwiftUI is used (as Arc does with
/// `ThemeAwareHostingController`). The form's fields are local SwiftUI state seeded from the snapshot; Save dispatches
/// `.space(.create(...))` or `.space(.update(...))`, Cancel dispatches `.sidebar(.openDialog(nil))`. Edits preview
/// live by dispatching `.space(.update(...))` for the theme (Arc's editor recolors the window as you drag).
@MainActor
public final class SpaceDialogHost: NSView {
    let dispatch: Dispatch
    private var hosting: NSHostingView<SpaceDialogForm>?

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        isHidden = true
        identify(.spaceDialog)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func render(_ dialog: SpaceDialogSnapshot?, frames: WindowFrames, palette: Palette) {
        // TODO(W5): nil -> hide and drop the hosting view. Else create (or keep, if the same dialog) an NSHostingView
        // of SpaceDialogForm(dialog, dispatch) centered over the content area; a new dialog resets the form.
        fatalError("not implemented")
    }
}

struct SpaceDialogForm: View {
    let dialog: SpaceDialogSnapshot
    let dispatch: Dispatch
    @State private var title = ""
    @State private var theme = SpaceTheme.default

    var body: some View {
        // TODO(W5): TextField for the name, icon picker, 4 x 9 preset grid from ThemePresets, texture picker,
        // intensity slider, appearance (auto/light/dark), Save and Cancel.
        Text(Copy.urlPlaceholder).hidden()
    }
}
