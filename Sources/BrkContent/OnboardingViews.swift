import AppKit
import BrkOverlays
import BrkUIKit

/// The onboarding window's content for BrkApp, which hosts that window itself but may not import BrkOverlays
/// (the same arrangement as `EaselExport`).
public enum OnboardingViews {
    @MainActor
    public static func make(dispatch: @escaping @MainActor (OnboardingAction) -> Void, appIcon: NSImage?) -> any OnboardingSurface {
        OnboardingHostView(dispatch: dispatch, appIcon: appIcon)
    }
}
