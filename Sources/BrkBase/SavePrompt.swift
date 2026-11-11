import Foundation

/// Chromium offering to keep what a page's form just sent (a login, an address, a card), asked the way Arc 1.170
/// asks: its centred card ("Save password for <site>?" with Never on this site / No / Save, "Save Address?",
/// "Save this card?"), in place of Chromium's own bubble, which a window without Chrome's toolbar left pinned to the
/// page's top-right corner.
public struct SavePrompt: Hashable, Sendable {
    public enum Kind: Hashable, Sendable { case password, address, card }
    public let id: String
    public let page: PageID
    public let kind: Kind
    /// The page's host ("www.canva.com", "127.0.0.1"); nil when it has none, and the title asks about "this password".
    public let site: String?
    public init(id: String, page: PageID, kind: Kind, site: String?) {
        self.id = id; self.page = page; self.kind = kind; self.site = site
    }
}

/// Arc's buttons: Save (Return), No / No Thanks / Not Now (Esc, a click beside the card) and, for a password only,
/// Never on this site.
public enum SavePromptAnswer: Hashable, Sendable { case save, notNow, never }
