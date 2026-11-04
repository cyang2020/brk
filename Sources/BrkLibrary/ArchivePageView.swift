import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// Owner: F5 (written by W4, moved from BrkOverlays). The Library's Archived Tabs page in the panel's page column
/// (P32-e): "Search Archive…" and Filter across the top, then the buckets (`ArchiveSnapshot.groups`, in the
/// projection's order) with Arc's two-line rows: a favicon tile, the title and the grey address. A click on a row
/// restores it (`.archive(.restore(id))`), as does its Restore button while hovered and its context menu, which also
/// says when, why and from which space it was archived (the row's tooltip too). The search narrows the list; the
/// Filter menu narrows it by how the tab closed, sets the auto-archive threshold (`.settings(.autoArchive(t))`) and
/// clears the archive, which asks inline first ("Are you sure you'd like to Clear Archive?": the bar's Clear Archive
/// confirms, Cancel backs out) and then dispatches `.archive(.clear)`. Esc in an empty search closes the Library.
@MainActor
final class ArchivePageView: NSView {
    let dispatch: Dispatch
    /// Time zone of the "3:05 PM" style times.
    var timeZone = TimeZone.current
    let filterField = LibrarySearchField(placeholder: LibraryCopy.search(.archive))
    let filterButton = LibraryFilterButton()
    let clearButton = ArchiveConfirmationButton()
    let cancelClearButton = NSButton()
    private let confirmBar = FlippedView()
    private let confirmText = NSTextField(wrappingLabelWithString: Copy.clearArchiveConfirm)
    private let scroll = LibraryScrollView()
    private let list = FlippedView()
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")
    private var archive: ArchiveSnapshot?
    private var scheme: Scheme?
    private var colors = LibraryColors.of(.light)
    private var confirming = false
    /// The reasons the Filter menu shows (view-local, like the search): all of them until the user unticks one.
    private(set) var shownReasons: Set<ArchiveReason> = [.manual, .auto, .clearToday, .containerDeleted]

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        isHidden = true
        identify(.archive)
        filterField.field.identify(.tabTool("archive-filter"))
        filterField.onChange = { [weak self] in self?.searchChanged() }
        filterField.onEscape = { [weak self] in self?.dispatch(.library(.close)) }
        filterButton.menuProvider = { [weak self] in self?.filterMenu() ?? NSMenu() }
        filterButton.identify(.tabTool("archive-filter-menu"))
        cancelClearButton.identify(.tabTool("archive-cancel-clear"))
        confirmText.identify(.tabTool("archive-confirmation"))
        clearButton.identify(.archiveClear)
        clearButton.title = LibraryCopy.clearArchive
        clearButton.controlSize = .small
        clearButton.bezelStyle = .push
        clearButton.hasDestructiveAction = true
        clearButton.bezelColor = .systemRed
        clearButton.target = self
        clearButton.action = #selector(clearClicked)
        cancelClearButton.title = LibraryCopy.cancel
        cancelClearButton.controlSize = .small
        cancelClearButton.bezelStyle = .push
        cancelClearButton.target = self
        cancelClearButton.action = #selector(cancelClearClicked)
        confirmText.font = .systemFont(ofSize: LibraryDraw.list.detailFont.value, weight: .medium)
        confirmBar.wantsLayer = true
        confirmBar.layer?.cornerCurve = .continuous
        confirmBar.layer?.cornerRadius = LibraryDraw.column.searchRadius.value
        for view in [confirmText, cancelClearButton, clearButton] as [NSView] { confirmBar.addSubview(view) }
        emptyLabel.alignment = .center
        emptyLabel.font = .systemFont(ofSize: LibraryDraw.list.titleFont.value)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = list
        for view in [filterField, filterButton, scroll, emptyLabel, confirmBar] as [NSView] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func hide() {
        isHidden = true
        archive = nil
    }

    /// Shows `archive` in `frame` (the Library's page column, in the Library view's coordinates). A new opening clears
    /// the search, the reason filter and any pending Clear question; the same opening keeps them and the scroll
    /// position.
    func show(_ archive: ArchiveSnapshot, in frame: CGRect, scheme: Scheme) {
        let reopened = archive.openID != self.archive?.openID
        guard reopened || isHidden || archive != self.archive || frame != self.frame || scheme != self.scheme else { return }
        // A new frame alone (a window resize) lays the list out again without rebuilding it.
        let rebuilds = reopened || isHidden || archive != self.archive || scheme != self.scheme
        if reopened {
            filterField.stringValue = ""
            shownReasons = [.manual, .auto, .clearToday, .containerDeleted]
            confirming = false
        }
        self.archive = archive
        self.frame = frame
        isHidden = false
        if scheme != self.scheme { applyColors(scheme) }
        if archive.groups.isEmpty { confirming = false }
        clearButton.isEnabled = !archive.groups.isEmpty
        if rebuilds { rebuildList() }
        layoutPage()
    }

