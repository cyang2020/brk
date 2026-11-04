import AppKit
import BrkControl
import BrkEngine

/// The control socket's `textLayout`: every text the app's visible windows show, next to the room it was given. Read
/// only; opt-in like the rest of the socket.
///
/// What is measured:
/// - `NSTextField`, `NSButton` (pop-ups included), `NSTextView`: the cell's or layout manager's own size for the text.
///   A label's frame needs `cellSize`, not `intrinsicContentSize`: the cell draws the text 2 points in from each side
///   (4 when centred), and on current macOS the intrinsic width leaves one of those sides out, so a frame of that width
///   cuts the last letter or, with a truncating line break, ends a text that would fit with an ellipsis.
/// - Text a view draws itself: `draw(_:)` runs once into a throwaway bitmap while `DrawnTextRecorder` notes each string.
/// - SwiftUI `Text`: not a view. Its accessibility node gives the string and the laid-out frame; the font is worked out
///   from the frame's height, because a Text's frame is exactly its lines (`SwiftUIText`). SwiftUI builds those nodes
///   only once an accessibility client has asked the app something, which the runner does first
///   (`NativeSystemInput.wakeAccessibilityTree`).
/// - Every text's rectangle against the ancestors that clip it: scrolling away along a scroll view's axis is not a
///   finding, being cut across the other axis is.
///
/// Native menus are measured by `menu(_:)`: AppKit sizes a menu to its widest row, so a row can only be cut by a custom
/// row view or a menu whose size disagrees.
@MainActor
enum TextLayoutAudit {
    static func run() -> TextLayoutReport {
        DrawnTextRecorder.install()
        var walk = Walk()
        for window in NSApp.windows where window.isVisible && !chromiumWindows.contains(NSStringFromClass(type(of: window))) { walk.visit(window) }
        return walk.report
    }

    /// The engine's own windows: their content is a page's, not ours.
    private static let chromiumWindows: Set<String> = ["NativeWidgetMacNSWindow", "CefNSWindow"]

    /// One open or built native menu, its submenus included.
    static func menu(_ menu: NSMenu) -> TextLayoutReport {
        var report = TextLayoutReport(windows: [])
        func visit(_ menu: NSMenu, path: String) {
            report.windows.append("menu \(path.isEmpty ? menu.title : path) \(Int(menu.size.width))x\(Int(menu.size.height))")
            menu.update()
            for item in menu.items where !item.isSeparatorItem && !item.isHidden {
                let text = item.attributedTitle ?? NSAttributedString(string: item.title, attributes: [.font: menu.font ?? NSFont.menuFont(ofSize: 0)])
                let needed = text.size()
                report.note(item.title, frame: CGRect(origin: .zero, size: menu.size), needed: needed)
                if needed.width > menu.size.width || item.view != nil {
                    report.findings.append(TextLayoutFinding(problem: .overflowsFrame, window: "menu", view: item.view.map { NSStringFromClass(type(of: $0)) } ?? "NSMenuItem",
                                                             text: item.title, frame: CGRect(origin: .zero, size: menu.size), needed: needed))
                }
                if let sub = item.submenu { visit(sub, path: path.isEmpty ? item.title : "\(path) › \(item.title)") }
            }
        }
        visit(menu, path: "")
        return report
    }

    nonisolated private static let slack = 0.5

    // MARK: The walk

    @MainActor struct Walk {
        var report = TextLayoutReport(windows: [])
        private var windowName = ""
        private var root: NSView = NSView()

        mutating func visit(_ window: NSWindow) {
            guard let top = window.contentView?.superview ?? window.contentView else { return }
            root = top
            let title = window.title.isEmpty ? "" : " \"\(window.title)\""
            windowName = "\(NSStringFromClass(type(of: window)))\(title)"
            report.windows.append("\(windowName) \(Int(window.frame.width))x\(Int(window.frame.height))")
            visit(top)
        }

        /// The tree in order, skipping what cannot show: a hidden view's subtree and the pages (Chromium's, not ours).
        /// A view at alpha 0 stays in: the row's and divider's hover controls wait that way and must fit when they appear.
        private mutating func visit(_ view: NSView) {
            guard !view.isHidden, !(view is PageSurfaceView) else { return }
            switch view {
            case let field as NSTextField: measure(field)
            case let button as NSButton: measure(button)
            case let text as NSTextView: measure(text)
            default: break
            }
            if DrawnTextRecorder.drawsItself(view) { measureDrawn(view) }
            if NSStringFromClass(type(of: view)).contains("NSHostingView") { measureHosted(view) }
            for subview in view.subviews { visit(subview) }
        }

