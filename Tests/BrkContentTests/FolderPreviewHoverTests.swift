import AppKit
@testable import BrkSidebar
import BrkUIKit
import XCTest

/// The pointer moving onto a row of a folder's hover card highlights that row. Build 24 quit instead: the row's
/// redraw asked for the highlight, and setting the highlight redrew the row, until the stack ran out.
/// The card's text reads on its surface in both appearances (user report 2026-11-12: in the dark appearance the
/// Gmail Favorite's card was #212222 with black text and looked covered by the page).
@MainActor
final class FolderPreviewHoverTests: XCTestCase {
    private func card() -> (FolderPreviewView, [PreviewRowView]) {
        let entries = ["a", "b", "c"].map {
            PreviewEntry(key: $0, title: $0, icon: .none, caption: nil, searchText: $0, open: [])
        }
        let card = FolderPreviewView(search: "Search folder…", entries: entries)
        return (card, card.subviews.compactMap { $0 as? PreviewRowView })
    }

    private func lit(_ rows: [PreviewRowView]) -> [Int] { rows.indices.filter { rows[$0].highlighted } }

    func testHoveringARowHighlightsOnlyThatRow() {
        let (_, rows) = card()
        XCTAssertEqual(lit(rows), [0])
        rows[1].setHovered(true)
        XCTAssertEqual(lit(rows), [1])
        rows[1].setHovered(false)
        rows[2].setHovered(true)
        XCTAssertEqual(lit(rows), [2])
    }

    func testArrowKeysMoveTheHighlightOffTheHoveredRow() {
        let (card, rows) = card()
        rows[1].setHovered(true)
        _ = card.control(NSTextField(), textView: NSTextView(), doCommandBy: #selector(NSResponder.moveDown(_:)))
        XCTAssertEqual(lit(rows), [2])
        _ = card.control(NSTextField(), textView: NSTextView(), doCommandBy: #selector(NSResponder.moveUp(_:)))
        _ = card.control(NSTextField(), textView: NSTextView(), doCommandBy: #selector(NSResponder.moveUp(_:)))
        XCTAssertEqual(lit(rows), [0])
    }

    func testCardTextReadsOnItsSurfaceInBothAppearances() throws {
        let entries = ["Inbox (8,965)", "Reminder"].map {
            PreviewEntry(key: $0, title: $0, icon: .none, caption: "10 hours ago", searchText: $0, open: [])
        }
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 600, height: 500), styleMask: [.borderless], backing: .buffered, defer: true)
            window.appearance = NSAppearance(named: name)
            let root = NSView(frame: window.contentLayoutRect)
            window.contentView = root
            for card in [FolderPreviewView(header: "Recent Emails · 34 unread", entries: entries, empty: ""),
                         FolderPreviewView(header: "Upcoming", entries: [], empty: "No meetings in the next 24 hours"),
                         FolderPreviewView(search: "Search folder…", entries: entries)] {
                card.frame = CGRect(origin: .zero, size: card.fittingSize)
                XCTAssertTrue(PopupLayer.present(card, over: root))
                let surface = try XCTUnwrap(card.layer?.backgroundColor.flatMap { NSColor(cgColor: $0) })
                XCTAssertEqual(surface, name == .darkAqua ? PreviewColors.dark : PreviewColors.light, "the card did not take the window's appearance")
                var labels: [NSTextField] = []
                func walk(_ view: NSView) {
                    if let field = view as? NSTextField, !field.isHidden, !field.stringValue.isEmpty, field.isEditable == false { labels.append(field) }
                    view.subviews.forEach(walk)
                }
                walk(card)
                XCTAssertFalse(labels.isEmpty)
                for label in labels {
                    let ratio = Self.contrast(label.textColor ?? .labelColor, on: surface, in: card.effectiveAppearance)
                    XCTAssertGreaterThan(ratio, 3, "\(name.rawValue): \"\(label.stringValue)\" reads at \(ratio):1 on the card")
                }
                card.removeFromSuperview()
            }
        }
    }

    /// WCAG contrast of `ink` laid over the opaque `surface`.
    private static func contrast(_ ink: NSColor, on surface: NSColor, in appearance: NSAppearance) -> Double {
        var result = 0.0
        appearance.performAsCurrentDrawingAppearance {
            guard let i = ink.usingColorSpace(.sRGB), let s = surface.usingColorSpace(.sRGB) else { return }
            func channel(_ c: CGFloat, _ under: CGFloat) -> Double {
                let v = Double(c * i.alphaComponent + under * (1 - i.alphaComponent))
                return v <= 0.03928 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            func luminance(_ r: Double, _ g: Double, _ b: Double) -> Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }
            let top = luminance(channel(i.redComponent, s.redComponent), channel(i.greenComponent, s.greenComponent), channel(i.blueComponent, s.blueComponent))
            let under = luminance(channel(s.redComponent, s.redComponent), channel(s.greenComponent, s.greenComponent), channel(s.blueComponent, s.blueComponent))
            result = (max(top, under) + 0.05) / (min(top, under) + 0.05)
        }
        return result
    }
}