    // MARK: Controls

    /// How the tab closed (Arc's "How was the tab closed?"), the threshold, Clear Archive.
    func filterMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let header = NSMenuItem(title: LibraryCopy.closedHow, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        for reason in [ArchiveReason.auto, .manual, .clearToday, .containerDeleted] {
            menu.addItem(LibraryFilterButton.item(LibraryCopy.reason(reason), checked: shownReasons.contains(reason)) { [weak self] in
                self?.toggle(reason)
            })
        }
        menu.addItem(.separator())
        let thresholds = NSMenu()
        thresholds.autoenablesItems = false
        for threshold in AutoArchiveThreshold.allCases {
            thresholds.addItem(LibraryFilterButton.item(LibraryCopy.threshold(threshold), checked: threshold == archive?.threshold) { [weak self] in
                self?.choose(threshold)
            })
        }
        let after = NSMenuItem(title: LibraryCopy.archiveThreshold, action: nil, keyEquivalent: "")
        after.submenu = thresholds
        menu.addItem(after)
        menu.addItem(.separator())
        menu.addItem(LibraryFilterButton.item(LibraryCopy.clearArchive + "…", enabled: archive?.groups.isEmpty == false) { [weak self] in
            self?.beginClearConfirmation()
        })
        return menu
    }

    func choose(_ threshold: AutoArchiveThreshold) {
        if threshold != archive?.threshold { dispatch(.settings(.autoArchive(threshold))) }
    }

    func toggle(_ reason: ArchiveReason) {
        if shownReasons.contains(reason) { shownReasons.remove(reason) } else { shownReasons.insert(reason) }
        rebuildList()
        layoutPage()
    }

    func beginClearConfirmation() {
        guard !isHidden, archive?.groups.isEmpty == false else { return }
        setConfirming(true)
    }

    @objc private func clearClicked() {
        guard confirming else { return }
        setConfirming(false)
        dispatch(.archive(.clear))
    }

    @objc private func cancelClearClicked() { setConfirming(false) }

    private func setConfirming(_ value: Bool) {
        confirming = value
        layoutPage()
    }

    func searchChanged() {
        rebuildList()
        layoutPage()
    }

    // MARK: List

