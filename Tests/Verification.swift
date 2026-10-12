import AppKit
import AVFoundation
import ScreenCaptureKit

struct Verification {
    func testRetinaOutputIsBoundedEvenAndNeverUpscaled() {
        let hd = RecordingMath.outputSize(source: CGSize(width: 1512, height: 982), scale: 2, maxHeight: 1080)
        expect(hd.height == 1080)
        expect(hd.width % 2 == 0)
        let small = RecordingMath.outputSize(source: CGSize(width: 301, height: 151), scale: 1, maxHeight: 2160)
        expect(small.width == 300); expect(small.height == 150)
    }

    func testRegionCoordinatesRespectDisplayOrigin() {
        let rect = RecordingMath.captureRect(selection: CGRect(x: 70, y: 100, width: 300, height: 200), displayHeight: 900)
        expect(rect == CGRect(x: 70, y: 600, width: 300, height: 200))
    }

    func testAreaSelectionClampsAndSupportsEveryDragDirection() {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let forward = RecordingMath.selectionRect(start: CGPoint(x: 90, y: 70), end: CGPoint(x: 450, y: 350), bounds: bounds)
        let reverse = RecordingMath.selectionRect(start: CGPoint(x: 450, y: 350), end: CGPoint(x: 90, y: 70), bounds: bounds)
        expect(forward == reverse && forward == CGRect(x: 90, y: 70, width: 360, height: 280))
        let outside = RecordingMath.selectionRect(start: CGPoint(x: 900, y: -10), end: CGPoint(x: -30, y: 700), bounds: bounds)
        expect(outside == bounds)
        expect(RecordingMath.selectionRect(start: .zero, end: .zero, bounds: bounds).isEmpty)
    }

    func testPresetSelectionUsesEffectiveCodecAndPreservesOtherOptions() {
        var settings = CaptureSettings()
        expect(RecordingPreset.everyday.matches(settings), "Automatic H.264 must match the default Everyday preset")
        settings.mode = .region; settings.camera = true; settings.systemAudio = false; settings.countdown = 10
        expect(RecordingPreset.everyday.matches(settings), "Unrelated capture options must not clear the preset")
        for preset in RecordingPreset.allCases {
            preset.apply(to: &settings)
            expect(RecordingPreset.allCases.filter { $0.matches(settings) } == [preset], "Only the applied preset should be selected")
            expect(settings.mode == .region && settings.camera && !settings.systemAudio && settings.countdown == 10)
            settings.codec = .automatic
            expect(preset.matches(settings), "Automatic and explicit equivalent codecs must match")
            settings.showCursor = false
            expect(!preset.matches(settings), "A custom adjustment must clear preset selection")
        }
    }

