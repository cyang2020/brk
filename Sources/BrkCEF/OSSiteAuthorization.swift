import AVFoundation
import BrkBase
import CoreLocation
import Foundation
import UserNotifications

/// OS authorization is a prerequisite, including for remembered site grants.
/// Tests only read real status; they never request or reset host authorization.
@MainActor
final class OSSiteAuthorization: NSObject, @preconcurrency CLLocationManagerDelegate {
    static let shared = OSSiteAuthorization()
    private let location = CLLocationManager()
    private var locationWaiters: [CheckedContinuation<Bool, Never>] = []
    override init() { super.init(); location.delegate = self }

    func readback() async -> [SiteCapability: String] {
        func device(_ type: AVMediaType) -> String {
            switch AVCaptureDevice.authorizationStatus(for: type) {
            case .authorized: "authorized"
            case .denied: "denied"
            case .restricted: "restricted"
            case .notDetermined: "not determined"
            @unknown default: "unknown"
            }
        }
        let locationState: String
        switch location.authorizationStatus {
        case .authorizedAlways: locationState = "authorized"
        case .denied: locationState = "denied"
        case .restricted: locationState = "restricted"
        case .notDetermined: locationState = "not determined"
        @unknown default: locationState = "unknown"
        }
        let notificationState: String
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional: notificationState = "authorized"
        case .denied: notificationState = "denied"
        case .notDetermined: notificationState = "not determined"
        @unknown default: notificationState = "unknown"
        }
        return [.camera: device(.video), .microphone: device(.audio), .location: locationState, .notifications: notificationState]
    }

    func grants(_ capabilities: Set<SiteCapability>, isCurrent: () -> Bool) async -> Bool {
        for capability in capabilities.sorted(by: { $0.rawValue < $1.rawValue }) {
            guard isCurrent() else { return false }
            switch capability {
            case .camera, .microphone:
                let type: AVMediaType = capability == .camera ? .video : .audio
                let status = AVCaptureDevice.authorizationStatus(for: type)
                if status == .notDetermined {
                    guard await AVCaptureDevice.requestAccess(for: type) else { return false }
                } else if status != .authorized { return false }
            case .location:
                guard CLLocationManager.locationServicesEnabled() else { return false }
                if location.authorizationStatus == .notDetermined {
                    let allowed = await withCheckedContinuation { continuation in
                        locationWaiters.append(continuation)
                        if locationWaiters.count == 1 { location.requestWhenInUseAuthorization() }
                    }
                    guard allowed else { return false }
                } else if !locationGranted { return false }
            case .notifications:
                let center = UNUserNotificationCenter.current()
                let status = await center.notificationSettings().authorizationStatus
                guard isCurrent() else { return false }
                if status == .notDetermined {
                    guard (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true else { return false }
                } else if status != .authorized && status != .provisional { return false }
            case .desktopCapture, .other: return false
            }
        }
        return isCurrent()
    }
    private var locationGranted: Bool {
        location.authorizationStatus == .authorizedAlways
    }
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard manager.authorizationStatus != .notDetermined else { return }
        let waiters = locationWaiters; locationWaiters.removeAll()
        for waiter in waiters { waiter.resume(returning: locationGranted) }
    }
}
