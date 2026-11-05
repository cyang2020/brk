import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit

/// The Media page (Arc: `HomeButton.ScreenshotsAndCapturesPage`; P32-i, P34): "Search Media…" across the top, then
/// Brk's own captures of the profile by day, in the archive list's two-line rows (P32-e): the thumbnail in the icon
/// tile, the title, its size and host. Arc lists the computer's screenshot folder after a permission prompt; Brk reads
/// no system photos or folders. A click previews a capture over the content area (`.capture(.preview(id))`, drawn by
/// `MediaPreviewView`; the previewed row keeps a grey fill); Open, Export…, Remove and Insert in Easel are in the
/// row's … menu (shown while hovered) and its context menu. Before the first capture, the page shows Arc's empty
/// list of grey cards under the "Your Media in the Library" card; its × and Show Media put it away for the rest of the
/// session and show the empty state.
@MainActor final class MediaPageView: NSView {
    private let dispatch: Dispatch
    let searchField = LibrarySearchField(placeholder: LibraryCopy.search(.media))
    private let scroll = LibraryScrollView()
    private let list = FlippedView()
    private let intro = MediaIntroCard()
    /// Arc's pink-to-blue glow around the introduction card.
    private let glow = MediaIntroGlow()
    private let empty = EmptyStateView()
    private let message = NSTextField(wrappingLabelWithString: "")
    private var records: [CaptureRecord] = []
    private var files: [String: URL] = [:]
    private var selected: String?
    private var scheme: Scheme?
    private var colors = LibraryColors.of(.light)
    private var rendered: (records: [CaptureRecord], selected: String?, query: String, files: [String: URL])?
    /// The window's clock, for the day headers.
    private var now = Instant(milliseconds: 0)
    /// The introduction card was put away (× or Show Media) in this session.
    static var introDismissed = false

    init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        isHidden = true
        searchField.onChange = { [weak self] in self?.rebuild(force: true) }
        searchField.onEscape = { dispatch(.library(.close)) }
        scroll.documentView = list
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        intro.onDismiss = { [weak self] in
            MediaPageView.introDismissed = true
            self?.rebuild(force: true)
        }
        message.font = .systemFont(ofSize: LibraryDraw.list.detailFont.value)
        message.alignment = .center
        for view in [searchField, scroll, empty, glow, intro, message] as [NSView] { addSubview(view) }
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    var introShown: Bool { !intro.isHidden }
    var rows: [LibraryRowView] { list.subviews.compactMap { $0 as? LibraryRowView } }
    /// Arc's grey cards before the first capture, instead of rows.
    private var placeholders = false

    func hide() {
        isHidden = true
        records = []
        files = [:]
        selected = nil
        rendered = nil
        searchField.stringValue = ""
        list.subviews.forEach { $0.removeFromSuperview() }
    }

    func show(_ library: LibrarySnapshot, in rect: CGRect, scheme: Scheme, now: Instant) {
        self.now = now
        frame = rect
        isHidden = false
        if scheme != self.scheme {
            self.scheme = scheme
            colors = LibraryColors.of(scheme)
            appearance = .library(scheme)
            searchField.apply(colors)
            intro.apply(scheme)
            message.textColor = colors.foregroundSecondary
            rendered = nil
        }
        records = library.captures
        files = library.captureFiles
        selected = records.first { $0.id == library.capturePreview }?.id
        message.stringValue = library.captureMessage ?? ""
        message.isHidden = library.captureMessage == nil
        rebuild(force: false)
    }

    private var query: String { searchField.stringValue.trimmingCharacters(in: .whitespaces) }

