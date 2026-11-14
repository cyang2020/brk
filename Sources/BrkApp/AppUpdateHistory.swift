import AppKit
import BrkBase
import BrkDomain

@MainActor
final class AppUpdateHistory {
    private let url: URL
    private var receipt: UpdateReceipt?

    init(url: URL) {
        self.url = url
        receipt = (try? Data(contentsOf: url)).flatMap(UpdateReceipt.decode)
    }

    func summary(for installed: UpdateRelease?, previouslyLaunched: Bool = false) -> UpdateRelease? {
        guard let installed else { return nil }
        if let previous = receipt {
            if installed.build != previous.lastRunBuild {
                receipt = UpdateReceipt(lastRunBuild: installed.build,
                                  summaryBuild: installed.build > previous.lastRunBuild ? installed.build : nil)
                save()
            }
        } else {
            // Sparkle versions predating this receipt already recorded their first launch.
            receipt = UpdateReceipt(lastRunBuild: installed.build, summaryBuild: previouslyLaunched ? installed.build : nil)
            save()
        }
        return receipt?.summaryBuild == installed.build ? installed : nil
    }

    func dismiss(_ release: UpdateRelease) {
        guard receipt?.summaryBuild == release.build else { return }
        receipt?.summaryBuild = nil
        save()
    }

    private func save() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try receipt?.encoded().write(to: url, options: .atomic)
        } catch {
            NSLog("Could not save update summary acknowledgement: %@", error.localizedDescription)
        }
    }
}

@MainActor
final class UpdateScreenState: NSObject {
    enum Reason: Hashable { case locked, screensaver, sleeping }
    private var reasons: Set<Reason> = []
    private var observing = false
    var changed: (() -> Void)?
    var isAway: Bool { !reasons.isEmpty }

    func set(_ reason: Reason, active: Bool) {
        if active { reasons.insert(reason) } else { reasons.remove(reason) }
        changed?()
    }

    func start() {
        guard !observing else { return }
        observing = true
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(self, selector: #selector(sleep), name: NSWorkspace.screensDidSleepNotification, object: nil)
        workspace.addObserver(self, selector: #selector(wake), name: NSWorkspace.screensDidWakeNotification, object: nil)
        let distributed = DistributedNotificationCenter.default()
        for (name, selector) in [
            ("com.apple.screenIsLocked", #selector(lock)),
            ("com.apple.screenIsUnlocked", #selector(unlock)),
            ("com.apple.screensaver.didstart", #selector(startScreensaver)),
            ("com.apple.screensaver.didstop", #selector(stopScreensaver)),
        ] {
            distributed.addObserver(self, selector: selector, name: Notification.Name(name), object: nil,
                                    suspensionBehavior: .deliverImmediately)
        }
    }

    @objc private func sleep(_ notification: Notification) { set(.sleeping, active: true) }
    @objc private func wake(_ notification: Notification) { set(.sleeping, active: false) }
    @objc private func lock(_ notification: Notification) { set(.locked, active: true) }
    @objc private func unlock(_ notification: Notification) { set(.locked, active: false) }
    @objc private func startScreensaver(_ notification: Notification) { set(.screensaver, active: true) }
    @objc private func stopScreensaver(_ notification: Notification) { set(.screensaver, active: false) }
}
