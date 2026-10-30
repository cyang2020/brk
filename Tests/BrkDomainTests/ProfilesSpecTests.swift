import BrkBase
import Foundation
import XCTest
@testable import BrkDomain

/// Owner: F2. Profiles and incognito: records, per-profile Favorites and settings, a space's profile, the browsing
/// context of pages, the URL pill's badge, the dialogs.
final class ProfilesSpecTests: XCTestCase {
    /// a fresh profile has the default profile, with its settings record and Favorites root
    func test_aFreshProfileHasTheDefaultProfile() {
        let d = Driver()
        XCTAssertEqual(d.snapshot.settings.profiles.map(\.profile.id), [.default])
        XCTAssertTrue(d.snapshot.settings.profiles[0].profile.isDefault)
        XCTAssertEqual(d.snapshot.settings.profiles[0].profile.spaceTitles, ["Space 1"])
        XCTAssertNil(d.view.urlPill.profile, "no badge for the default profile")
    }

    /// .profile(.create) adds a profile with its own Favorites root and default settings; a duplicate or blank name is refused
    func test_createAddsAProfileWithFavoritesAndSettings() {
        let d = Driver()
        d.user(.profile(.create(name: "Work", icon: .named(.briefcase))))
        let rows = d.snapshot.settings.profiles
        XCTAssertEqual(rows.map(\.profile.name), ["Default", "Work"])
        let work = rows[1].profile.id
        XCTAssertEqual(rows[1].settings, .default)
        assertUnchanged(d.state, d.user(.profile(.create(name: " work ", icon: nil))))
        assertUnchanged(d.state, d.user(.profile(.create(name: "  ", icon: nil))))
        d.user(.profile(.assign(.current, to: work)))
        XCTAssertNotEqual(d.view.favorites.root, Driver().view.favorites.root, "the space shows its profile's Favorites root")
        XCTAssertEqual(d.view.urlPill.profile, ProfileBadge(name: "Work", icon: .named(.briefcase), incognito: false))
        let r = Driver(file: d.savedFile)
        XCTAssertEqual(r.snapshot.settings.profiles.map(\.profile.name), ["Default", "Work"])
        XCTAssertEqual(r.view.urlPill.profile?.name, "Work")
    }

    /// pages of a space browse in its profile's context; incognito windows browse off the record
    func test_pagesCarryTheirBrowsingContext() throws {
        let d = Driver()
        d.user(.profile(.create(name: "Work", icon: nil)))
        let work = try XCTUnwrap(d.snapshot.settings.profiles.last?.profile.id)
        d.user(.profile(.assign(.current, to: work)))
        let t = d.open("http://127.0.0.1:9/work")
        XCTAssertEqual(d.snapshot.pages.first { $0.id == PageID(t) }?.context, .profile(work))
        d.user(.window(.newIncognito))
        let incognito = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .incognito })
        d.user(.commandBar(.submit("http://127.0.0.1:9/secret")), in: incognito.id)
        let secret = try XCTUnwrap(d.view(of: incognito.id).scratch?.rows.first?.id)
        XCTAssertEqual(d.snapshot.pages.first { $0.id == PageID(secret) }?.context, .incognito)
        XCTAssertEqual(d.view(of: incognito.id).urlPill.profile, ProfileBadge(name: "Incognito", icon: nil, incognito: true))
        d.page(secret, .committed(url("http://127.0.0.1:9/secret")))
        XCTAssertFalse((d.savedDoc["history"] as? [[String: Any]] ?? []).contains { ($0["url"] as? String) == "http://127.0.0.1:9/secret" },
                       "incognito visits are never history")
    }

    /// .profile(.delete) is refused for the default profile and a profile with spaces; otherwise its Favorites are archived and the engine forgets it
    func test_deleteRules() throws {
        let d = Driver()
        assertUnchanged(d.state, d.user(.profile(.delete(.default))))
        d.user(.profile(.create(name: "Work", icon: nil)))
        let work = try XCTUnwrap(d.snapshot.settings.profiles.last?.profile.id)
        d.user(.profile(.assign(.current, to: work)))
        assertUnchanged(d.state, d.user(.profile(.delete(work))))
        d.user(.profile(.assign(.current, to: .default)))
        d.user(.profile(.rename(work, name: "Side")))
        XCTAssertEqual(d.snapshot.settings.profiles.last?.profile.name, "Side")
        let t = d.user(.profile(.delete(work)))
        XCTAssertEqual(t.effects, [.forgetBrowsingData(.profile(work))])
        XCTAssertEqual(d.snapshot.settings.profiles.map(\.profile.id), [.default])
        XCTAssertEqual(Driver(file: d.savedFile).outcome, .restored(repairs: []))
    }

    /// closing the last incognito window asks the engine to forget the off-the-record context
    func test_closingTheLastIncognitoWindowForgetsTheContext() throws {
        let d = Driver()
        d.user(.window(.newIncognito))
        let incognito = try XCTUnwrap(d.snapshot.windows.values.first { $0.kind == .incognito })
        let t = d.user(.window(.close), in: incognito.id)
        XCTAssertEqual(t.effects, [.forgetBrowsingData(.incognito)])
        XCTAssertNil(d.snapshot.windows[incognito.id])
    }

    /// the dialogs open and close through one command; an unknown space or profile is ignored
    func test_profileDialogs() {
        let d = Driver()
        d.user(.profile(.openDialog(.create)))
        XCTAssertEqual(d.view.profileDialog, .create)
        XCTAssertEqual(d.view.focus, .profileDialog)
        d.user(.profile(.openDialog(.change(.current))))
        guard case .change(let space, let current, let profiles)? = d.view.profileDialog else { return XCTFail("\(String(describing: d.view.profileDialog))") }
        XCTAssertEqual(space, d.view.space.id)
        XCTAssertEqual(current, .default)
        XCTAssertEqual(profiles.map(\.id), [.default])
        assertUnchanged(d.state, d.user(.profile(.openDialog(.delete(ProfileID("ghost"))))))
        d.user(.profile(.openDialog(nil)))
        XCTAssertNil(d.view.profileDialog)
    }

    // MARK: F2 stubs

    func test_changingASpacesProfileReopensItsPagesInTheNewContext() throws {
        throw XCTSkip("F2: .profile(.assign) unloads the space's pages so they reopen in the new request context (Arc's dialog warning)")
    }

    func test_theProfileDialogsRenderArcsCopy() throws {
        throw XCTSkip("F2: CreateProfileDialog, ChangeProfileDialog, DeleteProfileDialog with Arc's copy (visual-and-copy.md Profiles)")
    }

    func test_incognitoWindowsRestoreNothingAndUseArcsIncognitoLook() throws {
        throw XCTSkip("F2: an incognito window is dropped from state.json, its pages never hit history or downloads, Arc's dark incognito theme")
    }
}
