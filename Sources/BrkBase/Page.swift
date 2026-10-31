import CoreGraphics
import Foundation

// The page vocabulary: the only words the domain and the web engine share. The domain decides which pages exist
// (`PageSpec`), asks for imperative page actions (`PageAction`) and receives what pages report (`PageEvent`).
// The engine knows nothing about tabs, spaces or sidebars, and the domain knows nothing about Chromium.

/// A logical tab realized in one window. The wire form is two canonical base64 UTF-8 components, separated by a colon.
/// Both components are opaque strings, including empty strings and delimiter characters.
public struct PageID: Hashable, Comparable, Sendable, Codable, CodingKeyRepresentable, CustomStringConvertible {
    public let window: WindowID
    public let item: ItemID
    public init(window: WindowID, item: ItemID) { self.window = window; self.item = item }

    public var description: String { "page:" + Data(window.rawValue.utf8).base64EncodedString() + ":" + Data(item.rawValue.utf8).base64EncodedString() }
    public init?(rawValue: String) {
        let parts = rawValue.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0] == "page",
              let w = Data(base64Encoded: String(parts[1])), let i = Data(base64Encoded: String(parts[2])),
              let window = String(data: w, encoding: .utf8), let item = String(data: i, encoding: .utf8) else { return nil }
        self.init(window: WindowID(window), item: ItemID(item))
        guard description == rawValue else { return nil }
    }
    public static func < (a: PageID, b: PageID) -> Bool { (a.window, a.item) < (b.window, b.item) }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        let raw = try c.decode(String.self)
        guard let id = PageID(rawValue: raw) else { throw DecodingError.dataCorruptedError(in: c, debugDescription: "Expected a composite page ID") }
        self = id
    }
    public func encode(to encoder: any Encoder) throws { var c = encoder.singleValueContainer(); try c.encode(description) }
    public var codingKey: any CodingKey { Key(stringValue: description) }
    public init?<T: CodingKey>(codingKey: T) { self.init(rawValue: codingKey.stringValue) }
    private struct Key: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { nil }
    }
}

/// Allocated only by PageLedger. Every observation is fenced by this browser incarnation.
public struct BrowserToken: Hashable, Sendable, Codable {
    public let page: PageID
    public let generation: UInt64
    public init(page: PageID, generation: UInt64) { self.page = page; self.generation = generation }
}

public struct DocumentToken: Hashable, Sendable, Codable {
    public let browser: BrowserToken
    public let sequence: UInt64
    public init(browser: BrowserToken, sequence: UInt64) { self.browser = browser; self.sequence = sequence }
}

public enum DocumentAvailability: Hashable, Sendable, Codable {
    case loading(DocumentToken)
    case ready(DocumentToken)
    case unavailable
}

/// Which Chromium request context (cookies, cache, storage, extensions) a page browses in. Arc: a space's
/// `Profile`, or incognito. The engine maps `.profile(p)` to one persistent context per profile (the default
/// profile is the runtime's own cache) and `.incognito(epoch)` to the current private session
/// shared by its windows. Closing the last window synchronously revokes that epoch. A profile is a `ProfileID`, never a path: where its data lives
/// is the engine's business.
public enum BrowsingContext: Hashable, Sendable, Codable {
    case profile(ProfileID)
    case incognito(PrivateSessionID)
}

/// A page that should be live. The engine creates it on first sight and removes presentation when it disappears from the
/// list (`WebEngine.reconcile`). Accepted operations may retain the original browser. `initialURL` is read only at creation; later navigation is a `PageAction`.
public struct PageSpec: Hashable, Sendable, Codable {
    public let id: PageID
    /// Nil for an empty split pane waiting for the command bar: the engine creates no browser for it.
    public let initialURL: URL?
    /// The request context the page browses in. A changed context recreates the browser so the tab cannot retain
    /// the previous profile's cookies and storage.
    public let context: BrowsingContext

    public var websitePolicy: WebsitePolicy = WebsitePolicy()
    public let downloadPolicy: DownloadPolicy

    public init(id: PageID, initialURL: URL?, context: BrowsingContext, downloadPolicy: DownloadPolicy = .default) {
        self.id = id
        self.initialURL = initialURL
        self.context = context
        self.downloadPolicy = downloadPolicy
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

/// What a live page reports. Delivered as `SystemEvent.page(browser, event)`; never written to the page's tab by
/// anything but the reducer.
public enum PageEvent: Hashable, Sendable, Codable {
    /// First event for an incarnation, before any native observations.
    case browserCreated(BrowsingContext, DocumentAvailability)
    case documentChanged(DocumentAvailability)
    /// Transient intent, never a restoration seed.
    case navigationRequested(URL)
    /// A committed main-frame document confirmed usable, or a same-document address update. Never a failed load.
    case committed(URL)
    case titleChanged(String)
    case faviconChanged(URL?)
    case loadingChanged(isLoading: Bool, canGoBack: Bool, canGoForward: Bool)
    case loadFailed(code: Int, description: String, url: String)
    /// The renderer process crashed or was killed. The page object stays; see `PageAction.recover`.
    case websitePolicyApplied(WebsitePolicyStatus)
    case rendererGone
    /// The page closed itself (`window.close()`); the engine has already started closing the browser.
    case closedByPage
    /// The page took keyboard focus (the user clicked into it, e.g. into another split pane).
    case gainedFocus
    case openRequested(URL, OpenDisposition)
    /// The browser finished closing (`OnBeforeClose`). The id may be reused by a new page right after.
    case closed
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
    public var requestedReloads: Int? = nil
    public var extensionDialogDecision: String? = nil
    public var extensionFileDialogCallbacks: Int? = nil
    public var websiteFrozen: Bool? = nil
    public var websitePolicyError: String? = nil
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
