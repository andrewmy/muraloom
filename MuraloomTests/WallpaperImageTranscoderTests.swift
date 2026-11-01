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

    @Test func downsamplingUsesFullImageInsteadOfEmbeddedThumbnail() throws {
        let image = makeCGImage(width: 1024, height: 768)
        let original = encode(image, as: .jpeg)
        let preview = encode(makeCGImage(width: 160, height: 120), as: .jpeg)
        // EXIF IFD1 points to a deliberately small JPEG preview at TIFF offset 44.
        var exif = Data([
            0x45, 0x78, 0x69, 0x66, 0, 0,
            0x49, 0x49, 42, 0, 8, 0, 0, 0,
            0, 0, 14, 0, 0, 0,
            2, 0,
            1, 2, 4, 0, 1, 0, 0, 0, 44, 0, 0, 0,
            2, 2, 4, 0, 1, 0, 0, 0,
        ])
        var previewLength = UInt32(preview.count).littleEndian
        withUnsafeBytes(of: &previewLength) { exif.append(contentsOf: $0) }
        exif.append(contentsOf: [0, 0, 0, 0])
        exif.append(preview)
        let segmentLength = exif.count + 2
        var data = Data([0xFF, 0xD8, 0xFF, 0xE1, UInt8(segmentLength >> 8), UInt8(segmentLength & 0xFF)])
        data.append(exif)
        data.append(original.dropFirst(2))

        let source = try #require(CGImageSourceCreateWithData(data as CFData, nil))
        let embedded = try #require(CGImageSourceCreateThumbnailAtIndex(source, 0, [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceThumbnailMaxPixelSize: 512,
        ] as CFDictionary))
        #expect(embedded.width < 512)

        let jpeg = try WallpaperImageTranscoder.prepareWallpaperJPEG(from: data as Data, maxDimension: 512)
        let size = try #require(decodePixelSize(jpeg))
        #expect(size.w == 512)
        #expect(size.h == 384)
    }

    @Test func asyncWrapperTranscodesImage() async throws {
        let image = makeCGImage(width: 1024, height: 768)
        let png = encode(image, as: .png)

        let jpeg = try await WallpaperImageTranscoder.prepareWallpaperJPEGAsync(
            from: png,
            maxDimension: 400,
            filenameHint: "photo.png",
            quality: 0.85
        )
        #expect(jpeg.count > 2)
        #expect(jpeg[0] == 0xFF && jpeg[1] == 0xD8)

        let size = try #require(decodePixelSize(jpeg))
        #expect(max(size.w, size.h) <= 400)
    }

    @Test func transcoderErrorDescriptionsAreStable() {
        #expect(WallpaperImageTranscoderError.invalidImageData.errorDescription == "Image decode failed.")
        #expect(WallpaperImageTranscoderError.thumbnailCreationFailed.errorDescription == "Image resize failed.")
        #expect(WallpaperImageTranscoderError.jpegDestinationCreationFailed.errorDescription == "JPEG encoder setup failed.")
        #expect(WallpaperImageTranscoderError.jpegFinalizeFailed.errorDescription == "JPEG encode failed.")
    }

    @Test func supportsRawDecodingMatchesLibRawAvailability() {
        #expect(WallpaperImageTranscoder.supportsRawDecoding == LibRawDecoder.isAvailable())
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

    @Test func recommendedDisplayDimensionHasPositiveFallback() {
        let dimension = WallpaperImageTranscoder.maxRecommendedDisplayPixelDimension()
        #expect(dimension > 0)
        #expect(WallpaperImageTranscoder.maxPhysicalDisplayPixelDimension() == dimension)
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
