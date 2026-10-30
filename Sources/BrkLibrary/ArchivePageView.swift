import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// Owner: F5 (written by W4, moved from BrkOverlays). The Library's archive page, in the content area beside the
/// Library panel. Groups by bucket (`ArchiveSnapshot.groups`, in the projection's order), each entry with favicon,
/// title, display URL, when, why and from which space, and a restore button (`.archive(.restore(id))`). A local
/// filter field narrows the list; the auto-archive threshold picker dispatches `.settings(.autoArchive(t))`; Clear
/// Archive asks inline first ("Are you sure you'd like to Clear Archive?": the same button confirms, Cancel backs
/// out) and then dispatches `.archive(.clear)`. Esc in an empty filter closes the Library; the panel's exit button
/// does too.
@MainActor
final class ArchivePageView: NSView, NSSearchFieldDelegate {
    let dispatch: Dispatch
    /// Time zone of the "3:05 PM" style times.
    var timeZone = TimeZone.current
    let filterField = NSSearchField()
    let thresholdMenu = NSPopUpButton()
    let clearButton = NSButton()
    let cancelClearButton = NSButton()
    private let title = NSTextField(labelWithString: LibraryCopy.title(.archive))
    private let thresholdLabel = NSTextField(labelWithString: LibraryCopy.archiveThreshold)
    private let confirmText = NSTextField(labelWithString: Copy.clearArchiveConfirm)
    private let scroll = NSScrollView()
    private let list = FlippedView()
    private let emptyLabel = NSTextField(wrappingLabelWithString: "")
    private var archive: ArchiveSnapshot?
    private var scheme: Scheme?
    private var colors = LibraryColors.of(.light)
    private var confirming = false

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        isHidden = true
        identify(.archive)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = Metrics.content.cornerRadius.value
        layer?.masksToBounds = true
        let a = LibraryDraw.archive
        title.font = .systemFont(ofSize: a.titleFontSize.value, weight: .bold)
        filterField.placeholderString = LibraryCopy.archiveFilter
        filterField.setAccessibilityLabel(LibraryCopy.archiveFilter)
        filterField.delegate = self
        filterField.sendsSearchStringImmediately = true
        thresholdLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        thresholdMenu.identify(.archiveThreshold)
        thresholdMenu.controlSize = .small
        thresholdMenu.addItems(withTitles: AutoArchiveThreshold.allCases.map(LibraryCopy.threshold))
        thresholdMenu.target = self
        thresholdMenu.action = #selector(thresholdChosen)
        clearButton.identify(.archiveClear)
        clearButton.title = LibraryCopy.clearArchive
        clearButton.controlSize = .small
        clearButton.bezelStyle = .push
        clearButton.target = self
        clearButton.action = #selector(clearClicked)
        cancelClearButton.title = LibraryCopy.cancel
        cancelClearButton.controlSize = .small
        cancelClearButton.bezelStyle = .push
        cancelClearButton.target = self
        cancelClearButton.action = #selector(cancelClearClicked)
        confirmText.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        emptyLabel.alignment = .center
        emptyLabel.font = .systemFont(ofSize: LibraryDraw.archive.entryTitleFontSize.value)
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.documentView = list
        for view in [title, filterField, thresholdLabel, thresholdMenu, confirmText, cancelClearButton, clearButton, scroll, emptyLabel] {
            addSubview(view)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func hide() {
        isHidden = true
        archive = nil
    }

    /// Shows `archive` in `frame` (the Library's page area, in the Library view's coordinates). A new opening clears
    /// the filter and any pending Clear question; the same opening keeps them and the scroll position.
    func show(_ archive: ArchiveSnapshot, in frame: CGRect, scheme: Scheme) {
        let reopened = archive.openID != self.archive?.openID
        guard reopened || isHidden || archive != self.archive || frame != self.frame || scheme != self.scheme else { return }
        // A new frame alone (a window resize) lays the list out again without rebuilding it.
        let rebuilds = reopened || isHidden || archive != self.archive || scheme != self.scheme
        if reopened {
            filterField.stringValue = ""
            confirming = false
        }
        self.archive = archive
        self.frame = frame
        isHidden = false
        if scheme != self.scheme { applyColors(scheme) }
        thresholdMenu.selectItem(at: AutoArchiveThreshold.allCases.firstIndex(of: archive.threshold) ?? 0)
        if archive.groups.isEmpty { confirming = false }
        clearButton.isEnabled = !archive.groups.isEmpty
        if rebuilds { rebuildList() }
        layoutPage()
    }

    // MARK: Controls

    @objc private func thresholdChosen() {
        let index = thresholdMenu.indexOfSelectedItem
        guard AutoArchiveThreshold.allCases.indices.contains(index) else { return }
        let chosen = AutoArchiveThreshold.allCases[index]
        if chosen != archive?.threshold { dispatch(.settings(.autoArchive(chosen))) }
    }

    @objc private func clearClicked() {
        if confirming {
            setConfirming(false)
            dispatch(.archive(.clear))
        } else {
            setConfirming(true)
        }
    }

    @objc private func cancelClearClicked() { setConfirming(false) }

    private func setConfirming(_ value: Bool) {
        confirming = value
        layoutPage()
    }

    func controlTextDidChange(_ notification: Notification) {
        rebuildList()
        layoutPage()
    }

    /// Esc in the filter clears it first, then closes the Library.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)), filterField.stringValue.isEmpty else { return false }
        dispatch(.library(.close))
        return true
    }

