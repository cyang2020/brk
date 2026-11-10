import AppKit
import BrkBase
import BrkDomain
import BrkLayout
import BrkUIKit
import UniformTypeIdentifiers

/// Owner: W4 / F4. The command bar: input row, then up to 5 results (`Suggest.rank`: the completed site or the top
/// hit, switch to tab, what you typed, top domains, the engine's suggestions, history, type travel). The typed query,
/// its inline completion, the highlighted row and site-search mode are view state; the snapshot's `openID` resets
/// them. Every edit dispatches `.commandBar(.queryChanged(text))` with the text as typed (never the completion) so
/// the reducer can ask for suggestions. Return dispatches the highlighted result's command (`Suggestion.command`),
/// Esc `.commandBar(.dismiss)`, and so does a click anywhere outside the card. Opening plays Arc's bounce (scale 0.95
/// -> 1, no fade).
///
/// Two cards, as Arc 1.170 draws them (2a96a9d7f0:verify/visual-pairs/run-20261103 P02-b/c, Q01-a/b): centered (Cmd+T) the
/// card fills the box, with a 64 pt input row (magnifier, 18 pt text, ⓘ) and a hairline over the rows, each recent
/// tab with "Switch to Tab" and an arrow square, the highlight a shade of the theme (grey under a white theme). Over the URL pill (Cmd+L) the card is 350 wide
/// from the pill's left edge (wider only when its input row needs it), its input row 50 tall with the page's icon
/// and 13 pt text, no hairline and no Switch to Tab captions, the highlight and the text selection shades of the
/// sidebar theme. Both follow the sidebar's scheme.
///
/// Inline completion (Arc): typing on the start of a site's domain shows the rest of it selected ("wiki" ->
/// "wiki|pedia.org"), the site leads the rows, Return opens or switches to it; typing replaces the selection, a
/// deletion never completes, and → or End keeps the whole domain as typed.
///
/// Site search (Arc): beside the input the bar offers "Search Wikipedia" and a Tab key (`Suggest.siteSearchOffer`);
/// Tab enters site search for that engine, and so does Space right after an engine's whole name or keyword. The
/// engine's name sits in a pill before the input, the placeholder reads "Search Bing…", and Return searches there
/// (`.commandBar(.submitSearch)`). Backspace in the empty input or Esc leaves the mode and gives back the engine's
/// name as typed.
///
/// Brk's own jobs beyond Arc (`Suggest.rank`): quick answers, apps and files in the last rows, Tab to ask the local AI. A
/// file row takes ⌘Return (show in the Finder) and ⌥Return (copy its path), which do nothing new on any other row.
///
/// Prefix words (`QuickPrefixes`, Brk's own) go through site search's own keys and pill: a whole word followed by Tab
/// enters, the word's name sits in the pill, Backspace in the empty input or Esc leaves and gives the word back. An engine
/// of the same name wins. Space never enters, so a search can start with one of these words. The word, or two letters of
/// it, offers the prefix beside the input with the Tab key while no site search is on offer. The offer and the key follow
/// one rule (`Suggest.tabAction`), which Tab works out again from the text at its press.
///
/// The view fills `frames.commandBar` (Arc's 338 pt box); the visible card sits at the top of it and is as tall as
/// its rows, and the empty rest of the box lets clicks through.
///
/// Public surface: `init(dispatch:)`, `render`, `focusInput`. The text field itself stays internal: the window
/// controller asks for focus, it does not reach into the bar.
@MainActor
public final class CommandBarView: NSView, NSTextFieldDelegate {
    enum Style { case centered, attached }

    let dispatch: Dispatch
    let input = NSTextField()
    /// Typed text -> URL: the domain's one URL policy with the bar's engine unless a test sets it.
    var resolve: ((String) -> URL?)?
    /// What the pill before the input says the text is for. The two kinds share entering, the pill and leaving.
    enum Pill: Equatable {
        case site(SearchEngineCandidate)
        case prefix(QuickPrefix)

        var title: String {
            switch self {
            case .site(let engine): engine.name
            case .prefix(let prefix): prefix.title
            }
        }
    }
    private var pill: Pill?
    /// Site-search mode: the engine the query goes to.
    var siteSearch: SearchEngineCandidate? { if case .site(let engine)? = pill { engine } else { nil } }
    /// A prefix word's mode.
    var prefix: QuickPrefix? { if case .prefix(let prefix)? = pill { prefix } else { nil } }
    /// The text that named the pill (given back on leaving).
    private var namedBy = ""
    /// What the user typed; the input shows it followed by the rest of `completion`, selected.
    private(set) var typed = ""
    private(set) var completion: String?
    /// The last edit typed on at the end of the text (not a deletion, not → or End keeping a completion): the completion may
    /// still change with the rows (`followFirstRow`).
    private var typingOn = false
    /// The engine Tab would search, shown beside the input.
    private(set) var offer: SearchEngineCandidate?
    /// The prefix Tab would enter, shown there when no engine is on offer.
    private(set) var prefixOffer: QuickPrefix?
    /// An AI prefix the text names that cannot work now: its reason there instead, and Tab opens the settings that change it.
    private(set) var blockedPrefix: QuickPrefixBlock?
    /// The pill before the input: a prefix's, in its colour, or a search engine's, in Arc's grey.
    let sitePill = QuickChip()
    private let leadingIcon = NSImageView()
    private let info = InfoButton()
    private let offerLabel = NSTextField(labelWithString: "")
    /// A prefix on offer, as the chip Tab will put before the input.
    let offerChip = QuickChip()
    private let keyCap = NSView()
    private let keyLabel = NSTextField(labelWithString: OverlayCopy.siteSearchKey)
    private(set) var results: [Suggestion] = []
    private(set) var highlighted = 0
    private let card = FlippedView()
    private let hairline = NSView()
    private var rows: [ResultRowView] = []
    private var openID: Int?
    private var bar: CommandBarSnapshot?
    private(set) var style = Style.centered
    private var fillsWindow = false {
        didSet { if fillsWindow != oldValue { layoutCard() } }
    }
    private var colors = CommandBarColors.of(.light, primary: RGBA(1, 1, 1))
    private let backdrop = NSVisualEffectView()
    private let backdropTint = NSView()
    private var look: (Scheme, Style, RGBA, Bool)?
    private var leadingFavicon: URL?
    private var eventMonitor: Any?
    private var savedSelection: [NSAttributedString.Key: Any]?

