import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit
import SwiftUI

/// Owner: F2. Arc's three profile dialogs (`ProfilesUI`: `CreateProfileDialog`, `ChangeProfileDialog`,
/// `DeleteProfileDialog`) in Arc's centred dialog (`ArcDialog.swift`), matched to the 2026-11-03 captures P42 a (New
/// Profile) and Q04 a (Change Profile). Copy and rules come from `ProfileCopy` (BrkDomain), so the dialog says no
/// exactly when the reducer does; the strings Arc 1.170 shows differently are in `ProfileDialogCopy`. The confirm
/// button dispatches one `.profile(...)` command, Cancel and Esc dispatch `.profile(.openDialog(nil))`.
///
/// - Create: two steps, as Arc's. The name (Next), then the icon (Create Profile). A taken name is refused by the
///   reducer and the dialog stays open on the name with "A Profile with that name already exists.".
/// - Change: "Change X’s Profile" and the space's profile as a pill that opens a menu of every profile and New
///   Profile….
/// - Delete: refused for the default profile and a profile with spaces (Arc's two rules, with the spaces named);
///   otherwise Arc's warning and "To continue, please type the name of this Profile:".
@MainActor
public final class ProfileDialogHost: NSView {
    let dispatch: Dispatch
    private var view: ProfileDialogView?
    private var dialog: ProfileDialogSnapshot?
    private var scheme: Scheme?

    public init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        isHidden = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    public override var isFlipped: Bool { true }

    /// W2's root holds the space dialog; until it holds this host too, these two calls keep it as the space
    /// dialog's sibling, just above it, with the same dispatch (added on the first dialog). `spaceNames` names the
    /// space in Change Profile's title (the dock's titles).
    public static func render(_ dialog: ProfileDialogSnapshot?, over sibling: SpaceDialogHost, frames: WindowFrames, palette: Palette,
                              spaceNames: [SpaceID: String] = [:]) {
        guard let root = sibling.superview else { return }
        var host = root.subviews.lazy.compactMap { $0 as? ProfileDialogHost }.first
        if host == nil, dialog != nil {
            host = ProfileDialogHost(dispatch: sibling.dispatch)
            root.addSubview(host!, positioned: .above, relativeTo: sibling)
        }
        host?.frame = root.bounds
        host?.render(dialog, scheme: palette.scheme, spaceNames: spaceNames)
    }

    public static func focus(over sibling: SpaceDialogHost) -> Bool {
        sibling.superview?.subviews.lazy.compactMap { $0 as? ProfileDialogHost }.first?.focusForm() ?? false
    }

    /// Keyboard focus into the dialog: its text field (create, delete), else the dialog itself (Return works).
    public func focusForm() -> Bool {
        guard !isHidden, let view else { return false }
        return view.dialog.focus()
    }

    public func render(_ dialog: ProfileDialogSnapshot?, frames: WindowFrames, palette: Palette) {
        render(dialog, scheme: palette.scheme, spaceNames: [:])
    }

    /// Another dialog (or another space's change dialog) starts afresh; the same one keeps what was typed.
    func render(_ dialog: ProfileDialogSnapshot?, scheme: Scheme, spaceNames: [SpaceID: String]) {
        guard let dialog else {
            isHidden = true
            view?.removeFromSuperview()
            view = nil
            self.dialog = nil
            return
        }
        if dialog != self.dialog || scheme != self.scheme || view == nil {
            view?.removeFromSuperview()
            var spaceName = ""
            if case .change(let space, _, _) = dialog { spaceName = spaceNames[space] ?? "" }
            let fresh = ProfileDialogView(ProfileDraft(dialog), spaceName: spaceName, scheme: scheme, dispatch: dispatch)
            addSubview(fresh)
            view = fresh
        }
        self.dialog = dialog
        self.scheme = scheme
        isHidden = false
        view?.frame = bounds
    }

    public override func hitTest(_ point: NSPoint) -> NSView? { isHidden ? nil : super.hitTest(point) }
}

/// What a profile dialog edits and says, and the command its confirm button sends. Plain data, so the decisions
/// are testable without SwiftUI.
struct ProfileDraft: Equatable {
    let dialog: ProfileDialogSnapshot
    var name = ""
    var icon: CustomIcon?
    /// The change dialog's chosen profile (starts at the space's current one).
    var chosen: ProfileID?
    /// What the user typed to confirm a deletion.
    var typedName = ""
    /// The name a create was refused for: with a non-blank name that means it is taken.
    var refusedName: String?

