import BrkBase
import BrkDomain
import Foundation
import LocalAuthentication
import Security

/// Selected CSV credentials go only to this app's protected local Keychain collection, never Chromium's
/// password database or state.json. Existing entries are skipped, never overwritten.
@MainActor
enum ImportedPasswordVault {
    static func store(_ passwords: [ImportedPassword], profile: ProfileID, stillValid: @escaping @MainActor () -> Bool) async throws -> Int {
        guard !passwords.isEmpty else { return 0 }
        let authentication = ImportedPasswordAuthentication()
        let auth = authentication.context
        guard auth.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            throw SidebarDataError.invalid("macOS authentication is unavailable. No passwords were imported.")
        }
        let allowed = try await withTaskCancellationHandler {
            try await auth.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Import the selected passwords into Brk's local Keychain collection")
        } onCancel: {
            Task { @MainActor in authentication.context.invalidate() }
        }
        guard allowed, stillValid() else { throw SidebarDataError.invalid("Password import cancelled. No passwords were imported.") }
        var error: Unmanaged<CFError>?
        guard let protection = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, &error) else {
            throw SidebarDataError.invalid("Could not create protected Keychain storage.")
        }
        return try ImportedPasswordTransaction.apply(passwords, stillValid: stillValid, add: { password in
            let origin = "\(password.url.scheme ?? "https")://\(password.url.host ?? ""):\(password.url.port ?? (password.url.scheme == "http" ? 80 : 443))"
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "dev.brk.imported.\(profile.rawValue).\(origin)",
                kSecAttrAccount as String: password.username,
                kSecAttrLabel as String: "Brk imported password (\(password.url.host ?? "site"))",
                kSecValueData as String: Data(password.password.utf8),
                kSecAttrAccessControl as String: protection,
                kSecUseAuthenticationContext as String: auth,
                kSecReturnPersistentRef as String: true,
            ]
            var reference: CFTypeRef?
            let result = SecItemAdd(query as CFDictionary, &reference)
            if result == errSecDuplicateItem { return nil }
            guard result == errSecSuccess, let data = reference as? Data else {
                throw SidebarDataError.invalid("Keychain import failed (\(result)).")
            }
            return data
        }, remove: { reference in
            SecItemDelete([kSecValuePersistentRef as String: reference] as CFDictionary) == errSecSuccess
        })
    }
}

@MainActor
private final class ImportedPasswordAuthentication {
    let context = LAContext()
}


@MainActor
enum ImportedPasswordTransaction {
    static func apply(_ passwords: [ImportedPassword], stillValid: () -> Bool,
                      add: (ImportedPassword) throws -> Data?, remove: (Data) -> Bool) throws -> Int {
        var created: [Data] = []
        do {
            for password in passwords {
                guard stillValid(), !Task.isCancelled else { throw SidebarDataError.invalid("Password import cancelled.") }
                if let reference = try add(password) { created.append(reference) }
            }
            guard stillValid(), !Task.isCancelled else { throw SidebarDataError.invalid("The import destination changed.") }
            return created.count
        } catch {
            let failures = created.reversed().filter { !remove($0) }.count
            if failures > 0 { throw SidebarDataError.invalid("Import failed; \(failures) newly created Keychain entries could not be removed. Review the Brk imported password collection in Keychain Access.") }
            throw SidebarDataError.invalid("\(error) No newly imported passwords were kept.")
        }
    }
}
