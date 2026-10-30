import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit
import SwiftUI

/// Owner: F4. Arc's Shortcuts pane (anatomy-m 1.14, 2.2, 4.2; strings around "PreferencesFeature/ShortcutsPane.swift"):
/// every action of the shortcut table with its shortcut as routing resolves it (`SettingsSnapshot.shortcuts`), a
/// recorder to change it, and a menu per shortcut with Arc's three priorities, "Reset Shortcut to Default", "Remove
/// Shortcut" and, on a conflict, "Remove Conflicting Shortcut". Changed shortcuts are listed first under "Customized
/// Shortcuts", the rest by menu under "Default Shortcuts". Every control dispatches a `.settings(.shortcuts(...))`
/// command and keeps no setting of its own (the filter text and a recording in progress are view state).
///
/// Mounted by F1's `SettingsHost` for `SettingsPane.shortcuts`: `ShortcutsPane(rows: settings.shortcuts, dispatch:)`.
struct ShortcutsPane: View {
    let rows: [ShortcutRow]
    let dispatch: Dispatch
    @State private var filter = ""

    var body: some View {
        VStack(alignment: .leading, spacing: ShortcutsPaneMetrics.sectionSpacing.value) {
            VStack(alignment: .leading, spacing: ShortcutsPaneMetrics.lineSpacing.value) {
                Text(ShortcutsCopy.title).font(.title2.weight(.semibold))
                Text(ShortcutsCopy.subtitle).foregroundStyle(.secondary)
            }
            HStack {
                TextField(ShortcutsCopy.filter, text: $filter)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier(ViewID.settingsField("shortcut-filter").identifier)
                Button(ShortcutsCopy.resetAll) { dispatch(.settings(.shortcuts(.resetAll))) }
                    .disabled(!rows.contains { $0.source == .userDefined })
                    .accessibilityIdentifier(ViewID.settingsField("shortcut-reset-all").identifier)
            }
            ForEach(ShortcutsPane.sections(rows, filter: filter), id: \.title) { section in
                VStack(alignment: .leading, spacing: ShortcutsPaneMetrics.lineSpacing.value) {
                    Text(section.title).font(.headline).padding(.top, ShortcutsPaneMetrics.sectionSpacing.value)
                    ForEach(section.rows, id: \.action) { row in
                        ShortcutRowView(row: row, others: rows, dispatch: dispatch)
                        Divider()
                    }
                }
            }
        }
    }

    struct Section {
        let title: String
        let rows: [ShortcutRow]
    }

    /// "Customized Shortcuts" (the user's, in table order), then each menu's other rows under its menu's name, the
    /// first of those headed "Default Shortcuts"; rows whose title or shortcut does not match `filter` are left out.
    static func sections(_ rows: [ShortcutRow], filter: String) -> [Section] {
        let needle = filter.trimmingCharacters(in: .whitespaces).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let shown = rows.filter { row in
            guard !needle.isEmpty else { return true }
            let title = ShortcutsCopy.title(of: row).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            return title.contains(needle) || ShortcutsCopy.chord(row.state).map { $0.lowercased().contains(needle) } == true
        }
        var sections: [Section] = []
        let custom = shown.filter { $0.source == .userDefined }
        if !custom.isEmpty { sections.append(Section(title: ShortcutsCopy.customized, rows: custom)) }
        for menu in MenuName.allCases {
            let list = shown.filter { $0.source == .default && $0.menu == menu }
            guard !list.isEmpty else { continue }
            let name = ShortcutsCopy.menuTitle(menu)
            sections.append(Section(title: sections.count == (custom.isEmpty ? 0 : 1) ? "\(ShortcutsCopy.defaults): \(name)" : name, rows: list))
        }
        return sections
    }
}

/// One shortcut: title, the conflict or system note, the recorder, the menu.
struct ShortcutRowView: View {
    let row: ShortcutRow
    let others: [ShortcutRow]
    let dispatch: Dispatch

