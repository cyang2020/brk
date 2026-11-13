import Metal
import XCTest
@testable import BrkDomain
@testable import BrkTheme

/// The crossfade, drawn offscreen and read back: what a space switch shows between two themes.
@MainActor
final class ThemeRendererTests: XCTestCase {
    /// Flat themes (three equal stops) with no texture, so every pixel is exactly the gradient at the layer alpha over the
    /// underlay, premultiplied. A: (0.2, 0.4, 0.6) at 0.75 over white at 0.5 -> (0.275, 0.425, 0.575), coverage 0.875.
    /// B: (0.8, 0.2, 0.1) at 0.5 over black at 0.2 -> (0.4, 0.1, 0.05), coverage 0.6. C: opaque green.
    private let a = flat(RGBA(0.2, 0.4, 0.6), alpha: 0.75, underlay: RGBA(1, 1, 1, 0.5))
    private let b = flat(RGBA(0.8, 0.2, 0.1), alpha: 0.5, underlay: RGBA(0, 0, 0, 0.2))
    private let c = flat(RGBA(0, 1, 0), alpha: 1, underlay: RGBA(0, 0, 0, 0))

    /// Half way through the crossfade the gradient, the texture factor and the layer are each half way between the two
    /// themes (Arc's gradient and overlay passes both take `progress`); at the end the pixel is B's and the renderer
    /// reports the transition over (the display link stops).
    func testCrossfadeMixesBothThemesAndEnds() throws {
        let renderer = try XCTUnwrap(ThemeRenderer(device: MTLCreateSystemDefaultDevice()))
        renderer.transition(to: a, duration: 0, at: 0)
        XCTAssertFalse(try draw(renderer, at: 0).animating)
        let first = try draw(renderer, at: 0)
        assertPixel(first.pixel, 70.13, 108.38, 146.63)
        XCTAssertEqual(first.coverage, 223.13, accuracy: 1)

        renderer.transition(to: b, duration: 1, at: 10)
        let start = try draw(renderer, at: 10)
        XCTAssertTrue(start.animating)
        assertPixel(start.pixel, 70.13, 108.38, 146.63)
        let middle = try draw(renderer, at: 10.5)
        XCTAssertTrue(middle.animating)
        // Gradient (0.5, 0.3, 0.35) at alpha 0.625 + underlay half way, 0.0625 -> (0.375, 0.25, 0.28125), coverage 0.7375.
        assertPixel(middle.pixel, 95.63, 63.75, 71.72)
        XCTAssertEqual(middle.coverage, 188.06, accuracy: 1)
        let end = try draw(renderer, at: 11)
        XCTAssertFalse(end.animating)
        assertPixel(end.pixel, 102, 25.5, 12.75)
        XCTAssertEqual(end.coverage, 153, accuracy: 1)
    }

    /// A switch during a crossfade starts from what is on screen (no jump), then fades to the new theme.
    func testAnInterruptingSwitchContinuesFromTheScreen() throws {
        let renderer = try XCTUnwrap(ThemeRenderer(device: MTLCreateSystemDefaultDevice()))
        renderer.transition(to: a, duration: 0, at: 0)
        try draw(renderer, at: 0)
        renderer.transition(to: b, duration: 1, at: 10)
        try draw(renderer, at: 10)
        let shown = try draw(renderer, at: 10.5).pixel
        renderer.transition(to: c, duration: 1, at: 10.5)
        assertPixel(try draw(renderer, at: 10.5).pixel, shown[0], shown[1], shown[2])
        assertPixel(try draw(renderer, at: 11.5).pixel, 0, 255, 0)
    }

    private static func flat(_ color: RGBA, alpha: Double, underlay: RGBA) -> ResolvedTheme {
        var theme = ResolvedTheme(scheme: .light, gradient: [color, color, color], texture: .grain, textureOpacity: 0, textureContrast: 1,
                                  wash: RGBA(0, 0, 0, 0), tokens: .light, windowColor: color)
        theme.layerAlpha = alpha
        theme.underlay = underlay
        return theme
    }

    /// Draws a 16 x 16 px frame at `time` and returns the mean BGRA -> RGB (premultiplied) and alpha of all its pixels.
    @discardableResult
    private func draw(_ renderer: ThemeRenderer, at time: CFTimeInterval) throws -> (pixel: [Double], coverage: Double, animating: Bool) {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: ThemeRenderer.drawableFormat, width: 16, height: 16,
                                                                  mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]
        descriptor.storageMode = .shared
        let texture = try XCTUnwrap(renderer.device.makeTexture(descriptor: descriptor))
        let commandBuffer = try XCTUnwrap(renderer.device.makeCommandQueue()?.makeCommandBuffer())
        let animating = renderer.encode(into: texture, scale: 1, at: time, commandBuffer: commandBuffer)
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        var bytes = [UInt8](repeating: 0, count: 16 * 16 * 4)
        texture.getBytes(&bytes, bytesPerRow: 16 * 4, from: MTLRegionMake2D(0, 0, 16, 16), mipmapLevel: 0)
        var sum = [0.0, 0.0, 0.0, 0.0]
        for i in stride(from: 0, to: bytes.count, by: 4) {
            sum[0] += Double(bytes[i + 2]); sum[1] += Double(bytes[i + 1]); sum[2] += Double(bytes[i]); sum[3] += Double(bytes[i + 3])
        }
        return (Array(sum.prefix(3)).map { $0 / 256 }, sum[3] / 256, animating)
    }

    private func assertPixel(_ pixel: [Double], _ r: Double, _ g: Double, _ b: Double, file: StaticString = #filePath, line: UInt = #line) {
        // Half a step of dither and 8-bit rounding.
        XCTAssertEqual(pixel[0], r, accuracy: 1, file: file, line: line)
        XCTAssertEqual(pixel[1], g, accuracy: 1, file: file, line: line)
        XCTAssertEqual(pixel[2], b, accuracy: 1, file: file, line: line)
    }
}
