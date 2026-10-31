import BrkBase
import BrkDomain
import Foundation

/// The user-selected file is read off the UI actor and bounded before JSON parsing.
enum SiteRulesFiles {
    static func read(_ file: URL) -> WebsiteRulesUpdate {
        do {
            let handle = try FileHandle(forReadingFrom: file)
            defer { try? handle.close() }
            let data = try handle.read(upToCount: 1_048_577) ?? Data()
            return StateCodec.decodeWebsiteRules(data)
        } catch { return .failed(error.localizedDescription) }
    }
}
