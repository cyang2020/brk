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
    /// The editor's visual controls (colour dots, light/dark, font, size, case). nil until one is touched; older
    /// Boost files have no such key and decode as nil.
    public var style: BoostStyle?
    public init(id: String, name: String, scope: BoostScope, css: String = "", javascript: String = "", enabled: Bool = true,
                allowPrivate: Bool = false, javascriptApproved: Bool = false, style: BoostStyle? = nil) {
        self.id = id; self.name = name; self.scope = scope; self.css = css; self.javascript = javascript
        self.enabled = enabled; self.allowPrivate = allowPrivate; self.javascriptApproved = javascriptApproved; self.style = style
    }
    /// What the page receives: the visual controls first, then the Code page's CSS, which can override them.
    public var injectedCSS: String { [style?.css ?? "", css].filter { !$0.isEmpty }.joined(separator: "\n") }
    /// Nothing made yet: closing such a never-saved draft creates no Boost.
    public var isBlank: Bool { (style ?? BoostStyle()) == BoostStyle() && css.isEmpty && javascript.isEmpty }
}

public struct BoostCatalog: Hashable, Sendable, Codable {
    public var version = 1
    public var boosts: [Boost]
    public init(boosts: [Boost] = []) { self.boosts = boosts }
}

/// Arc's Boost panel pages: the first-run card, the visual editor, and the Code page with its CSS / JS segments.
public enum BoostEditorPage: String, Hashable, Sendable, Codable { case intro, style, css, javascript }

/// What a page pick is for: Zap hides each clicked element (and keeps picking); the Code page's eyedropper
/// inserts one element's selector.
public enum BoostPickPurpose: String, Hashable, Sendable, Codable { case zap, selector }

public struct BoostEditor: Equatable, Sendable, Codable {
    public let id: String
    public let profile: ProfileID
    public let target: SiteTarget?
    public var draft: Boost
    public var page: BoostEditorPage = .style
    public var picking = false
    public var pickPurpose: BoostPickPurpose = .zap
    public var pickID: String? = nil
    public var message: String? = nil
}

/// Arc edits live and saves on close: `.close` (× and Escape) keeps the edits, `.discard` (Maybe Later) drops them,
/// `.save` (the Code page's hammer) writes now and asks before JavaScript may run.
public enum BoostCommand: Hashable, Sendable, Codable {
    case create, legacy, editCurrent, edit(String), gallery, preset(String)
    case update(Boost), save, close, discard, zap, inspect, page(BoostEditorPage)
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
