import BrkBase
import CBrkCore
import Foundation

/// A DevTools protocol failure on BrkCore, as `CefProtocolError` on CEF.
struct CoreProtocolError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// The page's DevTools session, with the call shape CEFEngine's code uses (`CefDevToolsSession.call`), so the engines' site policy, site data
/// and page reading send the same commands. The framework keeps the session attached once a command changed state (emulation, lifecycle).
@MainActor
struct CoreProtocolSession {
    let contents: any BrkCoreWebContents

    /// `timeout` is CEF's; the framework's session waits for Chromium's answer, which comes or fails when the page goes.
    func call(_ method: String, _ parameters: [String: Any] = [:], timeout: Double = 10) async throws -> [String: Any] {
        let text = String(decoding: try JSONSerialization.data(withJSONObject: parameters), as: UTF8.self)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[String: Any], Error>) in
            contents.sendDevToolsCommand(method, parameters: text) { result, error in
                if let result, let data = result.data(using: .utf8),
                   let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
                    continuation.resume(returning: json)
                } else {
                    continuation.resume(throwing: CoreProtocolError(message: error ?? "DevTools gave no answer to \(method)"))
                }
            }
        }
    }
}
