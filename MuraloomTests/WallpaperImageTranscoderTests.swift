import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
@testable import Muraloom

struct WallpaperImageTranscoderTests {
    private func makeCGImage(width: Int, height: Int) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 0, count: bytesPerRow * height)

        for y in 0..<height {
            for x in 0..<width {
                let i = y * bytesPerRow + x * 4
                bytes[i + 0] = 0x80
                bytes[i + 1] = 0xC0
                bytes[i + 2] = 0xFF
                bytes[i + 3] = 0xFF
            }
        }

        let data = Data(bytes)
        let provider = CGDataProvider(data: data as CFData)!
        return CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )!
    }

    private func encode(_ image: CGImage, as type: UTType) -> Data {
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
        return out as Data
    }

    private func decodePixelSize(_ data: Data) -> (w: Int, h: Int)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return nil }
        guard let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        else { return nil }
        return (w, h)
    }

    @Test func transcodesTIFFToJPEG() throws {
        let image = makeCGImage(width: 1, height: 1)
        let tiff = encode(image, as: .tiff)

        let jpeg = try WallpaperImageTranscoder.prepareWallpaperJPEG(from: tiff, maxDimension: 512)
        #expect(jpeg.count > 2)
        #expect(jpeg[0] == 0xFF && jpeg[1] == 0xD8)
    }

    @Test func downscalesWhenLargerThanMaxDimension() throws {
        let image = makeCGImage(width: 1024, height: 768)
        let png = encode(image, as: .png)

        let jpeg = try WallpaperImageTranscoder.prepareWallpaperJPEG(from: png, maxDimension: 512)
        let size = try #require(decodePixelSize(jpeg))
        #expect(max(size.w, size.h) <= 512)
    }

    @Test func throwsOnInvalidData() {
        let bytes = Data("not an image".utf8)
        #expect(throws: (any Error).self) {
            _ = try WallpaperImageTranscoder.prepareWallpaperJPEG(from: bytes, maxDimension: 512)
        }
    }

    @Test func rawUnsupportedThrowsClearErrorWhenLibRawDisabled() throws {
        guard LibRawDecoder.isAvailable() == false else {
            // CI/local builds with LibRaw enabled will attempt a real decode; skip here.
            return
        }

        let bytes = Data("not a raw".utf8)
        do {
            _ = try WallpaperImageTranscoder.prepareWallpaperJPEG(from: bytes, maxDimension: 512, filenameHint: "x.arw")
            #expect(Bool(false))
        } catch {
            #expect(error.localizedDescription.contains("RAW photos aren’t supported"))
        }
    }

    @Test func parsesPreferredTimingFromEDID() {
        var edid = Data(repeating: 0, count: 128)
        let base = 54

        // Pixel clock (non-zero to indicate DTD).
        edid[base] = 0x01
        edid[base + 1] = 0x00

        // Horizontal active 3840 (0x0F00).
        edid[base + 2] = 0x00
        edid[base + 4] = 0xF0

        // Vertical active 2160 (0x0870).
        edid[base + 5] = 0x70
        edid[base + 7] = 0x80

        let parsed = WallpaperImageTranscoder.parsePreferredTimingPixels(edid: edid)
        #expect(parsed?.w == 3840)
        #expect(parsed?.h == 2160)
    }
}
