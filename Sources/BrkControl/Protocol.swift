import BrkBase
import BrkDomain
import BrkLayout
import CoreGraphics
import Foundation

// The control socket contract, shared by the app's server (BrkApp/Control) and the e2e runner (BrkE2E), so the two
// sides cannot drift: a request the runner can build is one the server can decode.
//
// Transport: a Unix stream socket at $BRK_CONTROL_SOCKET (only when set). One JSON object per line each way;
// requests carry an `id`, replies echo it. Requests on one connection run in order on the main actor; a connection
// may stay open for a whole scenario. scripts/ctl.sh sends one line by hand for debugging.

public struct ControlRequest: Codable, Sendable, Equatable {
    public var id: Int
    public var op: ControlOp
    public init(id: Int, op: ControlOp) {
        self.id = id
        self.op = op
    }
}

public enum ControlOp: Codable, Sendable, Equatable {
    case sidebarData
    /// Opt-in native verification only. Operates on the initiating browser's real attached sheet controls.
    case sidebarPanel(window: WindowID?, action: SidebarPanelControlAction)
    /// Process facts: pid, windows, engine kind, data directory. The runner's readiness probe.
    case hello
    /// The window's `WindowSnapshot`, exactly what its views rendered last.
    case view(window: WindowID?)
    /// Activate a specific native window before physical input.
    case activate(window: WindowID)
    /// Makes the app the active application and the window key, for input posted through the window server (a
    /// physical key or click); `activate` alone keeps whatever app is frontmost. Replies with the real outcome:
    /// `.native` of the window, whose `isKey` is true only when the app became active.
    case activateApp(window: WindowID)
    /// Operate actual app-owned UI; available only on the opt-in control socket.
    case chooseOutputFixture(window: WindowID?, path: String)
    case cancelCurrentOutput(window: WindowID?)
    /// Explicit post-selection fixture; does not drive the remote save chooser.
    case selectLinkExportFixture(window: WindowID, path: String)
    case configureSavePanel(window: WindowID?, path: String)
    case answerSavePanel(window: WindowID?, path: String?)
    case cancelPrintPanel(window: WindowID?)
    case screenshotSheet(window: WindowID?, path: String)
    case menuAction(String)
    /// Sends `selector` to the first responder chain of the key window (nil target), from a text field holding
    /// `text`: what an AppKit panel button does (the spelling panel's Change sends `changeSpelling:` from the
    /// control whose selected cell holds the guess; the Substitutions panel's Replace sends `checkTextInDocument:`).
    case sendAction(selector: String, text: String?)
    case pasteboard(String?)
    case readPasteboard
    /// Computed frames, actual AppKit frames by view identifier, page facts, focus. See `NativeFacts`.
    case native(window: WindowID?)
    /// Runs a command through the normal dispatch path, as if a view sent it.
    case dispatch(window: WindowID?, command: Command)
    /// Scenario setup shortcut: opens `url` as a new Today tab through the same commands as Cmd+T, typing, Enter
    /// (`.commandBar(.open(.newTab))` then `.commandBar(.submit(url))`), and returns the new tab's id.
    case load(window: WindowID?, url: URL)
    /// Injects key-down and key-up NSEvents for "cmd+t", "ctrl+shift+=", "escape" into the key window, in process
    /// (no Accessibility permission), so they take the same path a real press takes: into Chromium and CEF's key
    /// handler when a page has focus, into the menu when a native view has focus.
    case press(chord: String)
    /// One key-down of `chord`, `repeats` auto-repeat key-downs (a held key), one key-up, in process like `press`.
    case pressHeld(chord: String, repeats: Int)
    /// Holds `modifiers` down, presses `chord` `times` times, then releases (Ctrl+Tab cycling, finding 6).
    case hold(modifiers: String, chord: String, times: Int)
    /// Types text into the first responder (command bar, rename field, or a focused page field).
    case type(text: String)
    /// Injects a left click at the centre of a view (by `ViewID`, located in the live view tree) or at a window point
    /// (top-left origin). `modifiers` like "cmd" for Cmd+click on a page link.
    case click(view: ViewID?, point: CGPoint?, modifiers: String?, count: Int)
    /// Opens a real page context menu, records its native items, and cancels tracking without selecting an action.
    case captureContextMenu(window: WindowID?, point: CGPoint, choose: String? = nil)
    /// Moves the pointer (hover: peek the hidden sidebar).
    case hover(point: CGPoint)
    /// A native pointer sequence. The down target keeps receiving dragged/up events, as with a physical mouse.
    case pointer(window: WindowID?, phase: PointerPhase, point: CGPoint)
    /// Native event sequences for scoped pointer and sidebar gesture acceptance.
    case pointerDrag(from: CGPoint, to: CGPoint, cancel: Bool)
    case scrollGesture(at: CGPoint, horizontal: Double, vertical: Double, cancel: Bool)
    case sheetButton(title: String)
    /// Makes this app's window `number` key (a DevTools or popup window), so `press` and `type` go to it.
    case focusAppWindow(number: Int)
    /// Clicks a button of the sheet attached to this app's window `number` (a popup's dialog, for example).
    case windowSheetButton(number: Int, title: String)
    /// Select an owned fixture directory in the actual native folder panel.
    case selectSheetDirectory(path: String)
    /// CGWindowListCreateImage of the window (works without screen recording permission, spike unknown 8), PNG.
    case screenshot(window: WindowID?, path: String)
    /// One pixel of a fresh window capture, at a window point (top-left origin, points), as sRGB 0...255.
    case pixel(window: WindowID?, point: CGPoint)
    /// Moves the test clock forward (BRK_TEST_CLOCK=1 only) and dispatches `.system(.clockTick)`.
    case advanceClock(seconds: Double)
    /// Runs JavaScript in a page through `WebEngine.evaluate`; fire and forget (fixture pages report through
    /// `document.title`).
    case evaluate(page: PageID, script: String)
    /// Navigates a page to chrome://crash (renderer crash) or chrome://gpucrash, for recovery scenarios.
    case crash(page: PageID, process: CrashTarget)
    /// Moves the NSWindow to a screen frame (finding 8).
    case setWindowFrame(window: WindowID?, frame: CGRect)
    /// `WebEngine.pageLog`: created, close requested and closed (OnBeforeClose) pages with generations, in order.
    case pageLog
    /// Reducer-accepted browser and document observations, including hidden demanded slots.
    case nativeDialogKey(number: Int, chord: String)
    case setAppAppearance(Scheme?)
    case siteControlsScreenshot(window: WindowID, path: String)
    /// Native semantic input in this owner's visible site-controls panel; typing still uses normal key events.
    case siteControlInput(window: WindowID, field: String, action: SiteControlAction)
    case siteControls
    /// Every label, title and value the owner's open site-controls panel exposes to accessibility, in tree order
    /// (what the panel shows: Secure or Insecure, the connection note, button titles). Reply: `menuItems`.
    case siteControlTexts(window: WindowID)
    /// The texts of Brk's open permission prompt for the window (`menuItems`); with `path`, also a PNG of it; with
    /// `press`, clicks that answer (a `settingsField` name) as `siteControlInput` does.
    case sitePrompt(window: WindowID, path: String?, press: String? = nil)
    case mediaSounds
    case mediaWindowScreenshot(number: Int, path: String)
    case captureProbe(page: PageID, directory: URL)
    case pageObservations
    /// Writes state.json now (skips the debounce).
    case flush
    /// Waits until no page is loading and the main queue is idle, or `timeout` seconds pass.
    case settle(timeout: Double)
    /// Starts the ordered quit. The reply comes before the process exits; the runner then waits for exit and checks
    /// the exit status and that no new crash report appeared.
    case quit
    /// The settings values and the settings window's pane (`AppSnapshot.settings`). F1.
    case settings
    /// Opens the settings window on a pane, as the Preferences… menu item does (`.settings(.openPane)` on the key
    /// window). F1.
    case openSettings(pane: SettingsPane)
    /// A link from another app, as the GetURL Apple Event delivers it (`SystemEvent.externalURL`). F3.
    case externalURL(url: URL)
    /// Native verification of the AppleScript dictionary only: compiles and runs AppleScript `script` inside the app
    /// (NSAppleScript, off the main thread, so its Apple Events reach the app the way an outside script's do) and
    /// answers `.text`: "permission <status>" (AEDeterminePermissionToAutomateTarget for the app itself, never
    /// asking), then "result: …" or "error <number>: …". Apple Events an app sends itself need no Automation
    /// consent; a separate osascript process does (macOS asks the user once per sender).
    case appleScript(script: String)
    /// Every text the app's visible windows show against the room it was given (`TextLayoutAudit`). Reply: `textLayout`.
    case textLayout
    /// Right-clicks a window point and measures the native menu that opens, submenus included, then cancels it.
    /// Reply: `textLayout`.
    case textLayoutMenu(window: WindowID?, point: CGPoint)
}