    /// Entries whose title, URL or space contains the search text (case- and diacritic-insensitive) and whose reason
    /// the Filter menu shows; groups left empty disappear.
    private var shownGroups: [(bucket: ArchiveBucket, entries: [ArchiveEntry])] {
        guard let archive else { return [] }
        let needle = filterField.stringValue.trimmingCharacters(in: .whitespaces)
        func matches(_ entry: ArchiveEntry) -> Bool {
            guard shownReasons.contains(entry.reason) else { return false }
            guard !needle.isEmpty else { return true }
            let texts = [entry.title, entry.url.map { displayURL($0) } ?? "", entry.fromSpaceTitle ?? ""]
            return texts.contains { $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        return archive.groups.compactMap { group in
            let entries = group.entries.filter(matches)
            return entries.isEmpty ? nil : (group.bucket, entries)
        }
    }

    private func rebuildList() {
        list.subviews.forEach { $0.removeFromSuperview() }
        let groups = shownGroups
        let formatter = ArchiveTime(timeZone: timeZone)
        for group in groups {
            let section = ArchiveGroupView(bucket: group.bucket, entries: group.entries, formatter: formatter, colors: colors) { [weak self] id in
                self?.dispatch(.archive(.restore(id)))
            }
            list.addSubview(section)
        }
        let hasEntries = !(archive?.groups.isEmpty ?? true)
        emptyLabel.stringValue = hasEntries ? LibraryCopy.noMatch : Copy.archiveEmpty
        emptyLabel.isHidden = !groups.isEmpty
    }

    private func layoutPage() {
        let m = LibraryDraw.list, pad = Metrics.library.columnPadding.value
        let top = LibraryColumnLayout.top(in: bounds, filter: true)
        filterField.frame = top.search
        filterButton.frame = top.filter ?? .zero
        var y = m.listTop.value
        // The Clear question, under the search field while it is asked.
        confirmBar.isHidden = !confirming
        if confirming {
            let width = max(0, bounds.width - 2 * pad), inner = width - 2 * pad
            confirmText.preferredMaxLayoutWidth = inner
            let textHeight = confirmText.fittingSize.height
            let cancel = cancelClearButton.fittingSize, clear = clearButton.fittingSize
            let height = pad + textHeight + pad / 2 + clear.height + pad
            confirmBar.frame = CGRect(x: pad, y: y + pad / 2, width: width, height: height)
            confirmText.frame = CGRect(x: pad, y: pad, width: inner, height: textHeight)
            clearButton.frame = CGRect(x: width - pad - clear.width, y: confirmText.frame.maxY + pad / 2, width: clear.width, height: clear.height)
            cancelClearButton.frame = CGRect(x: clearButton.frame.minX - pad / 2 - cancel.width, y: clearButton.frame.minY,
                                             width: cancel.width, height: cancel.height)
            y = confirmBar.frame.maxY + pad / 2
        }
        scroll.frame = CGRect(x: 0, y: y, width: bounds.width, height: max(0, bounds.height - y))
        var listY: CGFloat = 0
        for case let section as ArchiveGroupView in list.subviews {
            section.frame = CGRect(x: m.rowLeading.value, y: listY, width: max(0, bounds.width - 2 * m.rowLeading.value), height: section.height)
            listY += section.height
        }
        list.frame = CGRect(x: 0, y: 0, width: scroll.contentSize.width, height: max(listY + pad, scroll.contentSize.height))
        let column = max(0, min(bounds.width - 4 * pad, m.emptyWidth.value))
        emptyLabel.preferredMaxLayoutWidth = column
        let emptyHeight = emptyLabel.fittingSize.height
        emptyLabel.frame = CGRect(x: ((bounds.width - column) / 2).rounded(), y: (y + (bounds.height - y - emptyHeight) / 2).rounded(),
                                  width: column, height: emptyHeight)
    }

    private func applyColors(_ scheme: Scheme) {
        self.scheme = scheme
        colors = LibraryColors.of(scheme)
        appearance = .library(scheme)
        filterField.apply(colors)
        filterButton.apply(colors)
        confirmBar.layer?.backgroundColor = colors.control.cgColor
        confirmText.textColor = colors.foregroundPrimary
        emptyLabel.textColor = colors.foregroundSecondary
    }
}

/// One bucket: its header and entries, identified as `archive-group-<bucket>` so an entry is inside its group's frame.
@MainActor
final class ArchiveGroupView: NSView {
    let height: CGFloat

    init(bucket: ArchiveBucket, entries: [ArchiveEntry], formatter: ArchiveTime, colors: LibraryColors, restore: @escaping (ArchiveID) -> Void) {
        let m = LibraryDraw.list
        height = m.dayHeaderHeight.value + CGFloat(entries.count) * m.rowPitch.value
        super.init(frame: .zero)
        identify(.archiveGroup(bucket))
        addSubview(DayHeaderView(LibraryCopy.bucket(bucket), colors: colors))
        for entry in entries {
            addSubview(ArchiveEntryView(entry: entry, bucket: bucket, formatter: formatter, colors: colors, restore: restore))
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let m = LibraryDraw.list
        var y = m.dayHeaderHeight.value
        for view in subviews {
            if let entry = view as? ArchiveEntryView {
                entry.frame = CGRect(x: 0, y: y, width: bounds.width, height: m.rowPitch.value)
                y += m.rowPitch.value
            } else {
                view.frame = CGRect(x: 0, y: 0, width: bounds.width, height: m.dayHeaderHeight.value)
            }
        }
    }
}

/// One archived tab (P32-e): a favicon tile, the title over the grey address. Hovered, a Restore button shows at the
/// right; the tooltip and the context menu say when, why and from which space it was archived.
@MainActor
final class ArchiveEntryView: NSView {
    private let icon = LibraryTileView()
    private let title: NSTextField
    private let url: NSTextField
    private let restoreButton = NSButton()
    private let colors: LibraryColors
    private let onRestore: () -> Void
    /// "3:05 PM · Manually Closed · Work".
    let meta: String
    private var hovered = false

    init(entry: ArchiveEntry, bucket: ArchiveBucket, formatter: ArchiveTime, colors: LibraryColors, restore: @escaping (ArchiveID) -> Void) {
        let m = LibraryDraw.list
        self.colors = colors
        onRestore = { restore(entry.id) }
        title = NSTextField(labelWithString: entry.title)
        url = NSTextField(labelWithString: entry.url.map(ArchiveEntryView.address) ?? "")
        meta = [formatter.text(entry.archivedAt, in: bucket), LibraryCopy.reason(entry.reason), entry.fromSpaceTitle]
            .compactMap { $0 }.joined(separator: " · ")
        super.init(frame: .zero)
        identify(.archiveEntry(entry.id))
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = m.rowRadius.value
        toolTip = meta
        title.font = .systemFont(ofSize: m.titleFont.value)
        title.textColor = colors.foregroundPrimary
        title.lineBreakMode = .byTruncatingTail
        url.font = .systemFont(ofSize: m.detailFont.value)
        url.textColor = colors.foregroundSecondary
        url.lineBreakMode = .byTruncatingTail
        icon.show(favicon: entry.favicon, colors: colors)
        restoreButton.identify(.archiveRestore(entry.id))
        restoreButton.title = LibraryCopy.restore
        restoreButton.controlSize = .small
        restoreButton.bezelStyle = .push
        restoreButton.target = self
        restoreButton.action = #selector(restoreClicked)
        restoreButton.alphaValue = 0
        for view in [icon, title, url, restoreButton] { addSubview(view) }
        setAccessibilityLabel(entry.title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    var texts: [String] { [title.stringValue, url.stringValue] }

    /// The display URL with its query (P32-e: "127.0.0.1:8764/visual.html?peek=1").
    static func address(_ url: URL) -> String {
        guard let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery, !query.isEmpty else { return displayURL(url) }
        return displayURL(url) + "?" + query
    }

    @objc private func restoreClicked() { onRestore() }

    override func hitTest(_ point: NSPoint) -> NSView? { rowHit(point, buttons: [restoreButton]) }

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onRestore() }
    }

    override func menu(for event: NSEvent) -> NSMenu? { contextMenu() }

    func contextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(LibraryFilterButton.item(LibraryCopy.restore) { [weak self] in self?.onRestore() })
        menu.addItem(.separator())
        let info = NSMenuItem(title: meta, action: nil, keyEquivalent: "")
        info.isEnabled = false
        menu.addItem(info)
        return menu
    }

    override func layout() {
        super.layout()
        let m = LibraryDraw.list
        let inset = m.rowInset.value, side = m.iconTile.value
        icon.frame = CGRect(x: inset, y: ((bounds.height - side) / 2).rounded(), width: side, height: side)
        let button = restoreButton.fittingSize
        restoreButton.frame = CGRect(x: bounds.width - inset - button.width, y: ((bounds.height - button.height) / 2).rounded(),
                                     width: button.width, height: button.height)
        // A label draws its text 2 pt inside its frame; Arc's text starts 10 after the tile (P32-e), its two lines 17 apart.
        let x = icon.frame.maxX + m.iconToTitle.value - 2
        let right = hovered ? restoreButton.frame.minX - inset : bounds.width - inset
        let width = max(0, right - x)
        let titleHeight = title.fittingSize.height, urlHeight = url.fittingSize.height, gap = 1.0
        let top = ((bounds.height - titleHeight - urlHeight - gap) / 2).rounded()
        title.frame = CGRect(x: x, y: top, width: width, height: titleHeight)
        url.frame = CGRect(x: x, y: top + titleHeight + gap, width: width, height: urlHeight)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    private func setHovered(_ value: Bool) {
        hovered = value
        layer?.backgroundColor = value ? colors.rowHighlight.cgColor : nil
        restoreButton.alphaValue = value ? 1 : 0
        needsLayout = true
    }
}

/// When an entry was archived, worded for its bucket: "3:05 PM" under Today and Yesterday, "Mon 3:05 PM" under
/// Earlier This Week, "Oct 12" in the past month, "Oct 12, 2025" beyond. English like the rest of Arc's copy, so
/// the text does not change with the user's locale.
struct ArchiveTime {
    private let time: DateFormatter, weekday: DateFormatter, day: DateFormatter, dayAndYear: DateFormatter

    init(timeZone: TimeZone) {
        func formatter(_ format: String) -> DateFormatter {
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.timeZone = timeZone
            f.dateFormat = format
            return f
        }
        time = formatter("h:mm a")
        weekday = formatter("EEE h:mm a")
        day = formatter("MMM d")
        dayAndYear = formatter("MMM d, yyyy")
    }

    func text(_ instant: Instant, in bucket: ArchiveBucket) -> String {
        let date = Date(timeIntervalSince1970: Double(instant.milliseconds) / 1000)
        return switch bucket {
        case .today, .yesterday: time.string(from: date)
        case .pastWeek: weekday.string(from: date)
        case .pastMonth: day.string(from: date)
        case .beyond: dayAndYear.string(from: date)
        }
    }
}

/// The confirmation is already explicit. Accept its deliberate click in an inactive Brk window too.
@MainActor
final class ArchiveConfirmationButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
