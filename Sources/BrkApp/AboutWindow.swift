import AppKit
import BrkBase
import BrkDomain
import BrkSettings

/// The About window, laid out as Arc 1.170's (P39-a in 2a96a9d7f0:verify/visual-pairs/run-20261103): 360 by 262 points, the
/// app icon, the name, "Version <version> (<build>)", "Chromium Engine Version <version>", the copyright line and the
/// credits paragraph whose links open Chromium's site and its credits page in a tab. The name and versions are Brk's
/// own; the icon is the one the Icon pane chose.
@MainActor
final class AboutWindow: NSObject, NSTextViewDelegate {
    private var panel: NSPanel?
    private let send: @MainActor (Command) -> Void
    private let engineVersion: String?

    init(engineVersion: String?, send: @escaping @MainActor (Command) -> Void) {
        self.engineVersion = engineVersion
        self.send = send
    }

    func show(icon: AppIconChoice) {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        (panel.contentView?.viewWithTag(Tag.icon) as? NSImageView)?.image = AppIconArt.image(icon, side: About.icon.value)
        if !panel.isVisible { panel.center() }
        panel.makeKeyAndOrderFront(nil)
    }

    private enum Tag { static let icon = 1 }

    /// Arc's "Version 1.170.0 (89123)": the marketing version and, in the parentheses, the build. A Brk build is
    /// named by its commit (`BrkGitCommit`, written by scripts/declare-scripting.sh), the bundle's build number when
    /// there is none (a SwiftPM run).
    static func versionLine(_ info: [String: Any] = Bundle.main.infoDictionary ?? [:]) -> String {
        let version = info["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = (info["BrkGitCommit"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? info["CFBundleVersion"] as? String ?? "1"
        return "Version \(version) (\(build))"
    }

    static func engineLine(_ version: String?) -> String? { version.map { "Chromium Engine Version \($0)" } }

    /// A copyright line names the year of the release, like Arc's ("Copyright © 2026 The Browser Company.").
    static var copyright: String { "Copyright © 2026 \(Product.name). All rights reserved." }

    private func makePanel() -> NSPanel {
        let size = About.window.value
        let panel = AboutPanel(contentRect: CGRect(origin: .zero, size: size), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.title = ""
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = false
        panel.standardWindowButton(.miniaturizeButton)?.isEnabled = false
        panel.standardWindowButton(.zoomButton)?.isEnabled = false
        // The content size so the whole frame is Arc's 360 x 262.
        let chrome = panel.frame.height - (panel.contentView?.frame.height ?? panel.frame.height)
        panel.setContentSize(CGSize(width: size.width, height: size.height - chrome))
        let content = NSView(frame: CGRect(origin: .zero, size: panel.contentRect(forFrameRect: panel.frame).size))
        panel.contentView = content
        let width = content.bounds.width
        var y = content.bounds.height - About.iconTop.value

        let icon = NSImageView(frame: CGRect(x: (width - About.icon.value) / 2, y: y - About.icon.value, width: About.icon.value, height: About.icon.value))
        icon.tag = Tag.icon
        icon.imageScaling = .scaleProportionallyUpOrDown
        content.addSubview(icon)
        y -= About.icon.value + About.nameTop.value

        func line(_ text: String, font: NSFont, gap: CGFloat) {
            let label = NSTextField(labelWithString: text)
            label.font = font
            label.alignment = .center
            label.textColor = .labelColor
            label.sizeToFit()
            y -= label.frame.height
            label.frame = CGRect(x: 0, y: y, width: width, height: label.frame.height)
            content.addSubview(label)
            y -= gap
        }
        line(Product.name, font: .boldSystemFont(ofSize: About.nameSize.value), gap: About.versionTop.value)
        line(Self.versionLine(), font: .systemFont(ofSize: About.textSize.value), gap: 0)
        if let engine = Self.engineLine(engineVersion) { line(engine, font: .systemFont(ofSize: About.textSize.value), gap: 0) }
        y -= About.copyrightTop.value
        line(Self.copyright, font: .systemFont(ofSize: About.textSize.value), gap: About.creditsTop.value)

        let credits = NSTextView(frame: CGRect(x: About.creditsInset.value, y: 0, width: width - 2 * About.creditsInset.value, height: y))
        credits.isEditable = false
        credits.isSelectable = true
        credits.drawsBackground = false
        credits.textContainerInset = .zero
        credits.textContainer?.lineFragmentPadding = 0
        credits.delegate = self
        credits.linkTextAttributes = [.foregroundColor: NSColor.linkColor, .underlineStyle: NSUnderlineStyle.single.rawValue, .cursor: NSCursor.pointingHand]
        credits.textStorage?.setAttributedString(Self.credits)
        credits.layoutManager?.ensureLayout(for: credits.textContainer!)
        let used = credits.layoutManager?.usedRect(for: credits.textContainer!).height ?? 0
        credits.frame = CGRect(x: About.creditsInset.value, y: y - used, width: width - 2 * About.creditsInset.value, height: used)
        credits.setAccessibilityIdentifier("about-credits")
        content.addSubview(credits)
        return panel
    }

    /// "Brk is made possible by the Chromium open source project, Chromium's open source software, as well as other
    /// open source software." with Arc's three links: Chromium's site, Chromium's credits page and the licences of
    /// the rest of what Brk ships (Help/credits.html, Arc's Credits.html).
    static var credits: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        let base: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: About.textSize.value), .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
        let text = NSMutableAttributedString()
        func add(_ string: String, link: String? = nil) {
            var attributes = base
            if let link { attributes[.link] = URL(string: "brk-about://\(link)")! }
            text.append(NSAttributedString(string: string, attributes: attributes))
        }
        add("\(Product.name) is made possible by the ")
        add("Chromium", link: BrowserPage.chromium.rawValue)
        add(" open source project, Chromium's ")
        add("open source software", link: BrowserPage.credits.rawValue)
        add(", as well as other ")
        add("open source software", link: Self.otherCredits)
        add(".")
        return text
    }

