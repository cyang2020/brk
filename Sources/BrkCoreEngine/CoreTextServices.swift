import AppKit
import CBrkCore
import BrkBase
import ObjectiveC
import Foundation

/// Edit > Spelling and Grammar, Substitutions, Speech and Format > Font for the focused editor of a page (an input,
/// a textarea or a contenteditable host, also inside a same-origin frame). Chromium's input view, moved into Brk's
/// window, does not carry these out, so the surface does, with AppKit's services on the editor's text:
/// - Show Spelling and Grammar and Check Document Now find the next misspelling after the selection with
///   `NSSpellChecker` (and the next grammar issue when Check Grammar With Spelling is on), select it in the page and
///   show it in the spelling panel; the panel's Change and Ignore come back as `changeSpelling:`/`ignoreSpelling:`.
/// - Check Spelling While Typing is Chromium's own `browser.enable_spellchecking` for the page's profile, so the red
///   underlines come and go with it.
/// - The Substitutions panel's Replace buttons (`checkTextInSelection:`/`checkTextInDocument:`) apply the enabled
///   substitutions (Smart Quotes, Smart Dashes, Text Replacement, Smart Links, and corrections when Correct Spelling
///   Automatically is on) to the selection or the whole editor, one replacement at a time so formatting and undo
///   survive. Smart Copy/Paste and Data Detectors have no counterpart in a web editor and stay disabled.
/// - Start/Stop Speaking speak the selection, else the editor's text, else the page's text.
/// - Bold and Italic (NSFontManager's `changeFont:`) and Underline run the editor's formatting commands.
/// - While the user types, Smart Quotes, Smart Dashes and Text Replacement are Chromium's own: its input view checks
///   each insertion with `NSSpellChecker` and replaces as AppKit text views do, reading the three switches from the
///   `WebAutomatic…Enabled` user defaults. Brk publishes its toggles there in the registration domain (this process
///   only, nothing written to disk), so the menu's check marks are what typing does.
/// - Correct Spelling Automatically and Smart Links have no counterpart while typing in Chromium (its input view
///   implements neither), so in a web editor they are greyed as in Arc and Chrome; the Replace buttons still apply
///   Smart Links in a rich editor.
/// Toggle states are app-wide, start from the system's text settings, and are kept in the data directory.
@MainActor enum WebTextServices {
    struct State: Equatable {
        var quotes = NSSpellChecker.isAutomaticQuoteSubstitutionEnabled
        var dashes = NSSpellChecker.isAutomaticDashSubstitutionEnabled
        var replacement = NSSpellChecker.isAutomaticTextReplacementEnabled
        var links = false
        var correction = NSSpellChecker.isAutomaticSpellingCorrectionEnabled
        var grammar = false
        var flags: [String: Bool] { ["quotes": quotes, "dashes": dashes, "replacement": replacement, "links": links, "correction": correction, "grammar": grammar] }
        init() {}
        init(_ flags: [String: Bool]) {
            quotes = flags["quotes"] ?? quotes; dashes = flags["dashes"] ?? dashes; replacement = flags["replacement"] ?? replacement
            links = flags["links"] ?? links; correction = flags["correction"] ?? correction; grammar = flags["grammar"] ?? grammar
        }
    }
    private static var file: URL? {
        Product.dataDirectory().appendingPathComponent("web-text-services.json")
    }
    private static var cached: State?
    static var state: State {
        get {
            if let cached { return cached }
            let flags = file.flatMap { try? Data(contentsOf: $0) }.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Bool] }
            let loaded = flags.map(State.init) ?? State()
            cached = loaded
            publish(loaded)
            return loaded
        }
        set {
            cached = newValue
            publish(newValue)
            if let file, let data = try? JSONSerialization.data(withJSONObject: newValue.flags, options: [.sortedKeys]) { try? data.write(to: file, options: .atomic) }
        }
    }
    /// The switches Chromium's `RenderWidgetHostViewCocoa` reads before it asks for substitutions of typed text.
    static let chromiumDefaults = ["quotes": "WebAutomaticQuoteSubstitutionEnabled", "dashes": "WebAutomaticDashSubstitutionEnabled",
                                   "replacement": "WebAutomaticTextReplacementEnabled"]
    private static func publish(_ state: State) {
        let flags = state.flags
        UserDefaults.standard.register(defaults: chromiumDefaults.reduce(into: [String: Any]()) { $0[$1.value] = flags[$1.key] ?? false })
    }
    /// Loads (and publishes) the toggles before a page's input view first types.
    static func prepare() { _ = state }
    static let speech = NSSpeechSynthesizer()
    static let spellTag = NSSpellChecker.uniqueSpellDocumentTag()
}

