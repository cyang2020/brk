import AppKit
import BrkBase
import BrkEngine
import CBrkCore
import Foundation

/// AI page reading, translation and the page's language on BrkCore: the same isolated-world scripts as CEF's (BrkCEF/AIPageAdapter.swift,
/// copied below while that file is being changed on another branch; they should become one file), over the page's DevTools session.
extension CoreEngine {
    public func readAIPage(_ document: DocumentToken) async throws -> AIPageContent {
        guard let value = try await aiEvaluate(document, CoreAIPageScripts.capture) as? [String: Any],
              let text = value["text"] as? String, text.utf8.count <= 100_000,
              let address = value["url"] as? String, let url = URL(string: address),
              ["http", "https"].contains(url.scheme?.lowercased()),
              let title = value["title"] as? String, let language = value["language"] as? String,
              let nodes = value["nodes"] as? [[String: Any]], nodes.count <= 200 else { throw AIPageFailure.invalidReply }
        let parsed = try nodes.map { value -> AITextNode in
            guard let id = value["id"] as? Int, let text = value["text"] as? String, text.count <= 1000 else { throw AIPageFailure.invalidReply }
            return AITextNode(id: id, text: text)
        }
        return AIPageContent(document: document, url: url, title: String(title.prefix(500)), language: String(language.prefix(40)), text: text, nodes: parsed)
    }

    public func translateAIPage(_ content: AIPageContent, replacements: [AITextNode]) async throws -> Bool {
        let data = try JSONSerialization.data(withJSONObject: replacements.map { ["id": $0.id, "text": $0.text] as [String: Any] })
        return try await aiEvaluate(content.document, CoreAIPageScripts.replace(String(decoding: data, as: UTF8.self))) as? Bool == true
    }

    public func showAITranslation(_ document: DocumentToken, translated: Bool) async -> Bool {
        guard let value = try? await aiEvaluate(document, CoreAIPageScripts.swap(translated: translated)) else { return false }
        return value as? Bool == true
    }

    public func hoveredLink(_ document: DocumentToken, url: URL) async -> HoveredLink? {
        guard let page = livePage(document.browser.page),
              let data = try? JSONSerialization.data(withJSONObject: [url.absoluteString]),
              let object = try? await aiEvaluate(document, CoreAIPageScripts.hoveredLink(String(decoding: data, as: UTF8.self))) as? [String: Any],
              let x = object["x"] as? Double, let y = object["y"] as? Double, let w = object["w"] as? Double, let h = object["h"] as? Double,
              let ratio = object["ratio"] as? Double, ratio > 0 else { return nil }
        let factor = ratio / (page.surface.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
        return HoveredLink(frame: CGRect(x: x * factor, y: y * factor, width: w * factor, height: h * factor), previewSite: object["site"] as? Bool == true)
    }

    /// The ready document's language once it finished loading, as on CEF: its `<html lang>`, else what the delegate recognizes in a sample.
    func reportLanguage(_ page: CorePage) {
        guard !page.isAIReader, let document = page.readyDocument,
              let scheme = page.contents.committedURL?.scheme?.lowercased(), ["http", "https", "file"].contains(scheme) else { return }
        Task { @MainActor [weak self, weak page] in
            guard let self, let page, let probe = try? await self.aiEvaluate(document, CoreAIPageScripts.language) as? [String: Any],
                  self.isLive(page), page.readyDocument == document else { return }
            let finish: @MainActor (String) -> Void = { [weak self, weak page] language in
                guard let self, let page, self.isLive(page), page.readyDocument == document else { return }
                page.detectedLanguage = language
                self.pageDidEmit(page, .languageDetected(document, language))
            }
            if let declared = probe["declared"] as? String, !declared.isEmpty { finish(declared); return }
            let sample = probe["sample"] as? String ?? ""
            guard !sample.isEmpty, let delegate = self.delegate else { finish(""); return }
            delegate.engine(self, recognizeLanguageOf: sample) { finish($0 ?? "") }
        }
    }

    /// One expression in the main frame's isolated world "brk-ai-text" of `document`, its value returned by value.
    private func aiEvaluate(_ document: DocumentToken, _ expression: String) async throws -> Any? {
        guard let page = livePage(document.browser.page), page.incarnation == document.browser,
              page.readyDocument == document, isLive(page) else { throw AIPageFailure.unavailable }
        let session = page.protocolSession
        let tree = try await session.call("Page.getFrameTree")
        try aiFence(page, document)
        guard let frameTree = tree["frameTree"] as? [String: Any], let frame = frameTree["frame"] as? [String: Any],
              let id = frame["id"] as? String else { throw AIPageFailure.unavailable }
        let world = try await session.call("Page.createIsolatedWorld", ["frameId": id, "worldName": "brk-ai-text"])
        try aiFence(page, document)
        guard let context = world["executionContextId"] as? Int else { throw AIPageFailure.unavailable }
        let result = try await session.call("Runtime.evaluate", ["expression": expression, "contextId": context, "returnByValue": true])
        try aiFence(page, document)
        return (result["result"] as? [String: Any])?["value"]
    }

    private func aiFence(_ page: CorePage, _ document: DocumentToken) throws {
        try Task.checkCancellation()
        guard isLive(page), page.readyDocument == document else { throw AIPageFailure.changed }
    }
}

/// Runs in an isolated world in the main frame. The capture keeps Node references there, never in page globals.
enum CoreAIPageScripts {
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
    /// The declared language and, when there is none, up to 2000 characters of what the page shows.
    static let language = #"""
    (()=>{
      const declared=(document.documentElement.lang||'').trim().slice(0,40);
      if(declared)return {declared};
      const root=document.querySelector('main,article,[role="main"]')||document.body;
      return {declared:'',sample:root?(root.innerText||'').replace(/\s+/g,' ').trim().slice(0,2000):''};
    })()
    """#
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
