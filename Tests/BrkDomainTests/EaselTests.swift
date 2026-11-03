import BrkBase
import CoreGraphics
import XCTest
@testable import BrkDomain

/// Easels (Rules/EaselRules.swift): File > New Easel, the board's edits, pictures, Share, the Library's cards, the
/// delete confirmation (Q09 c) and the state file.
final class EaselTests: XCTestCase {
    /// The new Easel's id and its row.
    private func create(_ d: Driver) -> (EaselID, ItemID) {
        d.user(.easel(.create))
        guard case .tab(let row)? = d.view.space.pinned.rows.last, let id = EaselPage.id(of: row.url) else {
            XCTFail("New Easel added no row at the end of Pinned"); return (EaselID("missing"), ItemID("missing"))
        }
        return (id, row.id)
    }

    private func board(_ d: Driver) -> EaselSnapshot? { d.view.easels.first }

    private func rectangle(_ id: String, x: CGFloat = 0, y: CGFloat = 200) -> EaselElement {
        EaselElement(id: id, shape: .rectangle, frame: CGRect(x: x, y: y, width: 120, height: 80))
    }

    func test_newEaselAddsAPinnedRowAndShowsItsBoardWithTheTitleSelected() throws {
        let d = Driver()
        let pinnedBefore = d.pinnedIDs.count
        let (id, row) = create(d)
        XCTAssertEqual(d.pinnedIDs.count, pinnedBefore + 1)
        let tab = try XCTUnwrap(d.row(row))
        XCTAssertEqual(tab.title, "Untitled Easel")
        XCTAssertEqual(tab.favicon, EaselPage.favicon)
        XCTAssertEqual(tab.status, .current)
        XCTAssertEqual(d.view.content.panes.map(\.content), [.easel(PageID(window: d.window, item: row), id)])
        let shown = try XCTUnwrap(board(d))
        XCTAssertEqual(shown.title, "Untitled Easel")
        XCTAssertTrue(shown.editingTitle, "Arc selects the new Easel's title for typing (Q09 a)")
        XCTAssertEqual(shown.elements, [])
        XCTAssertEqual(d.view.focus, .easel(PageID(window: d.window, item: row)))
        // The pill is the Share button, and no browser loads the board.
        XCTAssertEqual(d.view.urlPill.share, id)
        XCTAssertEqual(d.view.urlPill.host, "Share")
        XCTAssertFalse(d.snapshot.pages.contains { $0.id.item == row })
        XCTAssertFalse(d.view.enabledActions.contains(.reloadPage))
    }

    func test_fileNewEaselIsControlShiftEAndEnabledInStandardWindows() throws {
        let spec = ActionID.newEasel.spec
        XCTAssertEqual(spec.title, "New Easel")
        XCTAssertEqual(spec.command, .easel(.create))
        XCTAssertEqual(spec.bindings.map(\.chord), [KeyChord([.control, .shift], .e)])
        XCTAssertTrue(Driver().view.enabledActions.contains(.newEasel))
    }