        // MARK: AppKit controls

        private mutating func measure(_ field: NSTextField) {
            guard let cell = field.cell, field.bounds.width > 0, field.bounds.height > 0 else { return }
            let placeholder = field.stringValue.isEmpty
            let text = placeholder ? (field.placeholderString ?? field.placeholderAttributedString?.string ?? "") : field.stringValue
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let bounds = field.bounds
            let mode = cell.lineBreakMode
            let truncates = [.byTruncatingTail, .byTruncatingHead, .byTruncatingMiddle].contains(mode) || cell.truncatesLastVisibleLine
            let wraps = cell.wraps || mode == .byWordWrapping || mode == .byCharWrapping

            // `cellSize` measures the placeholder when the field is empty.
            if wraps {
                var needed = cell.cellSize(forBounds: CGRect(x: 0, y: 0, width: bounds.width, height: 100_000))
                if field.maximumNumberOfLines > 0, let font = field.font {
                    needed.height = min(needed.height, ceil(NSLayoutManager().defaultLineHeight(for: font)) * Double(field.maximumNumberOfLines))
                }
                report.note(text, frame: bounds, needed: needed)
                if needed.height > bounds.height + TextLayoutAudit.slack {
                    add(truncates ? .ellipsis : .wrapOverflow, field, text, needed: needed)
                }
                checkClip(field, text, rect: bounds, needed: needed)
                return
            }
            // An editable field scrolls its text sideways; only its placeholder has to fit.
            let scrolls = (field.isEditable || cell.isScrollable) && !placeholder
            let needed = cell.cellSize(forBounds: CGRect(x: 0, y: 0, width: 100_000, height: 100_000))
            report.note(text, frame: bounds, needed: needed)
            // Measured on rendered labels: a clipping label's ink is whole from its advance plus the leading inset (half
            // of the cell's padding: 2 points, 4 when centred), one that truncates turns to an ellipsis below the whole
            // cell width.
            let advance = placeholder ? (text as NSString).size(withAttributes: [.font: field.font ?? NSFont.systemFont(ofSize: 0)]).width : field.attributedStringValue.size().width
            let room = truncates ? needed.width : needed.width - (needed.width - advance) / 2
            if !scrolls, room > bounds.width + 0.25 {
                // A frame of the intrinsic width is a frame that forgot the cell's inset: an ellipsis there is a bug.
                let fitsWithoutInset = truncates && !placeholder && bounds.width >= advance - TextLayoutAudit.slack
                add(truncates && !fitsWithoutInset ? .ellipsis : .overflowsFrame, field, text, needed: needed)
            }
            // The line's height holds leading the glyphs do not reach; a frame is short when it cuts ascent or descent.
            if let font = field.font, font.ascender - font.descender > bounds.height + TextLayoutAudit.slack { add(.tooShort, field, text, needed: needed) }
            let width = min(needed.width, bounds.width)
            let x: Double = switch field.alignment {
            case .right: bounds.maxX - width
            case .center: bounds.midX - width / 2
            default: bounds.minX
            }
            checkClip(field, text, rect: CGRect(x: x, y: bounds.minY, width: width, height: bounds.height), needed: needed)
        }

        private mutating func measure(_ button: NSButton) {
            // A window's traffic lights (`_NSThemeWidget`) keep AppKit's unused "Button" title.
            guard button.bounds.width > 0, button.bounds.height > 0, let cell = button.cell, !NSStringFromClass(type(of: button)).hasPrefix("_") else { return }
            let popUp = button as? NSPopUpButton
            let text = popUp?.titleOfSelectedItem ?? button.title
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, button.imagePosition != .imageOnly else { return }
            let huge = CGRect(x: 0, y: 0, width: 100_000, height: 100_000)
            var needed = cell.cellSize(forBounds: cell.wraps ? CGRect(x: 0, y: 0, width: button.bounds.width, height: 100_000) : huge)
            var fits = needed.width <= button.bounds.width + TextLayoutAudit.slack
            if let popUp, let cell = popUp.cell as? NSPopUpButtonCell {
                // A pop-up's cell size is its widest item's; what shows is the selected one, from the title's start (after
                // its image) to the end of the cell's drawing area.
                let title = (text as NSString).size(withAttributes: [.font: popUp.font ?? NSFont.menuFont(ofSize: 0)]).width
                let available = cell.drawingRect(forBounds: popUp.bounds).maxX - cell.titleRect(forBounds: popUp.bounds).minX
                needed.width = popUp.bounds.width - available + title
                fits = title <= available + TextLayoutAudit.slack
            }
            report.note(text, frame: button.bounds, needed: needed)
            if cell.wraps {
                if needed.height > button.bounds.height + TextLayoutAudit.slack { add(.wrapOverflow, button, text, needed: needed) }
            } else if !fits {
                let truncates = [.byTruncatingTail, .byTruncatingHead, .byTruncatingMiddle].contains(cell.lineBreakMode)
                add(truncates ? .ellipsis : .overflowsFrame, button, text, needed: needed)
            }
            checkClip(button, text, rect: button.bounds, needed: needed)
        }

