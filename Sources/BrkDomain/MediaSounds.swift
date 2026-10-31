import Foundation

/// Brk's original UI cues; these names are also the bundled asset names.
public enum MediaSoundEvent: String, Hashable, Sendable, Codable, CaseIterable {
    case captureCompleted, downloadCompleted, tabsArchived
}

extension Work {
    mutating func playSound(_ event: MediaSoundEvent) {
        if state.doc.settings.advanced.soundEffects { effects.append(.sound(event)) }
    }
}
