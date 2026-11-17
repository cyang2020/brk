import Foundation

/// Issue #14. Until the app declared Chromium's languages, Chromium ran in en-US whatever macOS preferred, and each profile's first run
/// saved that default list as if the person had chosen it (`intl.selected_languages`, LanguagePrefs::InitializeSelectedLanguagesPref).
/// Once, before Chromium starts, a profile whose list is still exactly that "en-US,en" drops it when macOS gives Chromium another
/// language, so it takes the new default. Any other list was chosen in chrome://settings/languages and stays, as does every list
/// after this first pass (as in Chrome, a later change of the macOS language does not rewrite a profile's languages).
struct SavedLanguageDefault {
    /// `<data dir>/Chromium`.
    let root: URL
    static let oldDefault = "en-US,en"

    var marker: URL { root.deletingLastPathComponent().appendingPathComponent("languages-follow-macos") }

    /// `appLanguage`: the app bundle's preferred localization, which Chromium takes as its locale ("zh_CN").
    func clearOldDefault(appLanguage: String) {
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        if !appLanguage.hasPrefix("en") {
            let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            for folder in folders where folder.lastPathComponent == "Default" || folder.lastPathComponent.hasPrefix(ProfileDirectories.prefix) {
                Self.clear(folder.appendingPathComponent("Preferences"))
            }
        }
        FileManager.default.createFile(atPath: marker.path, contents: nil)
    }

    static func clear(_ preferences: URL) {
        guard let data = try? Data(contentsOf: preferences),
              var json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              var intl = json["intl"] as? [String: Any], intl["selected_languages"] as? String == oldDefault,
              (intl["accept_languages"] as? String).map({ $0 == oldDefault }) ?? true else { return }
        intl["selected_languages"] = nil
        intl["accept_languages"] = nil
        json["intl"] = intl
        guard let out = try? JSONSerialization.data(withJSONObject: json, options: .withoutEscapingSlashes) else { return }
        try? out.write(to: preferences, options: .atomic)
    }
}