    private func rebuild(force: Bool) {
        let key = (records, selected, query, files)
        if !force, let rendered, rendered.records == key.0, rendered.selected == key.1, rendered.query == key.2, rendered.files == key.3 {
            needsLayout = true
            return
        }
        rendered = key
        list.subviews.forEach { $0.removeFromSuperview() }
        placeholders = records.isEmpty && !Self.introDismissed
        intro.isHidden = !placeholders
        glow.isHidden = !placeholders
        // Under the introduction card Arc's column is faded: the search field at half strength (P32-a: #F3F3F2, its
        // placeholder #D7D6D6) and the day headers lighter (#A0A09F against the Archived Tabs page's #757575).
        searchField.alphaValue = placeholders ? 0.5 : 1
        if placeholders {
            // Arc's media list before it is shown: grey cards under day headers.
            let today = DayHeaderView(LibraryCopy.today, colors: colors), yesterday = DayHeaderView(LibraryCopy.yesterday, colors: colors)
            for header in [today, yesterday] { header.alphaValue = 0.7 }
            list.addSubview(today)
            for _ in 0..<5 { list.addSubview(MediaPlaceholderCard(colors: colors)) }
            list.addSubview(yesterday)
            for _ in 0..<6 { list.addSubview(MediaPlaceholderCard(colors: colors)) }
        } else {
            let shown = query.isEmpty ? records : records.filter {
                [$0.title, $0.url.host ?? ""].contains { $0.range(of: query, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
            }
            for day in LibraryDays.group(shown, at: \.createdAt, now: now, calendar: .current) {
                list.addSubview(DayHeaderView(day.title, colors: colors))
                for record in day.items { list.addSubview(row(record)) }
            }
            empty.isHidden = !shown.isEmpty
            if shown.isEmpty {
                if records.isEmpty { empty.show(glyph: .media, title: LibraryCopy.nothingHereYet, subtitle: LibraryCopy.mediaEmpty, colors: colors) }
                else { empty.show(glyph: nil, title: LibraryCopy.noResults(query), subtitle: "", colors: colors) }
            }
        }
        if placeholders { empty.isHidden = true }
        needsLayout = true
    }

    /// One capture as a list row; its … and its context menu hold the four actions.
    private func row(_ record: CaptureRecord) -> LibraryRowView {
        let id = record.id
        let actions: [(String, CaptureCommand)] = [("Open", .open(id)), ("Export…", .export(id)), ("Remove", .remove(id)), ("Insert in Easel", .insertInEasel(id))]
        weak var shown: LibraryRowView?
        let more = LibraryRowView.Accessory(symbol: "ellipsis.circle", tooltip: LibraryCopy.more) { shown?.showMenu(under: LibraryCopy.more) }
        let row = LibraryRowView(id: .tabTool("capture-card-" + id), icon: nil, thumbnail: files[id].flatMap { NSImage(contentsOf: $0) },
                                 title: record.title, detail: "\(record.width) × \(record.height) · \(record.url.host ?? "")", progress: .none,
                                 accessories: [more], menu: actions.map { title, command in (title, { [dispatch] in dispatch(.capture(command)) }) },
                                 selected: id == selected, colors: colors, onClick: { [dispatch] in dispatch(.capture(.preview(id))) })
        shown = row
        return row
    }

    override func layout() {
        super.layout()
        let m = LibraryDraw.media, l = LibraryDraw.list, pad = Metrics.library.columnPadding.value
        searchField.frame = LibraryColumnLayout.top(in: bounds, filter: false).search
        let top = l.listTop.value
        scroll.frame = CGRect(x: 0, y: top, width: bounds.width, height: max(0, bounds.height - top))
        var y = 0.0
        if placeholders {
            // A header's text (16 pt tall) is centred at y 63 and the first card starts at 83 (P32-a).
            let headerStep = m.cardTop.value - top, width = max(0, bounds.width - 2 * m.cardLeading.value)
            let headerHeight = m.headerCenter.value + 8 + l.dayHeaderBottom.value - top
            for view in list.subviews {
                if view is DayHeaderView {
                    view.frame = CGRect(x: l.rowLeading.value, y: y, width: width, height: headerHeight)
                    y += headerStep
                } else {
                    view.frame = CGRect(x: m.cardLeading.value, y: y, width: width, height: m.cardHeight.value)
                    y += m.cardPitch.value
                }
            }
        } else {
            // The archive list's geometry (LibraryListPage): day headers, then 56 pt rows inside the column's padding.
            let width = max(0, bounds.width - 2 * l.rowLeading.value)
            for view in list.subviews {
                let height = view is DayHeaderView ? l.dayHeaderHeight.value : l.rowPitch.value
                view.frame = CGRect(x: l.rowLeading.value, y: y, width: width, height: height)
                y += height
            }
        }
        list.frame = CGRect(x: 0, y: 0, width: scroll.contentSize.width, height: max(y + pad, scroll.contentSize.height))
        let introWidth = max(0, bounds.width - 2 * m.introLeading.value)
        intro.frame = CGRect(x: m.introLeading.value, y: m.introTop.value, width: introWidth, height: intro.height(for: introWidth))
        glow.frame = intro.frame.insetBy(dx: -40, dy: -40)
        empty.place(in: CGRect(x: 0, y: top, width: bounds.width, height: max(0, bounds.height - top)))
        let messageHeight = message.isHidden ? 0 : message.fittingSize.height
        message.preferredMaxLayoutWidth = max(0, bounds.width - 2 * pad)
        message.frame = CGRect(x: pad, y: bounds.height - pad - messageHeight, width: max(0, bounds.width - 2 * pad), height: messageHeight)
    }
}

/// A grey card of the media list before anything is shown.
@MainActor private final class MediaPlaceholderCard: NSView {
    init(colors: LibraryColors) {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = LibraryDraw.media.cardRadius.value
        layer?.backgroundColor = colors.placeholder.cgColor
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
}

/// The previewed capture over the content card (P34: Brk opens a picked capture where the page is): the image fitted
/// in the card, its title, size and host under it, and × to put it away (until another capture is picked).
@MainActor public final class MediaPreviewView: NSView {
    private let image = NSImageView()
    private let caption = NSTextField(labelWithString: "")
    private let close = NSButton()
    private var shown: (String, URL?)?
    private var dismissed: String?

    override init(frame: CGRect) {
        super.init(frame: frame)
        isHidden = true
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.masksToBounds = true
        identify(.tabTool("capture-preview"))
        image.imageScaling = .scaleProportionallyUpOrDown
        image.wantsLayer = true
        image.layer?.shadowOpacity = 0.18
        image.layer?.shadowRadius = 10
        image.layer?.shadowOffset = CGSize(width: 0, height: -3)
        caption.font = .systemFont(ofSize: LibraryDraw.list.titleFont.value)
        caption.alignment = .center
        caption.lineBreakMode = .byTruncatingMiddle
        close.image = LibraryIcon.symbol("xmark.circle.fill", size: 20, label: LibraryCopy.close)
        close.isBordered = false
        close.toolTip = LibraryCopy.close
        close.target = self
        close.action = #selector(dismiss)
        for view in [image, caption, close] as [NSView] { addSubview(view) }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    public override var isFlipped: Bool { true }

    var captionText: String { caption.stringValue }

    func hide() {
        isHidden = true
        shown = nil
        dismissed = nil
    }

    func show(_ record: CaptureRecord, file: URL?, in rect: CGRect, cornerRadius: Double, scheme: Scheme) {
        guard dismissed != record.id else {
            isHidden = true
            return
        }
        dismissed = nil
        frame = rect
        layer?.cornerRadius = cornerRadius
        let colors = LibraryColors.of(scheme)
        layer?.backgroundColor = colors.panel.blended(withFraction: 0.04, of: .black)?.cgColor
        caption.textColor = colors.foregroundSecondary
        close.contentTintColor = colors.foregroundTertiary
        if shown?.0 != record.id || shown?.1 != file {
            image.image = file.flatMap { NSImage(contentsOf: $0) }
            shown = (record.id, file)
        }
        caption.stringValue = "\(record.title) · \(record.width) × \(record.height) · \(record.url.host ?? "")"
        isHidden = false
        needsLayout = true
    }

    @objc private func dismiss() {
        dismissed = shown?.0
        isHidden = true
    }

    public override func layout() {
        super.layout()
        let pad = 32.0, b = 28.0
        close.frame = CGRect(x: bounds.width - 12 - b, y: 12, width: b, height: b)
        let ch = caption.fittingSize.height
        caption.frame = CGRect(x: pad, y: bounds.height - pad / 2 - ch, width: max(0, bounds.width - 2 * pad), height: ch)
        image.frame = CGRect(x: pad, y: pad, width: max(0, bounds.width - 2 * pad), height: max(0, caption.frame.minY - pad / 2 - pad))
    }
}

/// Arc's "Your Media in the Library" card (P32-a): the media glyph, the bold title, the description, the blue Show
/// Media button, the privacy note with its shield, and × at the top right, over a soft violet glow.
@MainActor final class MediaIntroCard: NSView {
    var onDismiss: () -> Void = {}
    private let glyph = NSImageView()
    private let title = NSTextField(labelWithString: LibraryCopy.mediaIntroTitle)
    private let body = NSTextField(wrappingLabelWithString: LibraryCopy.mediaIntroBody)
    private let button = MediaShowButton()
    private let shield = NSImageView()
    private let footnote = NSTextField(wrappingLabelWithString: LibraryCopy.mediaPrivacy)
    private let close = NSButton()

    override init(frame: CGRect) {
        super.init(frame: frame)
        let m = LibraryDraw.media
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = m.introRadius.value
        layer?.borderWidth = 1
        // Drawn at its own size (a 42 pt frame scaled it down to 35 wide; Arc's is 42.5).
        glyph.image = LibraryIcon.symbol("photo.on.rectangle.angled", size: m.introGlyph.value * 0.98, weight: .medium)
        glyph.imageScaling = .scaleNone
        glyph.contentTintColor = NSColor(srgbRed: 0.53, green: 0.47, blue: 0.86, alpha: 1)
        title.font = .systemFont(ofSize: m.introTitleFont.value, weight: .bold)
        title.alignment = .center
        body.font = .systemFont(ofSize: m.introBodyFont.value)
        footnote.font = .systemFont(ofSize: m.introFootnoteFont.value)
        shield.image = LibraryIcon.symbol("lock.shield.fill", size: 12)
        close.image = LibraryIcon.symbol("xmark", size: 13, weight: .semibold, label: LibraryCopy.close)
        close.isBordered = false
        close.toolTip = LibraryCopy.close
        close.target = self
        close.action = #selector(dismiss)
        button.target = self
        button.action = #selector(dismiss)
        for view in [glyph, title, body, button, shield, footnote, close] as [NSView] { addSubview(view) }
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }

    @objc private func dismiss() { onDismiss() }

    func apply(_ scheme: Scheme) {
        let light = scheme == .light
        layer?.borderColor = NSColor(white: light ? 0 : 1, alpha: 0.06).cgColor
        // P32-a: the card #FAF7FC, the title, the description and × in one plum (#704067), the note a pale mauve (#B39FB5).
        // Q18-navy-library-media: the card #161C2B, white inks.
        layer?.backgroundColor = (light ? NSColor(srgbRed: 0xFA / 255.0, green: 0xF7 / 255.0, blue: 0xFC / 255.0, alpha: 1) : NSColor(srgbRed: 0x16 / 255.0, green: 0x1C / 255.0, blue: 0x2B / 255.0, alpha: 1)).cgColor
        let ink = light ? NSColor(srgbRed: 0x70 / 255.0, green: 0x40 / 255.0, blue: 0x67 / 255.0, alpha: 1) : .white
        let note = light ? NSColor(srgbRed: 0xB3 / 255.0, green: 0x9F / 255.0, blue: 0xB5 / 255.0, alpha: 1) : NSColor(white: 1, alpha: 0.55)
        title.textColor = ink
        body.attributedStringValue = Self.lines(LibraryCopy.mediaIntroBody, font: body.font, height: LibraryDraw.media.introBodyLine.value,
                                                color: light ? ink : NSColor(white: 1, alpha: 0.8))
        footnote.attributedStringValue = Self.lines(LibraryCopy.mediaPrivacy, font: footnote.font, height: LibraryDraw.media.introFootnoteLine.value, color: note)
        shield.contentTintColor = note
        close.contentTintColor = ink
    }

    private static func lines(_ text: String, font: NSFont?, height: Double, color: NSColor) -> NSAttributedString {
        let style = NSMutableParagraphStyle()
        style.minimumLineHeight = height
        style.maximumLineHeight = height
        return NSAttributedString(string: text, attributes: [.font: font as Any, .foregroundColor: color, .paragraphStyle: style])
    }

    func height(for width: Double) -> Double {
        layout(width: width)
        return footnote.frame.maxY + LibraryDraw.media.introPadding.value
    }

    override func layout() {
        super.layout()
        layout(width: bounds.width)
    }

    private func layout(width: Double) {
        let m = LibraryDraw.media, pad = m.introPadding.value
        let inner = max(0, width - 2 * pad)
        // × is centred 27 in from the right and 27.5 below the top (P32-a).
        close.frame = CGRect(x: width - 27 - 11, y: 16.5, width: 22, height: 22)
        let g = m.introGlyph.value
        glyph.frame = CGRect(x: ((width - 2 * g) / 2).rounded(), y: (m.introGlyphCenter.value - g).rounded(), width: 2 * g, height: 2 * g)
        let th = title.fittingSize.height
        title.frame = CGRect(x: pad, y: (m.introTitleCenter.value - th / 2).rounded(), width: inner, height: th)
        // The labels draw 2 pt inside their frames: the frames stand 2 pt out so the text starts at the padding, as
        // Arc's does, and the description's 37-character first line fits.
        let inset = 2.0
        body.preferredMaxLayoutWidth = inner + 2 * inset
        let bh = body.sizeThatFits(NSSize(width: inner + 2 * inset, height: .greatestFiniteMagnitude)).height
        body.frame = CGRect(x: pad - inset, y: m.introBodyTop.value, width: inner + 2 * inset, height: bh)
        button.frame = CGRect(x: pad, y: body.frame.maxY + 10, width: inner, height: m.introButtonHeight.value)
        let s = 12.0
        shield.frame = CGRect(x: pad + 1.5, y: button.frame.maxY + 18.5 - s / 2, width: s, height: s)
        let noteWidth = max(0, inner - s - 6 + 2 * inset)
        footnote.preferredMaxLayoutWidth = noteWidth
        let noteHeight = footnote.sizeThatFits(NSSize(width: noteWidth, height: .greatestFiniteMagnitude)).height
        footnote.frame = CGRect(x: pad + s + 6 - inset, y: button.frame.maxY + 18.5 - m.introFootnoteLine.value / 2, width: noteWidth, height: noteHeight)
    }
}

/// A blurred pink-to-blue rounded rectangle just outside the introduction card (P32-a's glow: pink at the top left,
/// blue at the right and the bottom).
@MainActor private final class MediaIntroGlow: NSView {
    private let shape = CAGradientLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerUsesCoreImageFilters = true
        shape.colors = [NSColor(srgbRed: 0.98, green: 0.62, blue: 0.75, alpha: 0.75).cgColor,
                        NSColor(srgbRed: 0.62, green: 0.58, blue: 1.0, alpha: 0.7).cgColor,
                        NSColor(srgbRed: 0.42, green: 0.48, blue: 1.0, alpha: 0.75).cgColor]
        // In this flipped view's layer y 0 is the top: pink from the top left, blue to the bottom right.
        shape.startPoint = CGPoint(x: 0, y: 0)
        shape.endPoint = CGPoint(x: 1, y: 1)
        shape.cornerRadius = LibraryDraw.media.introRadius.value + 4
        shape.filters = [CIFilter(name: "CIGaussianBlur", parameters: [kCIInputRadiusKey: 16]) as Any].compactMap { $0 }
        layer?.addSublayer(shape)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shape.frame = bounds.insetBy(dx: 36, dy: 36)
        CATransaction.commit()
    }
}

/// Show Media: white text on Arc's pink-to-blue gradient.
@MainActor private final class MediaShowButton: NSButton {
    private let gradient = CAGradientLayer()
    private let label = NSTextField(labelWithString: LibraryCopy.showMedia)

    override init(frame: CGRect) {
        super.init(frame: frame)
        title = ""
        isBordered = false
        wantsLayer = true
        gradient.colors = [NSColor(srgbRed: 0.79, green: 0.52, blue: 0.69, alpha: 1).cgColor, NSColor(srgbRed: 0.29, green: 0.39, blue: 0.93, alpha: 1).cgColor]
        gradient.startPoint = CGPoint(x: 0, y: 0.5)
        gradient.endPoint = CGPoint(x: 1, y: 0.5)
        gradient.cornerRadius = LibraryDraw.media.introButtonRadius.value
        gradient.cornerCurve = .continuous
        layer?.addSublayer(gradient)
        label.font = .systemFont(ofSize: LibraryDraw.column.searchFont.value, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        addSubview(label)
        setAccessibilityLabel(LibraryCopy.showMedia)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("not used") }
    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { !isHidden && frame.contains(point) ? self : nil }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        gradient.frame = bounds
        CATransaction.commit()
        let h = label.fittingSize.height
        label.frame = CGRect(x: 0, y: ((bounds.height - h) / 2).rounded(), width: bounds.width, height: h)
    }
}
