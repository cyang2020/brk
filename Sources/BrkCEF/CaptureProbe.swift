import AppKit
import BrkBase
import CefKit
import Foundation

extension CEFEngine {
    /// Opt-in control-socket evidence. Uses the same embedded page and shared request allocator as production.
    public func captureProbe(_ id: PageID, directory: URL) async throws -> String {
        guard let page = live[id], case .profile = page.context, let document = page.readyDocument,
              let channel = CefDevTools(browser: page.browser) else { throw CefDevTools.Failure.unavailable }
        defer { channel.invalidate() }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let metrics = try await channel.call("Page.getLayoutMetrics")
        try metrics.write(to: directory.appendingPathComponent("metrics.json"))
        guard let values = try JSONSerialization.jsonObject(with: metrics) as? [String: Any],
              let size = values["cssContentSize"] as? [String: Any], let width = size["width"] as? Double,
              let height = size["height"] as? Double else { throw CefDevTools.Failure.protocolError("no CSS metrics") }
        var result: [String: Any] = ["width": width, "height": height, "browser": "\(page.incarnation.page.description)#\(page.incarnation.generation)"]
        for (name, x, y, w, h) in [("area", 40.0, 80.0, 320.0, 180.0), ("full", 0.0, 0.0, width, height), ("portrait", 0.0, 0.0, min(360, width), min(640, height))] {
            let response = try await channel.call("Page.captureScreenshot", parameters: ["format": "png", "fromSurface": true,
                "captureBeyondViewport": true, "clip": ["x": x, "y": y, "width": w, "height": h, "scale": 1]])
            guard page.readyDocument == document, isLive(page),
                  let body = try JSONSerialization.jsonObject(with: response) as? [String: Any],
                  let encoded = body["data"] as? String, let png = Data(base64Encoded: encoded),
                  let image = NSBitmapImageRep(data: png) else { throw CefDevTools.Failure.detached }
            try png.write(to: directory.appendingPathComponent(name + ".png"))
            result[name] = ["width": image.pixelsWide, "height": image.pixelsHigh, "bytes": png.count]
        }
        let gpu = try await channel.call("Runtime.evaluate", parameters: ["expression":"(()=>{const c=document.getElementById('gpu');const g=c?.getContext('webgl2')||c?.getContext('webgl');if(!g)return null;const e=g.getExtension('WEBGL_debug_renderer_info');return {renderer:g.getParameter(e?e.UNMASKED_RENDERER_WEBGL:g.RENDERER),width:g.drawingBufferWidth,height:g.drawingBufferHeight};})()", "returnByValue":true])
        result["webGL"] = try JSONSerialization.jsonObject(with:gpu)
        for (name, expression) in [("videoPiP", "await video.requestPictureInPicture(); const active = document.pictureInPictureElement === video; await document.exitPictureInPicture(); return {active};"),
                                    ("documentPiP", "const w = await documentPictureInPicture.requestWindow({width:320,height:180}); const active = !!w; w.close(); return {active};")] {
            let script = "(async()=>{try {const video=document.querySelector('video'); \(expression)} catch(e) {return {error:e.name+': '+e.message, videoEnabled:document.pictureInPictureEnabled, documentAvailable:typeof documentPictureInPicture !== 'undefined'};}})()"
            let response = try await channel.call("Runtime.evaluate", parameters: ["expression": script, "awaitPromise": true, "returnByValue": true, "userGesture": true])
            result[name] = try JSONSerialization.jsonObject(with: response)
        }
        let json = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        try json.write(to: directory.appendingPathComponent("probe.json"))
        return String(decoding: json, as: UTF8.self)
    }
}
