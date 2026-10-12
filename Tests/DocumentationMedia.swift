import SwiftUI
import AVFoundation

/// Self-contained documentation media. Never reads a user's recording or desktop.
@MainActor enum DocumentationMedia {
    static func image<V: View>(_ view: V) throws -> NSImage {
        let renderer = ImageRenderer(content: view)
        renderer.scale = 1
        guard let image = renderer.nsImage else { throw PrismError.message("The documentation view could not render.") }
        return image
    }
    static func save<V: View>(_ view: V, to url: URL) throws {
        let image = try image(view)
        guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { throw PrismError.message("The documentation image could not encode.") }
        try png.write(to: url)
    }
    static func makeVideo(at url: URL) async throws -> NSImage {
        let image = try image(SampleWorkspace().preferredColorScheme(.dark))
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { throw PrismError.message("The sample frame is unavailable.") }
        var pixel: CVPixelBuffer?
        let width = cg.width, height = cg.height
        guard CVPixelBufferCreate(nil, width, height, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pixel) == kCVReturnSuccess, let pixel else { throw PrismError.message("The sample video buffer could not be created.") }
        CVPixelBufferLockBaseAddress(pixel, [])
        guard let context = CGContext(data: CVPixelBufferGetBaseAddress(pixel), width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixel), space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue) else { throw PrismError.message("The sample frame could not be drawn.") }
        context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height)); CVPixelBufferUnlockBaseAddress(pixel, [])
        var description: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixel, formatDescriptionOut: &description)
        guard let description else { throw PrismError.message("The sample frame has no video description.") }
        var settings = CaptureSettings(); settings.systemAudio = false
        let writer = try RecordingWriter(url: url, size: (width, height), settings: settings)
        for index in 0..<180 {
            var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: CMTime(seconds: 10 + Double(index) / 30, preferredTimescale: 60000), decodeTimeStamp: .invalid)
            var sample: CMSampleBuffer?
            let status = CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixel, formatDescription: description, sampleTiming: &timing, sampleBufferOut: &sample)
            guard status == noErr, let sample else { throw PrismError.message("The sample video frame could not be created.") }
            writer.consume(sample, type: .screen); try await Task.sleep(for: .milliseconds(3))
        }
        try await writer.finish(activeDuration: 6)
        return image
    }
}

private struct SampleWorkspace: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            HStack { PrismBrandBadge(size: 54); Text("Prism").font(.system(size: 23, weight: .semibold)); Spacer(); Text("SAMPLE WORKSPACE").font(.system(size: 11, weight: .semibold)).tracking(2).foregroundStyle(Color.muted) }
            Spacer()
            Text("Capture. Edit. Present.").font(.system(size: 52, weight: .semibold)).tracking(-1.8)
            Text("Give your next idea a clear frame.").font(.system(size: 22)).foregroundStyle(Color.muted)
            HStack(spacing: 18) {
                item("01", "Frame your source", "display")
                item("02", "Shape your story", "scissors")
                item("03", "Share a clean copy", "square.and.arrow.up")
            }
            Spacer()
            HStack { Text("SCREEN STUDIO").tracking(2); Spacer(); Text("A generated sample recording") }.font(.system(size: 11, weight: .medium)).foregroundStyle(Color.muted)
        }.padding(64).frame(width: 1280, height: 720).background(Color.canvas).foregroundStyle(Color.ink)
    }
    private func item(_ number: String, _ title: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack { PrismIcon(icon, size: 30).foregroundStyle(Color.accent); Spacer(); Text(number).font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.muted) }
            Text(title).font(.system(size: 18, weight: .medium))
        }.frame(maxWidth: .infinity, alignment: .leading).card(padding: 24)
    }
}

struct RepositoryHero: View {
    var body: some View {
        HStack(spacing: 64) {
            VStack(alignment: .leading, spacing: 26) {
                HStack(spacing: 28) { PrismBrandBadge(size: 120); VStack(alignment: .leading, spacing: 10) { Text("Prism").font(.system(size: 78, weight: .semibold)).tracking(-2.8); Text("SCREEN STUDIO").font(.system(size: 13, weight: .semibold)).tracking(4).foregroundStyle(Color.muted) } }
                Text("Capture clearly. Edit precisely.").font(.system(size: 34, weight: .medium)).tracking(-0.7)
                Text("A native recording studio for macOS.").font(.system(size: 20)).foregroundStyle(Color.muted)
                HStack(spacing: 12) { Chip(title: "macOS 15+", icon: "display"); Chip(title: "Apple Silicon", icon: "cpu"); Chip(title: "Local storage", icon: "lock.shield", color: .mint) }
            }
            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                row("01", "Capture", "display")
                row("02", "Edit", "scissors")
                row("03", "Present", "square.and.arrow.up")
            }.frame(width: 310)
        }.padding(.horizontal, 92).frame(width: 1600, height: 480).background(Color.canvas).foregroundStyle(Color.ink)
    }
    private func row(_ number: String, _ title: String, _ symbol: String) -> some View {
        HStack(spacing: 22) {
            PrismIcon(symbol, size: 30).foregroundStyle(Color.accent).frame(width: 64, height: 64).background(Color.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            Text(title).font(.system(size: 23, weight: .medium)); Spacer(); Text(number).font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.muted)
        }.card(padding: 18)
    }
}
