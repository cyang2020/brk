import CoreGraphics
import Foundation

// The page vocabulary: the only words the domain and the web engine share. The domain decides which pages exist
// (`PageSpec`), asks for imperative page actions (`PageAction`) and receives what pages report (`PageEvent`).
// The engine knows nothing about tabs, spaces or sidebars, and the domain knows nothing about Chromium.

/// One live web page. Equal to the tab's item id (a page is the live form of one tab), but typed separately so
/// engine code cannot reach into the sidebar.
public struct PageID: Hashable, Comparable, Sendable, Codable, CodingKeyRepresentable, CustomStringConvertible {
    public let item: ItemID
    public init(_ item: ItemID) { self.item = item }

    public var description: String { item.rawValue }
    public static func < (a: PageID, b: PageID) -> Bool { a.item < b.item }

    public init(from decoder: any Decoder) throws { item = try ItemID(from: decoder) }
    public func encode(to encoder: any Encoder) throws { try item.encode(to: encoder) }
    public var codingKey: any CodingKey { item.codingKey }
    public init?<T: CodingKey>(codingKey: T) {
        guard let item = ItemID(codingKey: codingKey) else { return nil }
        self.item = item
    }
}

/// Which Chromium request context (cookies, cache, storage, extensions) a page browses in. Arc: a space's
/// `Profile`, or incognito. The engine maps `.profile(p)` to one persistent context per profile (the default
/// profile is the runtime's own cache) and `.incognito` to one shared in-memory context that is forgotten when the
/// last incognito window closes (`WebEngine.forget`). A profile is a `ProfileID`, never a path: where its data lives
/// is the engine's business.
public enum BrowsingContext: Hashable, Sendable, Codable {
    case profile(ProfileID)
    case incognito
}

/// A page that should be live. The engine creates it on first sight and closes it when it disappears from the
/// list (`WebEngine.reconcile`). `initialURL` is read only at creation; later navigation is a `PageAction`.
public struct PageSpec: Hashable, Sendable, Codable {
    public let id: PageID
    /// Nil for an empty split pane waiting for the command bar: the engine creates no browser for it.
    public let initialURL: URL?
    /// The request context the page browses in. A changed context recreates the browser so the tab cannot retain
    /// the previous profile's cookies and storage.
    public let context: BrowsingContext

    public init(id: PageID, initialURL: URL?, context: BrowsingContext) {
        self.id = id
        self.initialURL = initialURL
        self.context = context
    }
}

public enum ZoomStep: String, Hashable, Sendable, Codable { case zoomIn = "in", zoomOut = "out", reset }

/// Imperative actions on a live page. Emitted by the reducer as `Effect.page`, executed by the engine.
public enum PageAction: Hashable, Sendable, Codable {
    case navigate(URL)
    case goBack
    case goForward
    case reload(ignoringCache: Bool)
    case stop
    case zoom(ZoomStep)
    case toggleDevTools
    /// Restart a renderer that died (`PageEvent.rendererGone`). The domain decides; the engine reloads.
    case recover
}

/// How a page asked to open a URL elsewhere (target=_blank, window.open, Cmd+click). Mirrors the subset of
/// Chromium's `WindowOpenDisposition` the domain distinguishes.
public enum OpenDisposition: String, Hashable, Sendable, Codable {
    case foregroundTab
    case backgroundTab
    /// `window.open` with features. v1 opens it as a foreground tab; Peek and real popups plug in here later.
    case popup
}

/// What a live page reports. Delivered as `SystemEvent.page(id, event)`; never written to the page's tab by
/// anything but the reducer.
public enum PageEvent: Hashable, Sendable, Codable {
    /// Main-frame navigation committed. Never sent for a failed load.
    case committed(URL)
    case titleChanged(String)
    case faviconChanged(URL?)
    case loadingChanged(isLoading: Bool, canGoBack: Bool, canGoForward: Bool)
    case loadFailed(code: Int, description: String, url: String)
    /// The renderer process crashed or was killed. The page object stays; see `PageAction.recover`.
    case rendererGone
    /// The page closed itself (`window.close()`); the engine has already started closing the browser.
    case closedByPage
    /// The page took keyboard focus (the user clicked into it, e.g. into another split pane).
    case gainedFocus
    case openRequested(URL, OpenDisposition)
    /// A file download this page started (CEF: OnBeforeDownload, OnDownloadUpdated). `Doc.downloads` is the ledger.
    case download(DownloadID, DownloadEvent)
    /// The browser finished closing (`OnBeforeClose`). The id may be reused by a new page right after.
    case closed
}

