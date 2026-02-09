#!/usr/bin/env swift
import AppKit

struct IconVariant {
    let pixels: Int
    let filename: String
    let simplified: Bool
}

func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    let r = CGFloat((hex >> 16) & 0xFF) / 255.0
    let g = CGFloat((hex >> 8) & 0xFF) / 255.0
    let b = CGFloat(hex & 0xFF) / 255.0
    return NSColor(srgbRed: r, green: g, blue: b, alpha: alpha)
}

func withGState(_ body: () -> Void) {
    NSGraphicsContext.saveGraphicsState()
    body()
    NSGraphicsContext.restoreGraphicsState()
}

func writePNG(_ data: Data, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: [.atomic])
}

func renderPNG(pixels: Int, simplified: Bool) -> Data {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)

    let context = NSGraphicsContext(bitmapImageRep: rep)!
    withGState {
        NSGraphicsContext.current = context
        context.shouldAntialias = true
        context.imageInterpolation = .high

        let size = CGFloat(pixels)
        let rect = NSRect(x: 0, y: 0, width: size, height: size)

        // Background (Tahoe-friendly: vibrant + soft highlights)
        let bgRadius = size * 0.225
        let bgPath = NSBezierPath(roundedRect: rect, xRadius: bgRadius, yRadius: bgRadius)

        // Brighter "Tahoe" gradient (still not neon).
        let bgGradient = NSGradient(
            colorsAndLocations:
                (color(0x2563EB), 0.00), // blue
                (color(0x2CBBC3), 0.55), // bright teal
                (color(0x7C6EE6), 1.00)  // periwinkle
        )!
        bgGradient.draw(in: bgPath, angle: 45)

        // Soft vignette
        withGState {
            let vignette = NSGradient(
                colorsAndLocations:
                    (NSColor.black.withAlphaComponent(0.0), 0.00),
                    (NSColor.black.withAlphaComponent(0.12), 1.00)
            )!
            vignette.draw(in: bgPath, angle: -90)
        }

        // Top-left highlight
        withGState {
            let highlight = NSGradient(
                colorsAndLocations:
                    (NSColor.white.withAlphaComponent(0.28), 0.00),
                    (NSColor.white.withAlphaComponent(0.00), 1.00)
            )!
            let hRect = rect.insetBy(dx: -size * 0.20, dy: -size * 0.20).offsetBy(dx: -size * 0.10, dy: size * 0.16)
            highlight.draw(in: bgPath, relativeCenterPosition: NSPoint(x: hRect.minX, y: hRect.maxY))
        }

        // Subtle border
        color(0xFFFFFF, alpha: 0.10).setStroke()
        bgPath.lineWidth = max(1, size * 0.008)
        bgPath.stroke()

        // Foreground symbol: stacked photos + OneDrive cloud
        // Center the whole mark vertically.
        let symbolCenter = NSPoint(x: size * 0.50, y: size * 0.50)
        let cardW = size * (simplified ? 0.72 : 0.64)
        let cardH = size * (simplified ? 0.56 : 0.48)
        let cardRadius = cardW * 0.14

        func cardPath(in rect: NSRect, includeCutouts: Bool) -> NSBezierPath {
            let outer = NSBezierPath(roundedRect: rect, xRadius: cardRadius, yRadius: cardRadius)
            guard includeCutouts else { return outer }

            let combined = NSBezierPath()
            combined.windingRule = .evenOdd
            combined.append(outer)

            let inner = rect.insetBy(dx: rect.width * 0.14, dy: rect.height * 0.16)

            // Mountain cutout
            let baseY = inner.minY + inner.height * 0.20
            let left = NSPoint(x: inner.minX + inner.width * 0.08, y: baseY)
            let leftPeak = NSPoint(x: inner.minX + inner.width * 0.35, y: inner.minY + inner.height * 0.76)
            let mid = NSPoint(x: inner.minX + inner.width * 0.52, y: inner.minY + inner.height * 0.45)
            let rightPeak = NSPoint(x: inner.minX + inner.width * 0.78, y: inner.minY + inner.height * 0.68)
            let right = NSPoint(x: inner.maxX - inner.width * 0.08, y: baseY)

            let mountain = NSBezierPath()
            mountain.move(to: left)
            mountain.line(to: leftPeak)
            mountain.line(to: mid)
            mountain.line(to: rightPeak)
            mountain.line(to: right)
            mountain.line(to: NSPoint(x: right.x, y: inner.minY + inner.height * 0.06))
            mountain.line(to: NSPoint(x: left.x, y: inner.minY + inner.height * 0.06))
            mountain.close()
            combined.append(mountain)

            // Sun cutout
            let sunD = min(inner.width, inner.height) * 0.16
            let sunRect = NSRect(
                x: inner.minX + inner.width * 0.12,
                y: inner.minY + inner.height * 0.62,
                width: sunD,
                height: sunD
            )
            combined.append(NSBezierPath(ovalIn: sunRect))

            return combined
        }

        func drawCard(rect: NSRect, rotationDegrees: CGFloat, alpha: CGFloat, includeCutouts: Bool) {
            let path = cardPath(in: rect, includeCutouts: includeCutouts)
            var transform = AffineTransform(translationByX: symbolCenter.x, byY: symbolCenter.y)
            transform.rotate(byDegrees: rotationDegrees)
            transform.translate(x: -symbolCenter.x, y: -symbolCenter.y)
            path.transform(using: transform)

            withGState {
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
                shadow.shadowBlurRadius = max(2, size * 0.030)
                shadow.shadowOffset = NSSize(width: 0, height: -size * 0.012)
                shadow.set()

                color(0xFFFFFF, alpha: alpha).setFill()
                path.fill()
            }

            // Glassy highlight stroke
            withGState {
                color(0xFFFFFF, alpha: 0.22).setStroke()
                path.lineWidth = max(1, size * 0.006)
                path.stroke()
            }
        }

        if !simplified {
            let backRect = NSRect(
                x: symbolCenter.x - cardW / 2 - size * 0.045,
                y: symbolCenter.y - cardH / 2,
                width: cardW,
                height: cardH
            )
            drawCard(rect: backRect, rotationDegrees: -9, alpha: 0.74, includeCutouts: false)
        }

        let frontRect = NSRect(
            x: symbolCenter.x - cardW / 2,
            y: symbolCenter.y - cardH / 2,
            width: cardW,
            height: cardH
        )
        drawCard(rect: frontRect, rotationDegrees: 0, alpha: 0.92, includeCutouts: !simplified)

        // OneDrive-ish cloud (simple + bold for small sizes)
        let cloudW = size * (simplified ? 0.40 : 0.34)
        let cloudH = size * (simplified ? 0.24 : 0.20)
        let cloudRect = NSRect(
            x: symbolCenter.x + cardW * 0.10,
            y: symbolCenter.y - cardH * 0.48,
            width: cloudW,
            height: cloudH
        )

        let cloud = NSBezierPath()
        let base = NSRect(x: cloudRect.minX, y: cloudRect.minY, width: cloudRect.width, height: cloudRect.height * 0.62)
        cloud.append(NSBezierPath(roundedRect: base, xRadius: base.height * 0.45, yRadius: base.height * 0.45))
        let c1 = NSRect(x: cloudRect.minX + cloudRect.width * 0.06, y: cloudRect.minY + cloudRect.height * 0.25, width: cloudRect.height * 0.62, height: cloudRect.height * 0.62)
        let c2 = NSRect(x: cloudRect.minX + cloudRect.width * 0.30, y: cloudRect.minY + cloudRect.height * 0.34, width: cloudRect.height * 0.76, height: cloudRect.height * 0.76)
        let c3 = NSRect(x: cloudRect.minX + cloudRect.width * 0.60, y: cloudRect.minY + cloudRect.height * 0.22, width: cloudRect.height * 0.64, height: cloudRect.height * 0.64)
        cloud.append(NSBezierPath(ovalIn: c1))
        cloud.append(NSBezierPath(ovalIn: c2))
        cloud.append(NSBezierPath(ovalIn: c3))

        withGState {
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.18)
            shadow.shadowBlurRadius = max(2, size * 0.022)
            shadow.shadowOffset = NSSize(width: 0, height: -size * 0.010)
            shadow.set()

            color(0xFFFFFF, alpha: 0.96).setFill()
            cloud.fill()
        }
    }

    return rep.representation(using: .png, properties: [:])!
}

