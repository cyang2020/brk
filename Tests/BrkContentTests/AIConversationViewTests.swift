import AppKit
import BrkBase
@testable import BrkContent
@testable import BrkDomain
import XCTest

/// The conversation's views where they hand the user's input on: the composers, and the Library's read-only preview.
@MainActor
final class AIConversationViewTests: XCTestCase {
    private func descendants<T: NSView>(_ view: NSView, _ type: T.Type) -> [T] {
        ((view as? T).map { [$0] } ?? []) + view.subviews.flatMap { descendants($0, type) }
    }

    private func find(_ id: String, in view: NSView) -> NSView? {
        if view.accessibilityIdentifier() == id { return view }
        for sub in view.subviews { if let found = find(id, in: sub) { return found } }
        return nil
    }

    /// A message over the limit is not sent. What the user typed or pasted stays in the composer to shorten, in the panel
    /// and in the conversation list, and a toast says why.
    func testATooLongMessageStaysInTheComposerAndSaysWhy() throws {
        let long = String(repeating: "a", count: AIValidation.messageLimit + 1)
        var sent: [Command] = []
        let panel = AIAnswerDocumentView(dispatch: { sent.append($0) })
        let composer = try XCTUnwrap(descendants(panel, AIComposerView.self).first)
        composer.text = long
        composer.onSend?(long)
        XCTAssertEqual(composer.text, long, "the panel's composer was emptied")
        XCTAssertEqual(sent, [.assist(.followUp(long))])
        let list = AIThreadListView(dispatch: { sent.append($0) })
        list.composer.text = long
        list.composer.onSend?(long)
        XCTAssertEqual(list.composer.text, long, "the list's composer was emptied")

        let ids = IDs(), now = Instant(milliseconds: 1_790_000_000_000)
        let restored = StateCodec.restore(nil, seed: RestoreSeed(startURL: URL(string: "http://127.0.0.1:9/a"), contentSize: CGSize(width: 1280, height: 776)),
                                          ctx: Context(now: now, newID: ids.next))
        let window = project(restored.state, ProjectionContext(now: now, calendar: Calendar(identifier: .gregorian))).windows.keys.sorted()[0]
        for command in [Command.assist(.followUp(long)), .assist(.listAsk(long))] {
            let after = reduce(restored.state, .user(window, command), Context(now: now, newID: ids.next)).state
            XCTAssertNotNil(after.session.windows[window]?.toast, "\(command) said nothing")
        }
    }

    /// The Library's preview of a conversation is read-only: a page shown there may not save (it is told so, rather than
    /// told its save worked), but its Keep as Tab icon and its links work as they do in the panel.
    func testTheLibraryPreviewsPagesKeepOpenLinksAndRefuseSaves() throws {
        var sent: [Command] = []
        let preview = LibraryConversationPreview(dispatch: { sent.append($0) })
        let transcript = try XCTUnwrap(descendants(preview, AITranscriptView.self).first)
        let page = AIPageID("checklist"), link = URL(string: "https://example.com/item")!
        transcript.onKeep?(page)
        transcript.pages.onEvent?(page, .link(link))
        XCTAssertEqual(sent, [.assist(.keepPage(page)), .assist(.pageLink(page, link))])
        let html = FileManager.default.temporaryDirectory.appendingPathComponent("brk-preview-\(UUID().uuidString).html")
        try Data("<!doctype html><p>Checklist</p>".utf8).write(to: html)
        addTeardownBlock { try? FileManager.default.removeItem(at: html) }
        let view = transcript.pages.view(for: AIPageSnapshot(id: page, title: "Checklist", html: html, height: 200, data: nil, kept: false))
        XCTAssertNil(view.onSave, "the page's saves are taken and dropped")
    }

    /// A theme change alone (the system going dark under a Space that follows it) restyles the preview's words, not only
    /// its card.
    func testTheLibraryPreviewRestylesWhenOnlyTheThemeChanges() throws {
        let preview = LibraryConversationPreview(dispatch: { _ in })
        let detail = LibraryConversationDetail(id: AIRequestID("groceries"), title: "Groceries", meta: "Personal · Claude", space: nil, state: .unread,
                                               answer: AIAnswerSnapshot(request: nil, title: "Groceries", text: "", busy: false, sources: []))
        let snapshot = LibraryConversationsSnapshot(query: ConversationLibraryQuery(), rows: [], waiting: 0, withPages: 0, spaces: [], agents: [], language: .en, selected: detail)
        var darkSpace = SpaceTheme.default
        darkSpace.appearance = .dark
        let light = resolveTheme(.default), dark = resolveTheme(darkSpace)
        XCTAssertNotEqual(light.scheme, dark.scheme)
        let card = CGRect(x: 0, y: 0, width: 900, height: 700)
        preview.render(snapshot, card: card, cornerRadius: 10, theme: light)
        preview.render(snapshot, card: card, cornerRadius: 10, theme: dark)
        let title = try XCTUnwrap(find("ai-library-preview-title", in: preview) as? NSTextField)
        XCTAssertEqual(title.textColor, AIPanelStyle(dark, onCard: true).cardText, "the title kept the light scheme's color on the dark card")
    }
}
