import AppKit
import ScreenCaptureKit
import AVFoundation

extension Verification {
    /// A moving test window in the background exercises WindowServer -> ScreenCaptureKit -> encoder.
    /// Only this process's window is captured; no desktop or other application's pixels are recorded.
    @MainActor func testAnimatedWindowCapture() async throws {
        guard CGPreflightScreenCaptureAccess() else { throw PrismError.message("Screen access is required for the live benchmark host.") }
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.accessory)
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 1920, height: 1080),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Prism performance verification"
        panel.hidesOnDeactivate = false
        let drawing = MovingPattern(frame: CGRect(x: 0, y: 0, width: 1920, height: 1080))
        panel.contentView = drawing
        panel.orderBack(nil)
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now(), repeating: 1.0 / 60, leeway: .milliseconds(1))
        timer.setEventHandler { drawing.frameIndex += 1; drawing.needsDisplay = true; panel.displayIfNeeded() }
        timer.resume()
        defer { timer.cancel(); panel.close() }
        try await Task.sleep(for: .milliseconds(300))
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
        guard let window = content.windows.first(where: { $0.owningApplication?.processID == ProcessInfo.processInfo.processIdentifier && $0.title == panel.title }) else {
            throw PrismError.message("The animated verification window is unavailable.")
        }
        let target = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/Prism-live-1080p60.mp4")
        try? FileManager.default.removeItem(at: target)
        var settings = CaptureSettings(); settings.systemAudio = false; settings.fps = 60
        let config = SCStreamConfiguration(); config.width = 1920; config.height = 1080
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60); config.queueDepth = 3
        config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange; config.showsCursor = false
        let engine = CaptureEngine()
        try await engine.start(filter: SCContentFilter(desktopIndependentWindow: window), configuration: config, url: target, settings: settings)
        let began = ProcessInfo.processInfo.systemUptime
        try await Task.sleep(for: .seconds(10))
        try await engine.stop(activeDuration: ProcessInfo.processInfo.systemUptime - began)
        let stats = engine.finalStatistics
        let duration = try await AVURLAsset(url: target).load(.duration).seconds
        print("LIVE 1080p60: \(stats.frames) received/saved frames in \(String(format: "%.2f", duration))s, \(stats.droppedVideo) writer drops, \(String(format: "%.2f", stats.processingMilliseconds)) ms average processing")
        expect(stats.frames >= 450, "Moving native window should deliver at least 45 fps on this host")
        expect(stats.droppedVideo == 0, "The live capture pipeline must have no encoder backpressure")
        let asset = AVURLAsset(url: target)
        let track = try unwrap(try await asset.loadTracks(withMediaType: .video).first)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil); reader.add(output); expect(reader.startReading())
        var frames = 0; var last = -1.0; var largestGap = 0.0
        while let sample = output.copyNextSampleBuffer() {
            let time = sample.presentationTimeStamp.seconds
            if last >= 0 { largestGap = max(largestGap, time - last) }; last = time; frames += 1
        }
        expect(reader.status == .completed)
        let result: [String: Any] = ["date": ISO8601DateFormatter().string(from: Date()), "duration": duration, "frames": frames,
            "savedFrames": stats.frames, "writerDrops": stats.droppedVideo, "averageProcessingMs": stats.processingMilliseconds,
            "largestEncodedFrameGapMs": largestGap * 1000, "source": "This verifier's moving native window only", "targetFPS": 60]
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: target.deletingLastPathComponent().appendingPathComponent("Live-performance-report.json"))
        print("LIVE encoded: \(frames) frames, longest gap \(String(format: "%.1f", largestGap * 1000)) ms")
    }
}

private final class MovingPattern: NSView {
    var frameIndex = 0
    override var isOpaque: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.07, green: 0.08, blue: 0.13, alpha: 1).setFill(); bounds.fill()
        let phase = CGFloat(frameIndex % 600) / 600
        NSColor(calibratedRed: 0.64, green: 0.56, blue: 0.98, alpha: 1).setFill()
        for index in 0..<12 {
            let offset = CGFloat(index) * 160
            NSBezierPath(roundedRect: CGRect(x: (phase * 1920 + offset).truncatingRemainder(dividingBy: 1920),
                y: CGFloat(index % 6) * 160 + 60, width: 100, height: 90), xRadius: 16, yRadius: 16).fill()
        }
        let text = "PRISM  /  LIVE 60 FPS  /  FRAME \(frameIndex)"
        text.draw(at: CGPoint(x: 60, y: 40), withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: 35, weight: .semibold), .foregroundColor: NSColor.white])
    }
}
