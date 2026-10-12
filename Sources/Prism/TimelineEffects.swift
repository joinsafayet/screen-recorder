import Foundation
import CoreImage
import CoreText

/// Reuses bounded raster overlays; Core Image performs the final blend on the compositor thread.
final class TimelineEffects: @unchecked Sendable {
    private let cache = NSCache<NSString, CIImage>()
    init() { cache.totalCostLimit = 128 * 1024 * 1024 }
    func render(_ image: CIImage, document: TimelineDocument, time: Double, sourceSize: CGSize, region: CGRect, output: CGSize) -> CIImage {
        var result = image
        let sourceTime = document.sourceTime(at: time)
        if document.spotlight, let pointer = Self.pointer(at: sourceTime, samples: document.pointers) {
            let point = CGPoint(x: (pointer.x * sourceSize.width - region.minX) / region.width * output.width,
                y: (sourceSize.height * (1 - pointer.y) - region.minY) / region.height * output.height)
            if CGRect(origin: .zero, size: output).contains(point) {
                let radius = min(output.width, output.height) * 0.12
                let mask = CIFilter(name: "CIRadialGradient", parameters: ["inputCenter": CIVector(cgPoint: point), "inputRadius0": radius, "inputRadius1": radius * 1.16, "inputColor0": CIColor.white, "inputColor1": CIColor.black])!.outputImage!
                let dark = image.applyingFilter("CIExposureAdjust", parameters: ["inputEV": -1.2])
                result = image.applyingFilter("CIBlendWithMask", parameters: [kCIInputBackgroundImageKey: dark, kCIInputMaskImageKey: mask])
            }
        }
        for annotation in document.annotations where time >= annotation.start && time <= annotation.end {
            if let overlay = raster(annotation, size: output) { result = overlay.composited(over: result) }
        }
        if document.showCaptions, let cue = Self.cue(at: sourceTime, cues: document.captions) {
            let caption = TimelineAnnotation(id: cue.id, kind: .caption, start: cue.start, end: cue.end, text: cue.text, color: 0xFFFFFF)
            if let overlay = raster(caption, size: output) { result = overlay.composited(over: result) }
        }
        if document.showShortcuts, let shortcut = document.shortcuts.last(where: { $0.time <= sourceTime && sourceTime - $0.time <= 1.8 }) {
            let annotation = TimelineAnnotation(kind: .shortcut, start: shortcut.time, end: shortcut.time + 1.8, text: shortcut.text, color: 0xFFFFFF)
            if let overlay = raster(annotation, size: output) { result = overlay.composited(over: result) }
        }
        return result.cropped(to: CGRect(origin: .zero, size: output))
    }
    private func raster(_ annotation: TimelineAnnotation, size: CGSize) -> CIImage? {
        let identity = annotation.kind == .shortcut ? annotation.text : annotation.id.uuidString
        let key = "\(annotation.kind.rawValue)-\(identity)-\(size.width)x\(size.height)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let width = Int(size.width), height = Int(size.height)
        guard width > 0, height > 0, width <= 7680, height <= 4320,
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        let color = CGColor(red: CGFloat((annotation.color >> 16) & 255) / 255, green: CGFloat((annotation.color >> 8) & 255) / 255, blue: CGFloat(annotation.color & 255) / 255, alpha: 1)
        context.setStrokeColor(color); context.setFillColor(color); context.setLineWidth(max(2, min(size.width, size.height) * annotation.thickness)); context.setLineCap(.round); context.setLineJoin(.round)
        let points = annotation.points.map { CGPoint(x: $0.x * size.width, y: (1 - $0.y) * size.height) }
        switch annotation.kind {
        case .arrow, .drawing:
            if let start = points.first, let end = points.last, points.count > 1 {
                context.move(to: start); for point in points.dropFirst() { context.addLine(to: point) }; context.strokePath()
                if annotation.kind == .arrow {
                    let angle = atan2(end.y - start.y, end.x - start.x), length = max(12, min(size.width, size.height) * 0.045)
                    context.move(to: end)
                    context.addLine(to: CGPoint(x: end.x - length * cos(angle - 0.45), y: end.y - length * sin(angle - 0.45)))
                    context.addLine(to: CGPoint(x: end.x - length * cos(angle + 0.45), y: end.y - length * sin(angle + 0.45)))
                    context.closePath(); context.fillPath()
                }
            }
        case .spotlight:
            if let point = points.first { context.strokeEllipse(in: CGRect(x: point.x - 30, y: point.y - 30, width: 60, height: 60)) }
        case .text, .caption, .shortcut:
            let font = CTFontCreateWithName("Helvetica-Bold" as CFString, max(13, min(size.width, size.height) * 0.04), nil)
            let text = String(annotation.text.prefix(500))
            let attributes: [NSAttributedString.Key: Any] = [NSAttributedString.Key(kCTFontAttributeName as String): font, NSAttributedString.Key(kCTForegroundColorAttributeName as String): color]
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
            let bounds = CTLineGetBoundsWithOptions(line, [])
            let point = points.first ?? CGPoint(x: annotation.kind == .shortcut ? size.width * 0.18 : size.width / 2, y: annotation.kind == .text ? size.height * 0.8 : size.height * 0.09)
            let x = max(8, min(size.width - bounds.width - 8, point.x - bounds.width / 2))
            context.setFillColor(CGColor(gray: 0.04, alpha: 0.78))
            let box = CGRect(x: x - 10, y: point.y - 8, width: min(size.width - x, bounds.width + 20), height: bounds.height + 22)
            context.addPath(CGPath(roundedRect: box, cornerWidth: 8, cornerHeight: 8, transform: nil)); context.fillPath()
            context.textPosition = CGPoint(x: x, y: point.y); CTLineDraw(line, context)
        }
        guard let cg = context.makeImage() else { return nil }
        let result = CIImage(cgImage: cg); cache.setObject(result, forKey: key, cost: width * height * 4); return result
    }
    static func pointer(at time: Double, samples: [PointerSample]) -> AnnotationPoint? {
        guard !samples.isEmpty else { return nil }
        var lower = 0, upper = samples.count
        while lower < upper { let mid = (lower + upper) / 2; if samples[mid].time <= time { lower = mid + 1 } else { upper = mid } }
        let index = max(0, lower - 1), a = samples[index]
        guard abs(time - a.time) < 0.75 else { return nil }
        if index + 1 < samples.count {
            let b = samples[index + 1]
            if b.time - a.time > 0 && b.time - a.time < 0.75 {
                let t = min(1, max(0, (time - a.time) / (b.time - a.time)))
                return AnnotationPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
            }
        }
        return AnnotationPoint(x: a.x, y: a.y)
    }
    static func cue(at time: Double, cues: [CaptionCue]) -> CaptionCue? {
        var lower = 0, upper = cues.count
        while lower < upper { let mid = (lower + upper) / 2; if cues[mid].start <= time { lower = mid + 1 } else { upper = mid } }
        guard lower > 0, cues[lower - 1].end >= time else { return nil }; return cues[lower - 1]
    }
}