    public init(dispatch: @escaping Dispatch) {
        self.dispatch = dispatch
        super.init(frame: .zero)
        isHidden = true
        identify(.commandBar)
        input.identify(.commandBarInput)
        input.delegate = self
        input.isBordered = false
        input.drawsBackground = false
        input.focusRingType = .none
        input.cell?.isScrollable = true
        input.cell?.wraps = false
        input.cell?.usesSingleLineMode = true
        card.wantsLayer = true
        card.layer?.cornerCurve = .continuous
        card.layer?.cornerRadius = OverlayMetrics.commandBar.cornerRadius.value
        card.layer?.borderWidth = 0.5
        hairline.wantsLayer = true
        sitePill.isHidden = true
        leadingIcon.imageScaling = .scaleProportionallyUpOrDown
        offerLabel.font = .systemFont(ofSize: OverlayMetrics.commandBar.titleFontSize.value, weight: .medium)
        offerLabel.lineBreakMode = .byTruncatingTail
        offerChip.isHidden = true
        offerChip.font = .systemFont(ofSize: OverlayMetrics.commandBar.titleFontSize.value, weight: .semibold)
        offerChip.padding = OverlayMetrics.commandBar.chipPadding.value
        keyCap.wantsLayer = true
        keyCap.layer?.cornerCurve = .continuous
        keyCap.layer?.cornerRadius = OverlayMetrics.commandBar.hintRadius.value
        keyLabel.font = .systemFont(ofSize: OverlayMetrics.commandBar.keyFontSize.value, weight: .medium)
        keyLabel.alignment = .center
        keyCap.addSubview(keyLabel)
        info.onClick = { [weak self] in self?.dispatch(.settings(.openPane(.shortcuts))) }
        // The dark card is translucent (P29-c); what shows through it is blurred, so the sidebar's text is not readable.
        backdrop.material = .hudWindow
        backdrop.blendingMode = .withinWindow
        backdrop.state = .active
        backdrop.appearance = NSAppearance(named: .darkAqua)
        backdrop.wantsLayer = true
        backdrop.layer?.cornerCurve = .continuous
        backdrop.layer?.cornerRadius = OverlayMetrics.commandBar.cornerRadius.value
        backdrop.layer?.masksToBounds = true
        backdropTint.wantsLayer = true
        backdrop.addSubview(backdropTint)
        sitePill.identify(.commandBarPill)
        for view in [backdrop, leadingIcon, sitePill, input, info, offerChip, offerLabel, keyCap, hairline] as [NSView] { card.addSubview(view) }
        addSubview(card)
        applyColors(.light, style: .centered, primary: RGBA(1, 1, 1), spaceless: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    public override var isFlipped: Bool { true }

    /// Makes the input first responder (AppKit selects its text, so Cmd+L's URL starts selected). False while the
    /// bar is hidden or not in a window.
    public func focusInput() -> Bool {
        guard !isHidden, let window else { return false }
        if input.currentEditor() != nil { tintSelection(); return true }
        let focused = window.makeFirstResponder(input)
        tintSelection()
        return focused
    }

    /// `window`: the window's kind; a window without a space (blank, Little, incognito) highlights in Arc's blue-violet.
    public func render(_ bar: CommandBarSnapshot?, frames: WindowFrames, palette: Palette, window: WindowKind = .standard) {
        guard let bar, let frame = frames.commandBar else { return hide() }
        // The bar that is its whole window (an empty Little window) leaves the ⓘ's place to the window's close button.
        fillsWindow = frame.size == frames.contentSize
        // Arc's card follows the system's dark appearance even over a light Space theme (P29-c); the sidebar does not.
        let system: Scheme = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? .dark : .light
        show(bar, in: frame, scheme: palette.scheme == .dark || system == .dark ? .dark : .light, primary: palette.accent, spaceless: window != .standard)
    }

    /// `render` once the slice and its frame are known. A new `openID` resets the query to `initialQuery` and the
    /// highlight to the first row and plays the bounce; the same opening re-ranks what the user typed against the
    /// new candidates.
    func show(_ bar: CommandBarSnapshot, in frame: CGRect, scheme: Scheme, primary: RGBA = RGBA(1, 1, 1), spaceless: Bool = false) {
        let reopened = bar.openID != openID
        let style: Style = bar.placement == .overURLPill && bar.aiMode == nil ? .attached : .centered
        let changedLook = look.map { $0 != (scheme, style, primary, spaceless) } ?? true
        guard reopened || isHidden || bar != self.bar || frame != self.frame || changedLook else { return }
        self.frame = frame
        isHidden = false
        if changedLook { applyColors(scheme, style: style, primary: primary, spaceless: spaceless) }
        self.bar = bar
        if reopened {
            openID = bar.openID
            pill = nil
            typed = bar.initialQuery
            completion = nil
            typingOn = false
            input.stringValue = bar.initialQuery
            input.currentEditor()?.selectAll(nil)
            applySiteSearchLook()
        } else {
            followFirstRow()
        }
        rerank(keepHighlight: !reopened)
        installEventMonitor()
        if reopened { bounce() }
    }

    private static func aiPlaceholder(_ mode: AIMode) -> String {
        switch mode {
        case .question: "Ask Max a question…"
        case .page: "Ask about this page…"
        case .instant: "Find a website with Instant Links…"
        case .translate: "Translate to language (e.g. English)…"
        case .browse: "Question | https://source, https://source…"
        }
    }

    private func hide() {
        guard !isHidden else { return }
        isHidden = true   // AppKit hands first responder to the window when the focused input's ancestor hides
        bar = nil
        removeEventMonitor()
    }

    // MARK: Keys inside the input

    public override func performKeyEquivalent(with event: NSEvent) -> Bool {
        takeSiteSearchEscape(event) || takeCommandReturn(event) || super.performKeyEquivalent(with: event)
    }

    /// ⌘Return on a row that has its own use for it (a file row). AppKit offers Command chords as key equivalents, so
    /// the text field's delegate never sees this one.
    private func takeCommandReturn(_ event: NSEvent) -> Bool {
        guard !isHiddenOrHasHiddenAncestor, event.type == .keyDown, event.keyCode == Key.returnKey.code, !event.isARepeat,
              event.modifierFlags.intersection([.command, .control, .option, .shift]) == .command, results.indices.contains(highlighted),
              let command = results[highlighted].commandReturn, let window, event.window == nil || event.window === window,
              let editor = input.currentEditor() as? NSTextView, window.firstResponder === editor, !editor.hasMarkedText() else { return false }
        dispatch(command)
        return true
    }

    /// For the window's own Escape handling, which runs before the page and before this view's event monitor (the
    /// app's monitor routes Escape to Exit while any overlay is open): true when site search took this Escape.
    public func takeEscape(_ event: NSEvent) -> Bool { takeSiteSearchEscape(event) }

    /// The window routes Escape to Exit before the text field's delegate sees it. Site search owns the first
    /// Escape while its input has focus. The key-equivalent path also covers input in an inactive window.
    private func takeSiteSearchEscape(_ event: NSEvent) -> Bool {
        guard !isHiddenOrHasHiddenAncestor, pill != nil, event.type == .keyDown, event.keyCode == Key.escape.code,
              event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty,
              let window, event.window == nil || event.window === window,
              let editor = input.currentEditor() as? NSTextView, window.firstResponder === editor, !editor.hasMarkedText() else { return false }
        leavePill()
        return true
    }

    public func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard !textView.hasMarkedText() else { return false }   // an input method is composing
        switch selector {
        case #selector(NSResponder.insertNewline(_:)), #selector(NSResponder.insertLineBreak(_:)), #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            // A held Return auto-repeats; only the first press chooses (`isARepeat` exists on key events only).
            let event = NSApp?.currentEvent
            if event?.type == .keyDown && event?.isARepeat == true { return true }
            // A file row's ⌥Return copies its path; on any other row it stays Return.
            if event?.modifierFlags.contains(.option) == true, results.indices.contains(highlighted), let command = results[highlighted].optionReturn {
                dispatch(command)
                return true
            }
            // Max's Instant Links: Shift+Return on a web search opens its top results instead (P48-a).
            if event?.modifierFlags.contains(.shift) == true, let bar {
                // A site search is a web search too: its engine's name and the query go to Instant Links whole (Arc's P48
                // "wikipedia arc browser").
                if let siteSearch, bar.instantLinks, !typed.trimmingCharacters(in: .whitespaces).isEmpty {
                    dispatch(.assist(.instant((namedBy.isEmpty ? siteSearch.name : namedBy) + " " + typed.trimmingCharacters(in: .whitespaces))))
                    return true
                }
                if pill == nil, let query = Suggest.instantQuery(typed, bar: bar, resolve: resolve) {
                    dispatch(.assist(.instant(query)))
                    return true
                }
            }
            choose(highlighted)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            if pill != nil { leavePill() } else { dispatch(.commandBar(.dismiss)) }
            return true
        case #selector(NSResponder.insertTab(_:)), #selector(NSResponder.insertBacktab(_:)):
            // Tab never leaves the bar. It does what `Suggest.tabAction` makes of the text as the input holds it at this
            // press, worked out again here rather than read from the offer last drawn beside the input.
            guard pill == nil, let bar else { return true }
            switch Suggest.tabAction(typed, completing: completion, bar: bar, resolve: resolve) {
            case .siteSearch(let engine)?: enter(.site(engine), namedBy: typed)
            case .prefix(let prefix)?: enter(.prefix(prefix), namedBy: typed)
            case .blocked(let block)?: dispatch(.settings(.openPane(block.pane)))
            case .provider?: dispatch(.assist(.open(.question)))
            case .ask(let question)?: dispatch(.assist(.ask(question)))
            case nil: break
            }
            return true
        case #selector(NSResponder.deleteBackward(_:)) where pill != nil && input.stringValue.isEmpty:
            leavePill()
            return true
        case #selector(NSResponder.moveUp(_:)):
            step(-1)
            return true
        case #selector(NSResponder.moveDown(_:)):
            step(1)
            return true
        case #selector(NSResponder.moveRight(_:)), #selector(NSResponder.moveToEndOfLine(_:)), #selector(NSResponder.moveToEndOfDocument(_:)):
            // Keeping the completion: the whole domain is now what was typed.
            if completion != nil { acceptCompletion() }
            return false
        default:
            return false
        }
    }

    public func controlTextDidChange(_ notification: Notification) {
        let text = input.stringValue
        if bar?.aiMode == nil, pill == nil, text.hasSuffix(" "), let bar, !text.dropLast().contains(where: \.isWhitespace) {
            let word = String(text.dropLast())
            if let engine = Suggest.siteSearchEngine(named: word, bar) { return enter(.site(engine), namedBy: word) }
        }
        // Typing (the caret at the end) may complete; a deletion, of the completion itself or of what was typed,
        // never does: the text is then the start of what was there.
        typingOn = !typed.hasPrefix(text) && caretAtEnd()
        typed = text
        completion = nil
        if pill == nil, typingOn, let bar, let domain = Suggest.completion(text, bar: bar, appName: Product.name) {
            complete(to: domain)
        }
        switch pill {
        case .site(let engine)?: dispatch(.commandBar(.queryChangedForSite(engine.id, text)))
        case .prefix(let prefix)?: dispatch(.commandBar(.prefixQuery(prefix.action, text)))
        case nil: dispatch(.commandBar(.queryChanged(text)))
        }
        rerank(keepHighlight: false)
    }

    public func controlTextDidEndEditing(_ notification: Notification) {
        guard let editor = notification.userInfo?["NSFieldEditor"] as? NSTextView, let savedSelection else { return }
        editor.selectedTextAttributes = savedSelection
        self.savedSelection = nil
    }

    private func caretAtEnd() -> Bool {
        guard let editor = input.currentEditor() else { return true }
        return NSMaxRange(editor.selectedRange) == (input.stringValue as NSString).length
    }

    /// Shows `domain`'s rest after what was typed, selected, so the next key replaces it.
    private func complete(to domain: String) {
        completion = domain
        let rest = String(domain.dropFirst(typed.count))
        input.stringValue = typed + rest
        if let editor = input.currentEditor() {
            editor.selectedRange = NSRange(location: (typed as NSString).length, length: (rest as NSString).length)
            tintSelection()
        }
    }

    /// Answers that arrive after a keystroke (the engine's suggestions, files, pages found by meaning) re-rank the rows. While
    /// the user is still typing on at the end, the completion follows the new first row, as it would have had the answer come
    /// before the keystroke (Arc completes only to its first row). So the input never shows one site while Return opens
    /// another. Once the caret moves or text is selected otherwise, the input is left alone.
    private func followFirstRow() {
        guard pill == nil, typingOn, let bar, let editor = input.currentEditor() else { return }
        let length = (typed as NSString).length
        let shown = completion.map { typed + $0.dropFirst(typed.count) } ?? typed
        let left = NSRange(location: length, length: (shown as NSString).length - length)
        guard editor.string == shown, editor.selectedRange == left else { return }
        let next = Suggest.completion(typed, bar: bar, appName: Product.name)
        guard next != completion else { return }
        if let next { return complete(to: next) }
        completion = nil
        input.stringValue = typed
        input.currentEditor()?.selectedRange = NSRange(location: length, length: 0)
    }

    private func acceptCompletion() {
        typed = input.stringValue
        completion = nil
        typingOn = false
        dispatch(.commandBar(.queryChanged(typed)))
        rerank(keepHighlight: false)
    }

    private func enter(_ mode: Pill, namedBy name: String) {
        namedBy = name.trimmingCharacters(in: .whitespaces)
        pill = mode
        typed = ""
        completion = nil
        typingOn = false
        input.stringValue = ""
        applySiteSearchLook()
        dispatch(.commandBar(.queryChanged("")))
        rerank(keepHighlight: false)
    }

    private func leavePill() {
        pill = nil
        typed = namedBy
        completion = nil
        typingOn = false
        input.stringValue = namedBy
        // The caret after the word: setting the text selects it, and the next key would replace it.
        input.currentEditor()?.selectedRange = NSRange(location: (namedBy as NSString).length, length: 0)
        applySiteSearchLook()
        dispatch(.commandBar(.queryChanged(namedBy)))
        rerank(keepHighlight: false)
    }

    private var isDark: Bool { look?.0 == .dark }

    /// A prefix wears its own colour, lightly; a search engine's pill stays Arc's grey.
    private func applyPillColors() {
        let o = OverlayMetrics.commandBar
        if let tint = prefix?.tint {
            let chip = QuickChipColors.of(tint, dark: isDark)
            sitePill.paint(fill: chip.fill, stroke: chip.stroke, text: chip.text, radius: o.chipRadius.value)
            sitePill.font = .systemFont(ofSize: o.chipFontSize.value, weight: .semibold)
            sitePill.padding = o.chipPadding.value
        } else {
            sitePill.paint(fill: colors.accessory, stroke: nil, text: colors.accessoryText, radius: o.hintRadius.value)
            sitePill.font = .systemFont(ofSize: o.titleFontSize.value, weight: .medium)
            sitePill.padding = o.hintPadding.value
        }
        if let tint = prefixOffer?.tint {
            let chip = QuickChipColors.of(tint, dark: isDark)
            offerChip.paint(fill: chip.fill, stroke: chip.stroke, text: chip.text, radius: o.chipRadius.value)
        }
    }

    private func applySiteSearchLook() {
        sitePill.isHidden = pill == nil
        sitePill.title = pill?.title ?? ""
        applyPillColors()
        let placeholder = siteSearch.map { OverlayCopy.siteSearchPlaceholder($0.name) } ?? prefix?.placeholder ?? (bar?.aiMode.map(Self.aiPlaceholder) ?? Copy.urlPlaceholder)
        input.placeholderAttributedString = NSAttributedString(string: placeholder, attributes: [
            .foregroundColor: colors.placeholder, .font: input.font ?? .systemFont(ofSize: OverlayMetrics.commandBar.centeredInputFontSize.value),
        ])
        layoutCard()
    }

    /// The text selection (Cmd+L's URL, the completed part) in the bar's colors. The window's field editor is shared,
    /// so its own selection colors come back when the input stops editing.
    private func tintSelection() {
        guard let editor = input.currentEditor() as? NSTextView else { return }
        if savedSelection == nil { savedSelection = editor.selectedTextAttributes }
        editor.selectedTextAttributes = [.backgroundColor: colors.textSelection, .foregroundColor: colors.text]
    }

    private func step(_ delta: Int) {
        guard !results.isEmpty else { return }
        setHighlight((highlighted + delta + results.count) % results.count)
    }

    private func choose(_ index: Int) {
        guard results.indices.contains(index) else { return }
        // A command row is learned first (the bar stays open for `.commandBar` commands), then it runs. The row is read
        // before: learning re-ranks the rows.
        let row = results[index]
        if let key = row.usageKey { dispatch(.commandBar(.ran(key))) }
        dispatch(row.command)
    }

    private func setHighlight(_ index: Int) {
        guard index != highlighted else { return }
        highlighted = index
        for (i, row) in rows.enumerated() where i < results.count { row.setHighlighted(i == highlighted, colors) }
    }

    // MARK: Results and layout

    /// `keepHighlight` (the same text, new answers): the first row stays the first row, and a row the user moved to, with the
    /// arrows or the pointer, stays that row wherever it now sits, so Return chooses what was chosen.
    private func rerank(keepHighlight: Bool) {
        guard let bar else { return }
        let moved = keepHighlight && highlighted > 0 && results.indices.contains(highlighted) ? results[highlighted] : nil
        results = Suggest.rank(query: typed, bar: bar, appName: Product.name, siteSearch: siteSearch, prefix: prefix, resolve: resolve, completing: completion)
        // Beside the input: what Tab would do now, by Tab's own rule.
        let tab = pill == nil ? Suggest.tabAction(typed, completing: completion, bar: bar, resolve: resolve) : nil
        offer = if case .siteSearch(let engine)? = tab { engine } else { nil }
        prefixOffer = if case .prefix(let prefix)? = tab { prefix } else { nil }
        blockedPrefix = if case .blocked(let block)? = tab { block } else { nil }
        if let moved, let same = results.firstIndex(of: moved) ?? results.firstIndex(where: { $0.command == moved.command }) { highlighted = same }
        else { highlighted = keepHighlight ? min(highlighted, max(results.count - 1, 0)) : 0 }
        while rows.count < results.count {
            let index = rows.count
            let row = ResultRowView()
            row.identify(.commandBarResult(index))
            row.onHover = { [weak self] in self?.setHighlight(index) }
            row.onChoose = { [weak self] in self?.choose(index) }
            card.addSubview(row)
            rows.append(row)
        }
        for (i, row) in rows.enumerated() {
            row.isHidden = i >= results.count
            if i < results.count { row.update(results[i], highlighted: i == highlighted, colors: colors, captions: style == .centered) }
        }
        updateLeadingIcon()
        layoutCard()
    }

    /// The page's icon while its address is untouched, the completed site's icon, sparkles for Max, else the magnifier.
    private func updateLeadingIcon() {
        let o = OverlayMetrics.commandBar
        var favicon: URL?
        var symbol = "magnifyingglass"
        if bar?.aiMode != nil { symbol = "sparkles" }
        else if let first = results.first, first.kind == .current || (completion != nil && results.first?.kind != .openTyped) {
            favicon = first.favicon
            symbol = first.symbol ?? "globe"
        }
        leadingIcon.contentTintColor = colors.inputGlyph
        leadingIcon.symbolConfiguration = .init(pointSize: o.symbolPointSize.value, weight: .medium)
        let glyph = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        leadingFavicon = favicon
        if let favicon {
            leadingIcon.image = FaviconCache.shared.image(for: favicon) { [weak self] image in
                if self?.leadingFavicon == favicon { self?.leadingIcon.image = image }
            } ?? glyph
        } else {
            leadingIcon.image = glyph
        }
        leadingIcon.isHidden = pill != nil
    }

    private func layoutCard() {
        let m = Metrics.commandBar, o = OverlayMetrics.commandBar
        let attached = style == .attached
        let inputHeight = attached ? m.inputRowHeight.value : m.centeredInputRowHeight.value
        let rowHeight = m.suggestionRowHeight.value
        let listTop = inputHeight + (attached ? 0 : m.centeredListTop.value)
        let listHeight = results.isEmpty ? 0 : listTop - inputHeight + CGFloat(results.count) * rowHeight + m.listBottom.value
        let side = o.accessorySize.value

        // The accessory at the input row's right: the site-search offer and its Tab key, else ⓘ.
        // An engine's offer is Arc's words; a prefix's is its chip.
        let chipOffer = offer == nil ? prefixOffer : nil
        let offered = offer.map { "\(OverlayCopy.searchVerb) \($0.name)" } ?? prefixOffer?.title ?? blockedPrefix?.reason
        offerLabel.isHidden = chipOffer != nil || offered == nil
        offerChip.isHidden = chipOffer == nil
        keyCap.isHidden = offered == nil
        info.isHidden = offered != nil || bar?.aiMode != nil || fillsWindow
        offerLabel.stringValue = chipOffer == nil ? offered ?? "" : ""
        offerChip.title = chipOffer?.title ?? ""
        if chipOffer != nil { applyPillColors() }
        // A label draws its text 2 in from each side of its frame.
        func width(_ label: NSTextField) -> CGFloat {
            ceil((label.stringValue as NSString).size(withAttributes: [.font: label.font ?? .systemFont(ofSize: o.titleFontSize.value)]).width)
        }
        let offerWidth = chipOffer != nil ? offerChip.fittingWidth : width(offerLabel) + 4
        // Half points, as Arc's 30.5 pt Tab key.
        let keyWidth = (((keyLabel.stringValue as NSString).size(withAttributes: [.font: keyLabel.font ?? .systemFont(ofSize: o.titleFontSize.value)]).width + 2 * o.keyPadding.value) * 2).rounded(.up) / 2
        let accessoryWidth = offered != nil ? offerWidth + o.keyGap.value + keyWidth : (info.isHidden ? 0 : side)

        // Over the pill the card is 350 wide unless the input row needs more (P02-c: 359 for "Search Google Docs").
        let font = input.font ?? .systemFont(ofSize: o.attachedInputFontSize.value)
        let textWidth = ceil((input.stringValue as NSString).size(withAttributes: [.font: font]).width)
        let needed = o.textX.value + textWidth + o.offerGap.value + accessoryWidth + o.accessoryRightInset.value
        let width = attached ? min(bounds.width, max(m.attachedCardWidth.value, needed)) : bounds.width
        card.frame = CGRect(x: 0, y: 0, width: width, height: min(bounds.height, inputHeight + listHeight))
        backdrop.frame = card.bounds
        backdropTint.frame = backdrop.bounds
        card.layer?.shadowPath = CGPath(roundedRect: card.bounds, cornerWidth: o.cornerRadius.value, cornerHeight: o.cornerRadius.value, transform: nil)

        let mid = inputHeight / 2
        let iconSide = o.iconSize.value
        leadingIcon.frame = CGRect(x: o.iconCentreX.value - iconSide / 2, y: (mid - iconSide / 2).rounded(), width: iconSide, height: iconSide)
        let right = width - o.accessoryRightInset.value
        var accessoryLeft = right
        if offered != nil {
            keyCap.frame = CGRect(x: right - keyWidth, y: (mid - side / 2).rounded(), width: keyWidth, height: side)
            let keyHeight = keyLabel.intrinsicContentSize.height
            // The whole key: a centred label keeps 4 on each side, so a frame about the text's width draws it right of centre.
            keyLabel.frame = CGRect(x: 0, y: ((side - keyHeight) / 2).rounded(), width: keyWidth, height: keyHeight)
            if chipOffer != nil {
                // As tall as the Tab key and level with it.
                offerChip.frame = CGRect(x: keyCap.frame.minX - o.keyGap.value - offerWidth, y: keyCap.frame.minY, width: offerWidth, height: side)
                offerChip.baseline = nil
                accessoryLeft = offerChip.frame.minX
            } else {
                let offerHeight = offerLabel.intrinsicContentSize.height
                offerLabel.frame = CGRect(x: keyCap.frame.minX - o.keyGap.value - offerWidth, y: (mid - offerHeight / 2).rounded(), width: offerWidth, height: offerHeight)
                accessoryLeft = offerLabel.frame.minX
            }
        } else if !info.isHidden {
            info.frame = CGRect(x: right - side, y: (mid - side / 2).rounded(), width: side, height: side)
            accessoryLeft = info.frame.minX
        }

        // NSTextField draws its text 2 in from its frame.
        let fieldHeight = input.intrinsicContentSize.height
        // P21-a, Q01-a: the centered bar's text sits half a point above the row's middle.
        let fieldY = (mid - fieldHeight / 2).rounded() - (attached ? 0 : o.inputRaise.value)
        var fieldX = o.textX.value - 2
        if !sitePill.isHidden {
            // The pill's word stands on the input's baseline, and the pill sits around its capitals.
            let inputBaseline = fieldY + input.firstBaselineOffsetFromTop
            let height = prefix != nil ? o.chipHeight.value : o.hintHeight.value
            let inPill = sitePill.centredBaseline(height: height)
            sitePill.frame = CGRect(x: o.iconCentreX.value - iconSide / 2, y: inputBaseline - inPill, width: sitePill.fittingWidth, height: height)
            sitePill.baseline = inPill
            fieldX = sitePill.frame.maxX + m.stackSpacing.value
        }
        input.frame = CGRect(x: fieldX, y: fieldY, width: max(40, accessoryLeft - o.offerGap.value - fieldX + 2), height: fieldHeight)

        let scale = window?.backingScaleFactor ?? 2
        hairline.isHidden = attached || results.isEmpty
        // Q01-a/b: the hairline's top is the input row's bottom (64 under the card's top)
        hairline.frame = CGRect(x: o.rowInset.value + o.hairlineInset.value, y: inputHeight, width: max(0, width - 2 * (o.rowInset.value + o.hairlineInset.value)), height: 1 / scale)
        for (i, row) in rows.enumerated() where i < results.count {
            row.frame = CGRect(x: o.rowInset.value, y: listTop + CGFloat(i) * rowHeight + o.rowVerticalInset.value,
                               width: max(0, width - 2 * o.rowInset.value), height: rowHeight - 2 * o.rowVerticalInset.value)
        }
    }

    private func applyColors(_ scheme: Scheme, style: Style, primary: RGBA, spaceless: Bool) {
        look = (scheme, style, primary, spaceless)
        self.style = style
        colors = CommandBarColors.of(scheme, primary: primary, spaceless: spaceless)
        appearance = .of(scheme)
        let o = OverlayMetrics.commandBar
        input.font = .systemFont(ofSize: style == .attached ? o.attachedInputFontSize.value : o.centeredInputFontSize.value, weight: .medium)
        let translucent = colors.card.alphaComponent < 1
        card.layer?.backgroundColor = translucent ? nil : colors.card.cgColor
        backdropTint.layer?.backgroundColor = translucent ? colors.card.cgColor : nil
        backdrop.isHidden = !translucent
        card.layer?.borderColor = colors.border.cgColor
        card.shadow = {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(scheme == .light ? o.cardShadowAlpha.value : 0.6)
            shadow.shadowBlurRadius = o.cardShadowRadius.value
            // the card sits in a flipped view: a positive height drops the shadow below it
            shadow.shadowOffset = NSSize(width: 0, height: o.cardShadowOffset.value)
            return shadow
        }()
        hairline.layer?.backgroundColor = colors.hairline.cgColor
        applyPillColors()
        offerLabel.textColor = colors.secondary
        keyCap.layer?.backgroundColor = colors.accessory.cgColor
        keyLabel.textColor = colors.accessoryText
        info.apply(colors)
        input.textColor = colors.text
        if input.currentEditor() != nil { tintSelection() }
        for (i, row) in rows.enumerated() where i < results.count { row.update(results[i], highlighted: i == highlighted, colors: colors, captions: style == .centered) }
        applySiteSearchLook()
    }

    /// Arc's `arc_commandBarBounce`: the card springs from Metrics.commandBar.openBounceFrom to full size about its
    /// centre, with no fade.
    private func bounce() {
        guard let layer = card.layer else { return }
        let from = Metrics.commandBar.openBounceFrom.value
        let centre = CGPoint(x: card.bounds.midX, y: card.bounds.midY)
        var start = CATransform3DMakeTranslation(centre.x, centre.y, 0)
        start = CATransform3DScale(start, from, from, 1)
        start = CATransform3DTranslate(start, -centre.x, -centre.y, 0)
        let spring = CASpringAnimation(keyPath: "transform")
        spring.fromValue = NSValue(caTransform3D: start)
        spring.toValue = NSValue(caTransform3D: CATransform3DIdentity)
        spring.stiffness = OverlayMetrics.commandBar.bounceStiffness.value
        spring.damping = OverlayMetrics.commandBar.bounceDamping.value
        spring.duration = spring.settlingDuration
        layer.add(spring, forKey: "arc_commandBarBounce")
    }

    // MARK: Pointer

    /// Only the card takes clicks; the empty part of the box below it belongs to whatever is underneath.
    public override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, card.frame.contains(convert(point, from: superview)) else { return nil }
        return super.hitTest(point)
    }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { removeEventMonitor() } else if !isHidden { installEventMonitor() }
    }

    /// Site-search Escape runs before the window's shortcut table. Outside clicks still reach their target after
    /// dismissing the bar.
    private func installEventMonitor() {
        guard eventMonitor == nil, window != nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                if event.type == .keyDown {
                    guard event.window != nil || NSApp.keyWindow === self?.window else { return false }
                    return self?.takeSiteSearchEscape(event) == true
                }
                self?.mouseDownSomewhere(event)
                return false
            }
            return consumed ? nil : event
        }
    }

    private func removeEventMonitor() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
    }

    private func mouseDownSomewhere(_ event: NSEvent) {
        guard !isHidden, let window, event.window === window else { return }
        if !card.bounds.contains(card.convert(event.locationInWindow, from: nil)) { dispatch(.commandBar(.dismiss)) }
    }
}

