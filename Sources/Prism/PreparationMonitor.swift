import AppKit
import AVFoundation
import ScreenCaptureKit
import CoreImage
import Combine

struct PreparationEstimate: Equatable {
    var width: Int
    var height: Int
    var bytesPerMinute: Int64
    static func make(source: CGSize, scale: Double, settings: CaptureSettings) -> PreparationEstimate {
        let size = RecordingMath.outputSize(source: source, scale: scale, maxHeight: settings.quality.maxHeight)
        let video = Double(size.width * size.height) * settings.quality.bitratePerPixel * Double(settings.fps) / 30
        let audio = (settings.systemAudio ? 192_000.0 : 0) + (settings.microphone ? 96_000.0 : 0)
        return PreparationEstimate(width: size.width, height: size.height, bytesPerMinute: Int64((video + audio) * 60 / 8))
    }
}
enum AudioActivity {
    static func rms(_ values: [Float]) -> Float {
        guard !values.isEmpty else { return 0 }
        return min(1, sqrt(values.reduce(0) { $0 + $1 * $1 } / Float(values.count)) * 4)
    }
    static func level(_ sample: CMSampleBuffer) -> Float {
        var required = 0
        CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sample, bufferListSizeNeededOut: &required, bufferListOut: nil, bufferListSize: 0, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: nil)
        guard required > 0, let format = CMSampleBufferGetFormatDescription(sample), let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(format) else { return 0 }
        let storage = UnsafeMutableRawPointer.allocate(byteCount: required, alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { storage.deallocate() }
        let list = storage.bindMemory(to: AudioBufferList.self, capacity: 1)
        var retained: CMBlockBuffer?
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sample, bufferListSizeNeededOut: nil, bufferListOut: list, bufferListSize: required, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, blockBufferOut: &retained) == noErr,
              let data = list.pointee.mBuffers.mData else { return 0 }
        let bytes = Int(list.pointee.mBuffers.mDataByteSize)
        var total: Float = 0, count = 0
        if asbd.pointee.mFormatFlags & kAudioFormatFlagIsFloat != 0, asbd.pointee.mBitsPerChannel == 32 {
            let samples = data.assumingMemoryBound(to: Float.self); count = bytes / 4
            for i in 0..<count { total += samples[i] * samples[i] }
        } else if asbd.pointee.mBitsPerChannel == 16 {
            let samples = data.assumingMemoryBound(to: Int16.self); count = bytes / 2
            for i in 0..<count { let value = Float(samples[i]) / 32768; total += value * value }
        }
        return count > 0 ? min(1, sqrt(total / Float(count)) * 4) : 0
    }
}

