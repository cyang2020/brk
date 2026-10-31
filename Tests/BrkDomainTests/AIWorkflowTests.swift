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
    func testUnavailableAndFailedAnswersAreActionable() throws {
        let d = enabled()
        let (id, _) = try request(d.user(.assist(.ask("Why?"))))
        d.system(.aiResult(id, .unavailable))
        XCTAssertTrue(d.view.ai!.text.contains("Settings → Max"))
        let (second, _) = try request(d.user(.assist(.ask("Why?"))))
        d.system(.aiResult(second, .failed("Sign in in Terminal")))
        XCTAssertEqual(d.view.ai?.text, "Sign in in Terminal")
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
        let reply = "[{\"folder\":\"Reading\",\"tabs\":" + String(decoding: try JSONEncoder().encode(tabs.map { $0.id.rawValue }), as: UTF8.self) + "}]"
        d.system(.aiResult(id, .text(reply)))
        guard case .folder(let folder)? = d.view.space.today.rows.first else { return XCTFail("no Today group") }
        XCTAssertEqual(folder.children.map(\.id), before)
        XCTAssertTrue(d.view.ai!.canUndo)
        let newTab = d.open("https://example.com/new")
        d.user(.assist(.undoOrganize))
        XCTAssertEqual(d.todayIDs, before + [newTab])
        XCTAssertEqual(Driver(file: d.savedFile).todayIDs, before + [newTab])
    }
    func testOrganizeRejectsStaleForeignAndDuplicateIDsAtomically() throws {
        let d = enabled(); d.user(.settings(.max(.tidyTabs(true)))); _ = d.open("https://example.com/b")
        let (id, _) = try request(d.user(.assist(.organizeToday)))
        let before = d.todayIDs
        d.system(.aiResult(id, .text("[{\"folder\":\"Bad\",\"tabs\":[\"foreign\"]}]")))
        XCTAssertEqual(d.todayIDs, before)
        XCTAssertTrue(d.view.ai!.text.contains("invalid"))
        let (second, task) = try request(d.user(.assist(.organizeToday)))
        guard case .tidyToday(_, let tabs) = task else { return XCTFail() }
        let reply = "[{\"folder\":\"Reading\",\"tabs\":" + String(decoding: try JSONEncoder().encode(tabs.map { $0.id.rawValue }), as: UTF8.self) + "}]"
        _ = d.open("https://example.com/c")
        d.system(.aiResult(second, .text(reply)))
        XCTAssertEqual(d.todayIDs.count, 3)
        XCTAssertFalse(d.view.space.today.rows.contains { if case .folder = $0 { true } else { false } })
        XCTAssertNil(AIValidation.plan("[{\"folder\":\"x\",\"tabs\":[\"a\",\"a\"]}]", eligible: [AITab(id: ItemID("a"), title: "", url: start)]))
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
        _ = try content(d)
        let transition = d.page(tab, .linkHovered(start))
        XCTAssertTrue(transition.effects.contains(.aiHover(d.window, start)))
        XCTAssertTrue(d.snapshot.pages.filter(\.isAIReader).isEmpty)
        d.system(.aiHoverReady(d.window, start))
        let id = try XCTUnwrap(d.view.ai?.request)
        XCTAssertEqual(d.snapshot.pages.filter(\.isAIReader).count, 1)
        d.page(tab, .linkHovered(nil))
        XCTAssertTrue(d.snapshot.pages.filter(\.isAIReader).isEmpty)
        XCTAssertNil(d.state.session.ai.requests[id])
    }
    func testInstantRejectsUnsafeURLAndFallbackUsesNormalSearch() throws {
        let d = enabled()
        let (id, _) = try request(d.user(.assist(.instant("some site"))))
        d.system(.aiResult(id, .text("javascript:alert(1)")))
        XCTAssertTrue(d.snapshot.pages.filter(\.isAIReader).isEmpty)
        d.user(.assist(.searchFallback))
        XCTAssertEqual(d.current?.url, SearchEngine.google.searchURL("some site"))
        for value in ["file:///tmp/a", "https://u:p@example.com", "https://example.com bad", "data:text/html,x"] { XCTAssertNil(AIValidation.destination(value)) }
    }
    func testTranslationValidatesExactNodesAndPersistsOnlyProfileExclusions() throws {
        let d = enabled(), c = try content(d)
        let id = try readRequest(d.user(.assist(.translate("English"))))
        d.system(.aiPageRead(id, c.document.browser.page, c))
        let invalid = d.system(.aiResult(id, .text("[{\"id\":9,\"text\":\"Hello\"}]")))
        XCTAssertFalse(invalid.effects.contains { if case .aiTranslate = $0 { true } else { false } })
        let second = try readRequest(d.user(.assist(.translate("English"))))
        d.system(.aiPageRead(second, c.document.browser.page, c))
        let valid = d.system(.aiResult(second, .text("[{\"id\":0,\"text\":\"Hello\"}]")))
        XCTAssertTrue(valid.effects.contains(.aiTranslate(second, c, [AITextNode(id: 0, text: "Hello")])))
        d.system(.aiTranslated(second, true))
        d.user(.assist(.neverTranslateLanguage))
        let restored = Driver(file: d.savedFile)
        XCTAssertEqual(restored.snapshot.settings.max.settings.translationExclusions?[.default]?.languages, ["fr"])
        let third = try readRequest(d.user(.assist(.translate("English"))))
        let blocked = d.system(.aiPageRead(third, c.document.browser.page, c))
        XCTAssertFalse(blocked.effects.contains { if case .ai = $0 { true } else { false } })
        XCTAssertTrue(d.view.ai!.text.contains("never translates"))
    }
    func testDownloadNamesRejectPathsAndKeepExtension() {
        for text in ["../../x", "/tmp/x", "a\\b", "a:b", ".hidden", "a\nb"] { XCTAssertNil(AIValidation.filename(text, original: "x.pdf")) }
        XCTAssertEqual(AIValidation.filename("Reading.pdf", original: "x.pdf"), "Reading.pdf")
        XCTAssertEqual(AIValidation.filename("Reading", original: "x.pdf"), "Reading.pdf")
    }
    func testMaxOptionalFieldsReadOlderSettings() throws {
        let value = try JSONDecoder().decode(MaxSettings.self, from: Data(#"{"provider":"auto","renamePinnedTabs":false,"tidyTabs":false}"#.utf8))
        XCTAssertFalse(value.enabled(.translation))
        XCTAssertNil(value.translationExclusions)
    }
    func testDeadlineDismissAndNeverTranslateSite() throws {
        let d = enabled(), c = try content(d)
        d.user(.assist(.open(.page)))
        let id = try readRequest(d.user(.assist(.translate("English"))))
        d.system(.aiPageRead(id, c.document.browser.page, c))
        d.system(.aiDeadline(id))
        XCTAssertFalse(d.view.ai!.busy)
        d.user(.assist(.neverTranslateSite))
        XCTAssertEqual(d.snapshot.settings.max.settings.translationExclusions?[.default]?.sites, ["127.0.0.1"])
        d.user(.settings(.max(.resetTranslationExclusions)))
        XCTAssertNil(d.snapshot.settings.max.settings.translationExclusions)
        d.user(.assist(.dismiss))
        XCTAssertNil(d.view.ai)
    }
    func testCompletedDownloadOnlyAndRenameReceipt() throws {
        let d = enabled(), tab = try XCTUnwrap(d.current?.id), download = DownloadID("ai-download")
        d.download(tab, download, .receiving(TransferProgress(received: 0, total: nil)))
        XCTAssertFalse(d.user(.assist(.renameDownload(download))).effects.contains { if case .ai = $0 { true } else { false } })
        let t = d.download(tab, download, .terminal(.completed(FileReceipt(url: URL(fileURLWithPath: "/tmp/fixture.txt"), bytes: 8))))
        let (id, _) = try request(t)
        let renamed = d.system(.aiResult(id, .text("Reading.txt")))
        XCTAssertTrue(renamed.effects.contains(.aiRenameDownload(download, originalPath: "/tmp/fixture.txt", filename: "Reading.txt")))
        d.system(.aiDownloadRenamed(download, originalPath: "/tmp/fixture.txt", newPath: "/tmp/Reading.txt", error: nil))
        XCTAssertEqual(d.state.doc.downloads.first?.filename, "Reading.txt")
    }

    func testFeatureOffAndProviderChangeCancelRunningWork() throws {
        let d = enabled()
        let (id, _) = try request(d.user(.assist(.ask("why"))))
        let turnedOff = d.user(.settings(.max(.feature(.commandBar, false))))
        XCTAssertTrue(turnedOff.effects.contains(.aiCancel(id)))
        d.system(.aiResult(id, .text("late")))
        XCTAssertNotEqual(d.view.ai?.text, "late")
        d.user(.settings(.max(.feature(.commandBar, true))))
        let (next, _) = try request(d.user(.assist(.ask("why"))))
        XCTAssertTrue(d.user(.settings(.max(.provider(.off)))).effects.contains(.aiCancel(next)))
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

    func testPinnedTitleRequestCancelsWhenTabChangesProfile() throws {
        let d = enabled(), tab = try XCTUnwrap(d.current?.id)
        d.user(.settings(.max(.renamePinnedTabs(true))))
        let (id, _) = try request(d.user(.tab(.togglePin(.item(tab)))))
        d.user(.profile(.create(name: "Other", icon: nil)))
        let other = try XCTUnwrap(d.snapshot.settings.profiles.first { $0.profile.id != .default }?.profile.id)
        let changed = d.user(.profile(.assign(.current, to: other)))
        XCTAssertTrue(changed.effects.contains(.aiCancel(id)))
        d.system(.aiResult(id, .text("Old profile title")))
        XCTAssertNotEqual(d.row(tab)?.title, "Old profile title")
    }

    func testBrowseCitationsRejectMissingOrUnknownSources() {
        XCTAssertTrue(AIValidation.citations("Answer [1] and [2]", sourceCount: 2))
        XCTAssertFalse(AIValidation.citations("Unsupported [3]", sourceCount: 2))
        XCTAssertFalse(AIValidation.citations("No sources", sourceCount: 2))
        XCTAssertFalse(AIValidation.citations("Invalid [0]", sourceCount: 2))
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
        d.system(.aiResult(id, .text("Navigated Home")))
        XCTAssertEqual(d.row(tab)?.title, "Navigated Home")
    }

    func testEmptySuccessfulReplyShowsAnActionableFailure() throws {
        let d = enabled()
        let (id, _) = try request(d.user(.assist(.ask("Question"))))
        d.system(.aiResult(id, .text("   \n")))
        XCTAssertFalse(d.view.ai!.busy)
        XCTAssertTrue(d.view.ai!.text.contains("no answer"))
        XCTAssertTrue(d.view.ai!.text.contains("Terminal"))
    }

}
