import BrkDomain
import Metal
import XCTest
@testable import BrkTheme

@MainActor
final class SpaceToolsThemeTests: XCTestCase {
    func testEditedColorChangesActualMetalPixelsAndFallbackImage() throws {
        let renderer = try XCTUnwrap(ThemeRenderer(device: MTLCreateSystemDefaultDevice()))
        var theme = SpaceTheme.default
        theme.colors = [RGBA(1, 0, 0), RGBA(0, 0, 1)]
        theme.intensity = 0
        theme.variants = ThemeVariants(legacy: theme)
        theme.variants!.selection = .light
        let first = resolveTheme(theme)
        renderer.transition(to: first, duration: 0, at: 0)
        let before = try pixels(renderer)
        theme.variants!.light.colors[0].color = RGBA(0, 1, 0)
        let second = resolveTheme(theme)
        renderer.transition(to: second, duration: 0, at: 1)
        let after = try pixels(renderer)
        XCTAssertGreaterThan(zip(before, after).reduce(0) { $0 + abs(Int($1.0) - Int($1.1)) }, 1_000)
        let fallbackBefore = try XCTUnwrap(ThemeBackgroundView.fallbackImage(first)?.dataProvider?.data) as Data
        let fallbackAfter = try XCTUnwrap(ThemeBackgroundView.fallbackImage(second)?.dataProvider?.data) as Data
        XCTAssertNotEqual(fallbackBefore, fallbackAfter)
    }
    private func pixels(_ renderer: ThemeRenderer) throws -> [UInt8] {
        let descriptor = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: ThemeRenderer.drawableFormat, width: 32, height: 32, mipmapped: false)
        descriptor.usage = [.renderTarget, .shaderRead]; descriptor.storageMode = .shared
        let texture = try XCTUnwrap(renderer.device.makeTexture(descriptor: descriptor))
        let buffer = try XCTUnwrap(renderer.device.makeCommandQueue()?.makeCommandBuffer())
        renderer.encode(into: texture, scale: 1, at: 2, commandBuffer: buffer)
        buffer.commit(); buffer.waitUntilCompleted()
        XCTAssertEqual(buffer.status, .completed)
        var bytes = [UInt8](repeating: 0, count: 32 * 32 * 4)
        texture.getBytes(&bytes, bytesPerRow: 32 * 4, from: MTLRegionMake2D(0, 0, 32, 32), mipmapLevel: 0)
        return bytes
    }
}
