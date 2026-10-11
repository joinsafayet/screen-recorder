import AppKit
import AVFoundation
import ScreenCaptureKit
import Darwin

extension Verification {
    func testSettingsMigrationAndClamping() throws {
        let legacy = Data("{\"quality\":\"High quality\",\"fps\":60,\"microphone\":true,\"mode\":\"Window\"}".utf8)
        let migrated = try JSONDecoder().decode(CaptureSettings.self, from: legacy)
        expect(migrated.quality == .high && migrated.fps == 60 && migrated.microphone)
        expect(migrated.mode == .window && migrated.presenterCorner == .bottomRight && migrated.mirrorCamera)
        let roundTrip = try JSONDecoder().decode(CaptureSettings.self, from: JSONEncoder().encode(migrated))
        expect(roundTrip == migrated)
        let unsafe = try JSONDecoder().decode(CaptureSettings.self, from: Data("{\"fps\":999,\"presenterSize\":8,\"systemGain\":-1}".utf8))
        expect(unsafe.fps == 30 && unsafe.presenterSize == 0.4 && unsafe.systemGain == 0)
    }

    func testStaticScreenPresenterKeepsUpdating() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("prism-static-camera-\(UUID()).mp4")
        defer { try? FileManager.default.removeItem(at: url) }
        var settings = CaptureSettings(); settings.systemAudio = false; settings.camera = true; settings.presenterCorner = .topLeft; settings.presenterSize = 0.35
        let writer = try RecordingWriter(url: url, size: (320, 180), settings: settings)
        let screen = try makeFrame(width: 320, height: 180, at: 10, value: 25)
        writer.consume(screen, type: .screen)
        try await Task.sleep(for: .milliseconds(50))
        for index in 1...8 {
            let sample = try makeFrame(width: 320, height: 180, at: 10 + Double(index) / 30, value: 220)
            writer.consumeCamera(sample)
            try await Task.sleep(for: .milliseconds(35))
        }
        expect(writer.frameCount >= 7, "Presenter updates must be encoded without any changed screen frames")
        writer.setPaused(true, atTime: CMTime(seconds: 10.3, preferredTimescale: 600))
        writer.consumeCamera(try makeFrame(width: 320, height: 180, at: 10.4, value: 10))
        let count = writer.frameCount
        try await writer.finish(activeDuration: 0.3)
        expect(count == writer.frameCount)
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero; generator.requestedTimeToleranceAfter = .zero
        let image = try await generator.image(at: CMTime(seconds: 0.2, preferredTimescale: 600)).image
        let bitmap = NSBitmapImageRep(cgImage: image)
        let bright = [bitmap.colorAt(x: 40, y: 40), bitmap.colorAt(x: 40, y: 140)].compactMap { $0?.usingColorSpace(.deviceRGB) }
        expect(bright.contains { $0.redComponent > 0.7 }, "The presenter must be in the selected left corner")
        let right = bitmap.colorAt(x: 280, y: 90)!.usingColorSpace(.deviceRGB)!
        expect(right.redComponent < 0.3)
    }

    func testExportCancellationPreservesExistingTarget() async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("prism-cancel-source-\(UUID()).mp4")
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("prism-cancel-target-\(UUID()).mp4")
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: target) }
        var settings = CaptureSettings(); settings.systemAudio = false
        let writer = try RecordingWriter(url: source, size: (320, 180), settings: settings)
        writer.consume(try makeFrame(width: 320, height: 180, at: 10, value: 60), type: .screen)
        try await Task.sleep(for: .milliseconds(50)); try await writer.finish(activeDuration: 2)
        let originalTarget = Data("Existing target must survive a cancellation".utf8)
        try originalTarget.write(to: target)
        let task = Task {
            try await VideoExporter.export(source: source, target: target, range: nil, format: .mp4, quality: .hd)
        }
        task.cancel()
        do { try await task.value; expect(false, "A cancelled export must throw") } catch {}
        let afterCancel = try Data(contentsOf: target)
        expect(afterCancel == originalTarget)
    }

    func testActiveExportCancellation() async throws {
        let source = FileManager.default.temporaryDirectory.appendingPathComponent("prism-active-cancel-\(UUID()).mp4")
        let target = FileManager.default.temporaryDirectory.appendingPathComponent("prism-active-target-\(UUID()).mp4")
        defer { try? FileManager.default.removeItem(at: source); try? FileManager.default.removeItem(at: target) }
        var settings = CaptureSettings(); settings.systemAudio = false
        let writer = try RecordingWriter(url: source, size: (1920, 1080), settings: settings)
        writer.consume(try makeFrame(width: 1920, height: 1080, at: 10, value: 100), type: .screen)
        try await Task.sleep(for: .milliseconds(50)); try await writer.finish(activeDuration: 60)
        let sentinel = Data("Keep this existing destination".utf8)
        try sentinel.write(to: target)
        let signal = ExportCancellationSignal()
        let export = Task {
            try await VideoExporter.export(source: source, target: target, range: 0.1...59.9, format: .mp4, quality: .compact) { value in
                if value == 0 { signal.schedule() }
            }
        }
        signal.setTask(export)
        do { try await export.value; expect(false, "Cancellation must interrupt an active export") } catch {}
        let after = try Data(contentsOf: target)
        expect(after == sentinel, "Active cancellation must leave an existing destination intact")
        expect(signal.cancelled)
    }

    func benchmark(soak: Bool = false) async throws {
        var results: [[String: Any]] = []
        let profiles = soak ? [(3840, 2160, true)] : [(1920, 1080, false), (3840, 2160, false), (1920, 1080, true), (3840, 2160, true)]
        for (width, height, camera) in profiles {
            let name = "\(height)p60\(camera ? "-presenter" : "")"
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("prism-benchmark-\(UUID()).mp4")
            defer { try? FileManager.default.removeItem(at: url) }
            var settings = CaptureSettings(); settings.systemAudio = soak; settings.microphone = soak; settings.fps = 60; settings.camera = camera
            settings.quality = height > 1080 ? .high : .balanced
            let writer = try RecordingWriter(url: url, size: (width, height), settings: settings)
            let format = camera ? kCVPixelFormatType_32BGRA : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
            var pool: CVPixelBufferPool?
            expect(CVPixelBufferPoolCreate(nil, nil, [kCVPixelBufferPixelFormatTypeKey: format,
                kCVPixelBufferWidthKey: width, kCVPixelBufferHeightKey: height,
                kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &pool) == kCVReturnSuccess)
            let frameCount = soak ? 3600 : 360
            let duration = Double(frameCount) / 60
            var audioSamples = 0
            let baselineMemory = residentMemory()
            var peakMemory = baselineMemory
            let began = ProcessInfo.processInfo.systemUptime
            for index in 0..<frameCount {
                let target = began + Double(index) / 60
                let wait = target - ProcessInfo.processInfo.systemUptime
                if wait > 0 { try await Task.sleep(for: .seconds(wait)) }
                try autoreleasepool {
                    let sample = try makeFrame(width: width, height: height, at: 10 + Double(index) / 60,
                                               value: UInt8(30 + index % 190), format: format, pool: pool)
                    if camera { writer.cameraBuffer = CMSampleBufferGetImageBuffer(try makeFrame(width: 640, height: 480, at: 10, value: UInt8(index % 255))) }
                    writer.consume(sample, type: .screen)
                    if soak {
                        while Double(audioSamples) / 48000 < Double(index + 1) / 60 {
                            let timestamp = 10 + Double(audioSamples) / 48000
                            writer.consume(try audio(at: timestamp, channels: 2), type: .audio)
                            writer.consume(try audio(at: timestamp, channels: 1), type: .microphone)
                            audioSamples += 1024
                        }
                    }
                }
                if index % 30 == 0 { peakMemory = max(peakMemory, residentMemory()) }
                if soak && index > 0 && index % 900 == 0 { print("SOAK \(index / 60)s: \(writer.statistics.frames) frames, \(writer.statistics.droppedVideo) video / \(writer.statistics.droppedAudio) audio drops, \(String(format: "%.1f", Double(residentMemory()) / 1_048_576)) MB") }
            }
            let captureWall = ProcessInfo.processInfo.systemUptime - began
            let finishBegan = ProcessInfo.processInfo.systemUptime
            try await writer.finish(activeDuration: Double(frameCount) / 60)
            let finalize = ProcessInfo.processInfo.systemUptime - finishBegan
            let stats = writer.statistics
            let asset = AVURLAsset(url: url)
            let track = try unwrap(try await asset.loadTracks(withMediaType: .video).first)
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil); reader.add(output); expect(reader.startReading())
            var encoded = 0; var last = -1.0; var maximumGap = 0.0
            while let sample = output.copyNextSampleBuffer() {
                let time = sample.presentationTimeStamp.seconds
                if last >= 0 { maximumGap = max(maximumGap, time - last) }; last = time; encoded += 1
            }
            expect(reader.status == .completed)
            expect(stats.frames >= frameCount - 1, "\(name) should save all paced frames")
            expect(stats.droppedVideo == 0, "\(name) should not encounter writer backpressure on this host")
            expect(maximumGap < 0.04, "\(name) must have smooth encoded frame timestamps")
            expect(captureWall < duration + 0.5, "\(name) must sustain real time")
            var mixSeconds = 0.0
            if soak {
                expect(stats.droppedAudio == 0, "Both audio streams must keep up under sustained capture")
                let beganMix = ProcessInfo.processInfo.systemUptime
                try await AudioMixer.mixTracks(at: url, format: .mp4)
                mixSeconds = ProcessInfo.processInfo.systemUptime - beganMix
                let audioTracks = try await AVURLAsset(url: url).loadTracks(withMediaType: .audio)
                expect(audioTracks.count == 1)
            }
            let record: [String: Any] = ["profile": name, "attemptedFrames": frameCount, "savedFrames": stats.frames,
                "encodedFrames": encoded, "droppedVideo": stats.droppedVideo, "droppedAudio": stats.droppedAudio, "audioMixSeconds": mixSeconds, "duration": duration, "averageProcessingMs": stats.processingMilliseconds,
                "peakProcessingMs": stats.peakProcessingMilliseconds, "captureWallSeconds": captureWall, "finalizeSeconds": finalize,
                "maximumFrameGapMs": maximumGap * 1000, "peakResidentMB": Double(peakMemory) / 1_048_576,
                "residentGrowthMB": Double(peakMemory - baselineMemory) / 1_048_576]
            results.append(record)
            print("BENCH \(name): \(stats.frames)/\(frameCount) frames, \(stats.droppedVideo) drops, \(String(format: "%.2f", stats.processingMilliseconds)) ms/frame, \(String(format: "%.1f", Double(peakMemory) / 1_048_576)) MB resident")
        }
        let report: [String: Any] = ["date": ISO8601DateFormatter().string(from: Date()), "os": ProcessInfo.processInfo.operatingSystemVersionString,
            "processorCount": ProcessInfo.processInfo.processorCount, "scope": soak ? "60-second paced 4K60 synthetic frames with presenter composition and two synthetic PCM audio streams; excludes physical devices and WindowServer" : "Paced changing synthetic frames, six seconds per profile; excludes physical devices and WindowServer", "results": results]
        let target = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(soak ? "build/Soak-performance-report.json" : "build/Performance-report.json")
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys]).write(to: target, options: .atomic)
    }
}

