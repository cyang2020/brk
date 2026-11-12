import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// The Boosts page (P32-f): "Search Boosts…" across the top, then one row per Boost (an icon tile, the name, the
/// site); a click edits it, the row's buttons enable or disable and remove it, the context menu also exports it.
/// Brk keeps two things Arc's page does not have (it has no Arc account's Boost gallery): New Boost and Install from
/// File… rows, and the Local Boost Gallery's presets, in the same row style under the Boosts.
@MainActor
final class BoostsPageView: NSView {
    private let dispatch: Dispatch
    let searchField = LibrarySearchField(placeholder: LibraryCopy.search(.boosts))
    private let feedback = NSTextField(wrappingLabelWithString: "")
    private let scroll = LibraryScrollView()
    private let list = FlippedView()
    private var snapshot: LibrarySnapshot?
    private var scheme: Scheme?
    private var colors = LibraryColors.of(.light)

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        isHidden = true
        identify(.boostControl("library"))
        searchField.onChange = { [weak self] in if let value = self?.snapshot { self?.rebuild(value) } }
        searchField.onEscape = { dispatch(.library(.close)) }
        feedback.font = .systemFont(ofSize: LibraryDraw.list.detailFont.value)
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.documentView = list
        for view in [searchField, feedback, scroll] as [NSView] { addSubview(view) }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    func show(_ value: LibrarySnapshot, in rect: CGRect, scheme: Scheme) {
        isHidden = false
        frame = rect
        var restyled = false
        if scheme != self.scheme {
            self.scheme = scheme
            colors = LibraryColors.of(scheme)
            appearance = .library(scheme)
            searchField.apply(colors)
            feedback.textColor = colors.foregroundSecondary
            restyled = true
        }
        feedback.stringValue = !value.canManageBoosts ? "Manage Boosts from a public window. Existing Boosts need explicit private-window permission." : value.boostMessage ?? ""
        feedback.isHidden = feedback.stringValue.isEmpty
        if restyled || snapshot?.boosts != value.boosts || snapshot?.canManageBoosts != value.canManageBoosts { rebuild(value) }
        snapshot = value
        needsLayout = true
    }

    func hide() {
        isHidden = true
        searchField.stringValue = ""
        // The rows were filtered by the text just cleared: the next show lists them again.
        snapshot = nil
    }

    private func rebuild(_ value: LibrarySnapshot) {
        list.subviews.forEach { $0.removeFromSuperview() }
        let query = searchField.stringValue.trimmingCharacters(in: .whitespaces)
        let boosts = query.isEmpty ? value.boosts : value.boosts.filter {
            [$0.name, $0.scope.label].contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
        }
        if value.boosts.isEmpty { list.addSubview(BoostSectionLabel(LibraryCopy.nothingBoosted, colors: colors, large: true)) }
        for boost in boosts {
            let id = boost.id
            var detail = boost.scope.label
            if !boost.enabled { detail += " · disabled" }
            if !boost.javascript.isEmpty && !boost.javascriptApproved { detail += " · JavaScript needs approval" }
            list.addSubview(BoostRowView(
                id: "edit-" + id, title: boost.name, detail: detail, favicon: Self.favicon(boost.scope), symbol: nil, colors: colors,
                dimmed: !boost.enabled,
                buttons: [.init(id: "toggle-" + id, symbol: boost.enabled ? "power.circle.fill" : "power.circle",
                                tooltip: boost.enabled ? "Disable" : "Enable", command: .boost(.enable(id, !boost.enabled))),
                          .init(id: "remove-" + id, symbol: "xmark", tooltip: "Remove", command: .boost(.remove(id)))],
                menu: [("Edit…", .boost(.edit(id))), (boost.enabled ? "Disable" : "Enable", .boost(.enable(id, !boost.enabled))),
                       ("Export…", .boost(.export(id))), ("Remove", .boost(.remove(id)))],
                command: .boost(.edit(id)), dispatch: dispatch))
        }
        if value.canManageBoosts {
            list.addSubview(BoostRowView(id: "new", title: LibraryCopy.newBoost, detail: "CSS previews live; JavaScript asks for permission.",
                                         favicon: nil, symbol: "plus", colors: colors, command: .boost(.create), dispatch: dispatch))
            list.addSubview(BoostRowView(id: "import", title: LibraryCopy.installFromFile, detail: "A .brkboost.json file",
                                         favicon: nil, symbol: "square.and.arrow.down", colors: colors, command: .boost(.importFile), dispatch: dispatch))
            list.addSubview(BoostSectionLabel(LibraryCopy.localGallery, colors: colors, large: false))
            for preset in BoostPresets.all {
                list.addSubview(BoostRowView(id: "preset-" + preset.id, title: preset.name, detail: "Local preset", favicon: nil,
                                             symbol: "paintbrush.pointed", colors: colors, command: .boost(.preset(preset.id)), dispatch: dispatch))
            }
        }
        needsLayout = true
    }