        private mutating func measure(_ view: NSTextView) {
            guard let manager = view.layoutManager, let container = view.textContainer, !view.string.isEmpty else { return }
            manager.ensureLayout(for: container)
            let used = manager.usedRect(for: container).insetBy(dx: -view.textContainerInset.width, dy: -view.textContainerInset.height)
            report.note(view.string, frame: view.bounds, needed: used.size)
            let scrolled = view.enclosingScrollView != nil
            if used.width > view.bounds.width + TextLayoutAudit.slack || (!scrolled && used.height > view.bounds.height + TextLayoutAudit.slack) {
                add(.wrapOverflow, view, view.string, needed: used.size)
            }
        }

        // MARK: Drawn text

        private mutating func measureDrawn(_ view: NSView) {
            for drawn in DrawnTextRecorder.texts(of: view) {
                let text = drawn.string
                let inner = drawn.clip.intersection(view.bounds).insetBy(dx: -TextLayoutAudit.slack, dy: -TextLayoutAudit.slack)
                report.note(text, frame: drawn.box ?? drawn.ink, needed: drawn.needed)
                if let box = drawn.box {
                    if drawn.needed.height > box.height + TextLayoutAudit.slack || drawn.needed.width > box.width + TextLayoutAudit.slack {
                        add(drawn.truncates ? .ellipsis : .wrapOverflow, view, text, needed: drawn.needed, rect: box)
                    }
                    let shown = drawn.truncates ? box : CGRect(origin: box.origin, size: CGSize(width: min(box.width, drawn.needed.width), height: min(box.height, drawn.needed.height)))
                    if !inner.contains(shown) { add(.drawnOutsideView, view, text, needed: drawn.needed, rect: shown) }
                    checkClip(view, text, rect: shown, needed: drawn.needed)
                } else {
                    // Without a box the glyphs themselves say what is cut: a line's box may overhang a tight view.
                    if !inner.contains(drawn.ink) { add(.drawnOutsideView, view, text, needed: drawn.needed, rect: drawn.ink) }
                    checkClip(view, text, rect: drawn.ink, needed: drawn.needed)
                }
            }
        }

        // MARK: SwiftUI

        private mutating func measureHosted(_ host: NSView) {
            guard let window = host.window else { return }
            var seen = Set<ObjectIdentifier>()
            var nodes: [(text: String, frame: CGRect)] = []
            // SwiftUI's `AccessibilityNode` answers these selectors without declaring NSAccessibilityProtocol.
            func collect(_ element: Any, depth: Int) {
                let node = element as AnyObject
                guard depth < 60, seen.insert(ObjectIdentifier(node)).inserted else { return }
                // AppKit controls in a SwiftUI region have their own rules; a nested host is visited as a view.
                if let view = node as? NSView, view !== host, view is NSControl || NSStringFromClass(type(of: view)).contains("NSHostingView") { return }
                let role = node.accessibilityRole?()
                let children = node.accessibilityChildren?() ?? []
                // Not buttons: an icon button's label is for accessibility, and the panes' text buttons are AppKit's.
                if role == .staticText {
                    let text = accessibilityValue(of: node) ?? node.accessibilityLabel?() ?? node.accessibilityTitle?() ?? ""
                    let frame = node.accessibilityFrame?() ?? .zero
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, frame.width > 0, frame.height > 0 {
                        nodes.append((text, window.convertFromScreen(frame)))
                    }
                }
                for child in children { collect(child, depth: depth + 1) }
            }
            collect(host, depth: 0)
            for node in nodes {
                let rect = root.convert(node.frame, from: nil)
                let needed = SwiftUIText.needed(for: node.text, frame: node.frame.size)
                report.note(node.text, frame: node.frame, needed: needed)
                if needed.width > node.frame.width + 1 || needed.height > node.frame.height + 1 {
                    report.truncated.append(finding(.ellipsis, describe(host) + " SwiftUI", node.text, rect, needed))
                }
                checkClip(host, node.text, rect: host.convert(node.frame, from: nil), needed: needed, includingSelf: true)
            }
        }

