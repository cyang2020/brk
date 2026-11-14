import Foundation

/// Extensions reach desktop apps (1Password, Bitwarden, KeePassXC, …) through native messaging: Chromium starts the app's
/// helper named in a manifest it finds in `<user data folder>/NativeMessagingHosts`. Those apps write their manifest only
/// into the browsers they know (Chrome, Arc, Brave, …), never into Brk's folder, so the extension installs but cannot
/// reach its app (1Password's stays locked and fills nothing). Brk takes the manifests the other browsers already have.
public enum NativeMessagingHosts {
    /// Copies every `*.json` manifest of the other Chromium browsers under `support` (~/Library/Application Support) into
    /// `chromiumRoot/NativeMessagingHosts`, Arc's first. A manifest Brk already has is left as it is. Returns the names copied.
    @discardableResult
    public static func adopt(into chromiumRoot: URL, support: URL) -> [String] {
        let files = FileManager.default
        let destination = chromiumRoot.appendingPathComponent("NativeMessagingHosts", isDirectory: true)
        var copied: [String] = []
        for kind in BrowserKind.allCases where kind.isChromium {
            let source = support.appendingPathComponent(kind.dataFolder, isDirectory: true).appendingPathComponent("NativeMessagingHosts", isDirectory: true)
            guard let names = try? files.contentsOfDirectory(atPath: source.path) else { continue }
            for name in names.sorted() where name.hasSuffix(".json") {
                let target = destination.appendingPathComponent(name)
                guard !files.fileExists(atPath: target.path) else { continue }
                try? files.createDirectory(at: destination, withIntermediateDirectories: true)
                if (try? files.copyItem(at: source.appendingPathComponent(name), to: target)) != nil { copied.append(name) }
            }
        }
        return copied
    }
}