    func test_shapesArrowsInkTextAndPicturesAreAddedMovedAndRemoved() throws {
        let d = Driver()
        let (id, _) = create(d)
        d.user(.easel(.add(id, rectangle("r"))))
        XCTAssertFalse(try XCTUnwrap(board(d)).editingTitle, "the first edit ends the selected title")
        d.user(.easel(.add(id, EaselElement(id: "e", shape: .ellipse, frame: CGRect(x: -200, y: 300, width: 90, height: 90)))))
        d.user(.easel(.add(id, EaselElement(id: "a", shape: .arrow, frame: .zero, points: [CGPoint(x: 10, y: 400), CGPoint(x: 150, y: 330)]))))
        d.user(.easel(.add(id, EaselElement(id: "i", shape: .ink, frame: .zero, points: [CGPoint(x: 0, y: 500), CGPoint(x: 20, y: 510), CGPoint(x: 40, y: 495)]))))
        d.user(.easel(.add(id, EaselElement(id: "t", shape: .text, frame: CGRect(x: -100, y: 600, width: 80, height: 22), text: "Plan"))))
        XCTAssertEqual(board(d)?.elements.map(\.id), ["r", "e", "a", "i", "t"])
        XCTAssertEqual(board(d)?.elements[2].frame, CGRect(x: 10, y: 330, width: 140, height: 70), "an arrow's frame is its points' box")
        // A duplicate id, an arrow without two points and a picture without a file are refused.
        d.user(.easel(.add(id, rectangle("r", x: 50))))
        d.user(.easel(.add(id, EaselElement(id: "bad-arrow", shape: .arrow, frame: .zero, points: [.zero]))))
        d.user(.easel(.add(id, EaselElement(id: "bad-image", shape: .image, frame: CGRect(x: 0, y: 0, width: 5, height: 5)))))
        XCTAssertEqual(board(d)?.elements.count, 5)

        // Move: the box and the points shift; the shape and the picture cannot change through an update.
        var moved = try XCTUnwrap(board(d)?.elements.first { $0.id == "a" }).moved(by: CGSize(width: 30, height: -10))
        moved.shape = .rectangle
        d.user(.easel(.update(id, [moved])))
        let arrow = try XCTUnwrap(board(d)?.elements.first { $0.id == "a" })
        XCTAssertEqual(arrow.shape, .arrow)
        XCTAssertEqual(arrow.points, [CGPoint(x: 40, y: 390), CGPoint(x: 180, y: 320)])
        // Retyping text; emptying it removes the box.
        var text = try XCTUnwrap(board(d)?.elements.first { $0.id == "t" })
        text.text = "Plan B"
        d.user(.easel(.update(id, [text])))
        XCTAssertEqual(board(d)?.elements.first { $0.id == "t" }?.text, "Plan B")
        text.text = "  "
        d.user(.easel(.update(id, [text])))
        XCTAssertNil(board(d)?.elements.first { $0.id == "t" })

        d.user(.easel(.duplicate(id, ["r"])))
        let copy = try XCTUnwrap(board(d)?.elements.last)
        XCTAssertNotEqual(copy.id, "r")
        XCTAssertEqual(copy.frame, CGRect(x: 24, y: 224, width: 120, height: 80), "the copy sits down and to the right")

        d.user(.easel(.remove(id, ["r", "e"])))
        XCTAssertEqual(board(d)?.elements.map(\.id), ["a", "i", copy.id])
    }

    func test_titleRenamesEveryRowAndItsSizeStepsThroughArcsThreeSizes() throws {
        let d = Driver()
        let (id, row) = create(d)
        XCTAssertEqual(board(d)?.titleSize, 25)
        d.user(.easel(.stepTitleSize(id, by: -1)))
        XCTAssertEqual(board(d)?.titleSize, 20)
        d.user(.easel(.stepTitleSize(id, by: -1)))
        d.user(.easel(.stepTitleSize(id, by: -1)))
        XCTAssertEqual(board(d)?.titleSize, 16, "Body is the smallest")
        d.user(.easel(.stepTitleSize(id, by: 1)))
        XCTAssertEqual(board(d)?.titleSize, 20)
        d.user(.easel(.rename(id, title: "  Trip ideas ")))
        XCTAssertEqual(board(d)?.title, "Trip ideas")
        XCTAssertEqual(d.row(row)?.title, "Trip ideas")
        d.user(.easel(.rename(id, title: "   ")))
        XCTAssertEqual(board(d)?.title, "Trip ideas", "a blank title keeps the old one")
    }

