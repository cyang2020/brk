import Foundation

/// Connects 1Password's browser extension in Brk to the 1Password app without the user copying anything.
///
/// The extension talks to the app through Chromium's native messaging: Chromium looks for `com.1password.1password.json`
/// in `<user data folder>/NativeMessagingHosts`. 1Password writes that file only into the browsers on its own list
/// (Chrome, Edge, Vivaldi, Arc and their channels, read from 1Password 8.12.44's `index.node`), so Brk writes its own,
/// with the same content, pointing into the 1Password app it found. It is rewritten whenever it differs (1Password moved
/// or a later Brk knows another extension id). Allowing Brk in 1Password → Settings → Browser stays the user's step.
public enum OnePasswordBridge {
    public static let bundleIdentifier = "com.1password.1password"
    static let fileName = "com.1password.1password.json"
    /// The helper 1Password starts for a browser, inside its app.
    static let helper = "Contents/Library/LoginItems/1Password Browser Helper.app/Contents/MacOS/1Password-BrowserSupport"
    /// 1Password's extensions (Chrome Web Store, Edge Add-ons, beta and nightly), in 1Password's own order.
    static let extensionIDs = ["hjlinigoblmkhjejkmbegnoaljkphmgo", "bkpbhnjcbehoklfkljkkbbmipaphipgl", "gejiddohjgogedgjnonbofjigllpkmbf",
                               "khgocmkkpikpnmmkgmdnfckapcdkgfaf", "aeblfdkhhhdcdjpifhhbdiojplfjncoa", "dppgmdbiimibapkepcbdbmkaabgiofem"]

    /// The manifest for the 1Password app at `app`; nil when that app has no browser helper.
    static func manifest(app: URL) -> Data? {
        let path = app.appendingPathComponent(helper).path
        guard FileManager.default.isExecutableFile(atPath: path) else { return nil }
        let object: [String: Any] = ["name": bundleIdentifier, "description": "1Password BrowserSupport", "path": path, "type": "stdio",
                                     "allowed_origins": extensionIDs.map { "chrome-extension://\($0)/" }]
        return try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    /// Writes Brk's manifest for the 1Password app at `app` (nil: not installed, nothing is written). True when the file changed.
    @discardableResult
    public static func connect(app: URL?, chromiumRoot: URL) -> Bool {
        guard let app, let data = manifest(app: app) else { return false }
        let folder = chromiumRoot.appendingPathComponent("NativeMessagingHosts", isDirectory: true)
        let file = folder.appendingPathComponent(fileName)
        if (try? Data(contentsOf: file)) == data { return false }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return (try? data.write(to: file, options: .atomic)) != nil
    }
}
