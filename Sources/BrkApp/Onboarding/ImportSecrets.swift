import BrkBase
import BrkImport
import Foundation
import Security

/// The keys an import needs: the source browser's ("<Browser> Safe Storage", read once per import; macOS asks for the
/// computer password, which is why the keychain explanation screen comes first) and Brk's own, the one Chromium encrypts
/// this profile's passwords and cookies with.
enum ImportKeys {
    /// Test launches (the control socket) never touch the login keychain: the source key comes from
    /// BRK_TEST_IMPORT_KEY, and Brk's own is Chromium's mock key (`--use-mock-keychain`).
    static var testing: Bool { LaunchOptions().controlSocket != nil }

    /// Blocks until macOS answers its prompt; call off the main thread.
    static func source(_ kind: BrowserKind) -> ChromiumKey? {
        if testing {
            guard let password = ProcessInfo.processInfo.environment["BRK_TEST_IMPORT_KEY"], !password.isEmpty else { return nil }
            return ChromiumKey(password: password)
        }
        for service in kind.keychainServices {
            if let password = genericPassword(service: service, account: nil) { return ChromiumKey(password: password) }
        }
        return nil
    }

    /// Matches BrkCoreRuntime: only controlled test launches use the mock key, regardless of build configuration.
    /// Nil when Chromium has not made its login keychain item yet.
    static func brk() -> ChromiumKey? {
        if testing { return ChromiumKey(password: "mock_password") }
        return genericPassword(service: "Chromium Safe Storage", account: "Chromium").map(ChromiumKey.init(password:))
    }

    private static func genericPassword(service: String, account: String?) -> String? {
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service,
                                    kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        if let account { query[kSecAttrAccount as String] = account }
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// Where a Brk profile's Chromium data lives: `<data>/Chromium/Default`, or `Profile-<id>` (the same rule as
/// `ProfileDirectories.directoryName` in BrkCoreEngine, which BrkApp cannot import).
enum BrkProfileFolders {
    static var chromiumRoot: URL { Product.dataDirectory().appendingPathComponent("Chromium", isDirectory: true) }
    static var staging: URL { Product.dataDirectory().appendingPathComponent("pending-logins", isDirectory: true) }

    static func folder(_ id: ProfileID) -> URL {
        guard id != .default else { return chromiumRoot.appendingPathComponent("Default", isDirectory: true) }
        let cleaned = id.rawValue.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: ":", with: "_").replacingOccurrences(of: "\\", with: "_")
        let trimmed = cleaned.drop { $0 == "." }
        return chromiumRoot.appendingPathComponent("Profile-" + (trimmed.isEmpty ? "Profile" : String(trimmed)), isDirectory: true)
    }
}

/// Imported passwords go into the profile's own Chromium password store, never Brk's own keychain items (user decision
/// 3, 2026-11-12): Chromium's password manager then fills them. See `LoginDataWriter` for why rows wait in a
/// staged file while Chromium holds the database.
enum PasswordImport {
    struct Outcome: Equatable { var written = 0, staged = 0 }

    static func write(_ logins: [SourceLogin], profile: ProfileID) throws -> Outcome {
        guard !logins.isEmpty else { return Outcome() }
        guard let key = ImportKeys.brk() else {
            throw NSError(domain: "Brk.Import", code: 1, userInfo: [NSLocalizedDescriptionKey: "Brk's own password store is not ready yet; open any page once, then import again"])
        }
        switch try LoginDataWriter.write(logins, key: key, profileFolder: BrkProfileFolders.folder(profile), staging: BrkProfileFolders.staging) {
        case .written(let count): return Outcome(written: count)
        case .staged(let count): return Outcome(staged: count)
        }
    }
}

/// Called by main.swift before Chromium starts: staged logins go into their profiles' Login Data while nothing holds it.
public enum BrowserImportStartup {
    public static func applyPendingLogins() {
        let staging = BrkProfileFolders.staging
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: staging.path), files.contains(where: { $0.hasSuffix(".json") }) else { return }
        // The rows were encrypted under Brk's key when they were staged; merging needs no key.
        LoginDataWriter.mergeStaged(chromiumRoot: BrkProfileFolders.chromiumRoot.resolvingSymlinksInPath(), staging: staging)
    }
}
