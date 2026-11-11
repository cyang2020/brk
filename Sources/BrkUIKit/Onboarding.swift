import AppKit
import BrkBase
import BrkDomain
import Foundation

// The first-run onboarding window and the "Import from Another Browser…" window share these values. BrkApp owns the
// flow (OnboardingController) and renders a snapshot; the views (BrkOverlays, reached through BrkContent) draw it and
// send actions back. The screen order follows Arc 1.170's Unboxing and Setup wizard (research report §1.4, §4.2):
// Welcome → name → pick browser → [profiles / keychain explanation / Safari ZIP / progress] → pick bookmarks →
// Favorites → theme → ad blocker → Max → default browser → finish.

public enum OnboardingStep: String, Sendable, Equatable, CaseIterable {
    case welcome, name, pickBrowser, profiles, keychain, safari, safariLegacy, progress, bookmarks, favorites, theme, adBlocker, max, defaultBrowser, finish
}

public enum OnboardingMode: Sendable, Equatable {
    /// First run: every screen, then the browser window and Brk 101.
    case firstRun
    /// Brk > Import from Another Browser… and Settings: the import screens, then a short summary.
    case importOnly
}

/// A browser on the picker. `id` is a `BrowserKind` raw value, or "file" for Import from a file….
public struct OnboardingBrowserTile: Hashable, Sendable {
    public var id: String
    public var name: String
    /// "2 profiles"; empty for Safari and the file tile.
    public var detail: String
    /// The installed app, for its icon; nil draws a letter tile.
    public var appPath: String?
    public init(id: String, name: String, detail: String, appPath: String?) {
        self.id = id; self.name = name; self.detail = detail; self.appPath = appPath
    }
}

public struct OnboardingProfileRow: Hashable, Sendable {
    public var id: String
    public var name: String
    public var selected: Bool
    public init(id: String, name: String, selected: Bool) { self.id = id; self.name = name; self.selected = selected }
}

/// One row of the bookmark tree (Arc's ImportBookmarks rows: selected, expanded, level, isFolder, the star).
public struct OnboardingBookmarkRow: Hashable, Sendable {
    public var id: String
    public var title: String
    public var detail: String
    public var level: Int
    public var isFolder: Bool
    public var expanded: Bool
    public var selected: Bool
    /// Some, not all, of the folder's bookmarks are selected.
    public var mixed: Bool
    public var starred: Bool
    public init(id: String, title: String, detail: String, level: Int, isFolder: Bool, expanded: Bool, selected: Bool, mixed: Bool, starred: Bool) {
        self.id = id; self.title = title; self.detail = detail; self.level = level; self.isFolder = isFolder
        self.expanded = expanded; self.selected = selected; self.mixed = mixed; self.starred = starred
    }
}

/// A site on the Favorites step.
public struct OnboardingSiteTile: Hashable, Sendable {
    public var id: String
    public var title: String
    public var host: String
    public var selected: Bool
    public init(id: String, title: String, host: String, selected: Bool) { self.id = id; self.title = title; self.host = host; self.selected = selected }
}

public struct OnboardingSnapshot: Equatable, Sendable {
    public var step: OnboardingStep = .welcome
    public var mode: OnboardingMode = .firstRun
    public var canGoBack = false
    public var name = ""
    public var browsers: [OnboardingBrowserTile] = []
    public var selectedBrowser: String?
    public var browserSentence = ""
    public var browserName = ""
    public var profiles: [OnboardingProfileRow] = []
    /// The keychain explanation: passwords and cookies on, and the macOS prompt is up now.
    public var importSecrets = true
    public var waitingForPassword = false
    public var waitingProfile = ""
    public var safariFile: String?
    public var safariError: String?
    /// Firefox holds its database while it runs (Arc: "Quit Firefox to continue importing").
    public var mustQuit: String?
    public var progressTitle = ""
    public var progressDetail = ""
    public var progressDone = false
    public var failures: [String] = []
    public var bookmarks: [OnboardingBookmarkRow] = []
    public var bookmarkTotal = 0
    public var bookmarkSelected = 0
    public var recommendedCount = 0
    public var sites: [OnboardingSiteTile] = []
    public var theme: SpaceTheme = .default
    public var blockAds = true
    public var maxOn = false
    public var isDefaultBrowser = false
    public var userName: String?
    /// The finish screen's lines in place of the Arc Card ("312 bookmarks in Pinned").
    public var summary: [String] = []
    public var passwordsNeedRestart = false
    public init() {}
}

public enum OnboardingAction: Sendable, Equatable {
    case next, back, skip
    case setName(String)
    case pickBrowser(String)
    case toggleProfile(String)
    case importSecrets(Bool)
    case beginImport
    case chooseSafariFile, openSafari, openFullDiskAccess, useSafariFile(URL)
    case toggleBookmark(String), expandBookmark(String), selectAllBookmarks(Bool)
    case toggleSite(String)
    case theme(SpaceTheme)
    case blockAds(Bool)
    case enableMax(Bool)
    case makeDefault(Bool)
    case restart
    case finish
}

/// The onboarding window's content view, made by BrkContent's `OnboardingViews.make`.
@MainActor
public protocol OnboardingSurface: AnyObject {
    var view: NSView { get }
    func render(_ snapshot: OnboardingSnapshot)
    /// Each interactive control's frame by identifier, in the view's coordinates with a top-left origin; the control
    /// socket turns them into screen points for real clicks.
    var controlFrames: [String: CGRect] { get }
}
