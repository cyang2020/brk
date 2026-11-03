import Foundation

/// Chromium's page zoom presets, expressed as percentages. Arbitrary origin zoom values step to the next preset.
public enum BrowserZoom {
    public static let percentages: [Int] = [25, 33, 50, 67, 75, 80, 90, 100, 110, 125, 150, 175, 200, 250, 300, 400, 500]
    private static let factors: [Double] = [0.25, 1.0 / 3, 0.5, 2.0 / 3, 0.75, 0.8, 0.9, 1, 1.1, 1.25, 1.5, 1.75, 2, 2.5, 3, 4, 5]

    public static func percentage(level: Double) -> Int {
        guard level.isFinite else { return 100 }
        return Int((pow(1.2, min(10, max(-10, level))) * 100).rounded())
    }

    public static func level(for percentage: Int) -> Double { log(Double(percentage) / 100) / log(1.2) }

    public static func next(_ step: ZoomStep, level current: Double) -> Double {
        let factor = current.isFinite ? pow(1.2, min(20, max(-20, current))) : 1
        let target: Double
        switch step {
        case .reset: target = 100
        case .zoomIn: target = 100 * (factors.first { $0 > factor + 1e-8 } ?? factors.last!)
        case .zoomOut: target = 100 * (factors.last { $0 < factor - 1e-8 } ?? factors.first!)
        }
        return log(target / 100) / log(1.2)
    }
}

public enum DeveloperOperation: String, Hashable, Sendable, Codable {
    case source, inspect, console, network
}

/// Bounded opt-in native verification receipts. Only shortcut chords are recorded, never typed text.
public struct PageKeyReceipt: Hashable, Sendable, Codable {
    public let stage: String
    public let chord: String?
    public let press: UInt64?
    public let handled: Bool
    public let shortcut: Bool?
    public let chromeCommand: Int?
    /// The table action the app dispatched for this delivery (`KeyHandling.action`).
    public let action: String?
    /// The press was a key auto-repeat.
    public let isRepeat: Bool?
    public init(stage: String, chord: String? = nil, press: UInt64? = nil, handled: Bool, shortcut: Bool? = nil, chromeCommand: Int? = nil,
                action: String? = nil, isRepeat: Bool? = nil) {
        self.stage = stage; self.chord = chord; self.press = press; self.handled = handled
        self.shortcut = shortcut; self.chromeCommand = chromeCommand; self.action = action; self.isRepeat = isRepeat
    }
}

extension DocumentAvailability {
    public var token: DocumentToken? {
        switch self {
        case .loading(let token), .ready(let token): token
        case .unavailable: nil
        }
    }
}
