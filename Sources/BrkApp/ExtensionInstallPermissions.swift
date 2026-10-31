import Foundation

enum ExtensionInstallPermissions {
    struct InvalidDeclaration: Error { let key: String }

    static func text(_ manifest: [String: Any]) throws -> String {
        func strings(_ key: String, in object: [String: Any]) throws -> [String] {
            guard let raw = object[key] else { return [] }
            guard let values = raw as? [String], values.allSatisfy({ !$0.isEmpty }) else {
                throw InvalidDeclaration(key: key)
            }
            return values
        }
        func list(_ values: [String]) -> String { values.isEmpty ? "None declared" : values.joined(separator: ", ") }
        var lines = [
            "Permissions (APIs or hosts): " + list(try strings("permissions", in: manifest)),
            "Host permissions: " + list(try strings("host_permissions", in: manifest)),
            "Optional permissions, requested separately: " + list(try strings("optional_permissions", in: manifest)),
            "Optional host permissions, requested separately: " + list(try strings("optional_host_permissions", in: manifest)),
        ]
        let scripts: [[String: Any]]
        if let raw = manifest["content_scripts"] {
            guard let values = raw as? [[String: Any]] else { throw InvalidDeclaration(key: "content_scripts") }
            scripts = values
        } else { scripts = [] }
        for (index, script) in scripts.enumerated() {
            let matches = try strings("matches", in: script)
            guard !matches.isEmpty else { throw InvalidDeclaration(key: "content_scripts.matches") }
            lines += ["", "Content script \(index + 1)", "Matches: " + list(matches),
                      "Excluded matches: " + list(try strings("exclude_matches", in: script)),
                      "Include globs: " + list(try strings("include_globs", in: script)),
                      "Exclude globs: " + list(try strings("exclude_globs", in: script))]
            for (key, title) in [("all_frames", "Matching subframes"), ("match_about_blank", "Related blank frames"),
                                 ("match_origin_as_fallback", "Other frames created by matching origins")] {
                if let raw = script[key] {
                    guard let value = raw as? Bool else { throw InvalidDeclaration(key: key) }
                    lines.append(title + ": " + (value ? "Yes" : "No"))
                }
            }
            if let world = script["world"] {
                guard let value = world as? String else { throw InvalidDeclaration(key: "world") }
                lines.append("Execution world: " + value)
            }
        }
        if scripts.isEmpty { lines.append("Content scripts: None declared") }
        lines += ["", "Install in this public profile. Private installation is disabled. Chromium's local-extension developer mode will be enabled for this profile."]
        return lines.joined(separator: "\n")
    }
}
