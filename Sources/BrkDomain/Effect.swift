import BrkBase
import CoreGraphics
import Foundation

/// What the reducer asks the outside world to do, besides changing state. Executed by `AppStore` after the new
/// snapshot is rendered (so a page created by this transition exists before it is navigated).
///
/// Only imperative one-shots are effects. Anything that is a function of state (which pages are live, which windows
/// exist, what has keyboard focus, frames) is derived from the snapshot and reconciled, never sent as an effect.
public enum Effect: Hashable, Sendable {
    case page(PageID, PageAction)
    case copyToPasteboard(String)
    case window(WindowID, WindowEffect)
    case app(AppEffect)
    /// A native popup menu built from state; each entry carries the command it dispatches when chosen.
    case popupMenu(WindowID, MenuModel, at: CGPoint)
}

public enum WindowEffect: Hashable, Sendable {
    case toggleFullScreen
    case miniaturize
}

public enum AppEffect: Hashable, Sendable {
    /// Starts the ordered shutdown (BrkApp/Lifecycle.swift): flush state, close pages, CEF shutdown, exit.
    case quit
    case hide
    case hideOthers
    case beep
}

public struct MenuModel: Hashable, Sendable {
    public var entries: [MenuEntry]
    public init(entries: [MenuEntry]) { self.entries = entries }
}

public enum MenuEntry: Hashable, Sendable {
    case action(title: String, command: Command, enabled: Bool)
    case separator
}