public enum CrashTarget: String, Codable, Sendable, Equatable { case renderer, gpu }
public enum PointerPhase: String, Codable, Sendable, Equatable { case down, dragged, up }
public enum SiteControlAction: String, Codable, Sendable, Equatable { case focus, press }

public struct ControlReply: Codable, Sendable, Equatable {
    public var id: Int
    public var result: ControlResult
    public init(id: Int, result: ControlResult) {
        self.id = id
        self.result = result
    }
}

public enum ControlResult: Codable, Sendable, Equatable {
    case sidebarData(SidebarDataSnapshot)
    case ok
    case hello(Hello)
    case view(WindowSnapshot)
    case native(NativeFacts)
    case menuItems([String])
    case text(String)
    case dispatched(rev: Int)
    case loaded(tab: ItemID)
    case pixel(red: Int, green: Int, blue: Int, alpha: Int)
    case screenshot(path: String, pixelWidth: Int, pixelHeight: Int)
    case clock(now: Instant)
    case pageLog([PageLogEntry])
    case siteControls([WindowID: SiteControlSnapshot])
    case pageObservations([PageID: PageObservation])
    case settings(SettingsSnapshot)
    case textLayout(TextLayoutReport)
    case failed(String)
}

public struct TextLayoutReport: Codable, Sendable, Equatable {
    /// How many texts were measured.
    public var inspected: Int
    /// The windows or menus walked: class, title, size.
    public var windows: [String]
    /// Texts that are cut: what the TextLayout scenario asserts is empty.
    public var findings: [TextLayoutFinding]
    /// Texts ended by an ellipsis or (SwiftUI, whose text ellipsizes by itself) short of room. A correct way to end a
    /// long title, listed so a person can see the short labels that should have fitted.
    public var truncated: [TextLayoutFinding]
    public init(inspected: Int, windows: [String], findings: [TextLayoutFinding], truncated: [TextLayoutFinding]) {
        self.inspected = inspected
        self.windows = windows
        self.findings = findings
        self.truncated = truncated
    }
}

