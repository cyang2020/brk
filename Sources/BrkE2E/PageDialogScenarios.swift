import BrkBase
import BrkControl
import BrkLayout
import CoreGraphics
import Foundation

/// Chromium's own dialogs that hang on a page: the passkey dialog, the HTTP sign-in prompt and print preview
/// (constrained_window), and FedCM's account chooser (TabDialogManager). Until 0.0.52 Brk's window gave Chromium no
/// place to hang them and each one quit Brk (issue #10: ChatGPT's passkey and "Sign in with Google"). Real keys and
/// clicks answer them, as a person would; Brk must still be running after each.
enum PageDialogScenarios {
    static let all = [
        Scenario("PageDialogs", "passkey, HTTP sign-in, FedCM and print dialogs open over their page without quitting Brk; real keys and clicks answer them, closing the tab under one takes it along, and one follows its page to another window",
                 dialogs),
    ]

    @Sendable static func dialogs(_ app: AppUnderTest) throws {
        guard WindowServerKeys.allowed else { throw Check(description: "no permission to post real keys and clicks") }
        guard let window = app.window else { throw Check(description: "no window") }
        guard case .hello(let hello) = try app.send(.hello) else { throw Check(description: "no hello") }
        let pid = hello.pid
        // WebAuthn needs a host name, not 127.0.0.1; localhost also makes FedCM's provider the page's own site.
        func url(_ path: String) -> URL { URL(string: "http://localhost:\(app.site.port)\(path)")! }
        var item: ItemID?
        // Read in the window that shows the page: a tab's title lives in that window's slot.
        var showing = window
        func title() throws -> String { item.flatMap { id in (try? app.view(showing)).flatMap { tab(id, in: $0)?.title } } ?? "" }
        // `ready: false`: a page held at Chromium's HTTP sign-in prompt has no document until someone signs in.
        func open(_ path: String, ready: Bool = true) throws -> PageID {
            let target = url(path)
            // Brk in front first: a dialog that opens with the page takes the key window from it.
            try WindowServerKeys.ensureFrontmost(app, window)
            item = try app.load(target)
            let page = PageID(window: window, item: item!)
            if ready { try app.waitForPageInput(page, at: target) }
            return page
        }
        func waitForDialog(_ what: String, timeout: Double = 10) throws -> CGRect {
            var found: CGRect?
            try app.waitUntil("\(what) opens over the page", timeout: timeout) {
                found = try dialogWindow(app, pid: pid, window: window)
                return found != nil
            }
            return found!
        }
        func waitClosed(_ what: String) throws {
            try app.waitUntil("\(what) closes", timeout: 8) { try dialogWindow(app, pid: pid, window: window) == nil }
        }
        // A person clicks the dialog before typing into it. The click lands well inside its frame (the window's edge
        // is a transparent border), on no control, and the dialog then has the keyboard, not the Brk window.
        func focus(_ dialog: CGRect, in owner: WindowID? = nil) throws {
            let point = CGPoint(x: dialog.minX + 40, y: dialog.minY + 40)
            guard PhysicalPointer.frontmost(at: point)?.pid == pid else { throw Check(description: "another window covers the dialog at \(point)") }
            try PhysicalPointer.post(clickAt: point)
            try app.waitUntil("the dialog has the keyboard", timeout: 3) { !(try app.native(owner ?? window).isKey) }
        }

        // 1. The passkey dialog (the crash in issue #10's report): centred on the page, Escape cancels the request.
        _ = try open("/dialog-passkey.html")
        let passkey = try waitForDialog("Chromium's passkey dialog")
        let card = try cardOnScreen(app, window)
        try expect(abs(passkey.midX - card.midX) < 24, "the passkey dialog is centred on the page: dialog \(passkey), page \(card)")
        try expect(abs(passkey.minY - card.minY) < 24, "the passkey dialog hangs from the page's top edge: dialog \(passkey), page \(card)")
        let listedHosts = try hostWindowsListed(app, window)
        try expect(listedHosts.isEmpty, "a dialog host window is listed in Mission Control: \(listedHosts)")
        _ = try app.screenshot("1-passkey")
        try focus(passkey)
        PhysicalKeys.press(KeyChord([], .escape), pid: pid)
        try app.waitUntil("Escape cancels the passkey request (\(try title()))") { try title() == "result: NotAllowedError" }
        try waitClosed("the passkey dialog")

        // 2. The HTTP sign-in prompt: typed into with real keys, Return signs in.
        _ = try open("/dialog-signin.html", ready: false)
        let signIn = try waitForDialog("Chromium's sign-in prompt")
        _ = try app.screenshot("2-sign-in")
        try focus(signIn)
        PhysicalKeys.type(PageDialogFixture.user, pid: pid)
        PhysicalKeys.press(KeyChord([], .tab), pid: pid)
        PhysicalKeys.type(PageDialogFixture.password, pid: pid)
        PhysicalKeys.press(KeyChord([], .returnKey), pid: pid)
        try app.waitUntil("the page signs in with the typed name and password (\(try title()))", timeout: 10) { try title() == "result: signed in" }
        try waitClosed("the sign-in prompt")
        // Brk then offers to save the typed password (its own card, as for a form); No (Escape) leaves it.
        let savePrompt = ViewID.spaceToolsControl("save-prompt")
        try app.waitUntil("Brk offers to save the sign-in's password", timeout: 8) { isShown(try app.native(window), savePrompt) }
        PhysicalKeys.press(KeyChord([], .escape), pid: pid)
        try app.waitUntil("No closes the save card") { !isShown(try app.native(window), savePrompt) }

        // 3. FedCM's account chooser (Chromium's other dialog path): a real click on "Continue as Brk" returns the token.
        _ = try open("/dialog-fedcm.html")
        let chooser = try waitForDialog("FedCM's account chooser")
        _ = try app.screenshot("3-fedcm")
        // Its "Continue as" button spans the chooser below the account row, 56% of the way down.
        let continueButton = CGPoint(x: chooser.midX, y: chooser.minY + chooser.height * 0.56)
        guard PhysicalPointer.frontmost(at: continueButton)?.pid == pid else { throw Check(description: "another window covers the chooser") }
        try PhysicalPointer.post(clickAt: continueButton)
        try app.waitUntil("Continue signs the page in through FedCM (\(try title()))", timeout: 10) { try title() == "result: token fixture-token" }
        try waitClosed("the account chooser")

        // 4. window.print(): Chromium's print preview, closed with Escape.
        _ = try open("/dialog-print.html")
        let preview = try waitForDialog("print preview", timeout: 15)
        _ = try app.screenshot("4-print")
        try focus(preview)
        PhysicalKeys.press(KeyChord([], .escape), pid: pid)
        try app.waitUntil("Escape closes print preview and window.print() returns (\(try title()))", timeout: 10) { try title() == "result: print returned" }
        try waitClosed("print preview")

        // 5. The tab closed while its passkey dialog is open: the dialog goes with it and Brk keeps running.
        let last = try open("/dialog-passkey.html")
        _ = try waitForDialog("the second passkey dialog")
        try app.dispatch(.tab(.close(.item(last.item))))
        try waitClosed("the passkey dialog of the closed tab")
        _ = try app.send(.hello)
        try app.waitUntil("the dialog host leaves the screen with its last dialog", timeout: 4) { try hostWindows(app, pid: pid, window: window).isEmpty }

        // 6. The page shown in a second window while its passkey dialog is open: Chromium moves the tab to that window's
        // Browser, and the dialog goes with it, still waiting for an answer, as in Chrome.
        let moving = try open("/dialog-passkey.html")
        _ = try waitForDialog("the passkey dialog before the move")
        try app.dispatch(.window(.new))
        guard case .hello(let now) = try app.send(.hello), let second = now.windows.first(where: { $0 != window }) else {
            throw Check(description: "no second window")
        }
        _ = try app.send(.dispatch(window: second, command: .tab(.focus(moving.item))))
        let moved = PageID(window: second, item: moving.item)
        try app.waitUntil("the page moves to the second window", timeout: 8) { try app.native(second).ownedPages?[moved] != nil }
        showing = second
        app.sleep(1)
        let afterMove = try title()
        try expect(afterMove == "passkey: waiting", "moving the page answered its passkey request: \(afterMove)")
        let followed = try waitForDialog("the passkey dialog in the second window")
        let secondFrame = try windowOnScreen(app, second)
        try expect(secondFrame.contains(CGPoint(x: followed.midX, y: followed.midY)), "the dialog stayed behind: dialog \(followed), second window \(secondFrame)")
        try WindowServerKeys.ensureFrontmost(app, second)
        try focus(followed, in: second)
        PhysicalKeys.press(KeyChord([], .escape), pid: pid)
        try app.waitUntil("Escape still answers the moved dialog") { try title() == "result: NotAllowedError" }
        _ = try app.send(.dispatch(window: second, command: .window(.close)))
        app.passed("each dialog opened over its page and answered real input, and followed its page to another window; Brk kept running")
    }