    static let otherCredits = "brk-credits"

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        guard let url = link as? URL, let host = url.host else { return false }
        if host == Self.otherCredits {
            if let credits = HelpLinks.credits() { send(.app(.help(.open(credits)))) }
            else { send(.settings(.openBrowserPage(.credits, profile: nil))) }
            return true
        }
        guard let page = BrowserPage(rawValue: host) else { return false }
        send(.settings(.openBrowserPage(page, profile: nil)))
        return true
    }
}

/// Cmd+W and Esc close the About window itself (they never reach the browser window's Cmd+W, which archives a tab).
final class AboutPanel: NSPanel {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if event.type == .keyDown, modifiers == .command, event.charactersIgnoringModifiers == "w" {
            performClose(nil)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func cancelOperation(_ sender: Any?) { performClose(nil) }
}

private var About: AboutMetricsTable { AboutMetrics }

let AboutMetrics = AboutMetricsTable()

struct AboutMetricsTable: MetricGroup {
    private static let capture = "~/brk-arc-reference/P39/P39-a-arc.png"
    let window = Metric(CGSize(width: 360, height: 262), .anatomy("\(capture): 720 x 524 px"))
    let icon = Metric(64.0, .anatomy("\(capture): the icon's tile spans x 308 to 412 px, a 64-point canvas"))
    let iconTop = Metric(16.5, .anatomy("\(capture): the title bar ends at y 64 px, the tile starts near 122 px"))
    let nameTop = Metric(7.5, .anatomy("\(capture): the tile ends near y 212 px, the name is centred at 257 px"))
    let nameSize = Metric(13.0, .anatomy("\(capture): the name's capitals are 18 px tall (y 247 to 265 px), a 13 pt bold line"))
    let versionTop = Metric(8.0, .anatomy("\(capture): the name centred at y 257 px, the version line at 300 px"))
    let textSize = Metric(11.0, .anatomy("\(capture): the version lines are 29 px apart"))
    let copyrightTop = Metric(8.0, .anatomy("\(capture): the engine line centred at y 329 px, the copyright at 374 px"))
    let creditsTop = Metric(8.0, .anatomy("\(capture): the copyright centred at y 374 px, the credits' first line at 418 px"))
    let creditsInset = Metric(20.0, .anatomy("\(capture): the credits span about x 48 to 682 px"))
}