public struct TextLayoutFinding: Codable, Sendable, Equatable {
    public enum Problem: String, Codable, Sendable {
        /// One line, no truncation, wider than its frame (or a frame of the text's width without the cell's inset).
        case overflowsFrame
        /// A frame shorter than the text's line.
        case tooShort
        /// Wrapped lines taller than the frame.
        case wrapOverflow
        /// The text's rectangle runs past an ancestor that clips.
        case clippedByAncestor
        /// Text a view draws itself, outside the view or the clip it set.
        case drawnOutsideView
        /// Not a failure: see `TextLayoutReport.truncated`.
        case ellipsis
    }
    public var problem: Problem
    public var window: String
    /// Class, parent's class and the nearest accessibility identifier.
    public var view: String
    public var text: String
    /// In the window's top-level view, top-left origin.
    public var frame: CGRect
    public var needed: CGSize
    /// The ancestor that cuts the text, for `clippedByAncestor`.
    public var clipper: String?
    public init(problem: Problem, window: String, view: String, text: String, frame: CGRect, needed: CGSize, clipper: String? = nil) {
        self.problem = problem
        self.window = window
        self.view = view
        self.text = text
        self.frame = frame
        self.needed = needed
        self.clipper = clipper
    }
}

public enum SidebarPanelControlAction: Codable, Sendable, Equatable {
    case capture(path: String)
    /// Configure only the starting directory; selection and confirmation remain real AX operations.
    case directory(path: String)
    case selection
    case inspect
    case button(String)
    case focus(identifier: String)
    case text(identifier: String, value: String)
    case select(identifier: String, index: Int)
    case save(directory: String, filename: String)
    case open(path: String)
}