    /// The page card in screen coordinates (top-left origin).
    private static func cardOnScreen(_ app: AppUnderTest, _ window: WindowID) throws -> CGRect {
        let facts = try app.native(window)
        let card = facts.computed.cards[0].rect
        let top = CGDisplayBounds(CGMainDisplayID()).height - facts.windowFrame.maxY
        return CGRect(x: facts.windowFrame.minX + card.minX, y: top + card.minY, width: card.width, height: card.height)
    }

    /// An on-screen window of Brk's smaller than the Brk window (which the dialog host covers exactly): a Chromium dialog.
    private static func dialogWindow(_ app: AppUnderTest, pid: Int32, window: WindowID) throws -> CGRect? {
        let frame = try app.native(window).windowFrame
        return windows(pid: pid).first { $0.width >= 100 && $0.height >= 60 && abs($0.width - frame.width) > 2 }
    }

    /// The dialog host's own window (BrkDialogHosts): transparent, exactly over the Brk window, on screen only while a
    /// dialog uses it. The Brk window itself is the other window with that frame.
    private static func hostWindows(_ app: AppUnderTest, pid: Int32, window: WindowID) throws -> [CGRect] {
        let frame = try windowOnScreen(app, window)
        return Array(windows(pid: pid).filter { abs($0.minX - frame.minX) < 2 && abs($0.minY - frame.minY) < 2 && abs($0.width - frame.width) < 2 }.dropFirst())
    }

