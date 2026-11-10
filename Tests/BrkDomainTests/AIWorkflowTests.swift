import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

final class AIWorkflowTests: XCTestCase {
    private func enabled() -> Driver {
        let d = Driver()
        for feature in AIFeature.allCases { d.user(.settings(.max(.feature(feature, true)))) }
        return d
    }
    private func request(_ transition: Transition) throws -> (AIRequestID, AITask) {
        for case .ai(let id, let task, _) in transition.effects { return (id, task) }
        throw XCTUnwrapError()
    }
    private struct XCTUnwrapError: Error {}
    private func content(_ d: Driver, text: String = "Bonjour") throws -> AIPageContent {
        let page = try XCTUnwrap(d.state.findPage(in: d.window))
        let browser = try XCTUnwrap(d.state.session.live[page]?.browser)
        let doc = DocumentToken(browser: browser, sequence: d.state.session.live[page]!.documentSequence + 1)
        d.page(page.item, .documentChanged(.loading(doc)))
        d.page(page.item, .documentChanged(.ready(doc)))
        return AIPageContent(document: doc, url: start, title: "Source", language: "fr", text: text, nodes: [AITextNode(id: 0, text: text)])
    }
    private func readRequest(_ t: Transition) throws -> AIRequestID {
        try XCTUnwrap(t.effects.compactMap { if case .aiRead(let id, _) = $0 { id } else { nil } }.first)
    }

