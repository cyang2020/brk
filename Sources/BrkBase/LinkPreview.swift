import Foundation

/// Ephemeral text fetched in the originating browser's request context. Never persisted or shared across pages.
public struct LinkPreviewRequest: Sendable {
    public let document: DocumentToken
    public let url: URL
    public let title: String
    public let text: String
    public init(document: DocumentToken, url: URL, title: String, text: String) {
        self.document = document; self.url = url; self.title = title; self.text = text
    }
}