    @MainActor func testRegionSelectionRetriesSmallDragsAndUsesFinalMouseUp() {
        let view = RegionSelectionView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        var callbacks = 0
        var result: CGRect?
        view.completion = { callbacks += 1; result = $0 }
        func mouse(_ type: NSEvent.EventType, _ point: CGPoint) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        view.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 20, y: 30)))
        view.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 25, y: 35)))
        expect(callbacks == 0, "A small accidental drag must keep the selector open")
        view.mouseDown(with: mouse(.leftMouseDown, CGPoint(x: 40, y: 60)))
        view.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: 80, y: 100)))
        view.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 400, y: 300)))
        expect(callbacks == 1 && result == CGRect(x: 40, y: 60, width: 360, height: 240), "Use the final mouse-up, not the last coalesced drag")
        view.mouseUp(with: mouse(.leftMouseUp, CGPoint(x: 400, y: 300)))
        expect(callbacks == 1, "Complete the selection only once")
        let cancelView = RegionSelectionView(frame: view.frame)
        cancelView.completion = { expect($0 == nil); callbacks += 1 }
        let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "\u{1B}", charactersIgnoringModifiers: "\u{1B}", isARepeat: false, keyCode: 53)!
        cancelView.keyDown(with: escape); cancelView.keyDown(with: escape)
        expect(callbacks == 2, "Escape cancels exactly once")
    }

    func testClockHandlesLongAndNegativeDurations() {
        expect(RecordingMath.clock(-1) == "00:00")
        expect(RecordingMath.clock(61.8) == "01:01")
        expect(RecordingMath.clock(3665) == "1:01:05")
    }

    func testVideoWriterRemovesPauseAndRetainsStaticTail() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("prism-test-\(UUID()).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        var settings = CaptureSettings(); settings.systemAudio = false
        let writer = try RecordingWriter(url: url, size: (320, 180), settings: settings)
        writer.consume(try frame(at: 10), type: .screen)
        try await Task.sleep(for: .milliseconds(40))
        writer.consume(try frame(at: 10.033333), type: .screen)
        writer.setPaused(true, atTime: CMTime(seconds: 10.05, preferredTimescale: 60000))
        writer.consume(try frame(at: 11), type: .screen)
        writer.setPaused(false, atTime: CMTime(seconds: 12.05, preferredTimescale: 60000))
        try await Task.sleep(for: .milliseconds(40))
        writer.consume(try frame(at: 12.066667), type: .screen)
        try await Task.sleep(for: .milliseconds(40))
        try await writer.finish(activeDuration: 0.5)
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        expect(abs(duration - 0.5) < 0.04)
        expect(writer.frameCount == 3)
        let tracks = try await asset.loadTracks(withMediaType: .video)
        expect(tracks.count == 1)
        let dimensions = try await tracks[0].load(.naturalSize)
        expect(dimensions == CGSize(width: 320, height: 180))
        let generator = AVAssetImageGenerator(asset: asset)
        let result = try await generator.image(at: CMTime(seconds: 0.4, preferredTimescale: 600))
        expect(result.image.width == 320)
    }

    func testEmptyWriterReportsFailureInsteadOfSavingBrokenVideo() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("prism-empty-\(UUID()).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        var settings = CaptureSettings(); settings.systemAudio = false
        let writer = try RecordingWriter(url: url, size: (320, 180), settings: settings)
        do { try await writer.finish(activeDuration: 0); expect(false, "An empty recording should fail") }
        catch { expect(error.localizedDescription.contains("No screen frames")) }
    }

    func testAudioMixProducesOneAudibleTrack() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("prism-audio-\(UUID()).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        var settings = CaptureSettings(); settings.microphone = true
        let writer = try RecordingWriter(url: url, size: (320, 180), settings: settings)
        var failure: Error?
        writer.failure = { failure = $0 }
        writer.consume(try frame(at: 10), type: .screen)
        for index in 0..<24 {
            if index == 12 {
                writer.setPaused(true, atTime: CMTime(seconds: 10.256, preferredTimescale: 48000))
                writer.setPaused(false, atTime: CMTime(seconds: 12.256, preferredTimescale: 48000))
            }
            let timestamp = 10 + Double(index) * 1024 / 48000 + (index >= 12 ? 2 : 0)
            writer.consume(try audio(at: timestamp, channels: 2), type: .audio)
            writer.consume(try audio(at: timestamp, channels: 1), type: .microphone)
            try await Task.sleep(for: .milliseconds(5))
        }
        try await writer.finish(activeDuration: 0.512)
        expect(failure == nil)
        let original = try await AVURLAsset(url: url).loadTracks(withMediaType: .audio)
        expect(original.count == 2)
        for track in original {
            let timeRange = try await track.load(.timeRange)
            expect(timeRange.duration.seconds > 0.45, "Both audio tracks must resume when the screen is static")
        }
        let videoBefore = try await compressedVideoPackets(url)
        try await AudioMixer.mixTracks(at: url, format: .mp4)
        let videoAfter = try await compressedVideoPackets(url)
        expect(videoAfter == videoBefore, "Audio mixing must preserve every compressed video packet")
        let asset = AVURLAsset(url: url)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        let video = try await asset.loadTracks(withMediaType: .video)
        expect(audio.count == 1); expect(video.count == 1)
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: audio[0], outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMIsFloatKey: true, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsNonInterleaved: false])
        reader.add(output); expect(reader.startReading())
        var peak: Float = 0
        while let sample = output.copyNextSampleBuffer(), let block = sample.dataBuffer {
            let length = CMBlockBufferGetDataLength(block)
            let memory = UnsafeMutableRawPointer.allocate(byteCount: length, alignment: 16)
            defer { memory.deallocate() }
            expect(CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: memory) == noErr)
            let floats = memory.assumingMemoryBound(to: Float.self)
            for index in 0..<(length / 4) { peak = max(peak, abs(floats[index])) }
        }
        expect(peak > 0.12, "Both audio sources must be audible in the mix")
        let duration = try await asset.load(.duration).seconds
        expect(abs(duration - 0.512) < 0.05)
    }

    func testTrimExportPreservesOriginal() async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("prism-trim-\(UUID()).mp4")
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("prism-export-\(UUID()).mov")
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: target) }
        var settings = CaptureSettings(); settings.systemAudio = false
        let writer = try RecordingWriter(url: source, size: (320, 180), settings: settings)
        for index in 0..<30 {
            writer.consume(try frame(at: 10 + Double(index) / 30), type: .screen)
            try await Task.sleep(for: .milliseconds(5))
        }
        try await writer.finish(activeDuration: 1)
        let original = try Data(contentsOf: source)
        try await VideoExporter.export(source: source, target: target, range: 0.2...0.6, format: .mov)
        let duration = try await AVURLAsset(url: target).load(.duration).seconds
        expect(abs(duration - 0.4) < 0.04)
        let afterExport = try Data(contentsOf: source)
        expect(afterExport == original)
        do { try await VideoExporter.export(source: source, target: source, range: nil, format: .mp4); expect(false, "Source overwrite must be rejected") }
        catch { expect(error.localizedDescription.contains("different location")) }
    }

    func testCameraBubbleAndHEVC() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("prism-camera-\(UUID()).mov")
        defer { try? FileManager.default.removeItem(at: url) }
        var settings = CaptureSettings(); settings.systemAudio = false; settings.camera = true; settings.format = .mov; settings.quality = .high
        let writer = try RecordingWriter(url: url, size: (320, 180), settings: settings)
        let camera = try unwrap(CMSampleBufferGetImageBuffer(frame(at: 10)))
        CVPixelBufferLockBaseAddress(camera, [])
        let bytes = CVPixelBufferGetBaseAddress(camera)!.assumingMemoryBound(to: UInt8.self)
        let stride = CVPixelBufferGetBytesPerRow(camera)
        for y in 0..<180 { for x in 0..<320 { let i = y * stride + x * 4; bytes[i] = 0; bytes[i+1] = 230; bytes[i+2] = 0; bytes[i+3] = 255 } }
        CVPixelBufferUnlockBaseAddress(camera, [])
        writer.cameraBuffer = camera
        writer.consume(try frame(at: 10), type: .screen)
        try await Task.sleep(for: .milliseconds(40))
        try await writer.finish(activeDuration: 0.3)
        let asset = AVURLAsset(url: url)
        let generator = AVAssetImageGenerator(asset: asset)
        let image = try await generator.image(at: .zero).image
        let bitmap = NSBitmapImageRep(cgImage: image)
        let colors = [bitmap.colorAt(x: 291, y: 151), bitmap.colorAt(x: 291, y: 29)].compactMap { $0?.usingColorSpace(.deviceRGB) }
        expect(colors.contains { $0.greenComponent > $0.redComponent + 0.3 }, "Camera bubble must be composited into the video")
        let track = try unwrap(try await asset.loadTracks(withMediaType: .video).first)
        let formats = try await track.load(.formatDescriptions)
        expect(formats.contains { CMFormatDescriptionGetMediaSubType($0) == kCMVideoCodecType_HEVC })
    }

    func testLiveWindowCapture() async throws {
        guard CGPreflightScreenCaptureAccess() else { throw PrismError.message("Live capture verification needs screen access for the terminal host.") }
        let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
        guard let window = content.windows.first(where: { $0.owningApplication?.bundleIdentifier == "com.prism.screenstudio" && $0.title == "Prism" }) else {
            throw PrismError.message("Launch Prism before running --capture-smoke. This check captures only Prism's window.")
        }
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("build/Prism-smoke.mp4")
        try? FileManager.default.removeItem(at: url)
        var settings = CaptureSettings(); settings.systemAudio = false
        let filter = SCContentFilter(desktopIndependentWindow: window)
        let config = SCStreamConfiguration(); config.width = 640; config.height = 444
        config.pixelFormat = kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange; config.queueDepth = 3; config.minimumFrameInterval = CMTime(value: 1, timescale: 30)
        let engine = CaptureEngine()
        try await engine.start(filter: filter, configuration: config, url: url, settings: settings)
        try await Task.sleep(for: .milliseconds(700))
        engine.pause(true)
        try await Task.sleep(for: .milliseconds(400))
        engine.pause(false)
        try await Task.sleep(for: .milliseconds(700))
        try await engine.stop(activeDuration: 1.4)
        let duration = try await AVURLAsset(url: url).load(.duration).seconds
        expect(abs(duration - 1.4) < 0.05)
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        let image = try await generator.image(at: CMTime(seconds: 0.5, preferredTimescale: 600)).image
        expect(image.width == 640)
        print("Live capture saved to \(url.path)")
    }

    func frame(at seconds: Double) throws -> CMSampleBuffer {
        var optionalPixel: CVPixelBuffer?
        expect(CVPixelBufferCreate(nil, 320, 180, kCVPixelFormatType_32BGRA, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &optionalPixel) == kCVReturnSuccess)
        let pixel = try unwrap(optionalPixel)
        CVPixelBufferLockBaseAddress(pixel, [])
        if let bytes = CVPixelBufferGetBaseAddress(pixel) { memset(bytes, 100, CVPixelBufferGetDataSize(pixel)) }
        CVPixelBufferUnlockBaseAddress(pixel, [])
        var description: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixel, formatDescriptionOut: &description)
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30), presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 60000), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        let result = CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixel, formatDescription: try unwrap(description), sampleTiming: &timing, sampleBufferOut: &sample)
        expect(result == noErr)
        return try unwrap(sample)
    }

    func audio(at seconds: Double, channels: Int) throws -> CMSampleBuffer {
        let count = 1024
        var asbd = AudioStreamBasicDescription(mSampleRate: 48000, mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: UInt32(channels * 4), mFramesPerPacket: 1, mBytesPerFrame: UInt32(channels * 4),
            mChannelsPerFrame: UInt32(channels), mBitsPerChannel: 32, mReserved: 0)
        var format: CMAudioFormatDescription?
        expect(CMAudioFormatDescriptionCreate(allocator: nil, asbd: &asbd, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil, extensions: nil, formatDescriptionOut: &format) == noErr)
        var block: CMBlockBuffer?
        expect(CMBlockBufferCreateWithMemoryBlock(allocator: nil, memoryBlock: nil, blockLength: count * channels * 4,
            blockAllocator: nil, customBlockSource: nil, offsetToData: 0, dataLength: count * channels * 4, flags: 0, blockBufferOut: &block) == noErr)
        let values = (0..<(count * channels)).map { Float(sin(Double($0 / channels) * 440 * 2 * .pi / 48000)) * 0.1 }
        values.withUnsafeBytes { bytes in _ = CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!, blockBuffer: block!, offsetIntoDestination: 0, dataLength: bytes.count) }
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 48000), presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 48000), decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        expect(CMSampleBufferCreateReady(allocator: nil, dataBuffer: block, formatDescription: format!, sampleCount: count,
            sampleTimingEntryCount: 1, sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample) == noErr)
        return try unwrap(sample)
    }
}