        /// `accessibilityValue` is `Any?` and overloaded, so dynamic lookup cannot name it.
        private func accessibilityValue(of node: AnyObject) -> String? {
            (node as? NSObject)?.value(forKey: "accessibilityValue") as? String
        }

        // MARK: Clipping ancestors

        /// `rect` in `view`'s coordinates: reports the first ancestor (and the window) that cuts it.
        private mutating func checkClip(_ view: NSView, _ text: String, rect: CGRect, needed: CGSize, includingSelf: Bool = false) {
            guard rect.width > 0, rect.height > 0 else { return }
            var inRoot = view.convert(rect, to: root)
            var ancestor: NSView? = includingSelf ? view : view.superview
            while let current = ancestor {
                defer { ancestor = current.superview }
                let isClip = current is NSClipView
                guard isClip || current === root || current.clipsToBounds || current.layer?.masksToBounds == true else { continue }
                let box = current.convert(current.bounds, to: root)
                // Wholly outside: scrolled away or a page of a sliding container, not a cut text.
                if !box.intersects(inRoot) { return }
                var horizontal = true, vertical = true
                if let clip = current as? NSClipView {
                    vertical = false
                    if clip.enclosingScrollView?.hasHorizontalScroller == true { horizontal = false }
                    // What scrolled out along that axis is not cut: the ancestors further out judge what is left.
                    if !vertical { inRoot = CGRect(x: inRoot.minX, y: max(inRoot.minY, box.minY), width: inRoot.width, height: min(inRoot.maxY, box.maxY) - max(inRoot.minY, box.minY)) }
                    if !horizontal { inRoot = CGRect(x: max(inRoot.minX, box.minX), y: inRoot.minY, width: min(inRoot.maxX, box.maxX) - max(inRoot.minX, box.minX), height: inRoot.height) }
                }
                let cutX = horizontal && (inRoot.minX < box.minX - TextLayoutAudit.slack || inRoot.maxX > box.maxX + TextLayoutAudit.slack)
                let cutY = vertical && (inRoot.minY < box.minY - TextLayoutAudit.slack || inRoot.maxY > box.maxY + TextLayoutAudit.slack)
                if cutX || cutY {
                    var entry = finding(.clippedByAncestor, describe(view), text, inRoot, needed)
                    entry.clipper = "\(describe(current)) \(Self.sizeText(box.size))"
                    report.findings.append(entry)
                    return
                }
            }
        }

        // MARK: Findings

        private mutating func add(_ problem: TextLayoutFinding.Problem, _ view: NSView, _ text: String, needed: CGSize, rect: CGRect? = nil) {
            let entry = finding(problem, describe(view), text, view.convert(rect ?? view.bounds, to: root), needed)
            if problem == .ellipsis { report.truncated.append(entry) } else { report.findings.append(entry) }
        }

        private func finding(_ problem: TextLayoutFinding.Problem, _ view: String, _ text: String, _ frame: CGRect, _ needed: CGSize) -> TextLayoutFinding {
            TextLayoutFinding(problem: problem, window: windowName, view: view, text: String(text.prefix(120)), frame: frame, needed: needed)
        }

        /// "NSTextField < ClearButton < today-clear": the class, its parent's class and the nearest identifier.
        private func describe(_ view: NSView) -> String {
            var parts = [Self.name(of: view)]
            if let parent = view.superview { parts.append(Self.name(of: parent)) }
            var current: NSView? = view
            while let v = current {
                let id = v.accessibilityIdentifier()
                if !id.isEmpty { parts.append(id); break }
                current = v.superview
            }
            return parts.joined(separator: " < ")
        }

        private static func name(of view: NSView) -> String {
            let full = NSStringFromClass(type(of: view))
            return full.components(separatedBy: ".").last ?? full
        }

        private static func sizeText(_ size: CGSize) -> String { "\(size.width)x\(size.height)" }
    }
}

// MARK: - SwiftUI Text

