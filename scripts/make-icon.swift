import AppKit
let output = URL(fileURLWithPath: CommandLine.arguments[1]).appendingPathComponent("AppIcon.iconset")
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let image = NSImage(size: CGSize(width: pixels, height: pixels))
        image.lockFocus()
        let rect = CGRect(x: Double(pixels) * 0.06, y: Double(pixels) * 0.06, width: Double(pixels) * 0.88, height: Double(pixels) * 0.88)
        let path = NSBezierPath(roundedRect: rect, xRadius: Double(pixels) * 0.22, yRadius: Double(pixels) * 0.22)
        let gradient = NSGradient(starting: NSColor(red: 0.17, green: 0.71, blue: 0.80, alpha: 1), ending: NSColor(red: 0.16, green: 0.39, blue: 0.78, alpha: 1))!
        gradient.draw(in: path, angle: -55)
        NSColor.white.withAlphaComponent(0.95).setStroke()
        let outer = NSBezierPath(ovalIn: CGRect(x: Double(pixels) * 0.24, y: Double(pixels) * 0.24, width: Double(pixels) * 0.52, height: Double(pixels) * 0.52))
        outer.lineWidth = Double(pixels) * 0.065; outer.stroke()
        NSColor.white.setFill()
        NSBezierPath(ovalIn: CGRect(x: Double(pixels) * 0.395, y: Double(pixels) * 0.395, width: Double(pixels) * 0.21, height: Double(pixels) * 0.21)).fill()
        image.unlockFocus()
        let bitmap = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let name = "icon_\(size)x\(size)\(scale == 2 ? "@2x" : "").png"
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
    }
}