    func test_picturesAreCopiedThroughAnEffectAndPlacedScaledDown() throws {
        let d = Driver()
        let (id, _) = create(d)
        let choose = d.user(.easel(.chooseImage(id, at: CGPoint(x: 0, y: 300))))
        XCTAssertEqual(choose.effects, [.easel(.chooseImage(d.window, id, at: CGPoint(x: 0, y: 300)))])
        let source = URL(fileURLWithPath: "/tmp/fixture.png")
        let imported = d.user(.easel(.importImage(id, from: source, at: CGPoint(x: 0, y: 300))))
        guard case .easel(.importImage(let window, let easel, let from, let at, let element))? = imported.effects.first else {
            return XCTFail("no copy was asked for: \(imported.effects)")
        }
        XCTAssertEqual([window.rawValue, easel.rawValue, from.path], [d.window.rawValue, id.rawValue, source.path])
        XCTAssertEqual(at, CGPoint(x: 0, y: 300))
        XCTAssertTrue(d.user(.easel(.importImage(id, from: URL(string: "https://example.com/a.png")!, at: .zero))).effects.isEmpty, "only files")
        let copy = URL(fileURLWithPath: "/tmp/data/Easels/\(id)/\(element).png")
        d.system(.easel(.imageImported(d.window, id, element: element, file: copy, size: CGSize(width: 1440, height: 720), at: CGPoint(x: 0, y: 300))))
        let picture = try XCTUnwrap(board(d)?.elements.first)
        XCTAssertEqual(picture.shape, .image)
        XCTAssertEqual(picture.image, copy)
        XCTAssertEqual(picture.frame, CGRect(x: -180, y: 210, width: 360, height: 180), "scaled to 360 on its long side, centred on the point")
        d.system(.easel(.failed(d.window, id, "Could not add the picture: unreadable")))
        XCTAssertEqual(d.view.tabTools.toast?.text, "Could not add the picture: unreadable")
    }

    func test_shareWritesTheBoardThroughASavePanel() throws {
        let d = Driver()
        let (id, _) = create(d)
        d.user(.easel(.add(id, rectangle("r"))))
        let share = d.user(.easel(.share(id)))
        guard case .easel(.share(let window, let card))? = share.effects.first else { return XCTFail("\(share.effects)") }
        XCTAssertEqual(window, d.window)
        XCTAssertEqual(card.title, "Untitled Easel")
        XCTAssertEqual(card.elements.map(\.id), ["r"])
        d.system(.easel(.shared(d.window, id, URL(fileURLWithPath: "/tmp/Untitled Easel.png"))))
        XCTAssertEqual(d.view.tabTools.toast?.text, "Saved Untitled Easel.png")
    }

    func test_libraryListsEveryEaselMostRecentlyEditedFirstAndOpensOne() throws {
        let d = Driver()
        let (first, firstRow) = create(d)
        d.advance(.seconds(60))
        let (second, _) = create(d)
        d.advance(.seconds(60))
        d.user(.easel(.rename(first, title: "Edited last")))
        d.user(.library(.open(.easelsAndNotes)))
        guard case .library(let library)? = d.view.overlay else { return XCTFail("the Library did not open") }
        XCTAssertEqual(library.easels.map(\.id), [first, second])
        XCTAssertEqual(library.easels.map(\.title), ["Edited last", "Untitled Easel"])
        // A card opens the Easel's row; with no row in this space, a new one at the end of Pinned.
        d.user(.easel(.open(first)))
        XCTAssertNil(d.view.overlay, "opening a card closes the Library")
        XCTAssertEqual(d.current?.id, firstRow)
        d.user(.tab(.archive(.item(firstRow))))
        XCTAssertFalse(d.pinnedIDs.contains(firstRow))
        d.user(.easel(.open(first)))
        guard case .tab(let reopened)? = d.view.space.pinned.rows.last else { return XCTFail("no row") }
        XCTAssertEqual(EaselPage.id(of: reopened.url), first)
        XCTAssertEqual(reopened.status, .current)
    }