/// The ⓘ at the input row's right: a 24 pt circle with the info glyph (Arc: `CommandBarIconView` infoOutline). It
/// opens the keyboard shortcuts.
@MainActor
final class InfoButton: NSView {
    var onClick: () -> Void = {}
    private let glyph = NSImageView()

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        glyph.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: "Keyboard Shortcuts")
        glyph.symbolConfiguration = .init(pointSize: 16, weight: .regular)
        addSubview(glyph)
        toolTip = "Keyboard Shortcuts"
        setAccessibilityRole(.button)
        setAccessibilityLabel("Keyboard Shortcuts")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    func apply(_ colors: CommandBarColors) {
        layer?.backgroundColor = colors.infoCircle.cgColor
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.12
        layer?.shadowRadius = 2
        layer?.shadowOffset = CGSize(width: 0, height: -0.5)
        glyph.contentTintColor = colors.accessoryText
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        let size = glyph.intrinsicContentSize
        glyph.frame = CGRect(x: ((bounds.width - size.width) / 2).rounded(), y: ((bounds.height - size.height) / 2).rounded(), width: size.width, height: size.height)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onClick() }
    }
}

/// One result row: icon (on a tile for Arc's own entries, and for a favicon on the highlighted row), the title with a
/// top domain's " — domain", and on the right "Switch to Tab" and its arrow square, or an action's key hint.
@MainActor
final class ResultRowView: NSView {
    var onHover: () -> Void = {}
    var onChoose: () -> Void = {}
    private let tile = NSView()
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    /// " — youtube.com/c/thebrowsercompany": its own label, so a long address loses its middle, as Arc's do (P20-a).
    private let detail = NSTextField(labelWithString: "")
    private let hint = NSTextField(labelWithString: "")
    private let hintPill = NSView()
    private let arrow = NSView()
    private let arrowGlyph = NSImageView()
    private var favicon: URL?
    private var suggestion: Suggestion?
    private var captions = true
    private var isSwitch = false
    private var hasFavicon = false

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layer?.cornerCurve = .continuous
        layer?.cornerRadius = OverlayMetrics.commandBar.rowCornerRadius.value
        label.lineBreakMode = .byTruncatingTail
        label.cell?.truncatesLastVisibleLine = true
        detail.lineBreakMode = .byTruncatingMiddle
        hint.alignment = .center
        hintPill.wantsLayer = true
        hintPill.layer?.cornerCurve = .continuous
        hintPill.layer?.cornerRadius = OverlayMetrics.commandBar.hintRadius.value
        for view in [tile, arrow] {
            view.wantsLayer = true
            view.layer?.cornerCurve = .continuous
            view.layer?.cornerRadius = OverlayMetrics.commandBar.hintRadius.value
        }
        icon.imageScaling = .scaleProportionallyUpOrDown
        arrowGlyph.image = NSImage(systemSymbolName: "arrow.right", accessibilityDescription: nil)
        arrowGlyph.symbolConfiguration = .init(pointSize: 16, weight: .semibold)
        arrow.addSubview(arrowGlyph)
        hintPill.addSubview(hint)
        for view in [tile, icon, label, detail, hintPill, arrow] { addSubview(view) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { true }

    /// `captions`: Switch to Tab and its arrow (the centered bar); over the URL pill the card is too narrow for them.
    func update(_ suggestion: Suggestion, highlighted: Bool, colors: CommandBarColors, captions: Bool) {
        self.suggestion = suggestion
        self.captions = captions
        // The Ask row lays out like Switch to Tab: the caption and the arrow square (P49).
        // So does a tab found by meaning: it switches to that tab.
        isSwitch = suggestion.kind == .switchToTab || suggestion.kind == .ask || (suggestion.kind == .meaning && suggestion.hint == OverlayCopy.switchToTab)
        let symbol = suggestion.kind == .ask ? ArcGlyphs.flower(size: OverlayMetrics.commandBar.iconSize.value, lineWidth: 1.2)
            : NSImage(systemSymbolName: suggestion.symbol ?? "globe", accessibilityDescription: nil)
        icon.symbolConfiguration = .init(pointSize: OverlayMetrics.commandBar.symbolPointSize.value, weight: .medium)
        favicon = suggestion.favicon
        hasFavicon = false
        // A file's, an app's or an emoji's own picture draws in its colors, on the highlight's tile like a favicon.
        if let picture = suggestion.icon.map(LocalIcons.image) {
            icon.image = picture
            hasFavicon = true
        } else if let url = suggestion.favicon, let image = FaviconCache.shared.image(for: url, then: { [weak self] image in
            guard let self, self.favicon == url else { return }
            self.icon.image = image
            self.hasFavicon = true
            if let s = self.suggestion { self.paint(s, highlighted: self.isHighlighted, colors) }
        }) {
            icon.image = image
            hasFavicon = true
        } else {
            icon.image = symbol
        }
        hint.font = .systemFont(ofSize: isSwitch ? OverlayMetrics.commandBar.titleFontSize.value : OverlayMetrics.commandBar.hintFontSize.value, weight: .medium)
        hint.stringValue = suggestion.hint ?? ""
        hintPill.isHidden = suggestion.hint == nil || (isSwitch && !captions)
        arrow.isHidden = !(isSwitch && captions)
        // The Ask row's arrow square names it for the control socket (rows are otherwise known by index).
        if suggestion.kind == .ask { arrow.identify(.aiControl("ask-row")) } else { arrow.setAccessibilityIdentifier(nil) }
        setAccessibilityLabel(suggestion.title)
        setHighlighted(highlighted, colors)
        needsLayout = true
    }

    private var isHighlighted = false
    private var lastColors: CommandBarColors?

    func setHighlighted(_ highlighted: Bool, _ colors: CommandBarColors) {
        isHighlighted = highlighted
        lastColors = colors
        layer?.backgroundColor = highlighted ? colors.highlight.cgColor : nil
        setAccessibilitySelected(highlighted)
        if let suggestion { paint(suggestion, highlighted: highlighted, colors) }
    }

    private func paint(_ suggestion: Suggestion, highlighted: Bool, _ colors: CommandBarColors) {
        let o = OverlayMetrics.commandBar
        let ink = highlighted ? colors.onHighlight : colors.text
        label.attributedStringValue = NSAttributedString(string: suggestion.title, attributes: [
            .font: NSFont.systemFont(ofSize: o.titleFontSize.value, weight: .medium), .foregroundColor: ink,
        ])
        // Over the URL pill (captions off) rows are titles only, P02-b.
        let subtitle = captions ? suggestion.subtitle ?? "" : ""
        detail.isHidden = subtitle.isEmpty
        // A style of its own: without one an attributed string wraps at the last word that fits instead of cutting the middle.
        let cut = NSMutableParagraphStyle()
        cut.lineBreakMode = .byTruncatingMiddle
        detail.attributedStringValue = NSAttributedString(string: " — " + subtitle, attributes: [
            .paragraphStyle: cut,
            .font: NSFont.systemFont(ofSize: o.titleFontSize.value, weight: .medium),
            .foregroundColor: highlighted ? colors.onHighlight.withAlphaComponent(0.7) : colors.secondary,
        ])
        // Arc's own entries keep their tile; a favicon gets a white one on the highlight so it stays legible. A glyph on
        // the highlight's white tile takes the highlight's color (P21-a's Contact the Team).
        tile.isHidden = !(suggestion.tile || (highlighted && hasFavicon))
        let onTile = !tile.isHidden && highlighted
        icon.contentTintColor = suggestion.accent.map { NSColor(srgbRed: $0.red, green: $0.green, blue: $0.blue, alpha: $0.alpha) }
            ?? (onTile ? colors.highlight : highlighted || hasFavicon ? ink : colors.rowGlyph)
        tile.layer?.backgroundColor = (highlighted ? colors.tileOnHighlight : colors.accessory).cgColor
        if isSwitch {
            hint.textColor = highlighted ? colors.onHighlight : colors.secondary
            hintPill.layer?.backgroundColor = nil
        } else {
            hint.textColor = highlighted ? colors.onHighlight : colors.accessoryText
            hintPill.layer?.backgroundColor = colors.accessory.cgColor
        }
        arrow.layer?.backgroundColor = (highlighted ? colors.tileOnHighlight : colors.accessory).cgColor
        arrowGlyph.contentTintColor = colors.accessoryText
    }

    override func layout() {
        super.layout()
        let m = Metrics.commandBar, o = OverlayMetrics.commandBar
        let side = o.iconSize.value, tileSide = o.accessorySize.value
        // Icon centre and text start are measured from the card; this row starts rowInset into it.
        let iconCentre = o.iconCentreX.value - o.rowInset.value
        icon.frame = CGRect(x: iconCentre - side / 2, y: ((bounds.height - side) / 2).rounded(), width: side, height: side)
        tile.frame = CGRect(x: iconCentre - tileSide / 2, y: ((bounds.height - tileSide) / 2).rounded(), width: tileSide, height: tileSide)
        var right = bounds.width - o.arrowRightInset.value
        if !arrow.isHidden {
            arrow.frame = CGRect(x: right - tileSide, y: ((bounds.height - tileSide) / 2).rounded(), width: tileSide, height: tileSide)
            let g = arrowGlyph.intrinsicContentSize
            arrowGlyph.frame = CGRect(x: ((tileSide - g.width) / 2).rounded(), y: ((tileSide - g.height) / 2).rounded(), width: g.width, height: g.height)
            // Q01-a: 9 between "Switch to Tab" and its square (the label keeps 2 of them inside its frame).
            right = arrow.frame.minX - 7
        }
        if !hintPill.isHidden {
            let textWidth = ceil(hint.intrinsicContentSize.width)
            let padding = isSwitch ? 0 : o.hintPadding.value
            let pill = CGSize(width: textWidth + 2 * padding, height: isSwitch ? tileSide : o.hintHeight.value)
            hintPill.frame = CGRect(x: right - pill.width, y: ((bounds.height - pill.height) / 2).rounded(), width: pill.width, height: pill.height)
            let textHeight = hint.intrinsicContentSize.height
            // A little room each side of the centred text: exactly the measured width can cut its last letter ("Copy Emoji").
            let slack = isSwitch ? 0 : o.hintTextSlack.value
            hint.frame = CGRect(x: padding - slack, y: ((pill.height - textHeight) / 2).rounded(), width: textWidth + 2 * slack, height: textHeight)
            right = hintPill.frame.minX - m.stackSpacing.value
        }
        let x = o.textX.value - o.rowInset.value - 2
        let height = label.intrinsicContentSize.height
        // Widths from the text itself (a label pads 2 on each side): the title is whole unless the row cannot hold it,
        // and only the address after it gives way, from its middle (P20-a, Q01-b).
        let titleWidth = min(ceil(label.attributedStringValue.size().width) + 4, max(0, right - x))
        label.frame = CGRect(x: x, y: ((bounds.height - height) / 2).rounded(), width: titleWidth, height: height)
        // The label pads 2 on each side, so the detail starts 4 back to sit right after the title's text.
        let detailX = label.frame.maxX - 4
        detail.frame = CGRect(x: detailX, y: label.frame.minY, width: max(0, min(ceil(detail.attributedStringValue.size().width) + 4, right - detailX, (bounds.width * o.detailMaxShare.value).rounded())), height: height)
    }

    // Hover follows pointer motion (not entry), so rows sliding under a still pointer keep the keyboard highlight.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseMoved(with event: NSEvent) { onHover() }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// Taken so the click does not reach the window; the input keeps keyboard focus.
    override func mouseDown(with event: NSEvent) {}
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { onChoose() }
    }
}