    func testQuestionStreamsCancelsAndDropsLateAnswersWithoutPersistence() throws {
        let d = enabled()
        d.user(.later(.aiCommandBar))
        XCTAssertEqual(d.bar?.aiMode, .question)
        let (id, task) = try request(d.user(.assist(.ask("Why?"))))
        XCTAssertEqual(task, .ask("Why?"))
        d.system(.aiPartial(id, "Partial"))
        XCTAssertEqual(d.view.ai?.text, "Partial")
        XCTAssertFalse(String(decoding: d.savedFile, as: UTF8.self).contains("Partial"))
        let transition = d.user(.assist(.cancel))
        XCTAssertTrue(transition.effects.contains(.aiCancel(id)))
        d.system(.aiResult(id, .text("Late answer")))
        XCTAssertEqual(d.view.ai?.text, "Request cancelled.")
        XCTAssertEqual(d.view.ai?.busy, false)
    }
    func testPageQuestionOnlyUsesCapturedDocumentAndCancelsOnNavigation() throws {
        let d = enabled(), c = try content(d)
        let id = try readRequest(d.user(.assist(.askPage("What?"))))
        let (_, task) = try request(d.system(.aiPageRead(id, c.document.browser.page, c)))
        XCTAssertEqual(task, .pageQuestion("What?", c))
        XCTAssertEqual(d.view.ai?.sources, [AISource(title: "Source", url: start)])
        d.user(.commandBar(.submit("https://example.com/changed")))
        d.page(c.document.browser.page.item, .documentChanged(.loading(DocumentToken(browser: c.document.browser, sequence: c.document.sequence + 1))))
        XCTAssertNil(d.state.session.ai.requests[id])
        d.system(.aiResult(id, .text("Wrong document")))
        XCTAssertNotEqual(d.view.ai?.text, "Wrong document")
    }
    func testPrivatePageNeverExtractsOrInvokesProvider() throws {
        let d = enabled()
        d.user(.window(.newIncognito))
        let window = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .incognito }?.id)
        let t = d.user(.assist(.askPage("secret")), in: window)
        XCTAssertTrue(t.effects.isEmpty)
        XCTAssertTrue(d.view(of: window).ai!.text.contains("private"))
    }
    func testOrganizeValidatesPlanAndUndoKeepsNewTabs() throws {
        let d = enabled(); d.user(.settings(.max(.tidyTabs(true))))
        _ = d.open("https://example.com/b"); let before = d.todayIDs
        let (id, task) = try request(d.user(.assist(.organizeToday)))
        guard case .tidyToday(_, let tabs) = task else { return XCTFail() }
        d.system(.aiResult(id, .reply(.groups([AIGroupPlan(folder: "Reading", tabs: tabs.map { $0.id.rawValue })]))))
        guard case .folder(let folder)? = d.view.space.today.rows.first else { return XCTFail("no Today group") }
        XCTAssertEqual(folder.children.map(\.id), before)
        // Arc's undo toast instead of an answer panel (P46: Tidy on the divider).
        XCTAssertNil(d.view.ai)
        XCTAssertEqual(d.view.tabTools.toast?.text, "Tidied Tabs! Use")
        XCTAssertNil(d.view.tabTools.toast?.placement, "a toast about the window stays at its corner")
        XCTAssertEqual(d.view.tabTools.toast?.keycap, "⌘Z")
        XCTAssertFalse(d.view.space.today.tidying)
        let newTab = d.open("https://example.com/new")
        d.user(.assist(.undoOrganize))
        XCTAssertEqual(d.todayIDs, before + [newTab])
        XCTAssertEqual(Driver(file: d.savedFile).todayIDs, before + [newTab])
    }
    /// Arc 1.170 keeps Tidy on its undo list: ⌘Z undoes it from a page after the toast has gone (probed 2026-11-10).
    /// A text field in the page keeps ⌘Z for its own typing.
    func testCommandZUndoesTidyAfterTheToastUnlessATextFieldHasFocus() throws {
        let d = enabled(); d.user(.settings(.max(.tidyTabs(true))))
        _ = d.open("https://example.com/b"); let before = d.todayIDs
        let (id, task) = try request(d.user(.assist(.organizeToday)))
        guard case .tidyToday(_, let tabs) = task else { return XCTFail() }
        d.system(.aiResult(id, .reply(.groups([AIGroupPlan(folder: "Reading", tabs: tabs.map { $0.id.rawValue })]))))
        d.advance(.seconds(6)); d.system(.clockTick)
        XCTAssertNil(d.view.tabTools.toast)
        let commandZ = KeyChord(.command, .z)
        XCTAssertFalse(d.key(commandZ, stage: .beforePage, pressID: 1, editable: true).keyHandled, "the text field's own undo")
        guard case .folder? = d.view.space.today.rows.first else { return XCTFail("a text field's ⌘Z undid Tidy") }
        XCTAssertTrue(d.key(commandZ, stage: .beforePage, pressID: 2).keyHandled)
        XCTAssertEqual(d.todayIDs, before)
        XCTAssertFalse(d.key(commandZ, stage: .beforePage, pressID: 3).keyHandled, "nothing left to undo: the page's ⌘Z")
    }
    func testOrganizeRejectsStaleForeignAndDuplicateIDsAtomically() throws {
        let d = enabled(); d.user(.settings(.max(.tidyTabs(true)))); _ = d.open("https://example.com/b")
        let (id, _) = try request(d.user(.assist(.organizeToday)))
        let before = d.todayIDs
        d.system(.aiResult(id, .reply(.groups([AIGroupPlan(folder: "Bad", tabs: ["foreign"])]))))
        XCTAssertEqual(d.todayIDs, before)
        XCTAssertTrue(d.view.tabTools.toast?.text.contains("invalid") == true)
        let (second, task) = try request(d.user(.assist(.organizeToday)))
        guard case .tidyToday(_, let tabs) = task else { return XCTFail() }
        _ = d.open("https://example.com/c")
        d.system(.aiResult(second, .reply(.groups([AIGroupPlan(folder: "Reading", tabs: tabs.map { $0.id.rawValue })]))))
        XCTAssertEqual(d.todayIDs.count, 3)
        XCTAssertFalse(d.view.space.today.rows.contains { if case .folder = $0 { true } else { false } })
        XCTAssertNil(AIValidation.plan([AIGroupPlan(folder: "x", tabs: ["a", "a"])], eligible: [AITab(id: ItemID("a"), title: "", url: start)]))
    }
    func testBrowseHiddenPagesOwnContextAndCloseBeforeAnswer() throws {
        let d = enabled()
        d.user(.assist(.browse(question: "Compare", sources: [start, url("https://example.com/b")])))
        let id = try XCTUnwrap(d.view.ai?.request)
        let hidden = d.snapshot.pages.filter(\.isAIReader)
        XCTAssertEqual(hidden.count, 2)
        XCTAssertTrue(hidden.allSatisfy { $0.context == .profile(.default) })
        for (index, spec) in hidden.enumerated() {
            let browser = BrowserToken(page: spec.id, generation: 1), doc = DocumentToken(browser: BrowserToken(page: spec.id, generation: 1), sequence: 1)
            d.system(.page(browser, .browserCreated(spec.context, .ready(doc))))
            let c = AIPageContent(document: doc, url: spec.initialURL!, title: "Source \(index)", language: "en", text: "Fixture \(index)", nodes: [])
            d.system(.aiPageRead(id, spec.id, c))
        }
        XCTAssertTrue(d.snapshot.pages.filter(\.isAIReader).isEmpty)
        XCTAssertEqual(d.view.ai?.sources.count, 2)
        guard case .browse = d.state.session.pendingAI[id] else { return XCTFail("no source-grounded task") }
        d.system(.aiResult(id, .text("Answer [1] [2]")))
        XCTAssertEqual(d.view.ai?.text, "Answer [1] [2]")
        XCTAssertFalse(String(decoding: d.savedFile, as: UTF8.self).contains("Answer [1]"))
    }
    func testPreviewRequiresDeliberateHoverAndCancels() throws {
        let d = enabled(), tab = try XCTUnwrap(d.current?.id)
        let c = try content(d)
        let transition = d.page(tab, .linkHovered(start))
        XCTAssertTrue(transition.effects.contains(.aiHover(d.window, start, c.document)))
        XCTAssertTrue(d.snapshot.pages.filter(\.isAIReader).isEmpty)
        let link = CGRect(x: 236, y: 74, width: 130, height: 25)
        d.system(.aiHoverReady(d.window, start, link))
        // Arc's card under the link (P45-a), not the answer panel.
        XCTAssertNil(d.view.ai)
        let card = try XCTUnwrap(d.view.aiPreview)
        XCTAssertEqual(card.link, link); XCTAssertTrue(card.busy); XCTAssertEqual(card.page, c.document.browser.page)
        let id = try XCTUnwrap(card.request)
        XCTAssertEqual(d.snapshot.pages.filter(\.isAIReader).count, 1)
        d.page(tab, .linkHovered(nil))
        XCTAssertTrue(d.snapshot.pages.filter(\.isAIReader).isEmpty)
        XCTAssertNil(d.state.session.ai.requests[id])
        XCTAssertNil(d.view.aiPreview)
    }
    func testInstantLinksRowOpensTheVerifiedResultsAndFailsInPlace() throws {
        let d = enabled()
        let before = d.todayIDs
        let (id, _) = try request(d.user(.assist(.instant("wikipedia arc browser, wikipedia chrome"))))
        // Arc's row heads Today (P48-a); no answer panel.
        XCTAssertNil(d.view.ai)
        guard case .tab(let row)? = d.view.space.today.rows.first else { return XCTFail("no Instant Links row") }
        XCTAssertEqual(row.instant, .searching); XCTAssertEqual(row.title, "Searching the web for you…")
        d.system(.aiResult(id, .reply(.links(["https://en.wikipedia.org/wiki/Arc_(web_browser)", "javascript:alert(1)", "https://en.wikipedia.org/wiki/Google_Chrome"]))))
        let readers = d.snapshot.pages.filter(\.isAIReader)
        XCTAssertEqual(readers.map(\.initialURL), [url("https://en.wikipedia.org/wiki/Arc_(web_browser)"), url("https://en.wikipedia.org/wiki/Google_Chrome")])
        for reader in readers {
            let doc = DocumentToken(browser: BrowserToken(page: reader.id, generation: 1), sequence: 1)
            d.system(.page(BrowserToken(page: reader.id, generation: 1), .browserCreated(reader.context, .ready(doc))))
            d.system(.aiPageRead(id, reader.id, AIPageContent(document: doc, url: reader.initialURL!, title: "Result", language: "en", text: "", nodes: [])))
        }
        // Both open as Today tabs at the top in the tool's order, the first shown; the row is gone.
        XCTAssertEqual(d.todayIDs.count, before.count + 2)
        XCTAssertEqual(d.current?.id, d.todayIDs.first)
        XCTAssertTrue(d.snapshot.pages.filter(\.isAIReader).isEmpty)
        XCTAssertFalse(d.view.space.today.rows.contains { if case .tab(let t) = $0 { t.instant != nil } else { false } })
        // An unsafe reply leaves Arc's failed row, whose × removes it.
        let (bad, _) = try request(d.user(.assist(.instant("some site"))))
        d.system(.aiResult(bad, .reply(.links(["javascript:alert(1)"]))))
        guard case .tab(let failed)? = d.view.space.today.rows.first else { return XCTFail("failed row missing") }
        XCTAssertEqual(failed.instant, .failed); XCTAssertEqual(failed.title, "Oops, something went wrong.")
        d.user(.tabTools(.bulk(.items([failed.id]), .close)))
        XCTAssertNotEqual(d.view.space.today.rows.first?.id, failed.id)
        XCTAssertEqual(AIValidation.destinations(["https://a.example/", "https://a.example/", "https://b.example/x", "file:///etc/passwd"]), [url("https://a.example/"), url("https://b.example/x")])
        for value in ["file:///tmp/a", "https://u:p@example.com", "https://example.com bad", "data:text/html,x"] { XCTAssertNil(AIValidation.destination(value)) }
    }
    func testTranslationValidatesExactNodesAndPersistsOnlyProfileExclusions() throws {
        let d = enabled(), c = try content(d)
        let id = try readRequest(d.user(.assist(.translate("English"))))
        d.system(.aiPageRead(id, c.document.browser.page, c))
        let invalid = d.system(.aiResult(id, .reply(.translation([AITextNode(id: 9, text: "Hello")]))))
        XCTAssertFalse(invalid.effects.contains { if case .aiTranslate = $0 { true } else { false } })
        let second = try readRequest(d.user(.assist(.translate("English"))))
        d.system(.aiPageRead(second, c.document.browser.page, c))
        let valid = d.system(.aiResult(second, .reply(.translation([AITextNode(id: 0, text: "Hello")]))))
        XCTAssertTrue(valid.effects.contains(.aiTranslate(second, c, [AITextNode(id: 0, text: "Hello")])))
        d.system(.aiTranslated(second, true))
        d.user(.assist(.neverTranslateLanguage))
        let restored = Driver(file: d.savedFile)
        XCTAssertEqual(restored.snapshot.settings.max.settings.translationExclusions?[.default]?.languages, ["fr"])
        let blocked = d.user(.assist(.translate("English")))
        XCTAssertFalse(blocked.effects.contains { if case .aiRead = $0 { true } else { false } })
        XCTAssertTrue(d.view.tabTools.toast?.text.contains("never translates") == true)
    }
    /// Arc's translation (P50): the page menu's Translate to English, the pill's Translated, Use Original with its
    /// "Translated back to French! Use ⌘Z to undo." toast, ⌘Z, and Choose Another Language.
    func testPageMenuTranslationPillPopoverAndUndo() throws {
        let d = enabled(), c = try content(d), page = c.document.browser.page
        d.page(page.item, .languageDetected(c.document, "fr"))
        XCTAssertEqual(d.view.urlPill.translation, .available)
        let menu = d.page(page.item, .translateRequested("English"))
        let id = try readRequest(menu)
        XCTAssertEqual(d.view.urlPill.translation, .translating)
        d.system(.aiPageRead(id, page, c))
        d.system(.aiResult(id, .reply(.translation([AITextNode(id: 0, text: "Hello")]))))
        d.system(.aiTranslated(id, true))
        XCTAssertNil(d.view.ai)
        XCTAssertEqual(d.view.urlPill.translation, .translated(from: "French"))
        let original = d.user(.assist(.useOriginal))
        XCTAssertTrue(original.effects.contains(.aiShowTranslation(c.document, translated: false)))
        XCTAssertEqual(d.view.urlPill.translation, .available)
        XCTAssertEqual(d.view.tabTools.toast?.text, "Translated back to French! Use")
        XCTAssertEqual(d.view.tabTools.toast?.keycap, "⌘Z")
        XCTAssertEqual(d.view.tabTools.toast?.placement, .page, "Arc shows this one inside the page card (P50-e)")
        let undo = d.user(.tabTools(.undoToast))
        XCTAssertTrue(undo.effects.contains(.aiShowTranslation(c.document, translated: true)))
        XCTAssertEqual(d.view.urlPill.translation, .translated(from: "French"))
        // Choose Another Language translates again; the page's own language stays French.
        let german = try readRequest(d.user(.assist(.translate("German"))))
        d.system(.aiPageRead(german, page, c))
        d.system(.aiResult(german, .reply(.translation([AITextNode(id: 0, text: "Hallo")]))))
        d.system(.aiTranslated(german, true))
        XCTAssertEqual(d.view.urlPill.translation, .translated(from: "French"))
        // A new document is the page's own text again.
        let next = DocumentToken(browser: c.document.browser, sequence: c.document.sequence + 1)
        d.page(page.item, .documentChanged(.loading(next)))
        d.page(page.item, .documentChanged(.ready(next)))
        XCTAssertNil(d.view.urlPill.translation)
        d.page(page.item, .languageDetected(next, "en-US"))
        XCTAssertNil(d.view.urlPill.translation, "a page in the system language offers nothing")
        d.user(.assist(.languageSettings))
        XCTAssertEqual(d.current?.url, url("chrome://settings/languages"))
        XCTAssertEqual(AILanguages.name("fr-CA"), "French")
        XCTAssertTrue(AILanguages.targets.prefix(3) == ["Afrikaans", "Akan", "Albanian"])
    }
    func testDownloadNamesRejectPathsAndKeepExtension() {
        for text in ["../../x", "/tmp/x", "a\\b", "a:b", ".hidden", "a\nb"] { XCTAssertNil(AIValidation.filename(text, original: "x.pdf")) }
        XCTAssertEqual(AIValidation.filename("Reading.pdf", original: "x.pdf"), "Reading.pdf")
        XCTAssertEqual(AIValidation.filename("Reading", original: "x.pdf"), "Reading.pdf")
    }
    func testCompletedDownloadOnlyAndRenameReceipt() throws {
        let d = enabled(), tab = try XCTUnwrap(d.current?.id), download = DownloadID("ai-download")
        d.download(tab, download, .receiving(TransferProgress(received: 0, total: nil)))
        XCTAssertFalse(d.user(.assist(.renameDownload(download))).effects.contains { if case .ai = $0 { true } else { false } })
        let t = d.download(tab, download, .terminal(.completed(FileReceipt(url: URL(fileURLWithPath: "/tmp/fixture.txt"), bytes: 8))))
        let (id, _) = try request(t)
        let renamed = d.system(.aiResult(id, .reply(.text("Reading.txt"))))
        XCTAssertTrue(renamed.effects.contains(.aiRenameDownload(download, originalPath: "/tmp/fixture.txt", filename: "Reading.txt")))
        d.system(.aiDownloadRenamed(download, originalPath: "/tmp/fixture.txt", newPath: "/tmp/Reading.txt", error: nil))
        XCTAssertEqual(d.state.doc.downloads.first?.filename, "Reading.txt")
    }

    func testProfileChangeClearsCompletedAnswerAndCancelsHiddenSources() throws {
        let d = enabled()
        let (id, _) = try request(d.user(.assist(.ask("why"))))
        d.system(.aiResult(id, .text("Source profile answer")))
        d.user(.profile(.create(name: "Other", icon: nil)))
        let other = try XCTUnwrap(d.snapshot.settings.profiles.first { $0.profile.id != .default }?.profile.id)
        d.user(.profile(.assign(.current, to: other)))
        XCTAssertNil(d.view.ai)
        d.user(.assist(.browse(question: "Read", sources: [start])))
        let requestID = try XCTUnwrap(d.view.ai?.request)
        XCTAssertEqual(d.snapshot.pages.first(where: \.isAIReader)?.context, .profile(other))
        d.user(.profile(.assign(.current, to: .default)))
        XCTAssertNil(d.state.session.ai.requests[requestID])
        XCTAssertTrue(d.snapshot.pages.filter(\.isAIReader).isEmpty)
    }

    func testPinAfterNavigationRenamesThePinnedHomeRatherThanOriginalSeed() throws {
        let d = enabled(), tab = try XCTUnwrap(d.current?.id), destination = url("https://example.com/navigated")
        d.user(.commandBar(.open(.editCurrent)))
        d.user(.commandBar(.submit(destination.absoluteString)))
        d.page(tab, .committed(destination))
        d.user(.settings(.max(.renamePinnedTabs(true))))
        let transition = d.user(.tab(.togglePin(.item(tab))))
        let (id, _) = try request(transition)
        XCTAssertFalse(transition.effects.contains(.aiCancel(id)))
        d.system(.aiResult(id, .reply(.text("Navigated Home"))))
        XCTAssertEqual(d.row(tab)?.title, "Navigated Home")
    }

}