    func test_deleteAsksFirstThenRemovesTheBoardItsRowsAndItsFiles() throws {
        let d = Driver()
        let (id, row) = create(d)
        d.user(.easel(.add(id, rectangle("r"))))
        d.user(.library(.open(.easelsAndNotes)))
        d.user(.easel(.requestDelete(id)))
        let request = try XCTUnwrap(d.view.pendingEaselDeletion)
        XCTAssertEqual(request.id, id)
        XCTAssertEqual(d.view.focus, .spaceDialog)
        guard case .library? = d.view.overlay else { return XCTFail("the confirmation closed the Library") }
        // A stale token and Cancel change nothing.
        d.user(.easel(.confirmDelete(id, token: "stale", confirmed: true)))
        XCTAssertNotNil(d.view.pendingEaselDeletion)
        d.user(.easel(.confirmDelete(id, token: request.token, confirmed: false)))
        XCTAssertNil(d.view.pendingEaselDeletion)
        XCTAssertTrue(d.pinnedIDs.contains(row))
        d.user(.easel(.requestDelete(id)))
        let again = try XCTUnwrap(d.view.pendingEaselDeletion)
        let deleted = d.user(.easel(.confirmDelete(id, token: again.token, confirmed: true)))
        XCTAssertTrue(deleted.effects.contains(.easel(.deleteFiles(id))))
        XCTAssertFalse(d.pinnedIDs.contains(row))
        XCTAssertNil(d.state.doc.easels[id])
        guard case .library(let library)? = d.view.overlay else { return XCTFail("the Library closed") }
        XCTAssertEqual(library.easels, [])
        XCTAssertEqual(d.view.easels, [])
    }

    func test_anArchivedEaselRowRestoresUntilTheEaselIsDeleted() throws {
        let d = Driver()
        let (id, row) = create(d)
        d.user(.tab(.archive(.item(row))))
        XCTAssertEqual(d.archive().first?.url, EaselPage.url(id))
        d.user(.easel(.requestDelete(id)))
        d.user(.easel(.confirmDelete(id, token: try XCTUnwrap(d.view.pendingEaselDeletion).token, confirmed: true)))
        XCTAssertFalse(d.archive().contains { $0.url == EaselPage.url(id) }, "no archive entry brings back a deleted Easel")
    }

    func test_theBoardAndItsRowSurviveARestart() throws {
        let d = Driver()
        let (id, row) = create(d)
        d.user(.easel(.rename(id, title: "Kept")))
        d.user(.easel(.add(id, rectangle("r"))))
        d.user(.easel(.add(id, EaselElement(id: "i", shape: .ink, frame: .zero, points: [CGPoint(x: 1, y: 2), CGPoint(x: 3, y: 5)]))))
        d.user(.easel(.add(id, EaselElement(id: "p", shape: .image, frame: CGRect(x: 0, y: 0, width: 40, height: 30), image: URL(fileURLWithPath: "/tmp/p.png")))))
        let r = Driver(file: d.savedFile)
        guard case .restored = r.outcome else { return XCTFail("\(r.outcome)") }
        XCTAssertTrue(r.pinnedIDs.contains(row), "the brk://easel row is not dropped like an address that cannot open")
        XCTAssertEqual(r.row(row)?.title, "Kept")
        r.user(.tab(.focus(row)))
        let shown = try XCTUnwrap(r.view.easels.first)
        XCTAssertEqual(shown.id, id)
        XCTAssertEqual(shown.elements, d.state.doc.easels[id]?.elements)
        XCTAssertFalse(shown.editingTitle)
    }

    func test_aFileWrittenBeforeEaselsRestores() throws {
        let d = Driver()
        let (id, _) = create(d)
        d.user(.easel(.add(id, rectangle("r"))))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: d.savedFile) as? [String: Any])
        var doc = try XCTUnwrap(json["doc"] as? [String: Any])
        XCTAssertNotNil(doc["easels"])
        doc["easels"] = nil
        json["doc"] = doc
        let r = Driver(file: try JSONSerialization.data(withJSONObject: json))
        guard case .restored = r.outcome else { return XCTFail("a file without Easels did not restore: \(r.outcome)") }
        XCTAssertTrue(r.state.doc.easels.isEmpty)
        XCTAssertEqual(r.view.easels, [], "a row whose Easel is gone shows no board")
    }

    func test_easelAddressesRoundTrip() {
        let id = EaselID("6F1B5D7A-0000-4000-8000-000000000001")
        XCTAssertEqual(EaselPage.id(of: EaselPage.url(id)), id)
        XCTAssertNil(EaselPage.id(of: URL(string: "brk://history/")))
        XCTAssertNil(EaselPage.id(of: URL(string: "https://easel.example.com/x")))
        XCTAssertNil(EaselPage.id(of: URL(string: "brk://easel/")))
    }
}
