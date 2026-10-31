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
            browser.inspectElement(at: CGPoint(x: surface.bounds.midX, y: surface.bounds.midY))
            developerResult = "Inspect requested at page center"
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
                        return
                    }
                } catch { self.developerResult = "Panel selection failed: \(error)"; return }
                do { try await Task.sleep(for: .milliseconds(100)) } catch { return }
            }
            self.developerResult = "DevTools opened; \(panel) selection could not be confirmed"
        }
    }

    func closeDeveloperWindows() {
        sourceRequest &+= 1
        sourceWindow?.close(); sourceWindow = nil
        developerPanelTask?.cancel(); developerPanelTask = nil
        developerTransport?.invalidate(); developerTransport = nil
        requestedDeveloperPanel = nil; toolsBrowser = nil
        browser.closeDevTools()
    }
}