public struct Hello: Codable, Sendable, Equatable {
    public var pid: Int32
    public var engine: String
    public var windows: [WindowID]
    public var dataDirectory: String
    public init(pid: Int32, engine: String, windows: [WindowID], dataDirectory: String) {
        self.pid = pid
        self.engine = engine
        self.windows = windows
        self.dataDirectory = dataDirectory
    }
}

/// What the window really looks like, next to what layout computed.
public struct NativeFacts: Codable, Sendable, Equatable {
    /// Registered native auxiliaries across every window, matching appWindows' process-wide scope.
    public var auxiliaryWindows: [Int]? = nil
    public var windowLevel: Int = 0
    public var miniaturized: Bool = false
    public var fullscreen: Bool = false
    public var fullscreenTransitioning: Bool? = nil
    public var keyWindowNumber: Int? = nil
    public var appHidden: Bool = false
    public var sheetClass: String? = nil
    /// The Icon pane's choice the Dock shows now (`NSApp.applicationIconImage` is that drawing), nil when it is none
    /// of them (the bundle's own icon).
    public var dockIcon: String? = nil
    public var window: WindowID
    /// NSWindow frame (screen, bottom-left origin) and content size.
    public var windowFrame: CGRect
    public var contentSize: CGSize
    public var backingScale: Double
    public var isKey: Bool
    /// `WindowLayout.compute` for the last rendered snapshot.
    public var computed: WindowFrames
    /// Every view in the window with an accessibility identifier: its frame in window coordinates (top-left),
    /// whether it is hidden, and its layer corner radius. Keys are `ViewID.identifier` strings.
    public var actual: [String: ActualView]
    /// Page surfaces attached to this window, keyed by page.
    public var pages: [PageID: PageFacts]
    /// All demanded pages belonging to this window, including hidden popup owners. `pages` remains attached surfaces.
    public var ownedPages: [PageID: PageFacts]? = nil
    /// Class name of the first responder, and the page that has keyboard focus, if any.
    public var firstResponder: String
    public var editorText: String? = nil
    public var focusedPage: PageID?
    /// Window numbers of every window the app owns, including CEF host windows; none of the host windows may be key.
    public var appWindows: [AppWindowFact]
    public init(window: WindowID, windowFrame: CGRect, contentSize: CGSize, backingScale: Double, isKey: Bool,
                computed: WindowFrames, actual: [String: ActualView], pages: [PageID: PageFacts],
                firstResponder: String, focusedPage: PageID?, appWindows: [AppWindowFact]) {
        self.window = window
        self.windowFrame = windowFrame
        self.contentSize = contentSize
        self.backingScale = backingScale
        self.isKey = isKey
        self.computed = computed
        self.actual = actual
        self.pages = pages
        self.firstResponder = firstResponder
        self.focusedPage = focusedPage
        self.appWindows = appWindows
    }
}

public struct ActualView: Codable, Sendable, Equatable {
    public var frame: CGRect
    public var hidden: Bool
    public var cornerRadius: Double
    public init(frame: CGRect, hidden: Bool, cornerRadius: Double) {
        self.frame = frame
        self.hidden = hidden
        self.cornerRadius = cornerRadius
    }
}

public struct AppWindowFact: Codable, Sendable, Equatable {
    public var number: Int
    public var className: String
    public var isKey: Bool
    public var isVisible: Bool
    public var isPageHost: Bool?
    public init(number: Int, className: String, isKey: Bool, isVisible: Bool, isPageHost: Bool? = nil) {
        self.number = number
        self.className = className
        self.isKey = isKey
        self.isVisible = isVisible
        self.isPageHost = isPageHost
    }
}

/// Newline-delimited JSON framing for both sides.
public enum ControlWire {
    public static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(value)
        data.append(0x0A)
        return data
    }

    public static func decode<T: Decodable>(_ type: T.Type, line: Data) throws -> T {
        try JSONDecoder().decode(type, from: line)
    }
}