private func residentMemory() -> UInt64 {
    var info = mach_task_basic_info_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info_data_t>.size / MemoryLayout<integer_t>.size)
    let result = withUnsafeMutablePointer(to: &info) { pointer in
        pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count) }
    }
    return result == KERN_SUCCESS ? info.resident_size : 0
}

func makeFrame(width: Int, height: Int, at seconds: Double, value: UInt8,
               format: OSType = kCVPixelFormatType_32BGRA, pool: CVPixelBufferPool? = nil) throws -> CMSampleBuffer {
    var optionalPixel: CVPixelBuffer?
    let result: CVReturn
    if let pool { result = CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(nil, pool, [kCVPixelBufferPoolAllocationThresholdKey: 8] as CFDictionary, &optionalPixel) }
    else { result = CVPixelBufferCreate(nil, width, height, format, [kCVPixelBufferIOSurfacePropertiesKey: [:]] as CFDictionary, &optionalPixel) }
    guard result == kCVReturnSuccess, let pixel = optionalPixel else { throw PrismError.message("The benchmark's bounded pixel pool was exhausted.") }
    CVPixelBufferLockBaseAddress(pixel, [])
    if CVPixelBufferIsPlanar(pixel) {
        for plane in 0..<CVPixelBufferGetPlaneCount(pixel) {
            memset(CVPixelBufferGetBaseAddressOfPlane(pixel, plane)!, plane == 0 ? Int32(value) : 128,
                   CVPixelBufferGetBytesPerRowOfPlane(pixel, plane) * CVPixelBufferGetHeightOfPlane(pixel, plane))
        }
    } else { memset(CVPixelBufferGetBaseAddress(pixel)!, Int32(value), CVPixelBufferGetDataSize(pixel)) }
    CVPixelBufferUnlockBaseAddress(pixel, [])
    var description: CMVideoFormatDescription?
    CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixel, formatDescriptionOut: &description)
    var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 60), presentationTimeStamp: CMTime(seconds: seconds, preferredTimescale: 60000), decodeTimeStamp: .invalid)
    var sample: CMSampleBuffer?
    let formatDescription = try unwrap(description)
    expect(CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixel, formatDescription: formatDescription, sampleTiming: &timing, sampleBufferOut: &sample) == noErr)
    return try unwrap(sample)
}


private final class ExportCancellationSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<Void, Error>?
    private var scheduled = false
    private(set) var cancelled = false
    func setTask(_ task: Task<Void, Error>) { lock.lock(); self.task = task; lock.unlock() }
    func schedule() {
        lock.lock(); let needed = !scheduled; scheduled = true; lock.unlock()
        guard needed else { return }
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.01) { [self] in
            lock.lock(); cancelled = true; let task = task; lock.unlock(); task?.cancel()
        }
    }
}
