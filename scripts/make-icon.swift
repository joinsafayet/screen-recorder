import AppKit

// Resample the approved artwork at exact macOS icon sizes.
guard CommandLine.arguments.count == 3 else { fatalError("Usage: make-icon.swift <output> <master.png>") }
let output = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("AppIcon.iconset")
guard let source = NSImage(contentsOfFile: CommandLine.arguments[2]),
      let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError("App icon master is unreadable") }
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: pixels * 4, bitsPerPixel: 32), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Could not create icon bitmap") }
        context.cgContext.interpolationQuality = .high
        context.cgContext.draw(cg, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
    }
}
