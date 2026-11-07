// The smallest program on BrkCore.framework: one AppKit window with one page, nothing else from Brk. It prints what the page reports, so a
// run can be read without looking at the screen. Built by engine/build-demo.sh.
//
//   BrkCoreDemo.app/Contents/MacOS/BrkCoreDemo [url] [user data folder]
import AppKit

@MainActor
final class Demo: NSObject, NSApplicationDelegate, BrkCoreWebContentsDelegate, BrkCoreBrowserDelegate {
    let application: any BrkCoreApplication
    let url: URL
    var window: NSWindow?
    var browser: (any BrkCoreBrowser)?
    var contents: (any BrkCoreWebContents)?

    init(application: any BrkCoreApplication, url: URL) {
        self.application = application
        self.url = url
    }

    func say(_ line: String) { print("[demo] \(line)"); fflush(stdout) }

    func applicationDidFinishLaunching(_ notification: Notification) {
        say("chromium \(application.version), NSApp is \(NSStringFromClass(type(of: NSApp!)))")
        let window = NSWindow(contentRect: NSRect(x: 200, y: 200, width: 1000, height: 700),
                              styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = "BrkCore"
        window.makeKeyAndOrderFront(nil)
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        application.loadProfile("Default") { [weak self] profile in
            guard let self, let profile else { self?.say("no profile"); return }
            self.say("profile \(profile.path)")
            let browser = profile.createBrowser(for: window, delegate: self)
            let contents = browser.createWebContents()
            contents.delegate = self
            contents.nativeView.frame = window.contentView!.bounds
            contents.nativeView.autoresizingMask = [.width, .height]
            window.contentView!.addSubview(contents.nativeView)
            contents.setHidden(false)
            contents.load(self.url)
            self.browser = browser
            self.contents = contents
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        contents?.close()
        DispatchQueue.main.async { NSApp.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }

    func webContents(_ c: any BrkCoreWebContents, decideNavigationTo url: URL, isRedirect: Bool, userGesture: Bool) -> Bool {
        say("navigating to \(url.absoluteString)")
        return true
    }
    func webContents(_ c: any BrkCoreWebContents, didChangeAddress url: URL?) {}

    /// What the page and its views look like now: for runs that are read without looking at the screen.
    func diagnose(_ c: any BrkCoreWebContents) {
        func tree(_ v: NSView, _ depth: Int) -> [String] {
            ["\(String(repeating: "  ", count: depth))\(NSStringFromClass(type(of: v))) \(NSStringFromRect(v.frame)) hidden=\(v.isHidden) layer=\(v.layer.map { NSStringFromClass(type(of: $0)) } ?? "none")"]
                + (depth < 4 ? v.subviews.flatMap { tree($0, depth + 1) } : [])
        }
        for line in tree(c.nativeView, 0) { say("view \(line)") }
        say("window visible=\(window?.isVisible ?? false) key=\(window?.isKeyWindow ?? false) occlusion visible=\(window?.occlusionState.contains(.visible) ?? false)")
        c.evaluateJavaScript("[document.visibilityState, innerWidth, innerHeight, document.hasFocus()].join(' ')") { [weak self] json, error in
            self?.say("page \(json ?? error ?? "?")")
        }
    }
    func webContents(_ c: any BrkCoreWebContents, didStartDocument url: URL?) { say("committed \(url?.absoluteString ?? "?")") }
    func webContents(_ c: any BrkCoreWebContents, didFinishDocument url: URL?) {
        say("loaded \(url?.absoluteString ?? "?")")
        c.evaluateJavaScript("navigator.userAgent") { [weak self] json, error in self?.say("javascript \(json ?? error ?? "?")") }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.diagnose(c) }
    }
    func webContents(_ c: any BrkCoreWebContents, didChangeLoading isLoading: Bool, canGoBack: Bool, canGoForward: Bool) {}
    func webContents(_ c: any BrkCoreWebContents, didChangeProgress progress: Double) {}
    func webContents(_ c: any BrkCoreWebContents, didFailLoadCode code: Int, description: String, url: String) { say("failed \(code) \(description)") }
    func webContents(_ c: any BrkCoreWebContents, didChangeTitle title: String) {
        window?.title = title
        say("title \(title)")
    }
    func webContents(_ c: any BrkCoreWebContents, didChangeFavicon url: URL?) {}
    func webContents(_ c: any BrkCoreWebContents, didHoverLink url: URL?) {}
    func webContentsRendererGone(_ c: any BrkCoreWebContents) { say("renderer gone") }
    func webContentsDidGainFocus(_ c: any BrkCoreWebContents) {}
    func webContents(_ c: any BrkCoreWebContents, didChangeZoomLevel level: Double) {}
    func webContentsClosed(byPage c: any BrkCoreWebContents) {}
    func webContentsDidClose(_ c: any BrkCoreWebContents) {}
    func webContents(_ c: any BrkCoreWebContents, keyBeforePage key: BrkCoreKeyPress) -> BrkCoreKeyAnswer { BrkCoreKeyAnswer(handled: false, shortcut: false) }
    func webContents(_ c: any BrkCoreWebContents, keyAfterPage key: BrkCoreKeyPress) -> Bool { false }
    func webContents(_ c: any BrkCoreWebContents, requestsOpening url: URL, disposition: BrkCoreDisposition, userGesture: Bool) {}

    func browser(_ browser: any BrkCoreBrowser, didOpenExtensionPopup extensionID: String, view: NSView) {}
    func browser(_ browser: any BrkCoreBrowser, didResizeExtensionPopup extensionID: String, size: NSSize) {}
    func browser(_ browser: any BrkCoreBrowser, didCloseExtensionPopup extensionID: String) {}
}

func step(_ text: String) { FileHandle.standardError.write(Data("[demo] step \(text)\n".utf8)) }

MainActor.assumeIsolated {
    step("start")
    let bundle = Bundle.main.bundleURL
    let framework = bundle.appendingPathComponent("Contents/Frameworks/BrkCore.framework/BrkCore").path
    guard let handle = dlopen(framework, RTLD_NOW | RTLD_LOCAL) else { fatalError(String(cString: dlerror())) }
    step("framework loaded")
    typealias Prepare = @convention(c) (Int32, UnsafePointer<UnsafePointer<CChar>>) -> Void
    typealias Shared = @convention(c) () -> UnsafeMutableRawPointer
    let arguments = CommandLine.arguments
    let data = arguments.count > 2 ? arguments[2] : NSTemporaryDirectory() + "brk-core-demo"
    let chromium = [arguments[0], "--user-data-dir=\(data)", "--profile-directory=Default", "--no-startup-window", "--no-first-run",
                    "--no-default-browser-check", "--use-mock-keychain", "--enable-logging=stderr", "--v=0"]
    let copies = chromium.map { UnsafePointer<CChar>(strdup($0)!) }
    copies.withUnsafeBufferPointer { unsafeBitCast(dlsym(handle, "BrkCoreApplicationPrepare"), to: Prepare.self)(Int32(copies.count), $0.baseAddress!) }
    step("prepared, NSApp is \(NSStringFromClass(type(of: NSApplication.shared)))")
    let object = Unmanaged<AnyObject>.fromOpaque(unsafeBitCast(dlsym(handle, "BrkCoreApplicationShared"), to: Shared.self)()).takeUnretainedValue()
    let application = object as! any BrkCoreApplication
    step("application object \(application.version)")
    let url = URL(string: arguments.count > 1 ? arguments[1] : "about:version")!
    let demo = Demo(application: application, url: url)
    NSApplication.shared.delegate = demo
    NSApplication.shared.setActivationPolicy(.regular)
    let code = application.run()
    print("[demo] chromium main returned \(code)")
    exit(code)
}
