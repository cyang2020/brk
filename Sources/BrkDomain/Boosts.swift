import BrkBase
import Foundation

public struct Boost: Hashable, Sendable, Codable {
    public var id: String
    public var name: String
    public var scope: BoostScope
    public var css: String
    public var javascript: String
    public var enabled: Bool
    public var allowPrivate: Bool
    public var javascriptApproved: Bool
    public init(id: String, name: String, scope: BoostScope, css: String = "", javascript: String = "", enabled: Bool = true,
                allowPrivate: Bool = false, javascriptApproved: Bool = false) {
        self.id = id; self.name = name; self.scope = scope; self.css = css; self.javascript = javascript
        self.enabled = enabled; self.allowPrivate = allowPrivate; self.javascriptApproved = javascriptApproved
    }
}

public struct BoostCatalog: Hashable, Sendable, Codable {
    public var version = 1
    public var boosts: [Boost]
    public init(boosts: [Boost] = []) { self.boosts = boosts }
}

public struct BoostEditor: Equatable, Sendable, Codable {
    public let id: String
    public let profile: ProfileID
    public let target: SiteTarget?
    public var draft: Boost
    public var picking = false
    public var pickID: String? = nil
    public var message: String? = nil
}

public enum BoostCommand: Hashable, Sendable, Codable {
    case create, legacy, editCurrent, edit(String), gallery, preset(String)
    case update(Boost), save, cancel, zap
    case enable(String, Bool), remove(String), export(String), importFile
    /// Selected-file commands also serve automation; both are restricted to the invoking public profile.
    case importSelected(URL), exportSelected(String, URL)
}

public enum BoostEvent: Sendable, Equatable {
    case loaded(ProfileID, BoostCatalog, error: String?)
    case written(WindowID, ProfileID, BoostCatalog, editor: String?)
    case failed(WindowID, String)
    case approved(WindowID, String, Boost)
    case picked(WindowID, String, SiteTarget, String?)
    case imported(WindowID, ProfileID, [Boost])
}

public enum BoostEffect: Hashable, Sendable {
    case write(WindowID, ProfileID, BoostCatalog, editor: String?)
    case confirm(WindowID, String, Boost)
    case pick(WindowID, String, SiteTarget)
    case importFile(WindowID, ProfileID, URL?)
    case exportFile(WindowID, Boost, URL?)
}

public enum BoostPresets {
    public static let all: [(id: String, name: String, css: String)] = [
        ("reader", "Comfortable reading", "body { font-size: 19px !important; line-height: 1.7 !important; }"),
        ("midnight", "Midnight", "html, body { background: #171522 !important; color: #eee8ff !important; } a { color: #b4a0ff !important; }"),
        ("focus", "Less motion", "*, *::before, *::after { animation: none !important; transition: none !important; scroll-behavior: auto !important; }")
    ]
}

extension AppState {
    /// File adapter authorization uses the same profile boundary as the reducer.
    public func boostProfileForIO(_ window: WindowID) -> ProfileID? { boostProfile(in: window) }
}
