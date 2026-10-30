import Metal
import XCTest
@testable import BrkDomain
@testable import BrkTheme

/// The crossfade, drawn offscreen and read back: what a space switch shows between two themes.
@MainActor
final class ThemeRendererTests: XCTestCase {
    /// Flat themes (three equal stops) with no texture, so every pixel is exactly gradient x 1, then the wash.
    /// A: (0.2, 0.4, 0.6) under white at 0.25 -> (0.4, 0.55, 0.7). B: (0.8, 0.2, 0.1) under black at 0.1 -> x 0.9.
    private let a = flat(RGBA(0.2, 0.4, 0.6), wash: RGBA(1, 1, 1, 0.25))
    private let b = flat(RGBA(0.8, 0.2, 0.1), wash: RGBA(0, 0, 0, 0.1))
    private let c = flat(RGBA(0, 1, 0), wash: RGBA(1, 1, 1, 0))

    /// Half way through the crossfade the gradient, the texture factor and the wash are each half way between the two
    /// themes (Arc's gradient and overlay passes both take `progress`); at the end the pixel is B's and the renderer
    /// reports the transition over (the display link stops).
    func testCrossfadeMixesBothThemesAndEnds() throws {
        let renderer = try XCTUnwrap(ThemeRenderer(device: MTLCreateSystemDefaultDevice()))
        renderer.transition(to: a, duration: 0, at: 0)
        XCTAssertFalse(try draw(renderer, at: 0).animating)
        assertPixel(try draw(renderer, at: 0).pixel, 102, 140.25, 178.5)

        renderer.transition(to: b, duration: 1, at: 10)
        let start = try draw(renderer, at: 10)
        XCTAssertTrue(start.animating)
        assertPixel(start.pixel, 102, 140.25, 178.5)
        let middle = try draw(renderer, at: 10.5)
        XCTAssertTrue(middle.animating)
        // Gradient (0.5, 0.3, 0.35) x (1 - wash alpha 0.175) + premultiplied wash 0.125 -> (0.5375, 0.3725, 0.41375).
        assertPixel(middle.pixel, 137.06, 94.99, 105.51)
        let end = try draw(renderer, at: 11)
        XCTAssertFalse(end.animating)
        assertPixel(end.pixel, 183.6, 45.9, 22.95)
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

    private static func flat(_ color: RGBA, wash: RGBA) -> ResolvedTheme {
        ResolvedTheme(scheme: .light, gradient: [color, color, color], texture: .grain, textureOpacity: 0, textureContrast: 1,
                      wash: wash, tokens: .light, windowColor: color)
    }

    /// Draws a 16 x 16 px frame at `time` and returns the mean BGRA -> RGB of all its pixels.
    @discardableResult
    private func draw(_ renderer: ThemeRenderer, at time: CFTimeInterval) throws -> (pixel: [Double], animating: Bool) {
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
        var sum = [0.0, 0.0, 0.0]
        for i in stride(from: 0, to: bytes.count, by: 4) {
            sum[0] += Double(bytes[i + 2]); sum[1] += Double(bytes[i + 1]); sum[2] += Double(bytes[i])
        }
        return (sum.map { $0 / 256 }, animating)
    }

    private func assertPixel(_ pixel: [Double], _ r: Double, _ g: Double, _ b: Double, file: StaticString = #filePath, line: UInt = #line) {
        // Half a step of dither and 8-bit rounding.
        XCTAssertEqual(pixel[0], r, accuracy: 1, file: file, line: line)
        XCTAssertEqual(pixel[1], g, accuracy: 1, file: file, line: line)
        XCTAssertEqual(pixel[2], b, accuracy: 1, file: file, line: line)
    }
}