/// What a SwiftUI `Text` needs, from its string and frame alone. A Text's frame is its own lines, so the frame's height
/// says which system font sizes it can be set in; the text fits when it fits at one of them. Regular weight is the
/// narrowest of what the panes use, so a bold label cannot be called short by accident.
@MainActor enum SwiftUIText {
    /// Down to the Max pane's miniature pictures, whose Text is scaled and whose frame says so.
    private static let sizes: [Double] = [3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 20, 22, 24, 26, 28, 30, 34]

    static func needed(for text: String, frame: CGSize) -> CGSize {
        func natural(_ size: Double) -> CGSize {
            (text as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: size)])
        }
        func wrapped(_ size: Double, width: Double) -> CGSize {
            (text as NSString).boundingRect(with: CGSize(width: width, height: 100_000), options: [.usesLineFragmentOrigin],
                                            attributes: [.font: NSFont.systemFont(ofSize: size)]).size
        }
        var smallest: CGSize?
        for size in sizes {
            let line = ceil(NSLayoutManager().defaultLineHeight(for: .systemFont(ofSize: size)))
            let lines = (frame.height / line).rounded()
            guard lines >= 1, abs(lines * line - frame.height) <= lines * 2 else { continue }
            let needed = lines == 1 ? natural(size) : wrapped(size, width: frame.width)
            if needed.width <= frame.width + 1, needed.height <= frame.height + 1 { return needed }
            if smallest == nil { smallest = needed }
        }
        return smallest ?? natural(sizes[0])
    }
}

// MARK: - Text a view draws itself

/// Notes each `NSString` and `NSAttributedString` drawing call while one view's `draw(_:)` runs into a bitmap. The
/// methods are exchanged on the first `textLayout` request and record nothing outside it, so a browser without the
/// control socket never has them exchanged.
enum DrawnTextRecorder {
    struct Drawn {
        var string: String
        /// Where the glyphs of `draw(at:)` land, in the view's coordinates.
        var ink: CGRect
        /// The box of `draw(in:)` and `draw(with:)`, in the view's coordinates; nil for `draw(at:)`.
        var box: CGRect?
        var needed: CGSize
        var truncates: Bool
        var clip: CGRect
    }

    nonisolated(unsafe) private static var log: [Drawn]?
    nonisolated(unsafe) private static var base: CGAffineTransform = .identity
    nonisolated(unsafe) private static var depth = 0
    nonisolated(unsafe) private static var installed = false

