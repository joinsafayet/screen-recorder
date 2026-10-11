import AppKit
import ScreenCaptureKit
import AVFoundation
import CoreImage
import VideoToolbox

/// All writer state lives on CaptureEngine.queue. Screen, mic, and system audio share that queue.
final class RecordingWriter {
    private let writer: AVAssetWriter
    private let video: AVAssetWriterInput
    private let systemAudio: AVAssetWriterInput?
    private let microphone: AVAssetWriterInput?
    private let adaptor: AVAssetWriterInputPixelBufferAdaptor
    private let frameDuration: CMTime
    private var origin: CMTime?
    private var pauseOffset = CMTime.zero
    private var pauseStarted: CMTime?
    private var lastVideoTime = CMTime.zero
    private var lastBuffer: CVPixelBuffer?
    private var lastScreen: CVPixelBuffer?
    private var paused = false
    private var earliestAllowedTime: CMTime?
    private var ended = false
    private let context = CIContext(options: [.cacheIntermediates: false])
    private let size: CGSize
    private let options: CaptureSettings
    private let circle: CGRect
    private let mask: CIImage
    private var processingTotal = 0.0
    private(set) var statistics: CaptureStatistics
    var cameraBuffer: CVPixelBuffer?
    var failure: ((Error) -> Void)?
    private var reportedFailure = false
    private(set) var frameCount = 0