func expect(_ condition: @autoclosure () -> Bool, _ message: String = "Verification failed", file: StaticString = #file, line: UInt = #line) {
    if !condition() { fputs("FAIL: \(message) at \(file):\(line)\n", stderr); exit(1) }
}
func unwrap<T>(_ value: T?) throws -> T {
    guard let value else { throw PrismError.message("Expected a non-nil value during verification") }
    return value
}
@main struct VerifyMain {
    static func main() async throws {
        setvbuf(stdout, nil, _IONBF, 0)
        let suite = Verification()
        if CommandLine.arguments.contains("--interrupted-fixture") {
            let url = URL(fileURLWithPath: CommandLine.arguments.last!)
            var settings = CaptureSettings(); settings.systemAudio = false; settings.format = .mov
            let writer = try RecordingWriter(url: url, size: (320, 180), settings: settings)
            for index in 0..<780 {
                writer.consume(try suite.frame(at: 10 + Double(index) / 60), type: .screen)
                try await Task.sleep(for: .milliseconds(3))
            }
            try await Task.sleep(for: .milliseconds(300))
            _exit(0)
        }
        let tests: [(String, () async throws -> Void)] = [
            ("Library persistence, markers, recovery, and failed writes", { try await suite.testLibraryPersistenceRecoveryAndFailedWrites() }),
            ("Settings migration and bounds", { try suite.testSettingsMigrationAndClamping() }),
            ("Static-screen presenter and position", { try await suite.testStaticScreenPresenterKeepsUpdating() }),
            ("Active export cancellation", { try await suite.testActiveExportCancellation() }),
            ("Export cancellation preserves existing files", { try await suite.testExportCancellationPreservesExistingTarget() }),
            ("Retina output dimensions", { suite.testRetinaOutputIsBoundedEvenAndNeverUpscaled() }),
            ("Region coordinate conversion", { suite.testRegionCoordinatesRespectDisplayOrigin() }),
            ("Area selection direction and screen-edge bounds", { suite.testAreaSelectionClampsAndSupportsEveryDragDirection() }),
            ("Area selection retry, release position, and cancellation", { suite.testRegionSelectionRetriesSmallDragsAndUsesFinalMouseUp() }),
            ("Adjustable regions and saved area persistence", { try suite.testAdjustableRegionsAndSavedAreas() }),
            ("Preset selection and effective codec", { suite.testPresetSelectionUsesEffectiveCodecAndPreservesOtherOptions() }),
            ("Preparation output estimates and audio activity", { suite.testPreparationEstimatesAndAudioMeter() }),
            ("Recovery journal ordering and path validation", { try await suite.testRecoveryJournalOrderingAndPathValidation() }),
            ("Interrupted fragment playback and restoration", { try await suite.testInterruptedFragmentIsPlayableAndRecoverable() }),
            ("Timeline history, crop geometry, and validation", { try suite.testTimelineHistoryGeometryAndValidation() }),
            ("Timeline cuts, crop export, persistence, and cancellation", { try await suite.testTimelineExportCutsCropAndEditPersistence() }),
            ("Shortcut privacy and edited caption timing", { suite.testShortcutFilteringAndCaptionRemapping() }),
            ("Presentation rendering and pointer interpolation", { try suite.testPresentationRasterAndPointerInterpolation() }),
            ("Project tags and batch favorites persist", { try await suite.testLibraryOrganizationAndBatchFavorites() }),
            ("Export queue capture priority and persistence", { try await suite.testExportQueueCapturePriorityAndPersistence() }),
            ("Duration formatting", { suite.testClockHandlesLongAndNegativeDurations() }),
            ("Pause removal and static-screen tail", { try await suite.testVideoWriterRemovesPauseAndRetainsStaticTail() }),
            ("Empty recording failure", { try await suite.testEmptyWriterReportsFailureInsteadOfSavingBrokenVideo() }),
            ("System and microphone audio mixing", { try await suite.testAudioMixProducesOneAudibleTrack() }),
            ("Non-destructive trim and MOV export", { try await suite.testTrimExportPreservesOriginal() }),
            ("Camera bubble compositing and HEVC", { try await suite.testCameraBubbleAndHEVC() })
        ]
        for (name, test) in tests { try await test(); print("PASS: \(name)") }
        print("All \(tests.count) media checks passed.")
        if CommandLine.arguments.contains("--live-benchmark") { try await suite.testAnimatedWindowCapture(); print("PASS: Native moving-window capture pipeline") }
        if CommandLine.arguments.contains("--soak") { try await suite.benchmark(soak: true); print("PASS: Sustained 4K60 presenter and dual audio capture") }
        if CommandLine.arguments.contains("--benchmark") { try await suite.benchmark(); print("PASS: Four paced 60 fps profiles") }
        if CommandLine.arguments.contains("--capture-smoke") { try await suite.testLiveWindowCapture(); print("PASS: Live ScreenCaptureKit window recording, pause, and playback") }
    }
}


func compressedVideoPackets(_ url: URL) async throws -> [Data] {
    let asset = AVURLAsset(url: url)
    let track = try await asset.loadTracks(withMediaType: .video).first
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: try unwrap(track), outputSettings: nil); reader.add(output)
    expect(reader.startReading())
    var packets: [Data] = []
    while let sample = output.copyNextSampleBuffer() {
        if let block = sample.dataBuffer {
            let length = CMBlockBufferGetDataLength(block)
            var data = Data(count: length)
            data.withUnsafeMutableBytes { pointer in _ = CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: pointer.baseAddress!) }
            packets.append(data)
        }
    }
    expect(reader.status == .completed)
    return packets
}
