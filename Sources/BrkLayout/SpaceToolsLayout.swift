import BrkBase
import CoreGraphics

public enum AddressToolbarLayout {
    public static var height: Double { Metrics.spaceTools.toolbarHeight.value }
    public static func address(in rect: CGRect) -> CGRect {
        CGRect(x: rect.minX + Metrics.spaceTools.toolbarAddressLeading.value, y: rect.minY + 4, width: max(0, rect.width - 148), height: 32)
    }
    public static func button(_ index: Int, in rect: CGRect) -> CGRect {
        CGRect(x: rect.minX + Double(index) * 34, y: rect.minY + 4, width: 32, height: 32)
    }
}

public struct SpaceManagerFrames {
    public let title: CGRect, create: CGRect, search: CGRect, feedback: CGRect, scroll: CGRect
    public let gridSize: CGSize
    public let cards: [CGRect]
}
public enum SpaceManagerLayout {
    public static func compute(in rect: CGRect, count: Int) -> SpaceManagerFrames {
        let m = Metrics.spaceTools, pad = m.managerPadding.value, gap = m.managerGap.value
        let width = max(0, rect.width - pad * 2)
        let columns = max(1, Int((width + gap) / (m.managerCardMinWidth.value + gap)))
        let cardWidth = max(0, (width - Double(columns - 1) * gap) / Double(columns))
        let cards = (0..<count).map { i in
            CGRect(x: Double(i % columns) * (cardWidth + gap), y: Double(i / columns) * (m.managerCardHeight.value + gap), width: cardWidth, height: m.managerCardHeight.value)
        }
        let scroll = CGRect(x: pad, y: pad + 134, width: width, height: max(0, rect.height - pad * 2 - 134))
        return SpaceManagerFrames(title: CGRect(x: pad, y: pad, width: max(0, width - 130), height: 36),
                                  create: CGRect(x: rect.maxX - pad - 125, y: pad, width: 125, height: 32),
                                  search: CGRect(x: pad, y: pad + 48, width: width, height: 30),
                                  feedback: CGRect(x: pad, y: pad + 86, width: width, height: 40), scroll: scroll,
                                  gridSize: CGSize(width: width, height: max(scroll.height, cards.last?.maxY ?? 0)), cards: cards)
    }
    public static func cardControls(in rect: CGRect) -> [CGRect] {
        let pad = Metrics.spaceTools.managerGap.value, width = max(0, rect.width - pad * 2)
        return [CGRect(x: pad, y: pad, width: width, height: 34), CGRect(x: pad, y: 52, width: width, height: 20),
                CGRect(x: pad, y: 82, width: max(0, width - 90), height: 28),
                CGRect(x: rect.maxX - pad - 76, y: 82, width: 34, height: 28),
                CGRect(x: rect.maxX - pad - 36, y: 82, width: 34, height: 28),
                CGRect(x: pad, y: 124, width: width, height: 28), CGRect(x: pad, y: 166, width: width, height: 28)]
    }
}
