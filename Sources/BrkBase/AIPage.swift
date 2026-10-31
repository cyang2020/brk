import Foundation

/// Main-frame data captured for one document. It contains no cookies, form values, storage or subframe text.
public struct AIPageContent: Hashable, Sendable, Codable {
    public let document: DocumentToken
    public let url: URL
    public let title: String
    public let language: String
    public let text: String
    public let nodes: [AITextNode]
    public init(document: DocumentToken, url: URL, title: String, language: String, text: String, nodes: [AITextNode]) {
        self.document = document; self.url = url; self.title = title; self.language = language; self.text = text; self.nodes = nodes
    }
}
public struct AITextNode: Hashable, Sendable, Codable {
    public let id: Int
    public let text: String
    public init(id: Int, text: String) { self.id = id; self.text = text }
}
public enum AIPageFailure: Error, Sendable { case unavailable, changed, invalidReply }
