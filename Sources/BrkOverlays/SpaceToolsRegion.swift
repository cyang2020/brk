import AppKit
import BrkLayout
import BrkUIKit
import SwiftUI

/// Reports a SwiftUI control's real frame to native input automation; it never intercepts a click.
private struct SpaceToolsRegion: NSViewRepresentable {
    let id: ViewID
    func makeNSView(context: Context) -> Region { let view = Region(); view.identify(id); return view }
    func updateNSView(_ view: Region, context: Context) { view.identify(id) }
    final class Region: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}

extension View {
    func spaceToolsID(_ name: String) -> some View { background(SpaceToolsRegion(id: .spaceToolsControl(name))) }
}