    /// The site's /favicon.ico, as Arc's row shows the boosted site's icon; none for every site.
    static func favicon(_ scope: BoostScope) -> URL? {
        switch scope {
        case .origin(let origin): URL(string: "/favicon.ico", relativeTo: origin.url)?.absoluteURL
        case .host(let host): URL(string: "https://\(host)/favicon.ico")
        case .allSites: nil
        }
    }

    override func layout() {
        super.layout()
        let pad = Metrics.library.columnPadding.value, b = LibraryDraw.boosts, m = LibraryDraw.list
        searchField.frame = LibraryColumnLayout.top(in: bounds, filter: false).search
        var top = b.rowTop.value
        if !feedback.isHidden {
            feedback.preferredMaxLayoutWidth = max(0, bounds.width - 2 * pad)
            let h = feedback.fittingSize.height
            feedback.frame = CGRect(x: pad, y: top + pad / 2, width: max(0, bounds.width - 2 * pad), height: h)
            top = feedback.frame.maxY + pad / 2
        }
        scroll.frame = CGRect(x: 0, y: top, width: bounds.width, height: max(0, bounds.height - top))
        var y = 0.0
        for view in list.subviews {
            let height = (view as? BoostSectionLabel).map { $0.large ? m.rowPitch.value : b.sectionGap.value + m.dayHeaderHeight.value - 8 } ?? m.rowPitch.value
            view.frame = CGRect(x: 0, y: y, width: bounds.width, height: height)
            y += height
        }
        list.frame = CGRect(x: 0, y: 0, width: scroll.contentSize.width, height: max(y + pad, scroll.contentSize.height))
    }
}

/// "Nothing Boosted Yet!" or the gallery's header between rows.
@MainActor private final class BoostSectionLabel: NSView {
    let large: Bool
    private let label: NSTextField

    init(_ text: String, colors: LibraryColors, large: Bool) {
        self.large = large
        label = NSTextField(labelWithString: text)
        super.init(frame: .zero)
        label.font = large ? .systemFont(ofSize: LibraryDraw.list.emptyTitleFont.value, weight: .semibold)
            : .systemFont(ofSize: LibraryDraw.list.dayHeaderFont.value, weight: .semibold)
        label.textColor = large ? colors.foregroundPrimary : colors.foregroundSecondary
        addSubview(label)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    override func layout() {
        super.layout()
        let h = label.fittingSize.height
        let y = large ? ((bounds.height - h) / 2).rounded() : bounds.height - h - LibraryDraw.list.dayHeaderBottom.value
        label.frame = CGRect(x: LibraryDraw.list.dayHeaderLeading.value, y: y, width: bounds.width, height: h)
    }
}

/// One row of the Boosts page (P32-f): a 44 pt tile with the site's icon (or a glyph, or Arc's struck-through square
/// when there is none), the name over the site, trailing buttons, a click and a context menu.
@MainActor private final class BoostRowView: NSView {
    struct Button {
        let id: String
        let symbol: String
        let tooltip: String
        let command: Command
    }

    private let tile = FlippedView()
    private let image = NSImageView()
    private let slash = CAShapeLayer()
    private let title: NSTextField
    private let detail: NSTextField
    private var buttons: [(NSButton, Command)] = []
    private let menuItems: [(String, Command)]
    private let command: Command
    private let dispatch: Dispatch
    private let colors: LibraryColors