extension NSShadow {
    /// Arc's popover shadow (PopoverShadow color; blur and drop are ours). Set through `NSView.shadow`, which AppKit
    /// keeps in sync with the layer, so it is not lost when AppKit updates a layer-backed view.
    static func popover(_ colors: OverlayColors) -> NSShadow {
        let shadow = NSShadow()
        shadow.shadowColor = colors.popoverShadow
        shadow.shadowBlurRadius = OverlayMetrics.commandBar.shadowRadius.value
        shadow.shadowOffset = NSSize(width: 0, height: -OverlayMetrics.commandBar.shadowOffset.value)
        return shadow
    }
}

/// A plain container with top-left origin, like every BrkUI container.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// The pictures of Brk's own rows: the system's icon for an app, once per path, for a kind of file, or an emoji drawn at
/// the row's icon size. A file's row uses its kind because asking for a file's own icon touches the file, and macOS asks
/// the user before an app touches the Desktop, Documents or Downloads folder.
@MainActor
enum LocalIcons {
    private static var files: [String: NSImage] = [:]

    static func image(_ icon: Suggestion.Icon) -> NSImage {
        switch icon {
        case .file(let path):
            if let image = files[path] { return image }
            if files.count > 200 { files.removeAll() }
            let image = NSWorkspace.shared.icon(forFile: path)
            files[path] = image
            return image
        case .document(let name, let contentType):
            return NSWorkspace.shared.icon(for: contentType.flatMap { UTType($0) } ?? UTType(filenameExtension: (name as NSString).pathExtension) ?? .data)
        case .swatch(let color):
            let side = OverlayMetrics.commandBar.iconSize.value
            return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
                let path = NSBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), xRadius: OverlayMetrics.commandBar.hintRadius.value, yRadius: OverlayMetrics.commandBar.hintRadius.value)
                NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha).setFill()
                path.fill()
                NSColor.black.withAlphaComponent(0.2).setStroke()
                path.stroke()
                return true
            }
        case .emoji(let emoji):
            let side = OverlayMetrics.commandBar.iconSize.value
            return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
                let text = NSAttributedString(string: emoji, attributes: [.font: NSFont.systemFont(ofSize: side * 0.82)])
                let size = text.size()
                text.draw(at: NSPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2))
                return true
            }
        }
    }
}

/// Favicons for result rows, archive entries and the tab switcher, fetched once per URL.
@MainActor
public final class FaviconCache {
    public static let shared = FaviconCache()
    private var images: [URL: NSImage] = [:]
    private var waiting: [URL: [(NSImage) -> Void]] = [:]

    /// The cached image, or nil now and `then` once it arrives (never, if the fetch fails).
    public func image(for url: URL, then: @escaping (NSImage) -> Void) -> NSImage? {
        if let image = images[url] { return image }
        if waiting[url] != nil {
            waiting[url]?.append(then)
            return nil
        }
        waiting[url] = [then]
        Task {
            let data = try? await URLSession.shared.data(from: url).0
            let callbacks = waiting.removeValue(forKey: url) ?? []
            guard let data, let image = NSImage(data: data) else { return }
            images[url] = image
            for callback in callbacks { callback(image) }
        }
        return nil
    }
}