    static func install() {
        guard !installed else { return }
        installed = true
        let pairs: [(AnyClass, Selector, Selector)] = [
            (NSAttributedString.self, NSSelectorFromString("drawAtPoint:"), #selector(NSAttributedString.brkAudit_draw(at:))),
            (NSAttributedString.self, NSSelectorFromString("drawInRect:"), #selector(NSAttributedString.brkAudit_draw(in:))),
            (NSAttributedString.self, NSSelectorFromString("drawWithRect:options:context:"), #selector(NSAttributedString.brkAudit_draw(with:options:context:))),
            (NSString.self, NSSelectorFromString("drawAtPoint:withAttributes:"), #selector(NSString.brkAudit_draw(at:withAttributes:))),
            (NSString.self, NSSelectorFromString("drawInRect:withAttributes:"), #selector(NSString.brkAudit_draw(in:withAttributes:))),
            (NSString.self, NSSelectorFromString("drawWithRect:options:attributes:context:"), #selector(NSString.brkAudit_draw(with:options:attributes:context:))),
        ]
        for (cls, original, swapped) in pairs {
            guard let a = class_getInstanceMethod(cls, original), let b = class_getInstanceMethod(cls, swapped) else { continue }
            method_exchangeImplementations(a, b)
        }
    }

    /// A class of this app overriding `draw(_:)`. AppKit's own controls are measured through their cells.
    @MainActor static func drawsItself(_ view: NSView) -> Bool {
        guard !(view is NSTextView), let image = class_getImageName(type(of: view)).map({ String(cString: $0) }),
              !image.hasPrefix("/System/"), !image.hasPrefix("/usr/lib/") else { return false }
        return class_getMethodImplementation(type(of: view), #selector(NSView.draw(_:))) != class_getMethodImplementation(NSView.self, #selector(NSView.draw(_:)))
    }

    @MainActor static func texts(of view: NSView) -> [Drawn] {
        let size = view.bounds.size
        guard size.width > 0, size.height > 0, size.width < 10_000, size.height < 10_000,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int(ceil(size.width)), height: Int(ceil(size.height)), bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return [] }
        if view.isFlipped {
            context.translateBy(x: 0, y: size.height)
            context.scaleBy(x: 1, y: -1)
        }
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: view.isFlipped)
        base = context.ctm
        log = []
        depth = 0
        defer { log = nil }
        view.effectiveAppearance.performAsCurrentDrawingAppearance { view.draw(view.bounds) }
        return log ?? []
    }

    fileprivate static func enter(_ text: NSAttributedString, origin: CGPoint?, box: CGRect?, options: NSString.DrawingOptions) -> Bool {
        depth += 1
        guard depth == 1, log != nil, let context = NSGraphicsContext.current?.cgContext else { return log != nil }
        let toView = context.ctm.concatenating(base.inverted())
        let natural = text.size()
        let paragraph = text.length > 0 ? text.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle : nil
        let modes: [NSLineBreakMode] = [.byTruncatingTail, .byTruncatingHead, .byTruncatingMiddle]
        var truncates = options.contains(.truncatesLastVisibleLine) || modes.contains(paragraph?.lineBreakMode ?? .byWordWrapping)
        var needed = natural
        if let box, options.contains(.usesLineFragmentOrigin) {
            needed = text.boundingRect(with: CGSize(width: box.width, height: 100_000), options: [.usesLineFragmentOrigin]).size
        } else if box == nil {
            truncates = false
        }
        var ink = CGRect.zero
        if let origin {
            let line = CTLineCreateWithAttributedString(text)
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            _ = CTLineGetTypographicBounds(line, &ascent, &descent, &leading)
            let glyphs = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            let flipped = NSGraphicsContext.current?.isFlipped ?? false
            ink = CGRect(x: origin.x + glyphs.minX, y: flipped ? origin.y + ascent - glyphs.maxY : origin.y + descent + glyphs.minY,
                         width: glyphs.width, height: glyphs.height).applying(toView)
        }
        log?.append(Drawn(string: text.string, ink: ink, box: box?.applying(toView), needed: needed,
                          truncates: truncates, clip: context.boundingBoxOfClipPath.applying(toView)))
        return true
    }

    fileprivate static func leave() { depth -= 1 }
}

extension NSAttributedString {
    @objc fileprivate func brkAudit_draw(at point: NSPoint) {
        _ = DrawnTextRecorder.enter(self, origin: point, box: nil, options: [])
        defer { DrawnTextRecorder.leave() }
        brkAudit_draw(at: point)
    }

    @objc fileprivate func brkAudit_draw(in rect: NSRect) {
        _ = DrawnTextRecorder.enter(self, origin: nil, box: rect, options: [.usesLineFragmentOrigin])
        defer { DrawnTextRecorder.leave() }
        brkAudit_draw(in: rect)
    }

    @objc fileprivate func brkAudit_draw(with rect: NSRect, options: NSString.DrawingOptions, context: NSStringDrawingContext?) {
        _ = DrawnTextRecorder.enter(self, origin: nil, box: rect, options: options)
        defer { DrawnTextRecorder.leave() }
        brkAudit_draw(with: rect, options: options, context: context)
    }
}

extension NSString {
    @objc fileprivate func brkAudit_draw(at point: NSPoint, withAttributes attributes: [NSAttributedString.Key: Any]?) {
        _ = DrawnTextRecorder.enter(NSAttributedString(string: self as String, attributes: attributes), origin: point, box: nil, options: [])
        defer { DrawnTextRecorder.leave() }
        brkAudit_draw(at: point, withAttributes: attributes)
    }

    @objc fileprivate func brkAudit_draw(in rect: NSRect, withAttributes attributes: [NSAttributedString.Key: Any]?) {
        _ = DrawnTextRecorder.enter(NSAttributedString(string: self as String, attributes: attributes), origin: nil, box: rect, options: [.usesLineFragmentOrigin])
        defer { DrawnTextRecorder.leave() }
        brkAudit_draw(in: rect, withAttributes: attributes)
    }

    @objc fileprivate func brkAudit_draw(with rect: NSRect, options: NSString.DrawingOptions, attributes: [NSAttributedString.Key: Any]?, context: NSStringDrawingContext?) {
        _ = DrawnTextRecorder.enter(NSAttributedString(string: self as String, attributes: attributes), origin: nil, box: rect, options: options)
        defer { DrawnTextRecorder.leave() }
        brkAudit_draw(with: rect, options: options, attributes: attributes, context: context)
    }
}
