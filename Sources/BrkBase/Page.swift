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

/// A page that should be live. The engine creates it on first sight and closes it when it disappears from the
/// list (`WebEngine.reconcile`). `initialURL` is read only at creation; later navigation is a `PageAction`.
public struct PageSpec: Hashable, Sendable, Codable {
    public let id: PageID
    /// Nil for an empty split pane waiting for the command bar: the engine creates no browser for it.
    public let initialURL: URL?
    /// Chromium request context (cookies, cache, extensions). v1: always `.default`. Profiles later map to one CEF
    /// request context each; incognito to an off-the-record one.
    public let profile: ProfileID

    public init(id: PageID, initialURL: URL?, profile: ProfileID) {
        self.id = id
        self.initialURL = initialURL
        self.profile = profile
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
    /// The browser finished closing (`OnBeforeClose`). The id may be reused by a new page right after.
    case closed
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