    init(_ dialog: ProfileDialogSnapshot) {
        self.dialog = dialog
        if case .change(_, let current, _) = dialog { chosen = current }
    }

    var title: String {
        switch dialog {
        case .create: ProfileCopy.createTitle
        case .change: ProfileCopy.changeTitle
        case .delete: ProfileCopy.deleteTitle
        }
    }

    var explanation: String {
        switch dialog {
        case .create: ProfileCopy.createExplanation
        case .change: ProfileCopy.changeExplanation
        case .delete(let row): ProfileCopy.deleteRefusal(row) ?? ProfileCopy.deleteWarning(row.name)
        }
    }

    /// The delete dialog of a profile that cannot be deleted lists what holds it.
    var detail: String? {
        guard case .delete(let row) = dialog, !row.isDefault, ProfileCopy.deleteRefusal(row) != nil else { return nil }
        return ProfileCopy.spaceCount(row.spaceTitles)
    }

    var confirmTitle: String {
        switch dialog {
        case .create: ProfileCopy.createButton
        case .change: ProfileCopy.changeButton
        case .delete: ProfileCopy.deleteButton
        }
    }

    var error: String? {
        guard case .create = dialog, let refusedName, !ProfileCopy.trimmed(name).isEmpty,
              ProfileCopy.isTaken(name, among: [refusedName]) else { return nil }
        return ProfileCopy.nameTaken
    }

    /// Nil while the button is disabled.
    var confirmCommand: Command? {
        switch dialog {
        case .create:
            guard ProfileCopy.acceptsName(name, among: refusedName.map { [$0] } ?? []) else { return nil }
            return .profile(.create(name: ProfileCopy.trimmed(name), icon: icon))
        case .change(let space, let current, _):
            guard let chosen, chosen != current else { return nil }
            return .profile(.assign(.space(space), to: chosen))
        case .delete(let row):
            guard ProfileCopy.deleteRefusal(row) == nil, ProfileCopy.trimmed(typedName) == row.name else { return nil }
            return .profile(.delete(row.id))
        }
    }

    /// Called right after the confirm command went out: if this dialog is still showing, a create was refused.
    mutating func confirmed() {
        if case .create = dialog { refusedName = ProfileCopy.trimmed(name) }
    }

    static let cancelCommand: Command = .profile(.openDialog(nil))
    static let newProfileCommand: Command = .profile(.openDialog(.create))
}

/// ARC_ProfilesUI's two colors (visual-and-copy.md "ARC_ProfilesUI"): ProfilePicker #3139FB @ 0.1 light, @ 0.898
/// dark; ProfilePickerText #060E2B light, #E3E2EE dark.
struct ProfilePickerColors {
    let fill: Color
    let text: Color

    static func of(_ scheme: Scheme) -> ProfilePickerColors {
        let blue = (red: 0x31 / 255.0, green: 0x39 / 255.0, blue: 0xFB / 255.0)
        return scheme == .light
            ? ProfilePickerColors(fill: Color(.sRGB, red: blue.red, green: blue.green, blue: blue.blue, opacity: 0.1),
                                  text: Color(.sRGB, red: 0x06 / 255.0, green: 0x0E / 255.0, blue: 0x2B / 255.0))
            : ProfilePickerColors(fill: Color(.sRGB, red: blue.red, green: blue.green, blue: blue.blue, opacity: 0.898),
                                  text: Color(.sRGB, red: 0xE3 / 255.0, green: 0xE2 / 255.0, blue: 0xEE / 255.0))
    }
}

/// A profile's icon: its emoji, named icon or symbol; Arc's person glyph when it has none.
struct ProfileGlyph: View {
    let icon: CustomIcon?

    static let defaultSymbol = "person.crop.circle"

    static func name(_ icon: CustomIcon) -> String {
        switch icon {
        case .emoji(let emoji): emoji
        case .named(let name): name.rawValue.capitalized
        case .symbol(let symbol): symbol
        }
    }

    var body: some View {
        switch icon {
        case nil: Image(systemName: Self.defaultSymbol)
        case .emoji(let emoji)?: Text(emoji)
        case .named(let name)?: Image(systemName: NamedIconSymbol.of(name))
        case .symbol(let symbol)?: Image(systemName: symbol)
        }
    }
}
