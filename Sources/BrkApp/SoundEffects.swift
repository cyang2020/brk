import AppKit
import BrkDomain

@MainActor
final class SoundEffects {
    struct Submission: Codable {
        let event: MediaSoundEvent
        let accepted: Bool
    }
    private var sounds: [MediaSoundEvent: NSSound] = [:]
    private(set) var submissions: [Submission] = []
    private var enabled = true

    init(directory: URL? = Bundle.main.resourceURL?.appendingPathComponent("BrkSounds")) {
        guard let directory else { return }
        for event in MediaSoundEvent.allCases {
            if let sound = NSSound(contentsOf: directory.appendingPathComponent(event.rawValue + ".wav"), byReference: false) {
                sound.volume = 0.28
                sounds[event] = sound
            }
        }
    }

    func setEnabled(_ value: Bool) {
        enabled = value
        if !value { for sound in sounds.values { sound.stop() } }
    }

    func play(_ event: MediaSoundEvent) {
        guard enabled else { return }
        let sound = sounds[event]
        sound?.stop()
        let accepted = sound?.play() ?? false
        submissions.append(Submission(event: event, accepted: accepted))
        if submissions.count > 32 { submissions.removeFirst(submissions.count - 32) }
    }
}
