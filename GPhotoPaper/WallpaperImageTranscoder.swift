import AppKit
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import IOKit.graphics
import UniformTypeIdentifiers

enum WallpaperImageTranscoderError: Error, LocalizedError {
    case invalidImageData
    case thumbnailCreationFailed
    case jpegDestinationCreationFailed
    case jpegFinalizeFailed

    var errorDescription: String? {
        switch self {
        case .invalidImageData:
            return "Image decode failed."
        case .thumbnailCreationFailed:
            return "Image resize failed."
        case .jpegDestinationCreationFailed:
            return "JPEG encoder setup failed."
        case .jpegFinalizeFailed:
            return "JPEG encode failed."
        }
    }
}

enum WallpaperImageTranscoder {
    private static let rawExtensions: Set<String> = [
        "arw", "dng", "cr2", "nef", "raf", "orf", "rw2",
    ]

    static var supportsRawDecoding: Bool {
        LibRawDecoder.isAvailable()
    }

    private actor TranscodeActor {
        func transcode(
            _ data: Data,
            maxDimension: Int,
            filenameHint: String?,
            quality: Double
        ) throws -> Data {
            try Task.checkCancellation()
            let result = try WallpaperImageTranscoder.prepareWallpaperJPEG(
                from: data,
                maxDimension: maxDimension,
                filenameHint: filenameHint,
                quality: quality
            )
            try Task.checkCancellation()
            return result
        }
    }

    private static let transcodeActor = TranscodeActor()

    static func prepareWallpaperJPEGAsync(
        from data: Data,
        maxDimension: Int,
        filenameHint: String? = nil,
        quality: Double = 0.9
    ) async throws -> Data {
        try await transcodeActor.transcode(
            data,
            maxDimension: max(1, maxDimension),
            filenameHint: filenameHint,
            quality: quality
        )
    }

    private struct DisplayModeInfo: Sendable {
        let width: Int
        let height: Int
        let pixelWidth: Int
        let pixelHeight: Int

        var isSane: Bool {
            width > 0 && height > 0 && width <= 20000 && height <= 20000
        }

        var looksNonHiDPI: Bool {
            abs(pixelWidth - width) <= 1 && abs(pixelHeight - height) <= 1
        }

        var area: Int {
            width * height
        }

        var maxDimension: Int {
            max(width, height)
        }
    }

    private static func displayId(for screen: NSScreen) -> CGDirectDisplayID? {
        let value = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")]
        if let n = value as? NSNumber {
            return CGDirectDisplayID(n.uint32Value)
        }
        if let n = value as? Int {
            return CGDirectDisplayID(UInt32(clamping: n))
        }
        if let n = value as? UInt32 {
            return CGDirectDisplayID(n)
        }
        return nil
    }

    private static func logicalPixels(for screen: NSScreen) -> (w: Int, h: Int) {
        // NSScreen.frame is in points; on macOS this corresponds to the user-facing “Looks like …” resolution.
        let w = Int(screen.frame.width.rounded())
        let h = Int(screen.frame.height.rounded())
        return (max(0, w), max(0, h))
    }

    private static func activeDisplayIds() -> [CGDirectDisplayID] {
        var displayCount: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &displayCount) == .success, displayCount > 0 else {
            return []
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        guard CGGetActiveDisplayList(displayCount, &displays, &displayCount) == .success else {
            return []
        }

        return Array(displays.prefix(Int(displayCount)))
    }

    private static func sizingDisplayIds() -> [CGDirectDisplayID] {
        var ids = Set<CGDirectDisplayID>()

        for id in activeDisplayIds() {
            ids.insert(id)
        }

        for screen in NSScreen.screens {
            if let id = displayId(for: screen) {
                ids.insert(id)
            }
        }

        return Array(ids)
    }

    private static func bestPanelPixels(from modes: [DisplayModeInfo]) -> (w: Int, h: Int)? {
        let sane = modes.filter(\.isSane)
        guard sane.isEmpty == false else { return nil }

        let nonHiDPI = sane.filter(\.looksNonHiDPI)
        let candidates = nonHiDPI.isEmpty ? sane : nonHiDPI

        guard let best = candidates.max(by: { a, b in
            if a.area != b.area { return a.area < b.area }
            if a.maxDimension != b.maxDimension { return a.maxDimension < b.maxDimension }
            return a.width < b.width
        }) else { return nil }

        return (best.width, best.height)
    }

