import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit
import SwiftUI

/// Owner: F4. Arc's Shortcuts pane as Arc 1.170 lays it out (P38-e): "Start with the basics" and its button on top;
/// at the left a search field and every action of the shortcut table by name, each with its shortcut in a key cap
/// (`SettingsSnapshot.shortcuts`, as routing resolves it; "---" when unset) that records a new one after a click and,
/// on hover, a menu with Arc's three priorities, "Reset Shortcut to Default", "Remove Shortcut" and, on a conflict,
/// "Remove Conflicting Shortcut"; at the right the key-cap drawing, "Custom Shortcuts" and "Reset All Shortcuts".
/// Changed shortcuts are listed first under "Customized Shortcuts", the rest by name under "Default Shortcuts". The
/// list scrolls inside its box; the window does not grow. Every control dispatches a `.settings(.shortcuts(...))`
/// command and keeps no setting of its own (the filter text and a recording in progress are view state).
///
/// Mounted by F1's `SettingsHost` for `SettingsPane.shortcuts`: `ShortcutsPane(rows: settings.shortcuts, dispatch:)`.
struct ShortcutsPane: View {
    let rows: [ShortcutRow]
    let dispatch: Dispatch
    var height: CGFloat = CardMetrics.paneSize.height
    @State private var filter = ""
    @State private var essentials = false
    @State private var customizedOnly = false

    private var shown: [ShortcutRow] {
        let base = essentials ? rows.filter { ShortcutsPane.essentials.contains($0.action) } : rows
        return customizedOnly ? base.filter { $0.source == .userDefined } : base
    }

    var body: some View {
        VStack(spacing: K.basicsToColumns.value) {
            basics
            HStack(alignment: .top, spacing: K.columnGap.value) {
                list.frame(width: K.listWidth.value, height: listHeight)
                side.frame(height: listHeight)
            }
            .frame(width: Metrics.settings.contentWidth.value, alignment: .topLeading)
        }
        .padding(.top, CardMetrics.paneTop.value)
        .frame(width: Metrics.settings.windowSize.value.width, alignment: .top)
    }

    /// The list box ends 27 points above the window's bottom (P38-e).
    private var listHeight: CGFloat {
        max(K.listMinHeight.value, height - CardMetrics.paneTop.value - K.basicsHeight.value - K.basicsToColumns.value - K.listBottom.value)
    }