/// AppKit's spelling and substitutions panels send their buttons' actions (`changeSpelling:`, `ignoreSpelling:`,
/// `checkTextInDocument:`, `checkTextInSelection:`) to the first responder, Chromium's input view. In Brk's window
/// that view takes `changeSpelling:` without changing anything, so on its class these actions go to the enclosing
/// page surface, which carries them out (a view outside a surface keeps Chromium's own behavior).
@MainActor enum PanelActionRouting {
    private static var installed: Set<ObjectIdentifier> = []
    private typealias Action = @convention(c) (AnyObject, Selector, AnyObject?) -> Void
    static let selectors = ["changeSpelling:", "ignoreSpelling:", "checkTextInDocument:", "checkTextInSelection:"]

    static func install(on view: NSView) {
        let cls: AnyClass = type(of: view)
        guard installed.insert(ObjectIdentifier(cls)).inserted else { return }
        for name in selectors {
            let selector = NSSelectorFromString(name)
            let inherited = class_getInstanceMethod(cls, selector)
            let original = inherited.map { unsafeBitCast(method_getImplementation($0), to: Action.self) }
            let block: @convention(block) (AnyObject, AnyObject?) -> Void = { object, sender in
                nonisolated(unsafe) let target = object, argument = sender
                let handled = MainActor.assumeIsolated { () -> Bool in
                    guard let view = target as? NSView, let surface = CoreSurface.enclosing(view) else { return false }
                    _ = surface.perform(selector, with: argument)
                    return true
                }
                if !handled { original?(object, selector, sender) }
            }
            let replacement = imp_implementationWithBlock(block)
            let added = if let types = inherited.flatMap({ method_getTypeEncoding($0) }) { class_addMethod(cls, selector, replacement, types) }
                        else { class_addMethod(cls, selector, replacement, "v@:@") }
            if !added, let inherited { method_setImplementation(inherited, replacement) }
        }
    }
}

extension CoreSurface {
    static func enclosing(_ view: NSView) -> CoreSurface? {
        var current: NSView? = view
        while let next = current { if let surface = next as? CoreSurface { return surface }; current = next.superview }
        return nil
    }

    /// The JavaScript that finds the focused editor: `find()` returns `{d, e, kind}` with kind field, rich or none.
    private static let editorPrelude = """
    const find=()=>{let d=document;for(;;){const a=d.activeElement;if(a&&a.tagName==='IFRAME'){try{if(a.contentDocument){d=a.contentDocument;continue}}catch(_){}}break}
    const e=d.activeElement;
    if(e&&(e.tagName==='TEXTAREA'||(e.tagName==='INPUT'&&['text','search','url','email',''].includes(e.type)))&&!e.readOnly&&!e.disabled)return{d,e,kind:'field'};
    if(e&&e.isContentEditable)return{d,e,kind:'rich'};
    return{d,e:null,kind:'none'}};
    const texts=f=>{const w=f.d.createTreeWalker(f.e,NodeFilter.SHOW_TEXT),out=[];for(let n=w.nextNode();n;n=w.nextNode())out.push(n);return out};
    """
    struct EditorState { var kind: String; var text: String; var start: Int; var end: Int }