let variants: [IconVariant] = [
    .init(pixels: 16, filename: "AppIcon_16.png", simplified: true),
    .init(pixels: 32, filename: "AppIcon_16@2x.png", simplified: true),
    .init(pixels: 32, filename: "AppIcon_32.png", simplified: true),
    .init(pixels: 64, filename: "AppIcon_32@2x.png", simplified: false),
    .init(pixels: 128, filename: "AppIcon_128.png", simplified: false),
    .init(pixels: 256, filename: "AppIcon_128@2x.png", simplified: false),
    .init(pixels: 256, filename: "AppIcon_256.png", simplified: false),
    .init(pixels: 512, filename: "AppIcon_256@2x.png", simplified: false),
    .init(pixels: 512, filename: "AppIcon_512.png", simplified: false),
    .init(pixels: 1024, filename: "AppIcon_512@2x.png", simplified: false),
]

let outputDir = URL(fileURLWithPath: "Muraloom/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
var wroteAny = false
for variant in variants {
    let png = renderPNG(pixels: variant.pixels, simplified: variant.simplified)
    let url = outputDir.appendingPathComponent(variant.filename)
    do {
        try writePNG(png, to: url)
        print("Wrote \(variant.filename)")
        wroteAny = true
    } catch {
        fputs("Failed writing \(url.path): \(error)\n", stderr)
        exit(1)
    }
}

if !wroteAny {
    fputs("No variants written.\n", stderr)
    exit(1)
}
