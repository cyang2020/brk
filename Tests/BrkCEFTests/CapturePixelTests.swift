import AppKit
import Foundation
import XCTest
@testable import BrkCEF

final class CapturePixelTests: XCTestCase {
    @MainActor func testRealEmbeddedPNGCanBeCroppedWithoutLosingItsColorProfile() throws {
        let fixture = URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("CaptureFixture.png")
        let png = try Data(contentsOf:fixture)
        let crop = try CapturePixels.crop(png,pixels:CGRect(x:825,y:604,width:516,height:376),scale:2)
        XCTAssertEqual(crop.width,516);XCTAssertEqual(crop.height,376)
        let image = try XCTUnwrap(NSBitmapImageRep(data:crop.png)?.cgImage)
        var pixel = [UInt8](repeating:0,count:4)
        pixel.withUnsafeMutableBytes { bytes in
            let context = CGContext(data:bytes.baseAddress,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image,in:CGRect(x:-258,y:-188,width:516,height:376))
        }
        for (actual,want) in zip(pixel.prefix(3),[208,32,48]) { XCTAssertLessThanOrEqual(abs(Int(actual)-want),2,"cropped PNG lost its ICC profile") }
    }
    @MainActor func testCropUsesTopLeftImagePixelsAndRejectsOutOfBounds() throws {
        let fixture = URL(fileURLWithPath:#filePath).deletingLastPathComponent().appendingPathComponent("CaptureFixture.png")
        let png = try Data(contentsOf:fixture)
        let crop = try CapturePixels.crop(png,pixels:CGRect(x:0,y:0,width:100,height:80),scale:2)
        let image = try XCTUnwrap(NSBitmapImageRep(data:crop.png)?.cgImage)
        var pixel = [UInt8](repeating:0,count:4)
        pixel.withUnsafeMutableBytes { bytes in
            let context=CGContext(data:bytes.baseAddress,width:1,height:1,bitsPerComponent:8,bytesPerRow:4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image,in:CGRect(x:-90,y:-40,width:100,height:80))
        }
        XCTAssertGreaterThan(pixel[0],250);XCTAssertEqual(Int(pixel[1]),204,accuracy:2)
        XCTAssertThrowsError(try CapturePixels.crop(png,pixels:CGRect(x:-1,y:0,width:10,height:10),scale:2))
    }
}
