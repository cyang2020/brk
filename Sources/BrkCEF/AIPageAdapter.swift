import AppKit
import BrkBase
import BrkEngine
import CefKit
import Foundation

extension CEFEngine {
    public func readAIPage(_ document: DocumentToken) async throws -> AIPageContent {
        guard let page = live[document.browser.page], page.incarnation == document.browser,
              page.readyDocument == document, isLive(page), let transport = CefDevTools(browser: page.browser) else { throw AIPageFailure.unavailable }
        defer { transport.invalidate() }
        let world = try await aiWorld(transport)
        try aiFence(page, document)
        let result = try await transport.call("Runtime.evaluate", parameters: ["expression": AIPageScripts.capture, "contextId": world, "returnByValue": true])
        try aiFence(page, document)
        guard let response = try JSONSerialization.jsonObject(with: result) as? [String: Any],
              let remote = response["result"] as? [String: Any], let object = remote["value"] as? [String: Any],
              let text = object["text"] as? String, text.utf8.count <= 100_000,
              let address = object["url"] as? String, let url = URL(string: address),
              ["http", "https"].contains(url.scheme?.lowercased()),
              let title = object["title"] as? String, let language = object["language"] as? String,
              let nodes = object["nodes"] as? [[String: Any]], nodes.count <= 200 else { throw AIPageFailure.invalidReply }
        let parsed = try nodes.map { value -> AITextNode in
            guard let id = value["id"] as? Int, let text = value["text"] as? String, text.count <= 1000 else { throw AIPageFailure.invalidReply }
            return AITextNode(id: id, text: text)
        }
        return AIPageContent(document: document, url: url, title: String(title.prefix(500)), language: String(language.prefix(40)), text: text, nodes: parsed)
    }

    public func translateAIPage(_ content: AIPageContent, replacements: [AITextNode]) async throws -> Bool {
        let document = content.document
        guard let page = live[document.browser.page], page.incarnation == document.browser,
              page.readyDocument == document, isLive(page), let transport = CefDevTools(browser: page.browser) else { throw AIPageFailure.unavailable }
        defer { transport.invalidate() }
        let world = try await aiWorld(transport)
        try aiFence(page, document)
        let data = try JSONSerialization.data(withJSONObject: replacements.map { ["id": $0.id, "text": $0.text] as [String: Any] })
        let expression = AIPageScripts.replace(String(decoding: data, as: UTF8.self))
        let result = try await transport.call("Runtime.evaluate", parameters: ["expression": expression, "contextId": world, "returnByValue": true])
        try aiFence(page, document)
        guard let response = try JSONSerialization.jsonObject(with: result) as? [String: Any], let remote = response["result"] as? [String: Any] else { return false }
        return remote["value"] as? Bool == true
    }

    public func showAITranslation(_ document: DocumentToken, translated: Bool) async -> Bool {
        guard let value = try? await aiEvaluate(document, AIPageScripts.swap(translated: translated)) else { return false }
        return value as? Bool == true
    }

