import Foundation
import AVFoundation

/// Mix only audio. The compressed video packets are copied without decoding or re-encoding.
enum AudioMixer {
    static func mixTracks(at url: URL, format: VideoFormat, systemGain: Float = 0.85, microphoneGain: Float = 0.85) async throws {
        let asset = AVURLAsset(url: url)
        let audio = try await asset.loadTracks(withMediaType: .audio)
        guard audio.count > 1 else { return }
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first,
              let hint = try await videoTrack.load(.formatDescriptions).first else {
            throw PrismError.message("The capture has no readable video track. Your original is preserved.")
        }
        let transform = try await videoTrack.load(.preferredTransform)
        let duration = try await asset.load(.duration)
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".mix-\(UUID().uuidString).\(format.ext)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let reader = try AVAssetReader(asset: asset)
        let videoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: nil)
        videoOutput.alwaysCopiesSampleData = false
        let audioOutput = AVAssetReaderAudioMixOutput(audioTracks: audio, audioSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true, AVLinearPCMIsNonInterleaved: false
        ])
        let mix = AVMutableAudioMix()
        mix.inputParameters = audio.enumerated().map { index, track in
            let parameters = AVMutableAudioMixInputParameters(track: track)
            parameters.setVolume(index == 0 ? systemGain : microphoneGain, at: .zero)
            return parameters
        }
        audioOutput.audioMix = mix
        guard reader.canAdd(videoOutput), reader.canAdd(audioOutput) else { throw PrismError.message("Audio tracks could not be mixed.") }
        reader.add(videoOutput); reader.add(audioOutput)
        let writer = try AVAssetWriter(outputURL: temporary, fileType: format.fileType)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: nil, sourceFormatHint: hint)
        videoInput.transform = transform
        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 48000,
            AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192000
        ])
        guard writer.canAdd(videoInput), writer.canAdd(audioInput) else { throw PrismError.message("The mixed recording could not be created.") }
        writer.add(videoInput); writer.add(audioInput)
        guard writer.startWriting(), reader.startReading() else { throw reader.error ?? writer.error ?? PrismError.message("Could not start the audio mix.") }
        writer.startSession(atSourceTime: .zero)
        let pump = MediaPump(reader: reader, writer: writer, pairs: [(videoOutput, videoInput), (audioOutput, audioInput)])
        try await pump.run()
        writer.endSession(atSourceTime: duration)
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? PrismError.message("Audio mixing failed. Your original is preserved.") }
        _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
    }
}

private final class MediaPump: @unchecked Sendable {
    let reader: AVAssetReader
    let writer: AVAssetWriter
    let pairs: [(AVAssetReaderOutput, AVAssetWriterInput)]
    let queue = DispatchQueue(label: "studio.prism.audio-mix", qos: .utility)
    var remaining: Int
    var completed = false
    var continuation: CheckedContinuation<Void, Error>?

    init(reader: AVAssetReader, writer: AVAssetWriter, pairs: [(AVAssetReaderOutput, AVAssetWriterInput)]) {
        self.reader = reader; self.writer = writer; self.pairs = pairs; remaining = pairs.count
    }
    func run() async throws {
        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            for index in pairs.indices {
                let input = pairs[index].1
                input.requestMediaDataWhenReady(on: queue) { [self] in
                    let (output, input) = pairs[index]
                    while input.isReadyForMoreMediaData && !completed {
                        let hasMore: Bool = autoreleasepool {
                            guard let sample = output.copyNextSampleBuffer() else { return false }
                            if !input.append(sample) { finish(error: writer.error ?? PrismError.message("An audio mix packet could not be saved.")) }
                            return true
                        }
                        if !hasMore {
                            input.markAsFinished(); remaining -= 1
                            if reader.status == .failed { finish(error: reader.error ?? PrismError.message("The recording could not be read.")) }
                            else if remaining == 0 { finish(error: nil) }
                            return
                        }
                    }
                }
            }
        }
    }
    private func finish(error: Error?) {
        guard !completed else { return }; completed = true
        if let error { reader.cancelReading(); writer.cancelWriting(); continuation?.resume(throwing: error) }
        else { continuation?.resume() }
        continuation = nil
    }
}
