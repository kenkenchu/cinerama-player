#!/usr/bin/env swift
import AppKit

// Package the Cinerama West Coast master into native TV icon layers. The
// foreground stays transparent; the platform supplies masking and parallax.
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let sourceURL = root.appendingPathComponent("Dusk/Resources/DuskIcon.icon/Assets/cinerama-west-coast.png")
let catalog = root.appendingPathComponent("DuskTV/Resources/Assets.xcassets/TVIcon.brandassets")
guard let source = NSImage(contentsOf: sourceURL),
      let sourceData = try? Data(contentsOf: sourceURL),
      let sourceBitmap = NSBitmapImageRep(data: sourceData) else {
    fatalError("Missing Mac icon source artwork")
}
// Center the visible mark independently of transparent source padding.
var minX = sourceBitmap.pixelsWide, minY = sourceBitmap.pixelsHigh, maxX = 0, maxY = 0
for y in 0..<sourceBitmap.pixelsHigh {
    for x in 0..<sourceBitmap.pixelsWide {
        if (sourceBitmap.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.03 {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
}
let visible = NSRect(x: minX, y: sourceBitmap.pixelsHigh - maxY - 1,
                     width: maxX - minX + 1, height: maxY - minY + 1)
func render(width: Int, height: Int, foreground: Bool) -> NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let canvas = NSRect(x: 0, y: 0, width: width, height: height)
    if foreground {
        let scale = CGFloat(height) * (2.0 / 3.0) / visible.height
        let target = NSRect(x: canvas.midX - visible.midX * scale,
            y: canvas.midY - visible.midY * scale,
            width: CGFloat(sourceBitmap.pixelsWide) * scale,
            height: CGFloat(sourceBitmap.pixelsHigh) * scale)
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.10)
        shadow.shadowBlurRadius = CGFloat(height) / 80
        shadow.shadowOffset = NSSize(width: 0, height: -CGFloat(height) / 120)
        shadow.set()
        NSGraphicsContext.current?.imageInterpolation = .high
        source.draw(in: target, from: NSRect(origin: .zero, size: source.size),
                    operation: .sourceOver, fraction: 1)
    } else {
        // Match the Mac icon's midnight-blue fill, full bleed for TV masking.
        NSGradient(starting: NSColor(calibratedRed: 0.055, green: 0.08, blue: 0.14, alpha: 1),
                   ending: NSColor(calibratedRed: 0.015, green: 0.025, blue: 0.055, alpha: 1))!
            .draw(in: canvas, angle: -90)
    }
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}
for (stack, width, height, scales) in [("App Icon", 400, 240, [1, 2]), ("App Store", 1280, 768, [1])] {
    for layer in ["Front", "Back"] {
        for scale in scales {
            let image = render(width: width * scale, height: height * scale, foreground: layer == "Front")
            let destination = catalog.appendingPathComponent("\(stack).imagestack/\(layer).imagestacklayer/Content.imageset/icon@\(scale)x.png")
            try image.representation(using: .png, properties: [:])!.write(to: destination)
        }
    }
}
// Review artifact only; source icon layers remain independent and unmasked.
let preview = render(width: 800, height: 480, foreground: false)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: preview)
NSImage(cgImage: render(width: 800, height: 480, foreground: true).cgImage!, size: NSSize(width: 800, height: 480))
    .draw(in: NSRect(x: 0, y: 0, width: 800, height: 480))
NSGraphicsContext.restoreGraphicsState()
let previewURL = root.appendingPathComponent(".build/tvos-icon-preview.png")
try FileManager.default.createDirectory(at: previewURL.deletingLastPathComponent(), withIntermediateDirectories: true)
try preview.representation(using: .png, properties: [:])!.write(to: previewURL)
print("TV icon layers generated from the Cinerama West Coast master. Preview: \(previewURL.path)")
