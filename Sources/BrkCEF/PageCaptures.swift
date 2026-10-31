import AppKit
import BrkBase
import CefKit
import Foundation

extension CEFEngine {
    public func capture(_ request: CaptureRequest) async throws -> CaptureImage {
        let id = request.document.browser.page
        guard let page = live[id], page.context == request.context, page.readyDocument == request.document,
              page.incarnation == request.document.browser, contexts.permitsWork(request.context),
              let channel = CefDevTools(browser: page.browser) else { throw CefDevTools.Failure.unavailable }
        defer { channel.invalidate() }
        func valid() throws {
            try Task.checkCancellation()
            guard isLive(page), page.readyDocument == request.document, contexts.permitsWork(request.context) else { throw CefDevTools.Failure.detached }
        }
        try valid()
        let metricsData = try await channel.call("Page.getLayoutMetrics")
        try valid()
        guard let metrics = try JSONSerialization.jsonObject(with: metricsData) as? [String: Any],
              let content = metrics["cssContentSize"] as? [String: Double],
              let viewport = metrics["cssVisualViewport"] as? [String: Double],
              let physical = metrics["contentSize"] as? [String: Double],
              let width = content["width"], let height = content["height"], width > 0, height > 0,
              let physicalWidth = physical["width"], let vw = viewport["clientWidth"], let vh = viewport["clientHeight"] else { throw CefDevTools.Failure.protocolError("Missing capture metrics") }
        let scale = physicalWidth / width
        var x = 0.0, y = 0.0, w = width, h = height
        if request.mode != .fullPage {
            guard let region = request.region, region.valid else { throw CefDevTools.Failure.protocolError("Choose a capture area") }
            x = (viewport["pageX"] ?? 0) + region.x * vw
            y = (viewport["pageY"] ?? 0) + region.y * vh
            w = region.width * vw; h = region.height * vh
        }
        // Bound renderer allocation before requesting bytes. Never silently truncate a long page.
        guard scale.isFinite, scale > 0, w >= 1, h >= 1, w * scale <= 32768, h * scale <= 32768,
              w * h * scale * scale <= 80_000_000 else { throw CefDevTools.Failure.protocolError("Capture exceeds 80 million pixels or 32,768 pixels per side. Choose a smaller area.") }
        let data = try await channel.call("Page.captureScreenshot", parameters: ["format":"png", "fromSurface":true,
            "captureBeyondViewport":true, "clip":["x":x,"y":y,"width":w,"height":h,"scale":1]])
        try valid()
        guard let body = try JSONSerialization.jsonObject(with: data) as? [String: Any], let encoded = body["data"] as? String,
              let png = Data(base64Encoded: encoded), let image = NSBitmapImageRep(data: png),
              abs(Double(image.pixelsWide) - w * scale) <= 2, abs(Double(image.pixelsHigh) - h * scale) <= 2 else {
            throw CefDevTools.Failure.protocolError("Capture pixels do not match the selected dimensions")
        }
        return CaptureImage(png: png, width: image.pixelsWide, height: image.pixelsHigh, scale: scale)
    }
}
