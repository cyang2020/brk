import BrkBase
import BrkDomain
import SwiftUI

/// Sun rays turn one eighth of a circle; the moon's two stars and automatic mode's three stars pulse in sequence.
/// Timing is from Arc's sun/moon/automatic animations at 60 fps; the symbols are drawn with SF Symbols.
struct ThemeAppearanceIcon: View {
    let choice: AppearanceChoice
    let selected: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var replay = 0

    private struct Pose {
        var turn = 0.0
        var first = 1.0
        var second = 1.0
        var third = 1.0
    }

    var body: some View {
        KeyframeAnimator(initialValue: Pose(), trigger: replay) { pose in
            picture(pose).frame(width: 15, height: 15)
        } keyframes: { _ in
            KeyframeTrack(\.turn) {
                MoveKeyframe(0)
                LinearKeyframe(choice == .light ? 45 : 0, duration: 59 / 60)
            }
            KeyframeTrack(\.first) {
                CubicKeyframe(choice == .dark ? 0.3 : 0.604, duration: 27 / 60)
                CubicKeyframe(1.059, duration: 23 / 60)
                CubicKeyframe(1, duration: 18 / 60)
            }
            KeyframeTrack(\.second) {
                LinearKeyframe(1, duration: (choice == .dark ? 14.0 : 10.0) / 60)
                CubicKeyframe(choice == .dark ? 0.3 : 0.429, duration: 27 / 60)
                CubicKeyframe(1.059, duration: 23 / 60)
                CubicKeyframe(1, duration: 18 / 60)
            }
            KeyframeTrack(\.third) {
                LinearKeyframe(1, duration: 22 / 60)
                CubicKeyframe(0.429, duration: 27 / 60)
                CubicKeyframe(1.048, duration: 23 / 60)
                CubicKeyframe(1, duration: 18 / 60)
            }
        }
        .onHover { if $0 && !reduceMotion { replay += 1 } }
        .onChange(of: selected) { _, on in if on && !reduceMotion { replay += 1 } }
        .accessibilityHidden(true)
    }

    @ViewBuilder private func picture(_ pose: Pose) -> some View {
        if choice == .light {
            Image(systemName: "sun.max.fill").rotationEffect(.degrees(pose.turn))
        } else {
            ZStack {
                if choice == .dark {
                    Image(systemName: "moon.fill").font(.system(size: 12, weight: .semibold)).offset(x: -1.5, y: 2)
                    star(size: 5, scale: pose.first).offset(x: 5, y: -2)
                    star(size: 3, scale: pose.second).offset(x: 2, y: -6)
                } else {
                    star(size: 11, scale: pose.first).offset(x: 2, y: 1)
                    star(size: 6, scale: pose.second).offset(x: -4, y: -5)
                    star(size: 5, scale: pose.third).offset(x: -5, y: 5)
                }
            }
        }
    }

    private func star(size: Double, scale: Double) -> some View {
        Image(systemName: "sparkle").font(.system(size: size, weight: .semibold)).scaleEffect(scale)
    }
}
