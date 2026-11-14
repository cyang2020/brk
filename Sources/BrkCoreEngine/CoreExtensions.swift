import BrkBase
import BrkEngine
import CBrkCore
import Foundation

/// Observes the profile's extension changes and edits settings through Chromium's extensions page.
extension CoreEngine {
    func observeExtensions(_ profile: any BrkCoreProfile, context: BrowsingContext) {
        let refresh: () -> Void = { [weak self] in
            Task { @MainActor [weak self] in
                guard let self, self.isRunning, self.contexts.permitsWork(context) else { return }
                let catalog = await self.extensionCatalog(context: context)
                guard self.isRunning, self.contexts.permitsWork(context) else { return }
                self.delegate?.engine(self, extensionsDidChange: catalog)
            }
        }
        profile.setExtensionsChangedHandler(refresh)
        refresh()
    }

    struct ManagedExtension {
        let incognitoAllowed: Bool?
        let canChangeIncognito: Bool?
        let commands: [BrowserExtensionCommand]
    }

    private func readyExtensionManager(context: BrowsingContext, target: PageID? = nil) -> CorePage? {
        livePages.sorted(by: { $0.id < $1.id }).first { page in
            guard target == nil || target == page.id, page.context == context,
                  page.contents.committedURL?.scheme == "chrome", page.contents.committedURL?.host == "extensions" else { return false }
            if case .ready = page.mainDocument.availability { return true }; return false
        }
    }

    private func extensionManager(context: BrowsingContext, target: PageID? = nil, wait seconds: Double = 10) async throws -> CorePage {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        while isRunning, contexts.permitsWork(context), ProcessInfo.processInfo.systemUptime < deadline {
            if let page = readyExtensionManager(context: context, target: target) { return page }
            try await Task.sleep(for: .milliseconds(30))
        }
        throw CoreProtocolError(message: "The originating profile's extension manager is unavailable")
    }

    private func managerValue(_ page: CorePage, expression: String, timeout: Double = 10, userGesture: Bool = false) async throws -> Any? {
        guard isLive(page), contexts.permitsWork(page.context), case .ready(let document) = page.mainDocument.availability,
              page.contents.committedURL?.scheme == "chrome", page.contents.committedURL?.host == "extensions" else {
            throw CoreProtocolError(message: "The extension manager document changed")
        }
        let response = try await page.protocolSession.call("Runtime.evaluate", ["expression": expression, "awaitPromise": true, "returnByValue": true, "userGesture": userGesture], timeout: timeout)
        guard isLive(page), contexts.permitsWork(page.context), page.mainDocument.availability == .ready(document) else {
            throw CoreProtocolError(message: "The extension manager document changed")
        }
        if let details = response["exceptionDetails"] as? [String: Any] {
            let exception = details["exception"] as? [String: Any]
            throw CoreProtocolError(message: exception?["description"] as? String ?? details["text"] as? String ?? "Chromium extension operation failed")
        }
        return (response["result"] as? [String: Any])?["value"]
    }

    func managerExtensionInfo(context: BrowsingContext) async -> [String: ManagedExtension] {
        guard let page = readyExtensionManager(context: context),
              let rows = try? await managerValue(page, expression: "chrome.developerPrivate.getExtensionsInfo({includeDisabled:true,includeTerminated:true})") as? [[String: Any]] else {
            return [:]
        }
        var out: [String: ManagedExtension] = [:]
        for row in rows {
            guard let id = row["id"] as? String else { continue }
            let access = row["incognitoAccess"] as? [String: Any]
            let commands = (row["commands"] as? [[String: Any]] ?? []).compactMap { command -> BrowserExtensionCommand? in
                guard let name = command["name"] as? String, let key = command["keybinding"] as? String else { return nil }
                return BrowserExtensionCommand(name: name, description: command["description"] as? String ?? name, keybinding: key, active: command["isActive"] as? Bool ?? false)
            }
            out[id] = ManagedExtension(incognitoAllowed: access?["isActive"] as? Bool, canChangeIncognito: access?["isEnabled"] as? Bool, commands: commands)
        }
        return out
    }

    public func editExtension(_ id: String, edit: ExtensionEdit, context: BrowsingContext) async -> String? {
        guard case .profile = context else { return "Private extension management is disabled" }
        do {
            let page = try await extensionManager(context: context)
            let literal = CorePage.jsString(id)
            let expression: String
            switch edit {
            case .incognito(let allowed):
                expression = "chrome.developerPrivate.updateExtensionConfiguration({extensionId:\(literal),incognitoAccess:\(allowed)})"
            case .shortcut(let command, let chord):
                var parts: [String] = []
                if let chord {
                    if chord.modifiers.contains(.command) { parts.append("Command") }
                    if chord.modifiers.contains(.control) { parts.append("Ctrl") }
                    if chord.modifiers.contains(.option) { parts.append("Alt") }
                    if chord.modifiers.contains(.shift) { parts.append("Shift") }
                    parts.append(chord.key.name.uppercased())
                }
                expression = "chrome.developerPrivate.updateExtensionCommand({extensionId:\(literal),commandName:\(CorePage.jsString(command)),keybinding:\(CorePage.jsString(parts.joined(separator: "+"))),scope:'CHROME'})"
            }
            _ = try await managerValue(page, expression: expression, userGesture: true)
            return nil
        } catch { return error.localizedDescription }
    }

    public func removeExtension(_ id: String, context: BrowsingContext, in target: PageID) async -> String? {
        guard case .profile = context else { return "Private extension management is disabled" }
        do {
            let page = try await extensionManager(context: context, target: target)
            _ = try await managerValue(page, expression: "new Promise((resolve,reject)=>{chrome.management.uninstall(\(CorePage.jsString(id)),{showConfirmDialog:true},()=>{const error=chrome.runtime.lastError;if(error)reject(new Error(error.message));else resolve(true)})})", timeout: 300, userGesture: true)
            return nil
        } catch { return error.localizedDescription }
    }
}