    private var basics: some View {
        HStack(spacing: K.basicsGap.value) {
            Text(ShortcutsCopy.basics).font(SettingsStyle.font).foregroundStyle(SettingsStyle.text)
            ProminentButton(title: essentials ? ShortcutsCopy.showAll : ShortcutsCopy.learnEssentials, field: "shortcut-essentials",
                            prominent: true, symbol: "command.circle.fill", accent: .controlAccentColor, weight: .regular,
                            width: K.essentialsWidth.value) { essentials.toggle() }
        }
        .padding(.horizontal, K.basicsPadding.value)
        .frame(height: K.basicsHeight.value)
        .background(RoundedRectangle(cornerRadius: K.basicsRadius.value, style: .continuous).fill(Color(nsColor: .textBackgroundColor))
            .shadow(color: .black.opacity(0.12), radius: 3, y: 1))
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: K.searchGap.value) {
                Image(systemName: "magnifyingglass").font(.system(size: K.searchGlyph.value, weight: .medium)).foregroundStyle(SettingsStyle.secondaryText)
                TextField(ShortcutsCopy.filter, text: $filter)
                    .textFieldStyle(.plain)
                    .font(SettingsStyle.font)
                    .accessibilityIdentifier(ViewID.settingsField("shortcut-filter").identifier)
            }
            .padding(.horizontal, K.searchInset.value)
            .frame(height: K.searchHeight.value)
            .offset(y: -0.5)
            CardDivider(inset: 0)
            ScrollView {
                // Not lazy: every row's key cap exists, so the control socket and tests can find any of them.
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(ShortcutsPane.sections(shown, filter: filter), id: \.title) { section in
                        Text(section.title).font(.system(size: K.headerSize.value, weight: .semibold)).foregroundStyle(Color.primary.opacity(K.inkOpacity.value))
                            .padding(.leading, K.headerInset.value).frame(height: K.headerHeight.value).offset(y: -0.5)
                        CardDivider(inset: 0)
                        ForEach(Array(section.rows.enumerated()), id: \.element.action) { index, row in
                            if index > 0 { RowDivider() }
                            ShortcutRowView(row: row, others: rows, dispatch: dispatch)
                                .padding(.top, index == 0 ? K.firstRowTop.value : 0)
                        }
                    }
                }
                .padding(.bottom, K.listPadding.value)
            }
        }
        .background(RoundedRectangle(cornerRadius: K.boxRadius.value, style: .continuous).fill(Color(nsColor: .textBackgroundColor)))
        .clipShape(RoundedRectangle(cornerRadius: K.boxRadius.value, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: K.boxRadius.value, style: .continuous).strokeBorder(Color(nsColor: .separatorColor)))
    }

    private var side: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: K.keyGap.value) {
                KeyCapArt(glyph: .command)
                KeyCapArt(glyph: .smile)
            }
            Text(ShortcutsCopy.title).font(.system(size: K.titleSize.value, weight: .semibold)).foregroundStyle(.primary)
                .padding(.top, K.titleTop.value)
            Text(ShortcutsCopy.subtitle).font(.system(size: K.subtitleSize.value)).foregroundStyle(Color.primary.opacity(K.subtitleOpacity.value))
                .lineSpacing(K.subtitleLeading.value)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, K.subtitleTop.value)
            Spacer(minLength: 0)
            HStack(spacing: K.moreGap.value) {
                SettingsButton(title: ShortcutsCopy.resetAll, field: "shortcut-reset-all") { dispatch(.settings(.shortcuts(.resetAll))) }
                    .disabled(!rows.contains { $0.source == .userDefined })
                Menu {
                    Toggle(ShortcutsCopy.customizedOnly, isOn: $customizedOnly)
                } label: {
                    Image(nsImage: MoreCircle.image)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityIdentifier(ViewID.settingsField("shortcut-more").identifier)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    struct Section {
        let title: String
        let rows: [ShortcutRow]
    }

    /// Arc's essential shortcuts ("Learn the Essential Shortcuts").
    static let essentials: Set<ActionID> = [
        .newTab, .archiveTab, .addressBar, .copyCurrentURL, .showSidebar, .addSplitView, .showLittleArc, .newWindow,
        .reopenLastClosedTab, .pinTab, .focusNextSpace, .focusPreviousSpace, .find, .viewLibrary,
    ]

    /// The rows of Arc 1.170's menu and shortcut table that carry an `arcKeyBindingID` (docs/arc-anatomy/
    /// model-and-shortcuts.md 2.3): the actions Arc's Shortcuts pane lists (P38-e: Add Split View, Archive Tab, Blank
    /// Window, Capture Full Page, …). `ActionSpec.row` is the table's row.
    static let arcRows: Set<Int> = [
        3, 10, 11, 14, 16, 17, 18, 19, 20, 21, 22, 28, 29, 30, 31, 32, 33, 35, 36, 37, 38, 39, 45, 46, 47, 49, 53, 54, 55, 56,
        57, 58, 91, 92, 95, 96, 97, 98, 99, 101, 102, 103, 105, 106, 109, 111, 113, 114, 115, 116, 117, 118, 120, 121, 122,
        124, 128, 129, 130, 133, 134, 135, 136, 137, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 153, 154,
        155, 157, 158, 159, 160, 161, 162, 163, 168, 170, 171,
    ]

    /// "Customized Shortcuts" (the user's), then "Default Shortcuts" (the actions Arc's pane lists), then "More
    /// Shortcuts" (Brk's other remappable actions, after Arc's list), each by title as Arc sorts them ("Capture Full
    /// Page", "Capture in Portrait Mode", "Capture…"); rows whose title or shortcut does not match `filter` are left
    /// out.
    static func sections(_ rows: [ShortcutRow], filter: String) -> [Section] {
        let needle = filter.trimmingCharacters(in: .whitespaces).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
        let shown = rows.filter { row in
            guard !needle.isEmpty else { return true }
            let title = ShortcutsCopy.title(of: row).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            return title.contains(needle) || ShortcutsCopy.chord(row.state).map { $0.lowercased().contains(needle) } == true
        }
        func byTitle(_ list: [ShortcutRow]) -> [ShortcutRow] {
            list.sorted { ShortcutsCopy.title(of: $0).compare(ShortcutsCopy.title(of: $1), options: [.caseInsensitive]) == .orderedAscending }
        }
        var sections: [Section] = []
        let custom = shown.filter { $0.source == .userDefined }
        if !custom.isEmpty { sections.append(Section(title: ShortcutsCopy.customized, rows: byTitle(custom))) }
        let defaults = shown.filter { $0.source == .default && arcRows.contains($0.action.spec.row) }
        if !defaults.isEmpty { sections.append(Section(title: ShortcutsCopy.defaults, rows: byTitle(defaults))) }
        let more = shown.filter { $0.source == .default && !arcRows.contains($0.action.spec.row) }
        if !more.isEmpty { sections.append(Section(title: ShortcutsCopy.more, rows: byTitle(more))) }
        return sections
    }
}

/// The hairline between two shortcut rows: from the titles' left edge to 16 points short of the box's right edge.
private struct RowDivider: View {
    var body: some View {
        Rectangle().fill(SettingsStyle.cardBorder).frame(height: CardMetrics.borderWidth.value)
            .padding(.leading, K.rowInset.value).padding(.trailing, K.dividerTrailing.value)
    }
}

/// One shortcut: title, the conflict or system note, the menu on hover, the key cap.
struct ShortcutRowView: View {
    let row: ShortcutRow
    let others: [ShortcutRow]
    let dispatch: Dispatch
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .center, spacing: ShortcutsPaneMetrics.controlSpacing.value) {
            VStack(alignment: .leading, spacing: ShortcutsPaneMetrics.lineSpacing.value) {
                // A later wave's action is remappable already; its title is dimmed like its menu item.
                Text(ShortcutsCopy.title(of: row)).font(SettingsStyle.font).foregroundStyle(row.action.spec.later == nil ? .primary : .secondary)
                if let note = ShortcutsCopy.conflict(row, among: others) {
                    Label(note, systemImage: "exclamationmark.circle.fill").font(.caption).foregroundStyle(.orange)
                } else if case .valid(let chord) = row.state, KeyBindings.isSystemShortcut(chord) {
                    Label(ShortcutsCopy.systemNote, systemImage: "exclamationmark.circle.fill").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: ShortcutsPaneMetrics.controlSpacing.value)
            menu.opacity(hovering ? 1 : 0)
            ChordRecorder(state: row.state, identifier: ViewID.settingsField("shortcut-\(row.action.rawValue)").identifier) { chord in
                dispatch(.settings(.shortcuts(.setChord(row.action, chord))))
            }
                .frame(width: ShortcutsPaneMetrics.recorderSize.value.width, height: ShortcutsPaneMetrics.recorderSize.value.height)
                .accessibilityIdentifier(ViewID.settingsField("shortcut-\(row.action.rawValue)").identifier)
        }
        .padding(.horizontal, K.rowInset.value)
        .frame(minHeight: K.rowHeight.value)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }

    private var menu: some View {
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
}

/// The shortcut field: shows the chord ("⌘T"), and records a new one after a click. While it records, every key-down
/// in the app comes here first (a local event monitor), so Command chords never reach the menu and Ctrl+Tab never
/// moves the focus. Esc cancels; Delete removes the shortcut; a key the table cannot name, or a plain key without
/// ⌘, ⌃ or ⌥ (F12 aside), is refused with a note and the recording goes on. Conflicts are recorded: they are a state
/// the row then shows, as in Arc.
struct ChordRecorder: NSViewRepresentable {
    let state: KeyBindingState
    /// The key cap's own accessibility identifier (`settings.field.shortcut-<action>`), so the AppKit view itself, not
    /// only SwiftUI's wrapper, can be found and clicked.
    var identifier: String? = nil
    let record: @MainActor (KeyChord?) -> Void

    func makeNSView(context: NSViewRepresentableContext<ChordRecorder>) -> ChordRecorderView { ChordRecorderView() }

    func updateNSView(_ view: ChordRecorderView, context: NSViewRepresentableContext<ChordRecorder>) {
        view.state = state
        view.record = record
        if let identifier, view.accessibilityIdentifier() != identifier { view.setAccessibilityIdentifier(identifier) }
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
        label.cell?.truncatesLastVisibleLine = true
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

    /// Arc's key cap: the chord, "---" when there is none; the accessibility label spells out what the cap means.
    private func refresh() {
        let text: String, spoken: String
        if isRecording {
            text = note ?? ShortcutsCopy.recording
            spoken = text
        } else {
            text = ShortcutsCopy.chord(state) ?? ShortcutsCopy.unsetCap
            spoken = ShortcutsCopy.chord(state) ?? ShortcutsCopy.record
        }
        label.stringValue = text
        // Arc's key caps (P38-e): a 12 pt chord, a shade lighter than the row titles.
        label.font = .systemFont(ofSize: isRecording ? NSFont.smallSystemFontSize : ShortcutsPaneMetrics.capFont.value)
        label.textColor = isRecording ? .secondaryLabelColor : .labelColor.withAlphaComponent(ShortcutsPaneMetrics.capOpacity.value)
        layer?.borderColor = (isRecording ? NSColor.controlAccentColor : NSColor.separatorColor).cgColor
        layer?.borderWidth = isRecording ? 2 * ShortcutsPaneMetrics.recorderBorder.value : ShortcutsPaneMetrics.recorderBorder.value
        layer?.backgroundColor = NSColor.textBackgroundColor.cgColor
        toolTip = isRecording ? text : nil
        setAccessibilityLabel(spoken)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }
}

/// Arc's Shortcuts pane copy (anatomy-m 4.2 and the strings next to `ShortcutsPane.swift` in Arc's binary); "Arc"
/// is the product name. GUESS marks the short labels Arc keeps in code.
enum ShortcutsCopy {
    static let title = "Custom Shortcuts"
    static let subtitle = "Change shortcuts for your favorite actions, and even choose whether \(Product.name) or a website takes priority."
    static let customized = "Customized Shortcuts"
    static let defaults = "Default Shortcuts"
    /// Brk's: the remappable actions Arc's pane does not list.
    static let more = "More Shortcuts"
    static let resetAll = "Reset All Shortcuts"
    static let resetOne = "Reset Shortcut to Default"
    static let removeConflicting = "Remove Conflicting Shortcut"
    static let removeConflictingMany = "Remove Conflicting Shortcuts"
    static let systemNote = "System shortcuts may take priority over this shortcut"
    /// GUESS: the string for "Menu item to remove a shortcut, i.e. unset it" did not survive.
    static let remove = "Remove Shortcut"
    /// GUESS labels.
    static let filter = "Type a feature name or shortcut (like “Command Bar” or ⌘T)"
    static let record = "Record Shortcut"
    static let recording = "Type Shortcut…"
    /// Observed (P38-e): an unset shortcut's key cap.
    static let unsetCap = "---"
    /// Observed (P38-e).
    static let basics = "Start with the basics"
    static let learnEssentials = "Learn the Essential Shortcuts"
    static let showAll = "Show All Shortcuts"
    static let customizedOnly = "Show Customized Shortcuts Only"
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

/// The pane's numbers, measured on Arc 1.170's capture (verify/visual-pairs/run-20261103/P38/P38-e-arc.png).
let ShortcutsPaneMetrics = ShortcutsPaneMetricsTable()

private var K: ShortcutsPaneMetricsTable { ShortcutsPaneMetrics }

struct ShortcutsPaneMetricsTable: MetricGroup {
    private static let capture = "verify/visual-pairs/run-20261103/P38/P38-e-arc.png"
    let recorderSize = Metric(CGSize(width: 64, height: 24), .anatomy("\(capture): the key caps span x 632 to 760 px, y 530 to 578 px"))
    let recorderRadius = Metric(6.0, .guess("the key cap's corner"))
    let capOpacity = Metric(0.6, .anatomy("\(capture): a chord and '---' are #858585 at their darkest"))
    let capFont = Metric(12.0, .anatomy("\(capture): ⌃⇧= spans x 668 to 723 px, 17 px tall, a 12 pt line"))
    let recorderBorder = Metric(1.0, .anatomy("\(capture): a 2 px grey edge"))
    let sectionSpacing = Metric(12.0, .guess("space between the pane's header, filter row and sections"))
    let controlSpacing = Metric(8.0, .guess("space between a row's title, menu and key cap"))
    let lineSpacing = Metric(4.0, .guess("space between a title and its note"))
    let rowPadding = Metric(2.0, .guess("the key cap's text inset; ⌃Space needs 58 of the 64 pt key cap"))
    let basicsHeight = Metric(36.0, .anatomy("\(capture): the basics box spans y 216 to 288 px"))
    let basicsPadding = Metric(16.0, .anatomy("\(capture): its text starts at x 336 px in a box that starts at 304 px"))
    let basicsGap = Metric(8.5, .anatomy("\(capture): the text ends near x 584 px, the button starts at 601 px"))
    let basicsRadius = Metric(8.0, .guess("the basics box's corner"))
    let basicsToColumns = Metric(30.0, .anatomy("\(capture): the basics box ends at y 288 px, the list at 348 px"))
    let columnGap = Metric(16.0, .anatomy("\(capture): the list ends at x 808 px, the drawing starts at 840 px"))
    let listWidth = Metric(340.0, .anatomy("\(capture): the list spans x 128 to 808 px"))
    let listBottom = Metric(27.0, .anatomy("\(capture): the list ends at y 1246 px of 1300"))
    let listMinHeight = Metric(200.0, .guess("the list's height on a short screen"))
    let boxRadius = Metric(8.0, .guess("the list box's corner"))
    let searchHeight = Metric(41.0, .anatomy("\(capture): the search row spans y 348 to 430 px"))
    let searchInset = Metric(16.0, .anatomy("\(capture): the magnifier starts at x 162 px"))
    let searchGap = Metric(4.0, .anatomy("\(capture): the magnifier ends near x 188 px, the placeholder starts at 201 px"))
    let searchGlyph = Metric(13.0, .anatomy("\(capture): the magnifier is about 26 px tall, a medium weight"))
    let headerHeight = Metric(27.0, .anatomy("\(capture): the Default Shortcuts row spans y 430 to 484 px, its hairline 484 to 486 px"))
    let headerSize = Metric(11.0, .anatomy("\(capture): 'Default Shortcuts' spans x 162 to 345 px, an 11 pt semibold line (13 pt is 223 px)"))
    let firstRowTop = Metric(9.5, .anatomy("\(capture): the first row spans y 486 to 600 px, the others 94 px between hairlines"))
    let headerInset = Metric(16.0, .anatomy("\(capture): 'Default Shortcuts' starts at x 160 px"))
    let rowHeight = Metric(47.0, .anatomy("\(capture): hairlines at y 600, 696, 792 px, 2 px each"))
    let rowInset = Metric(24.0, .anatomy("\(capture): titles start at x 176 px, hairlines span 176 to 776 px, key caps end at 760 px"))
    let dividerTrailing = Metric(16.0, .anatomy("\(capture): the row hairlines end at x 776 px in a box that ends at 808 px"))
    let listPadding = Metric(8.0, .guess("space under the last row"))
    let keyGap = Metric(1.5, .anatomy("\(capture): the first key cap ends at x 970 px, the second starts at 974 px"))
    let titleSize = Metric(14.0, .anatomy("\(capture): 'Custom Shortcuts' spans x 841 to 1083 px, a 14 pt semibold line"))
    let titleTop = Metric(23.0, .anatomy("\(capture): the key caps end at y 477 px, the heading is centred at 542 px"))
    let subtitleSize = Metric(12.0, .anatomy("\(capture): 'Change shortcuts for your favorite' spans x 841 to 1226 px, a 12 pt line"))
    let subtitleTop = Metric(7.0, .anatomy("\(capture): the heading centred at y 542 px, the paragraph's first line at 590 px"))
    let subtitleLeading = Metric(0.0, .anatomy("\(capture): paragraph lines 30 px apart, a 12 pt line's own height"))
    let subtitleOpacity = Metric(0.55, .anatomy("\(capture): the side paragraph is #8F8F8F at its darkest"))
    let inkOpacity = Metric(0.6, .anatomy("\(capture): 'Default Shortcuts' and the side paragraph are darker than the pane's grey descriptions"))
    let essentialsWidth = Metric(215.5, .anatomy("\(capture): Learn the Essential Shortcuts spans x 601 to 1032 px"))
    let moreGap = Metric(1.0, .anatomy("\(capture): Reset All Shortcuts ends at x 1118 px, the … circle starts at 1127 px"))
}
