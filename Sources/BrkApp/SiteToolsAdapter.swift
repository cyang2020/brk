import AppKit
import BrkBase
import BrkDomain
import BrkUIKit
import UniformTypeIdentifiers

/// Reads only selected sources. Tokens remain in the request closure and ephemeral URLSession.
@MainActor
final class SiteToolsAdapter {
    private var tasks: [WindowID: Task<Void, Never>] = [:]
    private var requests: [WindowID: String] = [:]
    private var panels: [WindowID: NSWindow] = [:]
    private let send: @MainActor (SystemEvent) -> Void
    init(send: @escaping @MainActor (SystemEvent) -> Void) { self.send = send }

    func reconcile(_ active: Set<String>) {
        for window in requests.keys where requests[window].map({ !active.contains($0) }) ?? true { cancel(window) }
    }
    private func cancel(_ window: WindowID) {
        requests[window] = nil
        tasks.removeValue(forKey: window)?.cancel()
        if let panel = panels.removeValue(forKey: window) {
            panel.sheetParent?.endSheet(panel, returnCode: .cancel)
            panel.orderOut(nil)
        }
    }
    func run(_ request: SiteRequest, in window: NSWindow) {
        cancel(request.window)
        requests[request.window] = request.id
        switch request.kind {
        case .github(let repository, _):
            if let repository { fetch(repository, token: "", request: request) }
            else { chooseRepository(request, in: window) }
        case .calendar:
            let panel = NSOpenPanel()
            panel.title = "Select a Calendar Export"
            panel.message = "Read this selected .ics file for upcoming meetings. Data stays in memory and expires after five minutes. No account access is requested."
            panel.allowedContentTypes = [UTType(filenameExtension: "ics") ?? .plainText]
            panels[request.window] = panel
            panel.beginSheetModal(for: window) { [weak self, weak window] response in
                guard let self, window?.isVisible == true, self.requests[request.window] == request.id else { return }
                self.panels[request.window] = nil
                guard response == .OK, let url = panel.url else { self.send(.siteResult(request.id, .cancelled)); return }
                do { self.send(.siteResult(request.id, .calendar(try CalendarFile.meetings(Data(contentsOf: url))))) }
                catch { self.send(.siteResult(request.id, .failed("Calendar could not be read. Select a nonrecurring calendar with meeting URLs."))) }
            }
        }
    }
    private func chooseRepository(_ request: SiteRequest, in window: NSWindow) {
        let alert = NSAlert()
        alert.messageText = "Connect a GitHub Repository"
        if case .github(_, .some) = request.kind {
            alert.informativeText = "Select owner/repository for unread notifications. A classic GitHub token with the notifications scope is required. It is used once and never saved. Only this repository is read."
        } else {
            alert.informativeText = "Enter owner/repository. Brk reads open pull requests only. Public repositories need no token. An optional read-only token is used once and is never saved."
        }
        alert.addButton(withTitle: "Connect")
        alert.addButton(withTitle: "Cancel")
        let accessory = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 72))
        let repository = NSTextField(frame: NSRect(x: 0, y: 40, width: 340, height: 26))
        repository.placeholderString = "owner/repository"
        repository.identify(.tabTool("repository"))
        let token = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 340, height: 26))
        token.placeholderString = "Optional token with Pull requests: read"
        accessory.addSubview(repository)
        accessory.addSubview(token)
        alert.buttons[0].identify(.tabTool("connect-repository"))
        alert.buttons[1].identify(.tabTool("cancel-repository"))
        alert.accessoryView = accessory
        panels[request.window] = alert.window
        alert.beginSheetModal(for: window) { [weak self, weak window] response in
            guard let self, window?.isVisible == true, self.requests[request.window] == request.id else { return }
            self.panels[request.window] = nil
            guard response == .alertFirstButtonReturn else { self.send(.siteResult(request.id, .cancelled)); return }
            self.fetch(repository.stringValue.trimmingCharacters(in: .whitespacesAndNewlines), token: token.stringValue, request: request)
            token.stringValue = ""
        }
    }
    private func fetch(_ repository: String, token: String, request: SiteRequest) {
        let parts = repository.split(separator: "/", omittingEmptySubsequences: false)
        let valid = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && $0.unicodeScalars.allSatisfy(valid.contains) }) else {
            send(.siteResult(request.id, .failed("Use an owner/repository name"))); return
        }
        let environment = ProcessInfo.processInfo.environment
        let fixture = environment["BRK_CONTROL_SOCKET"] != nil ? environment["BRK_GITHUB_FIXTURE_BASE"].flatMap(URL.init(string:)) : nil
        let base = fixture.flatMap { ["127.0.0.1", "localhost"].contains($0.host ?? "") ? $0 : nil } ?? URL(string: "https://api.github.com")!
        let unread: Bool = if case .github(_, .some) = request.kind { true } else { false }
        if unread, token.isEmpty, fixture == nil { send(.siteResult(request.id, .failed("Unread badges require a classic token with notifications scope"))); return }
        let endpoint = unread ? "notifications" : "pulls"
        let query = unread ? [URLQueryItem(name: "all", value: "false"), URLQueryItem(name: "per_page", value: "50")] : [URLQueryItem(name: "state", value: "open"), URLQueryItem(name: "per_page", value: "100")]
        let url = base.appendingPathComponent("repos/\(repository)/\(endpoint)").appending(queryItems: query)
        var http = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        http.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        http.setValue("2026-03-10", forHTTPHeaderField: "X-GitHub-Api-Version")
        http.setValue("Brk", forHTTPHeaderField: "User-Agent")
        if !token.isEmpty, fixture == nil { http.setValue("Bearer " + token, forHTTPHeaderField: "Authorization") }
        tasks[request.window] = Task { [weak self] in
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil
            configuration.urlCache = nil
            configuration.urlCredentialStorage = nil
            let session = URLSession(configuration: configuration, delegate: NoSiteRedirects(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            let result: SiteOutcome
            do {
                let (data, response) = try await session.data(for: http)
                try Task.checkCancellation()
                guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { throw CocoaError(.fileReadNoPermission) }
                if unread { result = .unread(repository: repository, count: try SiteCodec.unreadNotifications(data)) }
                else { result = .pullRequests(repository: repository, try SiteCodec.pullRequests(data)) }
            } catch is CancellationError { result = .cancelled }
            catch { result = .failed("GitHub refresh failed. Check the repository, access permission and connection.") }
            guard let self, self.requests[request.window] == request.id else { return }
            self.send(.siteResult(request.id, result))
            self.tasks[request.window] = nil
        }
    }
}
private final class NoSiteRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) { completionHandler(nil) }
}