    private static func physicalPixels(for displayId: CGDirectDisplayID) -> (w: Int, h: Int) {
        if let preferred = preferredTimingPixels(for: displayId) {
            return preferred
        }

        if let modesArray = CGDisplayCopyAllDisplayModes(displayId, nil) {
            let modes = (modesArray as NSArray).map { $0 as! CGDisplayMode }
            let infos = modes.map { mode in
                DisplayModeInfo(
                    width: mode.width,
                    height: mode.height,
                    pixelWidth: mode.pixelWidth,
                    pixelHeight: mode.pixelHeight
                )
            }

            if let best = bestPanelPixels(from: infos) {
                return best
            }
        }

        // Fallback: avoid HiDPI backing-buffer pixel sizes (e.g. 2976→5952) that can exceed a panel’s
        // physical pixel width. Using mode.width/height keeps us in the “Looks like …” space.
        if let mode = CGDisplayCopyDisplayMode(displayId) {
            return (max(0, mode.width), max(0, mode.height))
        }

        return (0, 0)
    }

    private static func preferredTimingPixels(for displayId: CGDirectDisplayID) -> (w: Int, h: Int)? {
        guard let service = ioService(for: displayId) else { return nil }
        defer { IOObjectRelease(service) }

        let info = IODisplayCreateInfoDictionary(service, 0).takeRetainedValue() as NSDictionary
        guard let edid = info[kIODisplayEDIDKey] as? Data, edid.count >= 128 else {
            return nil
        }

        return parsePreferredTimingPixels(edid: edid)
    }

