import Foundation

/// Main-frame data captured for one document. It contains no cookies, form values, storage or subframe text.
public struct AIPageContent: Hashable, Sendable, Codable {
    public let document: DocumentToken
    public let url: URL
    public let title: String
    public let language: String
    public let text: String
    public let nodes: [AITextNode]
    /// Some of the visible text is not among `nodes`: a piece too long to translate as one (it is in `text`), or the
    /// page went past what one read takes (200 pieces, 24,000 characters). Nil is the whole page.
    public let partial: Bool?
    public init(document: DocumentToken, url: URL, title: String, language: String, text: String, nodes: [AITextNode], partial: Bool? = nil) {
        self.document = document; self.url = url; self.title = title; self.language = language; self.text = text; self.nodes = nodes
        self.partial = partial
    }
}
public struct AITextNode: Hashable, Sendable, Codable {
    public let id: Int
    public let text: String
    public init(id: Int, text: String) { self.id = id; self.text = text }
}
public enum AIPageFailure: Error, Sendable { case unavailable, changed, invalidReply }
