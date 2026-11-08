import AppKit
import BrkBase
import BrkEngine
import CBrkCore
import Foundation

/// Page capture on BrkCore: CEFEngine's sizes and checks (BrkCEF/PageCaptures.swift, CaptureProbe.swift), the same DevTools commands over the
/// page's own session.
extension CoreEngine {
    public func capture(_ request: CaptureRequest) async throws -> CaptureImage {
        let id = request.document.browser.page
        guard let page = livePage(id), page.context == request.context, page.readyDocument == request.document,
              page.incarnation == request.document.browser, contexts.permitsWork(request.context) else { throw CoreProtocolError(message: "The page is not available") }
        let session = page.protocolSession
        let revision = page.captureRevision
        let zoomLevel = page.contents.zoomLevel
        func valid() throws {
            try Task.checkCancellation()
            guard isLive(page), page.captureRevision == revision, page.contents.zoomLevel == zoomLevel,
                  page.readyDocument == request.document, contexts.permitsWork(request.context) else { throw CoreProtocolError(message: "The page changed during the capture") }
        }
        try valid()
        let metrics = try await session.call("Page.getLayoutMetrics")
        try valid()
        guard let content = metrics["cssContentSize"] as? [String: Double],
              let viewport = metrics["cssVisualViewport"] as? [String: Double],
              let physical = metrics["contentSize"] as? [String: Double],
              let width = content["width"], let height = content["height"], width > 0, height > 0,
              let physicalWidth = physical["width"], let physicalHeight = physical["height"],
              let vw = viewport["clientWidth"], let vh = viewport["clientHeight"] else { throw CoreProtocolError(message: "Missing capture metrics") }
        let scale = height >= width ? physicalHeight / height : physicalWidth / width
        let zoom = viewport["zoom"] ?? pow(1.2, zoomLevel)
        var x = 0.0, y = 0.0, w = width, h = height
        if request.mode != .fullPage {
            guard let region = request.region, region.valid else { throw CoreProtocolError(message: "Choose a capture area") }
            x = (viewport["pageX"] ?? 0) + region.x * vw
            y = (viewport["pageY"] ?? 0) + region.y * vh
            w = region.width * vw; h = region.height * vh
        }
        guard scale.isFinite, scale > 0, zoom.isFinite, zoom > 0, w * scale >= 1, h * scale >= 1, w * scale <= 32768, h * scale <= 32768,
              w * h * scale * scale <= 80_000_000 else { throw CoreProtocolError(message: "Capture exceeds 80 million pixels or 32,768 pixels per side. Choose a smaller area.") }
        let pixelsPerDIP = scale / zoom
        let clipX = floor(x * zoom), clipY = floor(y * zoom)
        let clipW = ceil((x + w) * zoom) - clipX, clipH = ceil((y + h) * zoom) - clipY
        let body = try await session.call("Page.captureScreenshot", ["format": "png", "fromSurface": true, "captureBeyondViewport": true,
                                                                     "clip": ["x": clipX, "y": clipY, "width": clipW, "height": clipH, "scale": 1]])
        try valid()
        guard let encoded = body["data"] as? String, let png = Data(base64Encoded: encoded), let image = NSBitmapImageRep(data: png),
              abs(Double(image.pixelsWide) - clipW * pixelsPerDIP) <= 2, abs(Double(image.pixelsHigh) - clipH * pixelsPerDIP) <= 2 else {
            throw CoreProtocolError(message: "Capture pixels do not match the selected dimensions")
        }
        let pixels = CGRect(x: ((x * zoom - clipX) * pixelsPerDIP).rounded(), y: ((y * zoom - clipY) * pixelsPerDIP).rounded(),
                            width: (w * scale).rounded(), height: (h * scale).rounded())
        if pixels == CGRect(x: 0, y: 0, width: image.pixelsWide, height: image.pixelsHigh) {
            return CaptureImage(png: png, width: image.pixelsWide, height: image.pixelsHigh, scale: scale)
        }
        return try CapturePixels.crop(png, pixels: pixels, scale: scale)
    }

    /// Opt-in control-socket evidence, as on CEF.
    public func captureProbe(_ id: PageID, directory: URL) async throws -> String {
        guard let page = livePage(id), case .profile = page.context, let document = page.readyDocument else { throw CoreProtocolError(message: "The page is not available") }
        let session = page.protocolSession
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let values = try await session.call("Page.getLayoutMetrics")
        try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys]).write(to: directory.appendingPathComponent("metrics.json"))
        guard let size = values["cssContentSize"] as? [String: Any], let width = size["width"] as? Double,
              let height = size["height"] as? Double else { throw CoreProtocolError(message: "no CSS metrics") }
        var result: [String: Any] = ["width": width, "height": height, "browser": "\(page.incarnation.page.description)#\(page.incarnation.generation)"]
        for (name, x, y, w, h) in [("area", 40.0, 80.0, 320.0, 180.0), ("full", 0.0, 0.0, width, height), ("portrait", 0.0, 0.0, min(360, width), min(640, height))] {
            let body = try await session.call("Page.captureScreenshot", ["format": "png", "fromSurface": true, "captureBeyondViewport": true,
                                                                         "clip": ["x": x, "y": y, "width": w, "height": h, "scale": 1]])
            guard page.readyDocument == document, isLive(page), let encoded = body["data"] as? String, let png = Data(base64Encoded: encoded),
                  let image = NSBitmapImageRep(data: png) else { throw CoreProtocolError(message: "The page changed during the probe") }
            try png.write(to: directory.appendingPathComponent(name + ".png"))
            result[name] = ["width": image.pixelsWide, "height": image.pixelsHigh, "bytes": png.count]
        }
        result["webGL"] = try await session.call("Runtime.evaluate", ["expression": "(()=>{const c=document.getElementById('gpu');const g=c?.getContext('webgl2')||c?.getContext('webgl');if(!g)return null;const e=g.getExtension('WEBGL_debug_renderer_info');return {renderer:g.getParameter(e?e.UNMASKED_RENDERER_WEBGL:g.RENDERER),width:g.drawingBufferWidth,height:g.drawingBufferHeight};})()", "returnByValue": true])
        for (name, expression) in [("videoPiP", "await video.requestPictureInPicture(); const active = document.pictureInPictureElement === video; await document.exitPictureInPicture(); return {active};"),
                                   ("documentPiP", "const w = await documentPictureInPicture.requestWindow({width:320,height:180}); const active = !!w; w.close(); return {active};")] {
            let script = "(async()=>{try {const video=document.querySelector('video'); \(expression)} catch(e) {return {error:e.name+': '+e.message, videoEnabled:document.pictureInPictureEnabled, documentAvailable:typeof documentPictureInPicture !== 'undefined'};}})()"
            result[name] = try await session.call("Runtime.evaluate", ["expression": script, "awaitPromise": true, "returnByValue": true, "userGesture": true])
        }
        let json = try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys])
        try json.write(to: directory.appendingPathComponent("probe.json"))
        return String(decoding: json, as: UTF8.self)
    }
}