    /// Chromium's windows that Mission Control would show over the whole Brk window: a dialog host that forgot to be
    /// transient (dialogs themselves are smaller).
    private static func hostWindowsListed(_ app: AppUnderTest, _ window: WindowID) throws -> [AppWindowFact] {
        let frame = try windowOnScreen(app, window)
        return try app.native(window).appWindows.filter { $0.listedInMissionControl == true && $0.className == "NativeWidgetMacNSWindow" && $0.isPageHost != true }
            .filter { fact in
                let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(fact.number)) as? [[String: Any]] ?? []
                let bounds = list.first?[kCGWindowBounds as String] as? [String: Double]
                return abs((bounds?["Width"] ?? 0) - frame.width) < 2 && abs((bounds?["Height"] ?? 0) - frame.height) < 2
            }
    }

    /// The Brk window's frame in screen coordinates (top-left origin).
    private static func windowOnScreen(_ app: AppUnderTest, _ window: WindowID) throws -> CGRect {
        let frame = try app.native(window).windowFrame
        return CGRect(x: frame.minX, y: CGDisplayBounds(CGMainDisplayID()).height - frame.maxY, width: frame.width, height: frame.height)
    }

    private static func windows(pid: Int32) -> [CGRect] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        return list.compactMap { info in
            guard info[kCGWindowOwnerPID as String] as? Int32 == pid, info[kCGWindowLayer as String] as? Int == 0,
                  let bounds = info[kCGWindowBounds as String] as? [String: Double] else { return nil }
            return CGRect(x: bounds["X"] ?? 0, y: bounds["Y"] ?? 0, width: bounds["Width"] ?? 0, height: bounds["Height"] ?? 0)
        }
    }
}