    public func hoveredLink(_ document: DocumentToken, url: URL) async -> HoveredLink? {
        guard let page = live[document.browser.page],
              let data = try? JSONSerialization.data(withJSONObject: [url.absoluteString]),
              let object = try? await aiEvaluate(document, AIPageScripts.hoveredLink(String(decoding: data, as: UTF8.self))) as? [String: Any],
              let x = object["x"] as? Double, let y = object["y"] as? Double, let w = object["w"] as? Double, let h = object["h"] as? Double,
              let ratio = object["ratio"] as? Double, ratio > 0 else { return nil }
        // CSS pixels to points: devicePixelRatio is the backing scale times the page zoom.
        let factor = ratio / (page.surface.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
        return HoveredLink(frame: CGRect(x: x * factor, y: y * factor, width: w * factor, height: h * factor), previewSite: object["site"] as? Bool == true)
    }

    /// The ready document's declared language, read once it finished loading (the URL pill's Translation Available,
    /// the page menu's Translate to English). AI readers and non-web pages are skipped.
    func reportLanguage(_ page: ChromePage) {
        guard !page.isAIReader, let document = page.readyDocument,
              let scheme = page.browser.url?.scheme?.lowercased(), ["http", "https", "file"].contains(scheme) else { return }
        Task { @MainActor [weak self, weak page] in
            guard let self, let page, let value = try? await self.aiEvaluate(document, AIPageScripts.language) as? String,
                  self.isLive(page), page.readyDocument == document else { return }
            page.detectedLanguage = value
            self.pageDidEmit(page, .languageDetected(document, value))
        }
    }

    /// One expression in the main frame's isolated world of `document`, its value returned by value.
    private func aiEvaluate(_ document: DocumentToken, _ expression: String) async throws -> Any? {
        guard let page = live[document.browser.page], page.incarnation == document.browser,
              page.readyDocument == document, isLive(page), let transport = CefDevTools(browser: page.browser) else { throw AIPageFailure.unavailable }
        defer { transport.invalidate() }
        let world = try await aiWorld(transport)
        try aiFence(page, document)
        let result = try await transport.call("Runtime.evaluate", parameters: ["expression": expression, "contextId": world, "returnByValue": true])
        try aiFence(page, document)
        guard let response = try JSONSerialization.jsonObject(with: result) as? [String: Any], let remote = response["result"] as? [String: Any] else { return nil }
        return remote["value"]
    }

    private func aiFence(_ page: ChromePage, _ document: DocumentToken) throws {
        try Task.checkCancellation()
        guard isLive(page), page.readyDocument == document else { throw AIPageFailure.changed }
    }
    private func aiWorld(_ transport: CefDevTools) async throws -> Int {
        let data = try await transport.call("Page.getFrameTree")
        try Task.checkCancellation()
        guard let response = try JSONSerialization.jsonObject(with: data) as? [String: Any], let tree = response["frameTree"] as? [String: Any],
              let frame = tree["frame"] as? [String: Any], let id = frame["id"] as? String else { throw AIPageFailure.unavailable }
        let world = try await transport.call("Page.createIsolatedWorld", parameters: ["frameId": id, "worldName": "brk-ai-text"])
        try Task.checkCancellation()
        guard let response = try JSONSerialization.jsonObject(with: world) as? [String: Any], let context = response["executionContextId"] as? Int else { throw AIPageFailure.unavailable }
        return context
    }
}

/// Runs in an isolated world in the main frame. The capture keeps Node references there, never in page globals.
enum AIPageScripts {
    static let capture = #"""
    (()=>{
      const root=document.querySelector('main,article,[role="main"]')||document.body;
      if(!root)return null;
      const nodes=[],saved=[];let length=0;
      const walker=document.createTreeWalker(root,NodeFilter.SHOW_TEXT);
      let node;
      while((node=walker.nextNode())&&nodes.length<200&&length<24000){
        const e=node.parentElement,t=node.nodeValue;
        if(!e||!t.trim()||t.length>1000||e.isContentEditable||e.closest('script,style,noscript,input,textarea,select,button,svg,canvas,iframe,[hidden],[aria-hidden="true"],[data-private]'))continue;
        const s=getComputedStyle(e);if(s.display==='none'||s.visibility==='hidden'||!e.getClientRects().length)continue;
        if(length+t.length>24000)break;
        const id=nodes.length;nodes.push({id,text:t});saved.push({node,text:t});length+=t.length;
      }
      globalThis.brkAIText=saved;
      return {url:location.href,title:document.title,language:document.documentElement.lang||'',text:nodes.map(x=>x.text).join('\n'),nodes};
    })()
    """#
    /// Writes the translation and keeps, per text node, its own text and the translation (`brkAITranslation`), so
    /// Use Original and ⌘Z can swap them; a node translated again keeps its first own text.
    static func replace(_ json: String) -> String {
        """
        (()=>{const replacements=\(json),saved=globalThis.brkAIText;
        if(!saved||saved.length!==replacements.length)return false;
        const seen=new Set();
        for(const r of replacements){const old=saved[r.id];if(seen.has(r.id)||!old||!old.node.isConnected||old.node.nodeValue!==old.text||old.node.parentElement?.isContentEditable||typeof r.text!=='string')return false;seen.add(r.id);}
        const kept=globalThis.brkAITranslation||(globalThis.brkAITranslation=new Map());
        for(const r of replacements){const old=saved[r.id],entry=kept.get(old.node);kept.set(old.node,{original:entry?entry.original:old.text,translated:r.text});old.node.nodeValue=r.text;}
        globalThis.brkAIText=null;return true;})()
        """
    }
    /// Use Original (`translated` false) and its ⌘Z: every kept node still showing the other text gets this one.
    static func swap(translated: Bool) -> String {
        """
        (()=>{const kept=globalThis.brkAITranslation;if(!kept)return false;let n=0;
        for(const [node,e] of kept){if(!node.isConnected)continue;const from=\(translated)?e.original:e.translated,to=\(translated)?e.translated:e.original;
        if(node.nodeValue!==from)continue;node.nodeValue=to;n++;}return n>0;})()
        """
    }
    static let language = "(document.documentElement.lang||'').trim().slice(0,40)"
    /// The innermost hovered link to the address (`[url]`, JSON), its first line box in CSS pixels and the ratio.
    static func hoveredLink(_ json: String) -> String {
        """
        (()=>{const [want]=\(json);const links=[...document.querySelectorAll('a:hover,area:hover')].filter(a=>a.href===want);
        const a=links.pop();if(!a)return null;const r=a.getClientRects()[0]||a.getBoundingClientRect();
        const site=a.matches(".title .titleline > a,[data-testid=tweetText] a[role=link][target=_blank],[data-testid='card.wrapper'] a[role=link],a[role=link][rel='nofollow noreferrer'][target=_blank]")||!!(a.closest('g-section-with-header')&&a.querySelector('[role=heading]'));
        return {x:r.left,y:r.top,w:r.width,h:r.height,ratio:window.devicePixelRatio||1,site};})()
        """
    }
}