    init(url: URL, size: (width: Int, height: Int), settings: CaptureSettings) throws {
        self.size = CGSize(width: size.width, height: size.height)
        options = settings
        circle = settings.presenterCorner.rect(in: self.size, fraction: settings.presenterSize)
        mask = CIFilter(name: "CIRadialGradient", parameters: [
            "inputCenter": CIVector(x: circle.midX, y: circle.midY),
            "inputRadius0": circle.width / 2 - 1, "inputRadius1": circle.width / 2,
            "inputColor0": CIColor.white, "inputColor1": CIColor.clear
        ])!.outputImage!.cropped(to: CGRect(origin: .zero, size: self.size))
        statistics = CaptureStatistics(width: size.width, height: size.height, targetFPS: settings.fps)
        frameDuration = CMTime(value: 1, timescale: CMTimeScale(settings.fps))
        writer = try AVAssetWriter(outputURL: url, fileType: settings.format.fileType)
        let useHEVC = settings.codec.resolved(for: settings.quality) == .hevc
        var compression: [String: Any] = [
            AVVideoAverageBitRateKey: Int(Double(size.width * size.height) * settings.quality.bitratePerPixel * Double(settings.fps) / 30),
            AVVideoExpectedSourceFrameRateKey: settings.fps,
            AVVideoMaxKeyFrameIntervalKey: settings.fps * 2,
            AVVideoAllowFrameReorderingKey: false
        ]
        if !useHEVC { compression[AVVideoProfileLevelKey] = AVVideoProfileLevelH264HighAutoLevel }
        video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: useHEVC ? AVVideoCodecType.hevc : .h264,
            AVVideoWidthKey: size.width, AVVideoHeightKey: size.height,
            AVVideoCompressionPropertiesKey: compression,
            AVVideoEncoderSpecificationKey: [kVTVideoEncoderSpecification_EnableHardwareAcceleratedVideoEncoder as String: true]
        ])
        video.expectsMediaDataInRealTime = true
        adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size.width,
            kCVPixelBufferHeightKey as String: size.height,
            kCVPixelBufferIOSurfacePropertiesKey as String: [:]
        ])
        func audioInput(channels: Int) -> AVAssetWriterInput {
            let input = AVAssetWriterInput(mediaType: .audio, outputSettings: [
                AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000,
                AVNumberOfChannelsKey: channels, AVEncoderBitRateKey: channels == 1 ? 96000 : 192000
            ])
            input.expectsMediaDataInRealTime = true
            return input
        }
        systemAudio = settings.systemAudio ? audioInput(channels: 2) : nil
        microphone = settings.microphone ? audioInput(channels: 1) : nil
        for input in [video, systemAudio, microphone].compactMap({ $0 }) {
            guard writer.canAdd(input) else { throw PrismError.message("The selected recording format is unavailable.") }
            writer.add(input)
        }
        guard writer.startWriting() else { throw writer.error ?? PrismError.message("Could not create the video file.") }
    }

    func setPaused(_ value: Bool, atTime time: CMTime = CMClockGetTime(CMClockGetHostTimeClock())) {
        guard !ended, paused != value else { return }
        paused = value
        if value { pauseStarted = time }
        else {
            if let start = pauseStarted { pauseOffset = pauseOffset + max(.zero, time - start) }
            pauseStarted = nil; earliestAllowedTime = time
        }
    }

    func consume(_ sample: CMSampleBuffer, type: SCStreamOutputType) {
        guard !ended, !paused, sample.isValid, CMSampleBufferDataIsReady(sample) else { return }
        if writer.status == .failed { report(writer.error ?? PrismError.message("Recording could not continue.")); return }
        let rawTime = CMSampleBufferGetPresentationTimeStamp(sample)
        guard rawTime.isValid else { return }
        if let earliestAllowedTime, rawTime < earliestAllowedTime { return }
        if type == .screen {
            guard let buffer = CMSampleBufferGetImageBuffer(sample) else { return }
            if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
               let status = attachments.first?[.status] as? Int,
               status != SCFrameStatus.complete.rawValue && status != SCFrameStatus.started.rawValue { return }
            if origin == nil { origin = rawTime; writer.startSession(atSourceTime: .zero) }
            guard let origin else { return }
            let timestamp = rawTime - origin - pauseOffset
            guard timestamp.seconds >= 0, frameCount == 0 || timestamp > lastVideoTime else { return }
            lastScreen = buffer
            if options.camera, frameCount > 0, (timestamp - lastVideoTime).seconds < frameDuration.seconds * 0.85 { return }
            appendFrame(buffer, at: timestamp, sample: sample)
        } else {
            // Audio resumes immediately, even when a static screen produces no new video frame.
            guard let origin else { return }
            let input = type == .audio ? systemAudio : microphone
            guard let input else { return }
            guard input.isReadyForMoreMediaData else { statistics.droppedAudio += 1; return }
            let offset = origin + pauseOffset
            guard rawTime >= offset else { return }
            do {
                let adjusted = try Self.retime(sample, subtracting: offset)
                if !input.append(adjusted) { report(writer.error ?? PrismError.message("Audio could not be saved.")) }
            } catch { report(error) }
        }
    }

    /// A live camera must keep updating over a static desktop. Both sources share the host clock.
    func consumeCamera(_ sample: CMSampleBuffer) {
        guard let image = CMSampleBufferGetImageBuffer(sample) else { return }
        cameraBuffer = image
        guard !ended, !paused, let screen = lastScreen, let origin else { return }
        let raw = CMSampleBufferGetPresentationTimeStamp(sample)
        if let earliestAllowedTime, raw < earliestAllowedTime { return }
        let time = raw - origin - pauseOffset
        guard time.seconds >= 0, time - lastVideoTime >= frameDuration else { return }
        appendFrame(screen, at: time)
    }

    private func appendFrame(_ buffer: CVPixelBuffer, at timestamp: CMTime, sample: CMSampleBuffer? = nil) {
        guard video.isReadyForMoreMediaData else { statistics.droppedVideo += 1; return }
        let began = ProcessInfo.processInfo.systemUptime
        let output: CVPixelBuffer
        let success: Bool
        if cameraBuffer != nil {
            guard let composited = compose(buffer) else { statistics.droppedVideo += 1; return }
            output = composited; success = adaptor.append(output, withPresentationTime: timestamp)
        } else {
            output = buffer
            // Keep the capture's YCbCr buffers and color attachments intact. No per-frame GPU copy.
            if let sample, let origin {
                do { success = video.append(try Self.retime(sample, subtracting: origin + pauseOffset)) }
                catch { report(error); return }
            } else { success = adaptor.append(buffer, withPresentationTime: timestamp) }
        }
        guard success else { report(writer.error ?? PrismError.message("A video frame could not be saved.")); return }
        let milliseconds = (ProcessInfo.processInfo.systemUptime - began) * 1000
        processingTotal += milliseconds
        lastVideoTime = timestamp; lastBuffer = output; frameCount += 1
        statistics.frames = frameCount
        statistics.processingMilliseconds = processingTotal / Double(frameCount)
        statistics.peakProcessingMilliseconds = max(statistics.peakProcessingMilliseconds, milliseconds)
    }

    private func compose(_ screen: CVPixelBuffer) -> CVPixelBuffer? {
        guard let cameraBuffer, let pool = adaptor.pixelBufferPool else { return nil }
        var output: CVPixelBuffer?
        // Bound the compositor's in-flight memory when the encoder is under pressure.
        guard CVPixelBufferPoolCreatePixelBufferWithAuxAttributes(nil, pool,
            [kCVPixelBufferPoolAllocationThresholdKey: 6] as CFDictionary, &output) == kCVReturnSuccess, let output else { return nil }
        let base = CIImage(cvPixelBuffer: screen)
        var camera = CIImage(cvPixelBuffer: cameraBuffer)
        if options.mirrorCamera { camera = camera.transformed(by: CGAffineTransform(a: -1, b: 0, c: 0, d: 1, tx: camera.extent.width, ty: 0)) }
        let diameter = circle.width
        let scale = max(diameter / camera.extent.width, diameter / camera.extent.height)
        let resized = camera.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let positioned = resized.transformed(by: CGAffineTransform(translationX: circle.midX - resized.extent.midX, y: circle.midY - resized.extent.midY))
        let result = positioned.applyingFilter("CIBlendWithAlphaMask", parameters: [kCIInputBackgroundImageKey: base, kCIInputMaskImageKey: mask])
        context.render(result, to: output)
        return output
    }

    static func retime(_ sample: CMSampleBuffer, subtracting offset: CMTime) throws -> CMSampleBuffer {
        var count = 0
        var result = CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: 0, arrayToFill: nil, entriesNeededOut: &count)
        guard result == noErr else { throw PrismError.message("Audio timing could not be read.") }
        var timing = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: .invalid, decodeTimeStamp: .invalid), count: count)
        result = CMSampleBufferGetSampleTimingInfoArray(sample, entryCount: count, arrayToFill: &timing, entriesNeededOut: &count)
        guard result == noErr else { throw PrismError.message("Audio timing could not be read.") }
        for i in timing.indices {
            timing[i].presentationTimeStamp = timing[i].presentationTimeStamp - offset
            if timing[i].decodeTimeStamp.isValid { timing[i].decodeTimeStamp = timing[i].decodeTimeStamp - offset }
        }
        var copy: CMSampleBuffer?
        result = CMSampleBufferCreateCopyWithNewTiming(allocator: kCFAllocatorDefault, sampleBuffer: sample, sampleTimingEntryCount: count, sampleTimingArray: &timing, sampleBufferOut: &copy)
        guard result == noErr, let copy else { throw PrismError.message("Audio timing could not be adjusted.") }
        return copy
    }

    private func report(_ error: Error) {
        guard !reportedFailure else { return }
        reportedFailure = true; failure?(error)
    }

    func finish(activeDuration: Double) async throws {
        guard !ended else { return }
        ended = true
        guard origin != nil, frameCount > 0 else { writer.cancelWriting(); throw PrismError.message("No screen frames were received. Check Screen Recording access and try again.") }
        // Extend a static screen to the actual stop time instead of truncating at the last changed frame.
        // ScreenCaptureKit can deliver initial frames before startCapture() returns.
        // End at the user's active clock, trimming any startup or queued-frame overshoot.
        let end = CMTime(seconds: max(activeDuration, frameDuration.seconds), preferredTimescale: 600)
        if let lastBuffer, video.isReadyForMoreMediaData, end - frameDuration > lastVideoTime {
            _ = adaptor.append(lastBuffer, withPresentationTime: end - frameDuration)
        }
        writer.endSession(atSourceTime: end)
        video.markAsFinished(); systemAudio?.markAsFinished(); microphone?.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? PrismError.message("The recording could not be finalized.") }
    }
}