    private func evaluate(_ browser: any BrkCoreWebContents, _ body: String) async -> Any? {
        let expression = "(()=>{" + Self.editorPrelude + body + "})()"
        guard let result = try? await CoreProtocolSession(contents: browser).call("Runtime.evaluate", ["expression": expression, "returnByValue": true]),
              result["exceptionDetails"] == nil else { return nil }
        return (result["result"] as? [String: Any])?["value"]
    }
    private func editorState(_ browser: any BrkCoreWebContents) async -> EditorState? {
        let value = await evaluate(browser, """
        const f=find();
        if(f.kind==='field')return{kind:'field',text:f.e.value,start:f.e.selectionStart??0,end:f.e.selectionEnd??0};
        if(f.kind==='rich'){const s=f.d.getSelection(),r=s.rangeCount?s.getRangeAt(0):null;let text='',start=null,end=null;
          for(const n of texts(f)){if(r&&n===r.startContainer)start=text.length+r.startOffset;if(r&&n===r.endContainer)end=text.length+r.endOffset;text+=n.data}
          return{kind:'rich',text,start:start??0,end:end??start??0}}
        const sel=String(f.d.getSelection()||'');return{kind:'none',text:sel||document.body.innerText,start:0,end:sel.length}
        """) as? [String: Any]
        guard let value, let kind = value["kind"] as? String, let text = value["text"] as? String else { return nil }
        return EditorState(kind: kind, text: text, start: value["start"] as? Int ?? 0, end: value["end"] as? Int ?? 0)
    }
    @discardableResult private func select(_ browser: any BrkCoreWebContents, _ range: NSRange) async -> Bool {
        await evaluate(browser, """
        const f=find(),S=\(range.location),E=\(NSMaxRange(range));
        if(f.kind==='field'){f.e.setSelectionRange(S,E);return true}
        if(f.kind!=='rich')return false;let pos=0,r=f.d.createRange(),a=false,b=false;
        for(const n of texts(f)){const l=n.data.length;if(!a&&S<=pos+l){r.setStart(n,S-pos);a=true}if(!b&&E<=pos+l){r.setEnd(n,E-pos);b=true;break}pos+=l}
        if(!a||!b)return false;const s=f.d.getSelection();s.removeAllRanges();s.addRange(r);return true
        """) as? Bool == true
    }
    @discardableResult private func run(_ browser: any BrkCoreWebContents, command: String, value: String? = nil) async -> Bool {
        // A JSON array of one string is a JavaScript array literal; its element is the escaped string.
        let argument = value.map { String(decoding: (try? JSONSerialization.data(withJSONObject: [$0])) ?? Data("[\"\"]".utf8), as: UTF8.self) + "[0]" } ?? "undefined"
        return await evaluate(browser, "const f=find();if(f.kind==='none')return false;return f.d.execCommand('\(command)',false,\(argument))") as? Bool == true
    }
    private func note(_ entry: String) {
        guard ProcessInfo.processInfo.environment["BRK_CONTROL_SOCKET"] != nil else { return }
        textServiceLog.append(entry)
        if textServiceLog.count > 64 { textServiceLog.removeFirst(textServiceLog.count - 64) }
    }

    @objc override func uppercaseWord(_ sender: Any?) { transformSelection("upper") }
    @objc override func lowercaseWord(_ sender: Any?) { transformSelection("lower") }
    @objc override func capitalizeWord(_ sender: Any?) { transformSelection("capitalize") }

    private func transformSelection(_ mode: String) {
        guard let browser = editingBrowser else { return }
        Task { @MainActor [weak self] in
            _ = await self?.evaluate(browser, """
            const f=find();if(f.kind==='none')return false;
            let text=f.kind==='field'?f.e.value.slice(f.e.selectionStart,f.e.selectionEnd):f.d.getSelection().toString();
            if(!text)return false;
            text='\(mode)'==='upper'?text.toLocaleUpperCase():'\(mode)'==='lower'?text.toLocaleLowerCase():text.toLocaleLowerCase().replace(/(^|\\s)(\\S)/gu,(_,a,b)=>a+b.toLocaleUpperCase());
            return f.d.execCommand('insertText',false,text);
            """)
        }
    }

    // MARK: Spelling and grammar

    @objc func showGuessPanel(_ sender: Any?) { advanceSpelling(showPanel: true) }
    @objc func checkSpelling(_ sender: Any?) { advanceSpelling(showPanel: false) }