    var body: some View {
        HStack(alignment: .center, spacing: ShortcutsPaneMetrics.controlSpacing.value) {
            VStack(alignment: .leading, spacing: ShortcutsPaneMetrics.lineSpacing.value) {
                // A later wave's action is remappable already; its title is dimmed like its menu item.
                Text(ShortcutsCopy.title(of: row)).foregroundStyle(row.action.spec.later == nil ? .primary : .secondary)
                if let note = ShortcutsCopy.conflict(row, among: others) {
                    Label(note, systemImage: "exclamationmark.circle.fill").font(.caption).foregroundStyle(.orange)
                } else if case .valid(let chord) = row.state, KeyBindings.isSystemShortcut(chord) {
                    Label(ShortcutsCopy.systemNote, systemImage: "exclamationmark.circle.fill").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: ShortcutsPaneMetrics.sectionSpacing.value)
            ChordRecorder(state: row.state) { chord in dispatch(.settings(.shortcuts(.setChord(row.action, chord)))) }
                .frame(width: ShortcutsPaneMetrics.recorderSize.value.width, height: ShortcutsPaneMetrics.recorderSize.value.height)
                .accessibilityIdentifier(ViewID.settingsField("shortcut-\(row.action.rawValue)").identifier)
            Menu {
                Picker(ShortcutsCopy.priorityTitle, selection: Binding(get: { row.priority },
                                                                       set: { dispatch(.settings(.shortcuts(.setPriority(row.action, $0)))) })) {
                    ForEach(KeyPriority.allCases, id: \.self) { Text(ShortcutsCopy.priority($0)).tag($0) }
                }
                .pickerStyle(.inline)
                Divider()
                Button(ShortcutsCopy.resetOne) { dispatch(.settings(.shortcuts(.reset(row.action)))) }.disabled(row.source == .default)
                Button(ShortcutsCopy.remove) { dispatch(.settings(.shortcuts(.setChord(row.action, nil)))) }.disabled(row.state == .unset)
                if case .conflict(_, let with) = row.state {
                    Button(with.count == 1 ? ShortcutsCopy.removeConflicting : ShortcutsCopy.removeConflictingMany) {
                        for other in with { dispatch(.settings(.shortcuts(.setChord(other, nil)))) }
                    }
                    .accessibilityIdentifier(ViewID.settingsField("shortcut-remove-conflict-\(row.action.rawValue)").identifier)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .accessibilityIdentifier(ViewID.settingsField("shortcut-menu-\(row.action.rawValue)").identifier)
        }
        .padding(.vertical, ShortcutsPaneMetrics.rowPadding.value)
    }
}

/// The shortcut field: shows the chord ("⌘T"), and records a new one after a click. While it records, every key-down
/// in the app comes here first (a local event monitor), so Command chords never reach the menu and Ctrl+Tab never
/// moves the focus. Esc cancels; Delete removes the shortcut; a key the table cannot name, or a plain key without
/// ⌘, ⌃ or ⌥ (F12 aside), is refused with a note and the recording goes on. Conflicts are recorded: they are a state
/// the row then shows, as in Arc.
struct ChordRecorder: NSViewRepresentable {
    let state: KeyBindingState
    let record: @MainActor (KeyChord?) -> Void

    func makeNSView(context: NSViewRepresentableContext<ChordRecorder>) -> ChordRecorderView { ChordRecorderView() }

    func updateNSView(_ view: ChordRecorderView, context: NSViewRepresentableContext<ChordRecorder>) {
        view.state = state
        view.record = record
    }
}

@MainActor
final class ChordRecorderView: NSView {
    /// What a key-down means to the recorder.
    enum Outcome: Equatable {
        case record(KeyChord)
        case clear
        case cancel
        case refuse(String)
    }

    var state: KeyBindingState = .unset { didSet { if state != oldValue { refresh() } } }
    var record: @MainActor (KeyChord?) -> Void = { _ in }
    private(set) var isRecording = false
    private var note: String?
    private var monitor: Any?
    private let label = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = ShortcutsPaneMetrics.recorderRadius.value
        layer?.cornerCurve = .continuous
        layer?.borderWidth = 1
        label.alignment = .center
        label.font = .systemFont(ofSize: NSFont.systemFontSize)
        label.lineBreakMode = .byTruncatingTail
        addSubview(label)
        setAccessibilityRole(.button)
        refresh()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        super.layout()
        let height = label.intrinsicContentSize.height, inset = ShortcutsPaneMetrics.rowPadding.value
        label.frame = CGRect(x: inset, y: ((bounds.height - height) / 2).rounded(), width: bounds.width - 2 * inset, height: height)
    }

    override func mouseDown(with event: NSEvent) { isRecording ? stop() : start() }
    override func accessibilityPerformPress() -> Bool {
        isRecording ? stop() : start()
        return true
    }

    func start() {
        guard !isRecording else { return }
        isRecording = true
        note = nil
        window?.makeFirstResponder(self)
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            MainActor.assumeIsolated { self?.handle(event) ?? false } ? nil : event
        }
        refresh()
    }

    func stop() {
        isRecording = false
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        refresh()
    }

    override func resignFirstResponder() -> Bool {
        if isRecording { stop() }
        return super.resignFirstResponder()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil, isRecording { stop() }
    }

    /// Takes the key-down while recording; false lets it go on to the app.
    @discardableResult
    func handle(_ event: NSEvent) -> Bool {
        guard isRecording else { return false }
        switch Self.interpret(keyCode: event.keyCode, flags: event.modifierFlags) {
        case .record(let chord):
            stop()
            record(chord)
        case .clear:
            stop()
            record(nil)
        case .cancel:
            stop()
        case .refuse(let why):
            note = why
            refresh()
        }
        return true
    }

    /// The physical key and the four shortcut modifiers, as the table matches them (`Key` by key code).
    static func interpret(keyCode: UInt16, flags: NSEvent.ModifierFlags) -> Outcome {
        let mask = Modifiers.shift.rawValue | Modifiers.control.rawValue | Modifiers.option.rawValue | Modifiers.command.rawValue
        let modifiers = Modifiers(rawValue: flags.intersection(.deviceIndependentFlagsMask).rawValue & mask)
        let escape: UInt16 = 53, delete: UInt16 = 51, forwardDelete: UInt16 = 117
        if modifiers.isEmpty, keyCode == escape { return .cancel }
        if modifiers.isEmpty, keyCode == delete || keyCode == forwardDelete { return .clear }
        guard let key = Key.byCode(keyCode) else { return .refuse(ShortcutsCopy.unsupportedKey) }
        if modifiers.intersection([.command, .control, .option]).isEmpty, key != .f12 { return .refuse(ShortcutsCopy.needsModifier) }
        return .record(KeyChord(modifiers, key))
    }

    private func refresh() {
        let text: String
        if isRecording {
            text = note ?? ShortcutsCopy.recording
        } else {
            text = ShortcutsCopy.chord(state) ?? ShortcutsCopy.record
        }
        label.stringValue = text
        label.textColor = isRecording || ShortcutsCopy.chord(state) == nil ? .secondaryLabelColor : .labelColor
        layer?.borderColor = (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        setAccessibilityLabel(text)
    }
}

/// Arc's Shortcuts pane copy (anatomy-m 4.2 and the strings next to `ShortcutsPane.swift` in Arc's binary); "Arc"
/// is the product name. GUESS marks the short labels Arc keeps in code.
enum ShortcutsCopy {
    static let title = "Custom Shortcuts"
    static let subtitle = "Change shortcuts for your favorite actions, and even choose whether \(Product.name) or a website takes priority."
    static let customized = "Customized Shortcuts"
    static let defaults = "Default Shortcuts"
    static let resetAll = "Reset All Shortcuts"
    static let resetOne = "Reset Shortcut to Default"
    static let removeConflicting = "Remove Conflicting Shortcut"
    static let removeConflictingMany = "Remove Conflicting Shortcuts"
    static let systemNote = "System shortcuts may take priority over this shortcut"
    /// GUESS: the string for "Menu item to remove a shortcut, i.e. unset it" did not survive.
    static let remove = "Remove Shortcut"
    /// GUESS labels.
    static let filter = "Search Shortcuts"
    static let record = "Record Shortcut"
    static let recording = "Type Shortcut…"
    static let priorityTitle = "Priority"
    static let unsupportedKey = "This key can't be a shortcut"
    static let needsModifier = "Add ⌘, ⌃ or ⌥"

    /// Arc's three priority subtitles (anatomy-m 2.2), in `KeyPriority` order.
    static func priority(_ priority: KeyPriority) -> String {
        switch priority {
        case .app: "When shortcuts conflict, \(Product.name) wins."
        case .pageThenApp: "Press this shortcut once to use the website's shortcut. Press it twice to use \(Product.name)'s shortcut."
        case .page: "When shortcuts conflict, the website wins."
        }
    }

    static func title(of row: ShortcutRow) -> String { row.action.title(appName: Product.name) }

    static func chord(_ state: KeyBindingState) -> String? {
        switch state {
        case .valid(let chord), .conflict(let chord, _): chord.glyphs
        case .unset: nil
        }
    }

    /// Arc: "%@ is already in use by %@", "… and one other action", "… and %d other actions".
    static func conflict(_ row: ShortcutRow, among rows: [ShortcutRow]) -> String? {
        guard case .conflict(let chord, let with) = row.state, let first = with.first else { return nil }
        let name = first.title(appName: Product.name)
        let more = with.count - 1
        let tail = more == 0 ? "" : more == 1 ? " and one other action" : " and \(more) other actions"
        return "\(chord.glyphs) is already in use by \(name)\(tail)"
    }

    static func menuTitle(_ menu: MenuName) -> String {
        switch menu {
        case .app: Product.name
        case .file: "File"
        case .edit: "Edit"
        case .view: "View"
        case .spaces: "Spaces"
        case .tabs: "Tabs"
        case .archive: "Archive"
        case .extensions: "Extensions"
        case .window: "Window"
        case .help: "Help"
        }
    }
}

/// The pane's numbers; Arc's Shortcuts pane was not measured, so all are guesses (the login wall keeps the real
/// Arc from being captured).
let ShortcutsPaneMetrics = ShortcutsPaneMetricsTable()

struct ShortcutsPaneMetricsTable: MetricGroup {
    let recorderSize = Metric(CGSize(width: 132, height: 24), .guess("shortcut field: room for four modifier glyphs and a key, a regular control's height"))
    let recorderRadius = Metric(6.0, .guess("shortcut field corner radius, a rounded text field's"))
    let sectionSpacing = Metric(12.0, .guess("space between the pane's header, filter row and sections"))
    let controlSpacing = Metric(8.0, .guess("space between a row's title, shortcut field and menu"))
    let lineSpacing = Metric(4.0, .guess("space between a title and its note"))
    let rowPadding = Metric(4.0, .guess("a row's vertical padding, and the shortcut field's text inset"))
}
