import AppKit
import BrkBase
import CefKit

extension ChromePage {
    func developer(_ operation: DeveloperOperation) {
        guard engine.isLive(self) else { return }
        switch operation {
        case .source:
            guard let document = readyDocument else { developerResult = "Source unavailable while the document is loading"; return }
            sourceRequest &+= 1
            let request = sourceRequest
            browser.readSource { [weak self] text in
                guard let self, self.engine.isLive(self), self.readyDocument == document, self.sourceRequest == request else { return }
                guard let text else { self.developerResult = "Could not read page source"; return }
                let window = self.sourceWindow ?? NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 650),
                    styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.title = "Source — " + (self.browser.url?.absoluteString ?? "Page")
                let scroll = NSScrollView(frame: window.contentView?.bounds ?? .zero)
                scroll.autoresizingMask = [.width, .height]; scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = true
                let editor = NSTextView(frame: scroll.bounds)
                editor.isEditable = false; editor.isRichText = false
                editor.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
                editor.string = text
                editor.autoresizingMask = [.width]
                scroll.documentView = editor
                window.contentView = scroll
                if self.sourceWindow == nil { window.center() }
                self.sourceWindow = window
                window.makeKeyAndOrderFront(nil)
                self.developerResult = "Source displayed: \(text.utf8.count) bytes"
            }
        case .inspect:
            // Arc's Inspect Elements is Chrome's: DevTools opens on Elements with its element picker on, and the
            // node the user then points at and clicks in the page is the one selected.
            requestedDeveloperPanel = "elements"
            inspectPickRequested = true
            developerResult = "Inspect requested"
            browser.showDevTools()
            selectDeveloperPanel()
        case .console, .network:
            requestedDeveloperPanel = operation == .console ? "console" : "network"
            browser.showDevTools()
            selectDeveloperPanel()
        }
    }

    func selectDeveloperPanel() {
        guard let panel = requestedDeveloperPanel, let tools = toolsBrowser, tools.id > 0 else { return }
        developerPanelTask?.cancel()
        developerTransport?.invalidate(); developerTransport = nil
        developerPanelTask = Task { @MainActor [weak self, weak tools] in
            guard let self, let tools, let transport = CefDevTools(browser: tools) else { return }
            self.developerTransport = transport
            defer { transport.invalidate(); if self.developerTransport === transport { self.developerTransport = nil } }
            // InspectorFrontendAPI.showPanel is the DevTools embedder's named panel event. Confirm the actual
            // selected tab instead of reporting the JavaScript submission as success.
            for _ in 0..<30 {
                guard !Task.isCancelled, self.engine.isLive(self), self.toolsBrowser === tools else { return }
                do {
                    let expression = "(()=>{if(typeof globalThis.InspectorFrontendAPI?.showPanel!=='function')return false;InspectorFrontendAPI.showPanel('\(panel)');function selected(root){for(const e of root.querySelectorAll('*')){if(e.id==='tab-\(panel)'&&(e.getAttribute('aria-selected')==='true'||e.classList.contains('selected')))return true;if(e.shadowRoot&&selected(e.shadowRoot))return true}return false}return selected(document)})()"
                    let data = try await transport.call("Runtime.evaluate", parameters: ["expression": expression, "returnByValue": true])
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
                    if (json?["result"] as? [String: Any])?["value"] as? Bool == true {
                        self.developerResult = "\(panel) selected"
                        self.requestedDeveloperPanel = nil
                        if panel == "elements", self.inspectPickRequested { await self.enterElementPicker(transport) }
                        return
                    }
                } catch { self.developerResult = "Panel selection failed: \(error)"; return }
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
            self.developerResult = "DevTools opened; \(panel) selection could not be confirmed"
        }
    }

    /// Turns on DevTools' element picker (the embedder's `enterInspectElementMode`, what Chrome sends for its
    /// Inspect command). Under the e2e control socket it then reports the node the picker selected, read from the
    /// Elements tree, so a native run can prove which element a click in the page picked.
    private func enterElementPicker(_ transport: CefDevTools) async {
        inspectPickRequested = false
        let toggled = "(()=>{function on(root){for(const e of root.querySelectorAll('[aria-label]')){if(/select an element/i.test(e.getAttribute('aria-label'))&&(e.getAttribute('aria-pressed')==='true'||e.classList.contains('toggled')||e.hasAttribute('toggled')))return true;if(e.shadowRoot&&on(e.shadowRoot))return true}for(const e of root.querySelectorAll('*'))if(e.shadowRoot&&on(e.shadowRoot))return true;return false}return on(document)})()"
        do {
            _ = try await transport.call("Runtime.evaluate", parameters: ["expression": "InspectorFrontendAPI.enterInspectElementMode(),true", "returnByValue": true])
            for _ in 0..<20 {
                let data = try await transport.call("Runtime.evaluate", parameters: ["expression": toggled, "returnByValue": true])
                if ((try JSONSerialization.jsonObject(with: data) as? [String: Any])?["result"] as? [String: Any])?["value"] as? Bool == true { break }
                try await Task.sleep(for: .milliseconds(100))
            }
            developerResult = "inspect mode"
        } catch { developerResult = "Element picker failed: \(error)"; return }
        guard ProcessInfo.processInfo.environment["BRK_CONTROL_SOCKET"] != nil else { return }
        let selected = "(()=>{function find(root){for(const e of root.querySelectorAll('li.selected'))if(e.closest('ol.elements-tree-outline, .elements-tree-outline'))return e;for(const e of root.querySelectorAll('*'))if(e.shadowRoot){const r=find(e.shadowRoot);if(r)return r}return null}const li=find(document);return li?li.textContent.replace(/[\\u200b]/g,'').slice(0,160):''})()"
        var baseline: String?
        for _ in 0..<240 {
            guard !Task.isCancelled, engine.isLive(self), toolsBrowser != nil else { return }
            guard let data = try? await transport.call("Runtime.evaluate", parameters: ["expression": selected, "returnByValue": true]),
                  let text = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any]).flatMap({ $0["result"] as? [String: Any] })?["value"] as? String else { return }
            if baseline == nil { baseline = text }
            if text != baseline, !text.isEmpty { developerResult = "inspected: " + text; return }
            try? await Task.sleep(for: .milliseconds(250))
        }
    }

    func closeDeveloperWindows() {
        sourceRequest &+= 1
        sourceWindow?.close(); sourceWindow = nil
        developerPanelTask?.cancel(); developerPanelTask = nil
        developerTransport?.invalidate(); developerTransport = nil
        requestedDeveloperPanel = nil; inspectPickRequested = false; toolsBrowser = nil
        browser.closeDevTools()
    }
}