/// One download's lifecycle, as the engine reports it. `started` carries where the engine decided to write it
/// (the delegate's `DownloadDecision`); `progress` repeats until `finished`, `failed` or `cancelled`.
public enum DownloadEvent: Hashable, Sendable, Codable {
    case started(url: URL, filename: String, path: String?)
    /// `total` is nil when the server did not say.
    case progress(received: Int64, total: Int64?)
    case finished(path: String)
    case failed
    case cancelled
}

/// What the app tells the engine to do with a download that is about to begin (CEF's OnBeforeDownload answers
/// synchronously). Decided from the page's profile settings ("Download location", "Ask where to save").
public enum DownloadDecision: Hashable, Sendable {
    /// Write to this directory under the suggested name (a clash gets a numbered suffix).
    case save(directory: String)
    /// Show a save panel (BrkApp) starting in `directory`; the panel's answer becomes the destination.
    case ask(directory: String)
    case deny
}

/// One line of the engine's page-lifecycle log (`WebEngine.pageLog`), read by the control socket's `pageLog` op.
/// `generation` tells incarnations of a reused id apart; `uptime` is `ProcessInfo.systemUptime` at the event,
/// for ordering only (the engine has no app clock). Diagnostic: the app never branches on it.
public struct PageLogEntry: Hashable, Sendable, Codable {
    public enum Kind: String, Hashable, Sendable, Codable {
        /// A browser was created for the page.
        case created
        /// The engine stopped listing the page and asked its browser to close.
        case closeRequested
        /// The browser reported OnBeforeClose. For a close the engine did not start this is a page-initiated close.
        case closed
    }
    public var page: PageID
    public var generation: UInt64
    public var kind: Kind
    public var browserID: Int?
    public var uptime: Double
    public init(page: PageID, generation: UInt64, kind: Kind, browserID: Int?, uptime: Double) {
        self.page = page
        self.generation = generation
        self.kind = kind
        self.browserID = browserID
        self.uptime = uptime
    }
}

/// How `WebEngine.shutdown()` ended. `Lifecycle` decides what the process does with it (BrkApp/Lifecycle.swift).
public enum ShutdownOutcome: Hashable, Sendable {
    /// Every browser reported OnBeforeClose and the runtime was shut down; the process may exit normally.
    case clean
    /// Some browsers never reported OnBeforeClose within Metrics.persistence.shutdownTimeout. The runtime was NOT
    /// shut down (cef_shutdown with live browsers is the crash the spike saw); the engine logged each unclosed page.
    /// The caller must still exit, with a non-zero status, so the e2e runner fails the scenario.
    case timedOut(unclosed: [PageID])
}

/// What the engine can tell the e2e harness about one page. Diagnostic only: the app never branches on it.
public struct PageFacts: Hashable, Sendable, Codable {
    /// The page surface's frame in its window, top-left origin, points. Nil when the surface is in no window.
    public var surfaceFrame: CGRect?
    /// Class names of the Chromium views currently inside the surface (embed mode: ViewsCompositorSuperview,
    /// WebContentsViewCocoa). Empty for the stub engine or before the views arrive.
    public var embeddedViews: [String]
    /// CEF's browser id, if a browser exists.
    public var browserID: Int?
    /// The window number of the CEF-owned host window, which must never be key.
    public var hostWindowNumber: Int?
    public var hasKeyboardFocus: Bool

    public init(surfaceFrame: CGRect?, embeddedViews: [String], browserID: Int?, hostWindowNumber: Int?, hasKeyboardFocus: Bool) {
        self.surfaceFrame = surfaceFrame
        self.embeddedViews = embeddedViews
        self.browserID = browserID
        self.hostWindowNumber = hostWindowNumber
        self.hasKeyboardFocus = hasKeyboardFocus
    }
}