    init(id: String, title: String, detail: String, favicon: URL?, symbol: String?, colors: LibraryColors, dimmed: Bool = false,
         buttons: [Button] = [], menu: [(String, Command)] = [], command: Command, dispatch: @escaping Dispatch) {
        self.title = NSTextField(labelWithString: title)
        self.detail = NSTextField(labelWithString: detail)
        menuItems = menu
        self.command = command
        self.dispatch = dispatch
        self.colors = colors
        super.init(frame: .zero)
        identify(.boostControl(id))
        setAccessibilityRole(.button)
        setAccessibilityLabel(title)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = LibraryDraw.list.rowRadius.value
        let b = LibraryDraw.boosts
        tile.wantsLayer = true
        tile.layer?.cornerCurve = .continuous
        tile.layer?.cornerRadius = b.tileRadius.value
        tile.layer?.backgroundColor = colors.page.cgColor
        tile.layer?.borderWidth = 1
        tile.layer?.borderColor = colors.edge.cgColor
        image.imageScaling = .scaleProportionallyUpOrDown
        image.contentTintColor = colors.foregroundSecondary
        if let symbol { image.image = LibraryIcon.symbol(symbol, size: 18) }
        if let favicon { image.image = FaviconCache.shared.image(for: favicon) { [weak self] loaded in self?.image.image = loaded; self?.slash.isHidden = true } }
        slash.strokeColor = colors.foregroundTertiary.cgColor
        slash.lineWidth = 2
        slash.isHidden = image.image != nil
        tile.layer?.addSublayer(slash)
        tile.addSubview(image)
        self.title.font = .systemFont(ofSize: b.titleFont.value)
        self.title.textColor = dimmed ? colors.foregroundSecondary : colors.foregroundPrimary
        self.title.lineBreakMode = .byTruncatingTail
        self.detail.font = .systemFont(ofSize: b.detailFont.value)
        self.detail.textColor = colors.foregroundSecondary
        self.detail.lineBreakMode = .byTruncatingTail
        for view in [tile, self.title, self.detail] as [NSView] { addSubview(view) }
        for spec in buttons {
            let button = NSButton()
            button.image = LibraryIcon.symbol(spec.symbol, size: 13, label: spec.tooltip)
            button.isBordered = false
            button.contentTintColor = colors.foregroundSecondary
            button.toolTip = spec.tooltip
            button.identify(.boostControl(spec.id))
            button.target = self
            button.action = #selector(buttonClicked(_:))
            self.buttons.append((button, spec.command))
            addSubview(button)
        }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? { rowHit(point, buttons: buttons.map(\.0)) }

    @objc private func buttonClicked(_ sender: NSButton) {
        if let command = buttons.first(where: { $0.0 === sender })?.1 { dispatch(command) }
    }

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { dispatch(command) }
    }

    override func accessibilityPerformPress() -> Bool {
        dispatch(command)
        return true
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard !menuItems.isEmpty else { return nil }
        let menu = NSMenu()
        for (title, command) in menuItems { menu.addItem(LibraryFilterButton.item(title) { [dispatch] in dispatch(command) }) }
        return menu
    }

    override func layout() {
        super.layout()
        let b = LibraryDraw.boosts, side = b.tile.value
        tile.frame = CGRect(x: b.tileLeading.value, y: ((bounds.height - side) / 2).rounded(), width: side, height: side)
        let inner = (side * 0.5).rounded()
        image.frame = CGRect(x: (side - inner) / 2, y: (side - inner) / 2, width: inner, height: inner)
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 4, y: 4))
        path.addLine(to: CGPoint(x: side - 4, y: side - 4))
        slash.path = path
        var right = bounds.width - Metrics.library.columnPadding.value
        for (button, _) in buttons.reversed() {
            button.frame = CGRect(x: right - 24, y: ((bounds.height - 24) / 2).rounded(), width: 24, height: 24)
            right = button.frame.minX
        }
        let x = b.titleLeading.value, width = max(0, right - 4 - x)
        let th = title.fittingSize.height, dh = detail.fittingSize.height
        let top = ((bounds.height - th - dh) / 2).rounded()
        title.frame = CGRect(x: x, y: top, width: width, height: th)
        detail.frame = CGRect(x: x, y: top + th, width: width, height: dh)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { layer?.backgroundColor = colors.rowHighlight.cgColor }
    override func mouseExited(with event: NSEvent) { layer?.backgroundColor = nil }
}
