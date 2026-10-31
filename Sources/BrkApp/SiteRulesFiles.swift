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
            if data.first(where: { ![9, 10, 13, 32].contains($0) }) == 123 { return StateCodec.decodeWebsiteRules(data) }
            return StateCodec.decodeEasyListRules(data)
        } catch { return .failed(error.localizedDescription) }
    }
}