    private static func ioService(for displayId: CGDirectDisplayID) -> io_service_t? {
        let vendor = CGDisplayVendorNumber(displayId)
        let product = CGDisplayModelNumber(displayId)
        let serial = CGDisplaySerialNumber(displayId)

        guard let matching = IOServiceMatching("IODisplayConnect") as NSMutableDictionary? else {
            return nil
        }

        matching["DisplayVendorID"] = NSNumber(value: vendor)
        matching["DisplayProductID"] = NSNumber(value: product)
        if serial != 0 {
            matching["DisplaySerialNumber"] = NSNumber(value: serial)
        }

        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iterator) }

        let service = IOIteratorNext(iterator)
        return service != 0 ? service : nil
    }

    static func parsePreferredTimingPixels(edid: Data) -> (w: Int, h: Int)? {
        guard edid.count >= 128 else { return nil }

        // EDID detailed timing descriptors (DTDs) start at byte 54, 4 blocks × 18 bytes.
        // Prefer the first descriptor with a non-zero pixel clock (a real timing block).
        for i in 0..<4 {
            let base = 54 + (i * 18)
            guard edid.count >= base + 18 else { continue }

            let pixelClockLSB = edid[base]
            let pixelClockMSB = edid[base + 1]
            if pixelClockLSB == 0 && pixelClockMSB == 0 {
                continue
            }

            let hActiveLSB = Int(edid[base + 2])
            let hHigh = Int(edid[base + 4])
            let hActiveMSB = (hHigh & 0xF0) >> 4

            let vActiveLSB = Int(edid[base + 5])
            let vHigh = Int(edid[base + 7])
            let vActiveMSB = (vHigh & 0xF0) >> 4

            let hActive = (hActiveMSB << 8) | hActiveLSB
            let vActive = (vActiveMSB << 8) | vActiveLSB

            if hActive > 0, vActive > 0, hActive <= 20000, vActive <= 20000 {
                return (hActive, vActive)
            }
        }

        return nil
    }

    static func debugRecommendedWidths() -> (logicalMax: Int, physicalMax: Int, recommended: Int) {
        let logicalMax = NSScreen.screens.map { logicalPixels(for: $0).w }.max() ?? 0
        let physicalMax = sizingDisplayIds().map { physicalPixels(for: $0).w }.max() ?? 0
        return (logicalMax, physicalMax, max(logicalMax, physicalMax))
    }

    static func maxRecommendedDisplayPixelWidth() -> Int {
        let logicalMax = NSScreen.screens.map { logicalPixels(for: $0).w }.max() ?? 0
        let physicalMax = sizingDisplayIds().map { physicalPixels(for: $0).w }.max() ?? 0
        let recommended = max(logicalMax, physicalMax)
        return recommended > 0 ? recommended : Int(NSScreen.main?.frame.width ?? 1920)
    }

    static func maxRecommendedDisplayPixelDimension() -> Int {
        let logicalMax = NSScreen.screens.map { screen in
            let logical = logicalPixels(for: screen)
            return max(logical.w, logical.h)
        }.max() ?? 0

        let physicalMax = sizingDisplayIds().map { id in
            let physical = physicalPixels(for: id)
            return max(physical.w, physical.h)
        }.max() ?? 0

        let recommended = max(logicalMax, physicalMax)
        return recommended > 0 ? recommended : Int(NSScreen.main?.frame.width ?? 1920)
    }

    // Back-compat: previous API name. Keep it, but make it match the current “recommended” behavior
    // (avoid using HiDPI backing-buffer sizes that can exceed the panel's physical pixel size).
    static func maxPhysicalDisplayPixelDimension() -> Int {
        maxRecommendedDisplayPixelDimension()
    }

    static func prepareWallpaperJPEG(
        from data: Data,
        maxDimension: Int,
        filenameHint: String? = nil,
        quality: Double = 0.9
    ) throws -> Data {
        let extHint: String? = filenameHint.flatMap { name -> String? in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.isEmpty == false else { return nil }
            let ext = (trimmed as NSString).pathExtension
            return ext.isEmpty ? nil : ext.lowercased()
        }

        if let extHint, rawExtensions.contains(extHint) {
            guard LibRawDecoder.isAvailable() else {
                throw NSError(
                    domain: "WallpaperImageTranscoder",
                    code: 100,
                    userInfo: [NSLocalizedDescriptionKey: "RAW photos aren’t supported in this build (type: \(extHint))."]
                )
            }

            do {
                return try LibRawDecoder.decodeRAW(
                    toJPEGData: data,
                    maxDimension: max(1, maxDimension),
                    quality: quality
                )
            } catch {
                throw NSError(
                    domain: "WallpaperImageTranscoder",
                    code: 101,
                    userInfo: [NSLocalizedDescriptionKey: "\(error.localizedDescription) (type: \(extHint))."]
                )
            }
        }

        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw WallpaperImageTranscoderError.invalidImageData
        }

        let sourceType = (CGImageSourceGetType(source) as String?).flatMap(UTType.init)
        let typeLabel = extHint ?? sourceType?.preferredFilenameExtension ?? sourceType?.identifier ?? "unknown"

        let imageCount = max(1, CGImageSourceGetCount(source))

        func properties(at index: Int) -> [CFString: Any]? {
            CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        }

        // Prefer index 0, but RAW-ish formats can expose multiple images (embedded preview, thumbnails, etc).
        let props = properties(at: 0) ?? (0..<imageCount).lazy.compactMap { properties(at: $0) }.first
        let width = (props?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue
        let height = (props?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue
        let orientationRaw = (props?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        let orientation = Int32(orientationRaw)

        if let sourceType,
           sourceType.conforms(to: .jpeg),
           let width,
           let height,
           max(width, height) <= maxDimension {
            return data
        }

        let maxDimension = max(1, maxDimension)
        func thumbnailOptionsPreferEmbedded(applyTransform: Bool) -> [CFString: Any] {
            [
                // Prefer embedded thumbnails/previews when present (important for RAW formats like ARW
                // where generating a thumbnail from the full image can fail).
                kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
                kCGImageSourceCreateThumbnailWithTransform: applyTransform,
                kCGImageSourceThumbnailMaxPixelSize: maxDimension,
                kCGImageSourceShouldCache: false,
            ]
        }

        func thumbnailOptionsForceDecode(applyTransform: Bool) -> [CFString: Any] {
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: applyTransform,
                kCGImageSourceThumbnailMaxPixelSize: maxDimension,
                kCGImageSourceShouldCache: false,
            ]
        }

        func createThumbnail(at index: Int) -> CGImage? {
            // First: use embedded thumbnail/preview (best-effort, avoids decoding RAW).
            CGImageSourceCreateThumbnailAtIndex(source, index, thumbnailOptionsPreferEmbedded(applyTransform: true) as CFDictionary)
                ?? CGImageSourceCreateThumbnailAtIndex(source, index, thumbnailOptionsPreferEmbedded(applyTransform: false) as CFDictionary)
                // Fallback: force decoding the image to generate a thumbnail.
                ?? CGImageSourceCreateThumbnailAtIndex(source, index, thumbnailOptionsForceDecode(applyTransform: true) as CFDictionary)
                ?? CGImageSourceCreateThumbnailAtIndex(source, index, thumbnailOptionsForceDecode(applyTransform: false) as CFDictionary)
        }

        let thumbnail: CGImage? = {
            for i in 0..<imageCount {
                if let t = createThumbnail(at: i) {
                    return t
                }
            }
            return nil
        }()

        let decoded: CGImage
        if let thumbnail {
            decoded = thumbnail
        } else if let rawDecoded = decodeRawWithCoreImage(
            data: data,
            maxDimension: maxDimension,
            orientation: orientation,
            pixelWidth: width,
            pixelHeight: height,
            fileExtensionHint: extHint
        ) {
            decoded = rawDecoded
        } else {
            let imageOptions: [CFString: Any] = [
                kCGImageSourceShouldCache: false,
            ]

            let full: CGImage? = {
                for i in 0..<imageCount {
                    if let image = CGImageSourceCreateImageAtIndex(source, i, imageOptions as CFDictionary) {
                        return image
                    }
                }
                return nil
            }()

            guard let full else {
                throw NSError(
                    domain: "WallpaperImageTranscoder",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Image resize failed (type: \(typeLabel))."]
                )
            }

            // If we couldn't downsample at decode-time, do a fallback resize via Core Image.
            let srcW = full.width
            let srcH = full.height
            let srcMax = max(srcW, srcH)
            let scale = srcMax > maxDimension ? (Double(maxDimension) / Double(srcMax)) : 1.0

            let ci = CIImage(cgImage: full).oriented(forExifOrientation: orientation)
            let scaled = scale < 1.0
                ? ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
                : ci

            let context = CIContext(options: nil)
            guard let out = context.createCGImage(scaled, from: scaled.extent) else {
                throw NSError(
                    domain: "WallpaperImageTranscoder",
                    code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Image resize failed (type: \(typeLabel))."]
                )
            }
            decoded = out
        }

        let outData = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(outData, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw WallpaperImageTranscoderError.jpegDestinationCreationFailed
        }

        let finalImage: CGImage = {
            // JPEG doesn't support alpha; ensure we encode an opaque image to avoid unexpected results.
            let alpha = decoded.alphaInfo
            let hasAlpha = alpha == .first || alpha == .last || alpha == .premultipliedFirst || alpha == .premultipliedLast
            guard hasAlpha else { return decoded }

            let w = decoded.width
            let h = decoded.height
            guard let ctx = CGContext(
                data: nil,
                width: w,
                height: h,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else {
                return decoded
            }

            ctx.setFillColor(CGColor(red: 0, green: 0, blue: 0, alpha: 1))
            ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
            ctx.draw(decoded, in: CGRect(x: 0, y: 0, width: w, height: h))
            return ctx.makeImage() ?? decoded
        }()

        let destOptions: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: min(1.0, max(0.0, quality)),
        ]
        CGImageDestinationAddImage(dest, finalImage, destOptions as CFDictionary)

        guard CGImageDestinationFinalize(dest) else {
            throw WallpaperImageTranscoderError.jpegFinalizeFailed
        }

        return outData as Data
    }

    private static func decodeRawWithCoreImage(
        data: Data,
        maxDimension: Int,
        orientation: Int32,
        pixelWidth: Int?,
        pixelHeight: Int?,
        fileExtensionHint: String?
    ) -> CGImage? {
        // Many camera RAW formats (including ARW) are TIFF-based; ImageIO thumbnailing can fail with paramErr (-50).
        // Core Image's RAW decoder tends to be more reliable for these.
        var options: [CIRAWFilterOption: Any] = [
            .allowDraftMode: true,
        ]

        if let pixelWidth, let pixelHeight, pixelWidth > 0, pixelHeight > 0 {
            let srcMax = max(pixelWidth, pixelHeight)
            if srcMax > maxDimension {
                options[.scaleFactor] = CGFloat(maxDimension) / CGFloat(srcMax)
            }
        }

        var tempURL: URL?
        defer {
            if let tempURL {
                try? FileManager.default.removeItem(at: tempURL)
            }
        }

        let rawFilter: CIRAWFilter? = {
            if let filter = CIRAWFilter(imageData: data, options: options) {
                return filter
            }

            // Some RAW decoders are more reliable when loading from a URL with the right extension.
            guard let ext = fileExtensionHint, ext.isEmpty == false else {
                return nil
            }

            let dir = FileManager.default.temporaryDirectory
            let url = dir.appendingPathComponent("gphotopaper-raw-\(UUID().uuidString).\(ext)")
            do {
                try data.write(to: url, options: [.atomic])
                tempURL = url
                return CIRAWFilter(imageURL: url, options: options)
            } catch {
                return nil
            }
        }()

        guard let rawFilter else { return nil }

        guard let output = rawFilter.outputImage else {
            return nil
        }

        // Some RAWs log `-[CIImage imageBySettingProperties:] properties is not a NSDictionary.` when applying
        // EXIF orientation. For MVP reliability, skip orientation for RAW decode.
        let oriented = output
        let extent = oriented.extent.integral
        guard extent.isEmpty == false else {
            return nil
        }

        let srcMax = max(extent.width, extent.height)
        let maxDim = CGFloat(max(1, maxDimension))
        let scale = srcMax > maxDim ? (maxDim / srcMax) : 1.0
        let scaled = scale < 1.0
            ? oriented.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            : oriented

        let context = CIContext(options: nil)
        return context.createCGImage(scaled, from: scaled.extent)
    }
}