/// Device capture and image conversion stay off the UI thread. Published previews are bounded to 2 fps.
final class PreparationMonitor: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureAudioDataOutputSampleBufferDelegate, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    @Published private(set) var running = false
    @Published private(set) var cameraImage: NSImage?
    @Published private(set) var screenImage: NSImage?
    @Published private(set) var microphoneLevel: Float = 0
    @Published private(set) var systemLevel: Float = 0
    @Published private(set) var issue: String?
    private let sessionQueue = DispatchQueue(label: "prism.preparation.session", qos: .utility)
    private let mediaQueue = DispatchQueue(label: "prism.preparation.media", qos: .utility)
    private let context = CIContext(options: [.cacheIntermediates: false])
    private var session: AVCaptureSession?
    private var stream: SCStream?
    private let stateLock = NSLock()
    private var generation = UUID()
    private var requestID: UUID { stateLock.lock(); defer { stateLock.unlock() }; return generation }
    @discardableResult private func resetID() -> UUID { stateLock.lock(); defer { stateLock.unlock() }; generation = UUID(); return generation }
    private var lastCamera = 0.0, lastScreen = 0.0, lastMic = 0.0, lastSystem = 0.0

    @MainActor func start(settings: CaptureSettings, filter: SCContentFilter?, previewScreen: Bool = true, crop: CGRect? = nil) async throws {
        await stop()
        let id = resetID(); issue = nil
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    let session = AVCaptureSession(); session.beginConfiguration(); session.sessionPreset = .medium
                    if settings.camera {
                        let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external], mediaType: .video, position: .unspecified).devices
                        guard let device = devices.first(where: { $0.uniqueID == settings.cameraID }) ?? AVCaptureDevice.default(for: .video) else { throw PrismError.message("Connect a camera to preview the presenter.") }
                        let input = try AVCaptureDeviceInput(device: device)
                        guard session.canAddInput(input) else { throw PrismError.message("The camera is unavailable.") }; session.addInput(input)
                        let output = AVCaptureVideoDataOutput(); output.alwaysDiscardsLateVideoFrames = true
                        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
                        output.setSampleBufferDelegate(self, queue: self.mediaQueue)
                        guard session.canAddOutput(output) else { throw PrismError.message("Camera preview is unavailable.") }; session.addOutput(output)
                    }
                    if settings.microphone {
                        let devices = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices
                        guard let device = devices.first(where: { $0.uniqueID == settings.microphoneID }) ?? AVCaptureDevice.default(for: .audio) else { throw PrismError.message("Connect a microphone to test your voice.") }
                        let input = try AVCaptureDeviceInput(device: device)
                        guard session.canAddInput(input) else { throw PrismError.message("The microphone is unavailable.") }; session.addInput(input)
                        let output = AVCaptureAudioDataOutput(); output.setSampleBufferDelegate(self, queue: self.mediaQueue)
                        guard session.canAddOutput(output) else { throw PrismError.message("Microphone monitoring is unavailable.") }; session.addOutput(output)
                    }
                    session.commitConfiguration()
                    if !session.inputs.isEmpty { session.startRunning(); guard session.isRunning else { throw PrismError.message("The selected devices could not start.") }; self.session = session }
                    continuation.resume()
                } catch { continuation.resume(throwing: error) }
            }
        }
        guard requestID == id, !Task.isCancelled else { await stop(); throw CancellationError() }
        do {
            if let filter {
                let config = SCStreamConfiguration(); config.width = 640; config.height = 360
                if let crop { config.sourceRect = crop }
                config.minimumFrameInterval = CMTime(value: 1, timescale: 2); config.queueDepth = 2
                config.pixelFormat = kCVPixelFormatType_32BGRA; config.showsCursor = false
                config.capturesAudio = settings.systemAudio; config.excludesCurrentProcessAudio = true; config.sampleRate = 48000; config.channelCount = 2
                let stream = SCStream(filter: filter, configuration: config, delegate: self)
                if previewScreen { try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: mediaQueue) }
                if settings.systemAudio { try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: mediaQueue) }
                if previewScreen || settings.systemAudio { self.stream = stream; try await stream.startCapture() }
            }
            guard requestID == id, !Task.isCancelled else { await stop(); throw CancellationError() }
            running = true
        } catch { await stop(); throw error }
    }
    @MainActor func stop() async {
        resetID(); running = false
        let active = stream; stream = nil; try? await active?.stopCapture()
        await withCheckedContinuation { continuation in sessionQueue.async { self.session?.stopRunning(); self.session = nil; continuation.resume() } }
        cameraImage = nil; screenImage = nil; microphoneLevel = 0; systemLevel = 0
    }
    private func image(_ buffer: CVPixelBuffer) -> NSImage? {
        let input = CIImage(cvPixelBuffer: buffer)
        let scale = min(1, 640 / input.extent.width)
        let scaled = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        guard let cg = context.createCGImage(scaled, from: scaled.extent) else { return nil }
        return NSImage(cgImage: cg, size: .zero)
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime, id = requestID
        if output is AVCaptureVideoDataOutput {
            guard now - lastCamera >= 0.5, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }; lastCamera = now
            let image = autoreleasepool { self.image(buffer) }
            Task { @MainActor in if self.running && self.requestID == id { self.cameraImage = image } }
        } else {
            guard now - lastMic >= 0.15 else { return }; lastMic = now
            let value = AudioActivity.level(sampleBuffer)
            Task { @MainActor in if self.running && self.requestID == id { self.microphoneLevel = value } }
        }
    }
    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
        let now = ProcessInfo.processInfo.systemUptime, id = requestID
        if type == .audio {
            guard now - lastSystem >= 0.15 else { return }; lastSystem = now
            let value = AudioActivity.level(sampleBuffer)
            Task { @MainActor in if self.running && self.requestID == id { self.systemLevel = value } }
        } else if type == .screen {
            guard now - lastScreen >= 0.5, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }; lastScreen = now
            let image = autoreleasepool { self.image(buffer) }
            Task { @MainActor in if self.running && self.requestID == id { self.screenImage = image } }
        }
    }
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        Task { @MainActor in guard self.stream === stream else { return }; self.issue = error.localizedDescription; await self.stop() }
    }
}