    /// The next misspelling (or grammar issue) after the selection, wrapping once, selected in the page.
    private func advanceSpelling(showPanel: Bool) {
        guard let browser = editingBrowser else { return }
        Task { @MainActor [weak self] in
            guard let self, let state = await self.editorState(browser), state.kind != "none" else { NSSound.beep(); return }
            let checker = NSSpellChecker.shared, text = state.text as NSString
            let from = min(state.end, text.length)
            let spelling = checker.checkSpelling(of: state.text, startingAt: from, language: checker.language(), wrap: true,
                                                 inSpellDocumentWithTag: WebTextServices.spellTag, wordCount: nil)
            var found = spelling.location == NSNotFound ? nil : spelling
            var grammar: (range: NSRange, detail: [String: Any])?
            if WebTextServices.state.grammar {
                var details: NSArray?
                let sentence = checker.checkGrammar(of: state.text, startingAt: from, language: checker.language(), wrap: true,
                                                    inSpellDocumentWithTag: WebTextServices.spellTag, details: &details)
                if sentence.location != NSNotFound, let detail = (details as? [[String: Any]])?.first,
                   let issue = detail[NSGrammarRange] as? NSRange {
                    let range = NSRange(location: sentence.location + issue.location, length: issue.length)
                    let ahead = { (r: NSRange) in r.location >= from ? r.location - from : r.location + text.length - from }
                    if found == nil || ahead(range) < ahead(found!) { found = range; grammar = (range, detail) }
                }
            }
            guard let range = found else {
                checker.updateSpellingPanel(withMisspelledWord: "")
                if showPanel { checker.spellingPanel.orderFront(nil) }
                self.note("spelling:none"); return
            }
            await self.select(browser, range)
            if let grammar {
                checker.updateSpellingPanel(withGrammarString: text.substring(with: grammar.range), detail: grammar.detail)
                self.note("grammar:" + text.substring(with: grammar.range))
            } else {
                checker.updateSpellingPanel(withMisspelledWord: text.substring(with: range))
                self.note("spelling:" + text.substring(with: range))
            }
            if showPanel { checker.spellingPanel.orderFront(nil); self.note("panel:spelling") }
        }
    }
    /// The spelling panel's Change: `sender`'s selected cell holds the replacement for the selected word.
    @objc func changeSpelling(_ sender: Any?) {
        guard let browser = editingBrowser, let word = (sender as? NSControl)?.selectedCell()?.stringValue ?? (sender as? NSControl)?.stringValue,
              !word.isEmpty else { return }
        Task { @MainActor [weak self] in
            guard let self, await self.run(browser, command: "insertText", value: word) else { return }
            self.note("change:" + word)
        }
    }
    @objc func ignoreSpelling(_ sender: Any?) {
        guard let word = (sender as? NSControl)?.stringValue, !word.isEmpty else { return }
        NSSpellChecker.shared.ignoreWord(word, inSpellDocumentWithTag: WebTextServices.spellTag)
        note("ignore:" + word)
    }
    @objc func toggleContinuousSpellChecking(_ sender: Any?) {
        guard let browser = editingBrowser else { return }
        let on = !browser.spellCheckingEnabled
        browser.spellCheckingEnabled = on
        note("spellcheck:\(on)")
    }
    @objc func toggleGrammarChecking(_ sender: Any?) { WebTextServices.state.grammar.toggle(); note("grammar-checking:\(WebTextServices.state.grammar)") }
    @objc func toggleAutomaticSpellingCorrection(_ sender: Any?) { WebTextServices.state.correction.toggle(); note("correction:\(WebTextServices.state.correction)") }

    // MARK: Substitutions

    @objc func orderFrontSubstitutionsPanel(_ sender: Any?) { NSSpellChecker.shared.substitutionsPanel.orderFront(nil); note("panel:substitutions") }
    @objc func toggleAutomaticQuoteSubstitution(_ sender: Any?) { WebTextServices.state.quotes.toggle(); note("quotes:\(WebTextServices.state.quotes)") }
    @objc func toggleAutomaticDashSubstitution(_ sender: Any?) { WebTextServices.state.dashes.toggle(); note("dashes:\(WebTextServices.state.dashes)") }
    @objc func toggleAutomaticTextReplacement(_ sender: Any?) { WebTextServices.state.replacement.toggle(); note("replacement:\(WebTextServices.state.replacement)") }
    @objc func toggleAutomaticLinkDetection(_ sender: Any?) { WebTextServices.state.links.toggle(); note("links:\(WebTextServices.state.links)") }
    @objc func checkTextInSelection(_ sender: Any?) { applySubstitutions(selectionOnly: true) }
    @objc func checkTextInDocument(_ sender: Any?) { applySubstitutions(selectionOnly: false) }

    private func applySubstitutions(selectionOnly: Bool) {
        guard let browser = editingBrowser else { return }
        let enabled = WebTextServices.state
        Task { @MainActor [weak self] in
            guard let self, let state = await self.editorState(browser), state.kind != "none" else { return }
            let text = state.text as NSString
            let scope = selectionOnly ? NSRange(location: min(state.start, state.end), length: abs(state.end - state.start)) : NSRange(location: 0, length: text.length)
            var types: NSTextCheckingResult.CheckingType = []
            if enabled.quotes { types.insert(.quote) }
            if enabled.dashes { types.insert(.dash) }
            if enabled.replacement { types.insert(.replacement) }
            if enabled.links, state.kind == "rich" { types.insert(.link) }
            let checker = NSSpellChecker.shared
            var edits: [(range: NSRange, replacement: String, link: URL?)] = []
            if !types.isEmpty {
                for result in checker.check(state.text, range: scope, types: types.rawValue, options: nil,
                                            inSpellDocumentWithTag: WebTextServices.spellTag, orthography: nil, wordCount: nil) {
                    if result.resultType == .link, let url = result.url { edits.append((result.range, text.substring(with: result.range), url)) }
                    else if let replacement = result.replacementString { edits.append((result.range, replacement, nil)) }
                }
            }
            if enabled.correction {
                var position = scope.location
                while position < NSMaxRange(scope) {
                    let miss = checker.checkSpelling(of: state.text, startingAt: position, language: nil, wrap: false,
                                                     inSpellDocumentWithTag: WebTextServices.spellTag, wordCount: nil)
                    guard miss.location != NSNotFound, NSMaxRange(miss) <= NSMaxRange(scope) else { break }
                    if let correction = checker.correction(forWordRange: miss, in: state.text, language: checker.language(),
                                                           inSpellDocumentWithTag: WebTextServices.spellTag) {
                        edits.append((miss, correction, nil))
                    }
                    position = NSMaxRange(miss)
                }
            }
            var applied = 0
            for edit in edits.sorted(by: { $0.range.location > $1.range.location }) {
                guard await self.select(browser, edit.range) else { continue }
                let done = if let link = edit.link { await self.run(browser, command: "createLink", value: link.absoluteString) }
                           else { await self.run(browser, command: "insertText", value: edit.replacement) }
                if done { applied += 1 }
            }
            self.note("substitutions:\(applied)")
        }
    }