/// The pages and endpoints `PageDialogs` opens, served by the e2e fixture server on localhost.
enum PageDialogFixture {
    static let user = "brk-user"
    static let password = "brk-pass-7"

    static func response(_ path: String, request: Data) -> Data? {
        let headers = String(decoding: request, as: UTF8.self).components(separatedBy: "\r\n")
        func header(_ name: String) -> String? {
            headers.first { $0.lowercased().hasPrefix(name.lowercased() + ":") }.map { String($0.dropFirst(name.count + 1)).trimmingCharacters(in: .whitespaces) }
        }
        let origin = "http://" + (header("Host") ?? "localhost")
        func reply(_ body: String, type: String = "text/html; charset=utf-8", status: String = "200 OK", extra: String = "") -> Data {
            let data = Data(body.utf8)
            return Data("HTTP/1.1 \(status)\r\nContent-Type: \(type)\r\nContent-Length: \(data.count)\r\nCache-Control: no-store\r\n\(extra)Connection: close\r\n\r\n".utf8) + data
        }
        func json(_ object: Any, extra: String = "") -> Data {
            reply(String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self), type: "application/json", extra: extra)
        }
        func page(_ name: String, _ script: String) -> Data {
            reply("<!doctype html><meta charset=\"utf-8\"><title>\(name): waiting</title><h1>\(name)</h1><script>\(script)</script>")
        }
        func settle(_ call: String, _ result: String) -> String {
            "(async () => { try { \(call); document.title = 'result: ' + \(result); } catch (e) { document.title = 'result: ' + e.name; } })();"
        }
        switch path {
        case "/dialog-passkey.html":
            // USB only: Chromium goes straight to "Use your security key", with no phone or Bluetooth step.
            return page("passkey", settle("await navigator.credentials.get({publicKey: {challenge: new Uint8Array(32), rpId: location.hostname, timeout: 120000, allowCredentials: [{type: 'public-key', id: new Uint8Array(16).fill(7), transports: ['usb']}]}})", "'resolved'"))
        case "/dialog-signin.html":
            let expected = "Basic " + Data("\(user):\(password)".utf8).base64EncodedString()
            if header("Authorization") == expected { return reply("<!doctype html><title>result: signed in</title><p>signed in</p>") }
            return reply("<!doctype html><title>sign-in: refused</title>", status: "401 Unauthorized", extra: "WWW-Authenticate: Basic realm=\"Brk fixture\"\r\n")
        case "/dialog-fedcm.html":
            return page("fedcm", settle("await navigator.login.setStatus('logged-in'); const credential = await navigator.credentials.get({identity: {providers: [{configURL: location.origin + '/fedcm/config.json', clientId: 'brk-test'}]}})", "'token ' + credential.token"))
        case "/dialog-print.html":
            return page("print", "setTimeout(() => { window.print(); document.title = 'result: print returned'; }, 300);")
        case "/.well-known/web-identity":
            return json(["provider_urls": [origin + "/fedcm/config.json"]])
        case "/fedcm/config.json":
            return json(["accounts_endpoint": "/fedcm/accounts", "client_metadata_endpoint": "/fedcm/client_metadata",
                         "id_assertion_endpoint": "/fedcm/assert", "login_url": "/fedcm/login"])
        case "/fedcm/accounts":
            return json(["accounts": [["id": "1", "email": "test@example.com", "name": "Brk Test", "given_name": "Brk", "approved_clients": [String]()]]])
        case "/fedcm/client_metadata":
            return json(["privacy_policy_url": origin + "/privacy", "terms_of_service_url": origin + "/terms"])
        case "/fedcm/assert":
            let caller = header("Origin") ?? origin
            return json(["token": "fixture-token"], extra: "Access-Control-Allow-Origin: \(caller)\r\nAccess-Control-Allow-Credentials: true\r\n")
        case "/fedcm/login":
            return reply("<!doctype html><title>login</title>", extra: "Set-Login: logged-in\r\n")
        default:
            return nil
        }
    }
}