    // MARK: List

    /// Entries whose title, URL or space contains the filter text (case- and diacritic-insensitive); groups left
    /// empty by the filter disappear.
    private var shownGroups: [(bucket: ArchiveBucket, entries: [ArchiveEntry])] {
        guard let archive else { return [] }
        let needle = filterField.stringValue.trimmingCharacters(in: .whitespaces)
        func matches(_ entry: ArchiveEntry) -> Bool {
            let texts = [entry.title, entry.url.map { displayURL($0) } ?? "", entry.fromSpaceTitle ?? ""]
            return texts.contains { $0.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        return archive.groups.compactMap { group in
            let entries = needle.isEmpty ? group.entries : group.entries.filter(matches)
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
        let a = LibraryDraw.archive
        let column = min(bounds.width - 2 * a.padding.value, a.columnMaxWidth.value)
        let left = ((bounds.width - column) / 2).rounded()
        var y = a.padding.value
        let titleHeight = title.intrinsicContentSize.height
        title.frame = CGRect(x: left, y: y + (a.headerHeight.value - titleHeight) / 2, width: column, height: titleHeight)
        y += a.headerHeight.value + a.gap.value

        // Toolbar: filter on the left; the threshold picker, or the Clear question, then Clear on the right.
        let row = a.toolbarHeight.value
        func place(_ view: NSView, right: inout CGFloat) {
            let size = view.fittingSize
            view.frame = CGRect(x: right - size.width, y: y + ((row - size.height) / 2).rounded(), width: size.width, height: size.height)
            right = view.frame.minX - a.gap.value / 2
        }
        filterField.frame = CGRect(x: left, y: y + ((row - filterField.fittingSize.height) / 2).rounded(), width: min(a.filterWidth.value, column / 2),
                                   height: filterField.fittingSize.height)
        var right: CGFloat = left + column
        clearButton.hasDestructiveAction = confirming
        clearButton.bezelColor = confirming ? .systemRed : nil
        place(clearButton, right: &right)
        for view in [confirmText, cancelClearButton] as [NSView] { view.isHidden = !confirming }
        for view in [thresholdLabel, thresholdMenu] as [NSView] { view.isHidden = confirming }
        if confirming {
            place(cancelClearButton, right: &right)
            place(confirmText, right: &right)
        } else {
            place(thresholdMenu, right: &right)
            place(thresholdLabel, right: &right)
        }
        y += row + a.gap.value

        scroll.frame = CGRect(x: 0, y: y, width: bounds.width, height: max(0, bounds.height - y))
        var listY: CGFloat = 0
        for case let section as ArchiveGroupView in list.subviews {
            section.frame = CGRect(x: left, y: listY, width: column, height: section.height)
            listY += section.height + a.gap.value
        }
        list.frame = CGRect(x: 0, y: 0, width: scroll.contentSize.width, height: max(listY + a.padding.value, scroll.contentSize.height))
        let emptyHeight = emptyLabel.fittingSize.height
        emptyLabel.frame = CGRect(x: left, y: y + a.padding.value, width: column, height: emptyHeight)
    }

    private func applyColors(_ scheme: Scheme) {
        self.scheme = scheme
        colors = LibraryColors.of(scheme)
        appearance = .library(scheme)
        layer?.backgroundColor = colors.page.cgColor
        title.textColor = colors.foregroundPrimary
        thresholdLabel.textColor = colors.foregroundSecondary
        confirmText.textColor = colors.foregroundPrimary
        emptyLabel.textColor = colors.foregroundSecondary
    }
}

/// One bucket: its header and entries, identified as `archive-group-<bucket>` so an entry is inside its group's frame.
@MainActor
final class ArchiveGroupView: NSView {
    let height: CGFloat

    init(bucket: ArchiveBucket, entries: [ArchiveEntry], formatter: ArchiveTime, colors: LibraryColors, restore: @escaping (ArchiveID) -> Void) {
        let a = LibraryDraw.archive
        height = a.groupHeaderHeight.value + CGFloat(entries.count) * a.entryHeight.value
        super.init(frame: .zero)
        identify(.archiveGroup(bucket))
        let header = NSTextField(labelWithString: LibraryCopy.bucket(bucket))
        header.font = .systemFont(ofSize: a.groupFontSize.value, weight: .semibold)
        header.textColor = colors.foregroundSecondary
        addSubview(header)
        for entry in entries {
            addSubview(ArchiveEntryView(entry: entry, bucket: bucket, formatter: formatter, colors: colors, restore: restore))
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let a = LibraryDraw.archive
        var y = a.groupHeaderHeight.value
        for view in subviews {
            if let entry = view as? ArchiveEntryView {
                entry.frame = CGRect(x: 0, y: y, width: bounds.width, height: a.entryHeight.value)
                y += a.entryHeight.value
            } else {
                let h = view.fittingSize.height
                view.frame = CGRect(x: 0, y: a.groupHeaderHeight.value - h - a.gap.value / 2, width: bounds.width, height: h)
            }
        }
    }
}

/// One archived tab: favicon, title over display URL, "when · why · space", Restore.
@MainActor
final class ArchiveEntryView: NSView {
    private let icon = NSImageView()
    private let title: NSTextField
    private let url: NSTextField
    private let meta: NSTextField
    private let restoreButton = NSButton()
    private let colors: LibraryColors
    private let onRestore: () -> Void

    init(entry: ArchiveEntry, bucket: ArchiveBucket, formatter: ArchiveTime, colors: LibraryColors, restore: @escaping (ArchiveID) -> Void) {
        let a = LibraryDraw.archive
        self.colors = colors
        onRestore = { restore(entry.id) }
        title = NSTextField(labelWithString: entry.title)
        url = NSTextField(labelWithString: entry.url.map(displayURL) ?? "")
        meta = NSTextField(labelWithString: [formatter.text(entry.archivedAt, in: bucket), LibraryCopy.reason(entry.reason), entry.fromSpaceTitle]
            .compactMap { $0 }.joined(separator: " · "))
        super.init(frame: .zero)
        identify(.archiveEntry(entry.id))
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = a.entryCornerRadius.value
        title.font = .systemFont(ofSize: a.entryTitleFontSize.value, weight: .medium)
        title.textColor = colors.foregroundPrimary
        title.lineBreakMode = .byTruncatingTail
        url.font = .systemFont(ofSize: a.entryDetailFontSize.value)
        url.textColor = colors.foregroundSecondary
        url.lineBreakMode = .byTruncatingTail
        meta.font = .systemFont(ofSize: a.entryDetailFontSize.value)
        meta.textColor = colors.foregroundSecondary
        meta.alignment = .right
        let globe = NSImage(systemSymbolName: "globe", accessibilityDescription: nil)
        icon.contentTintColor = colors.foregroundTertiary
        icon.image = entry.favicon.flatMap { url in
            FaviconCache.shared.image(for: url) { [weak self] image in self?.icon.image = image }
        } ?? globe
        restoreButton.identify(.archiveRestore(entry.id))
        restoreButton.title = LibraryCopy.restore
        restoreButton.controlSize = .small
        restoreButton.bezelStyle = .push
        restoreButton.target = self
        restoreButton.action = #selector(restoreClicked)
        for view in [icon, title, url, meta, restoreButton] { addSubview(view) }
        setAccessibilityLabel(entry.title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    @objc private func restoreClicked() { onRestore() }

    override func layout() {
        super.layout()
        let a = LibraryDraw.archive
        let inset = a.gap.value / 2
        let side = a.faviconSize.value
        icon.frame = CGRect(x: inset, y: ((bounds.height - side) / 2).rounded(), width: side, height: side)
        let button = restoreButton.fittingSize
        restoreButton.frame = CGRect(x: bounds.width - inset - button.width, y: ((bounds.height - button.height) / 2).rounded(),
                                     width: button.width, height: button.height)
        let metaWidth = ceil(meta.fittingSize.width)
        let metaHeight = meta.fittingSize.height
        meta.frame = CGRect(x: restoreButton.frame.minX - a.gap.value - metaWidth, y: ((bounds.height - metaHeight) / 2).rounded(),
                            width: metaWidth, height: metaHeight)
        let x = icon.frame.maxX + a.gap.value
        let width = max(0, meta.frame.minX - a.gap.value - x)
        let titleHeight = title.fittingSize.height, urlHeight = url.fittingSize.height
        let top = ((bounds.height - titleHeight - urlHeight) / 2).rounded()
        title.frame = CGRect(x: x, y: top, width: width, height: titleHeight)
        url.frame = CGRect(x: x, y: top + titleHeight, width: width, height: urlHeight)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { layer?.backgroundColor = colors.rowHighlight.cgColor }
    override func mouseExited(with event: NSEvent) { layer?.backgroundColor = nil }
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