    // MARK: Speech and font

    @objc func startSpeaking(_ sender: Any?) {
        guard let browser = editingBrowser else { return }
        Task { @MainActor [weak self] in
            guard let self, let state = await self.editorState(browser) else { return }
            let text = state.text as NSString
            let selected = state.end > state.start ? text.substring(with: NSRange(location: state.start, length: min(state.end, text.length) - state.start)) : ""
            let spoken = (state.kind == "none" || selected.isEmpty) ? state.text : selected
            guard !spoken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            if WebTextServices.speech.isSpeaking { WebTextServices.speech.stopSpeaking() }
            let started = WebTextServices.speech.startSpeaking(spoken)
            self.note("speak:\(started):" + spoken)
        }
    }
    @objc func stopSpeaking(_ sender: Any?) { WebTextServices.speech.stopSpeaking(); note("speak-stop") }

    @objc func underline(_ sender: Any?) { format("underline") }
    /// NSFontManager's Bold and Italic: the trait the manager adds to a plain font says which command to run.
    @objc func changeFont(_ sender: Any?) {
        guard let manager = sender as? NSFontManager else { return }
        let plain = NSFont.systemFont(ofSize: NSFont.systemFontSize), converted = manager.convert(plain)
        let added = manager.traits(of: converted).subtracting(manager.traits(of: plain))
        if added.contains(.boldFontMask) { format("bold") }
        if added.contains(.italicFontMask) { format("italic") }
    }
    private func format(_ command: String) {
        guard let browser = editingBrowser else { return }
        Task { @MainActor [weak self] in
            guard let self, await self.run(browser, command: command) else { return }
            self.note("format:" + command)
        }
    }

    /// Whether the surface carries out `action` now (nil: not one of these), with the toggles' check marks.
    func validateTextService(_ item: NSMenuItem) -> Bool? {
        guard let action = item.action else { return nil }
        let toggles: [Selector: Bool] = [
            #selector(toggleGrammarChecking(_:)): WebTextServices.state.grammar,
            #selector(toggleAutomaticSpellingCorrection(_:)): WebTextServices.state.correction,
            #selector(toggleAutomaticQuoteSubstitution(_:)): WebTextServices.state.quotes,
            #selector(toggleAutomaticDashSubstitution(_:)): WebTextServices.state.dashes,
            #selector(toggleAutomaticTextReplacement(_:)): WebTextServices.state.replacement,
            #selector(toggleAutomaticLinkDetection(_:)): WebTextServices.state.links,
        ]
        if let on = toggles[action] {
            item.state = on ? .on : .off
            // Chromium does not correct spelling or make links while typing; only the Replace buttons do links.
            if action == #selector(toggleAutomaticSpellingCorrection(_:)) { return false }
            if action == #selector(toggleAutomaticLinkDetection(_:)) { return editingBrowser != nil && richEditableFocused }
            return editingBrowser != nil
        }
        if action == #selector(toggleContinuousSpellChecking(_:)) {
            guard let browser = editingBrowser else { return false }
            item.state = browser.spellCheckingEnabled ? .on : .off
            return true
        }
        let editors: Set<Selector> = [#selector(showGuessPanel(_:)), #selector(checkSpelling(_:)), #selector(orderFrontSubstitutionsPanel(_:)),
                                      #selector(checkTextInSelection(_:)), #selector(checkTextInDocument(_:))]
        if editors.contains(action) { return editingBrowser != nil && editableFocused }
        if action == #selector(startSpeaking(_:)) { return editingBrowser != nil }
        if action == #selector(stopSpeaking(_:)) { return WebTextServices.speech.isSpeaking }
        if action == #selector(underline(_:)) { return editingBrowser != nil && richEditableFocused }
        return nil
    }
}