// Media state is confined to queue; camera session state is confined to cameraQueue.
final class CaptureEngine: NSObject, SCStreamOutput, SCStreamDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "studio.prism.capture", qos: .userInitiated)
    private let cameraQueue = DispatchQueue(label: "studio.prism.camera", qos: .userInitiated)
    private var stream: SCStream?
    private var recorder: RecordingWriter?
    private var cameraSession: AVCaptureSession?
    private var lastMeterTime = 0.0
    private var lastStatisticsTime = 0.0
    private var activity: NSObjectProtocol?
    var onError: ((Error) -> Void)?
    var onAudioLevel: ((Float) -> Void)?
    var onStatistics: ((CaptureStatistics) -> Void)?
    var finalStatistics: CaptureStatistics { queue.sync { recorder?.statistics ?? stoppedStatistics } }
    private var stoppedStatistics = CaptureStatistics()

    func start(filter: SCContentFilter, configuration: SCStreamConfiguration, url: URL, settings: CaptureSettings) async throws {
        let writer = try RecordingWriter(url: url, size: (configuration.width, configuration.height), settings: settings)
        writer.failure = { [weak self] error in self?.onError?(error) }
        queue.sync { recorder = writer }
        activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleDisplaySleepDisabled], reason: "Recording your screen")
        do {
            if settings.camera { try await startCamera(id: settings.cameraID) }
            let capture = SCStream(filter: filter, configuration: configuration, delegate: self)
            try capture.addStreamOutput(self, type: .screen, sampleHandlerQueue: queue)
            if settings.systemAudio { try capture.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue) }
            if settings.microphone { try capture.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue) }
            stream = capture
            try await capture.startCapture()
        } catch {
            try? await stop(activeDuration: 0)
            try? FileManager.default.removeItem(at: url)
            throw error
        }
    }

    func pause(_ value: Bool) {
        let timestamp = CMClockGetTime(CMClockGetHostTimeClock())
        queue.async { self.recorder?.setPaused(value, atTime: timestamp) }
    }

    func stop(activeDuration: Double) async throws {
        defer { if let activity { ProcessInfo.processInfo.endActivity(activity) }; activity = nil }
        var streamError: Error?
        if let stream { do { try await stream.stopCapture() } catch { streamError = error } }
        stream = nil
        await withCheckedContinuation { continuation in
            cameraQueue.async { self.cameraSession?.stopRunning(); self.cameraSession = nil; continuation.resume() }
        }
        let writer: RecordingWriter? = queue.sync { let writer = recorder; stoppedStatistics = writer?.statistics ?? CaptureStatistics(); recorder = nil; return writer }
        // The output queue has now drained; no more buffers can reach this writer.
        if let writer { try await writer.finish(activeDuration: activeDuration) }
        else if let streamError { throw streamError }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        autoreleasepool {
        recorder?.consume(sampleBuffer, type: type)
        let now = ProcessInfo.processInfo.systemUptime
        if now - lastStatisticsTime >= 0.5, let stats = recorder?.statistics {
            lastStatisticsTime = now
            onStatistics?(stats)
        }
        if (type == .microphone || type == .audio), now - lastMeterTime >= 0.15 {
            lastMeterTime = now
            var block: CMBlockBuffer?
            var needed = 0
            CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, bufferListSizeNeededOut: &needed,
                bufferListOut: nil, bufferListSize: 0, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
                flags: 0, blockBufferOut: nil)
            let storage = UnsafeMutableRawPointer.allocate(byteCount: max(needed, MemoryLayout<AudioBufferList>.size), alignment: 16)
            defer { storage.deallocate() }
            let list = storage.bindMemory(to: AudioBufferList.self, capacity: 1)
            let result = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sampleBuffer, bufferListSizeNeededOut: nil, bufferListOut: list,
                bufferListSize: max(needed, MemoryLayout<AudioBufferList>.size), blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
                flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment), blockBufferOut: &block)
            if result == noErr, let pointer = list.pointee.mBuffers.mData,
               let format = CMSampleBufferGetFormatDescription(sampleBuffer),
               let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format),
               asbd.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0 {
                let samples = pointer.assumingMemoryBound(to: Float.self)
                let count = Int(list.pointee.mBuffers.mDataByteSize) / MemoryLayout<Float>.size
                if count > 0 {
                    var sum: Float = 0
                    for i in 0..<count { sum += samples[i] * samples[i] }
                    onAudioLevel?(min(1, sqrt(sum / Float(count)) * 4))
                }
            }
        }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) { onError?(error) }

    private func startCamera(id: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            cameraQueue.async {
                do {
                    let discovery = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external], mediaType: .video, position: .unspecified)
                    guard let device = discovery.devices.first(where: { $0.uniqueID == id }) ?? AVCaptureDevice.default(for: .video) else { throw PrismError.message("Connect a camera to use the presenter bubble.") }
                    let session = AVCaptureSession(); session.beginConfiguration(); session.sessionPreset = .medium
                    let input = try AVCaptureDeviceInput(device: device)
                    guard session.canAddInput(input) else { throw PrismError.message("This camera is unavailable.") }
                    session.addInput(input)
                    let output = AVCaptureVideoDataOutput(); output.alwaysDiscardsLateVideoFrames = true
                    output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                    output.setSampleBufferDelegate(self, queue: self.queue)
                    guard session.canAddOutput(output) else { throw PrismError.message("The camera could not be configured.") }
                    session.addOutput(output); session.commitConfiguration(); self.cameraSession = session
                    session.startRunning()
                    guard session.isRunning else { throw PrismError.message("Your camera is in use or could not be started.") }
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        autoreleasepool { recorder?.consumeCamera(sampleBuffer) }
    }
}
