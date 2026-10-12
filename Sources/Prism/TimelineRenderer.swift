import AVFoundation
import CoreImage

struct TimelineComposition {
    let asset: AVMutableComposition
    let video: AVMutableVideoComposition
    let audio: AVMutableAudioMix
}
enum TimelineRenderer {
    static func compose(source: URL, document: TimelineDocument, quality: ExportQuality = .original) async throws -> TimelineComposition {
        let sourceAsset = AVURLAsset(url: source)
        let duration = try await sourceAsset.load(.duration).seconds
        try document.validate(sourceDuration: duration)
        guard let sourceVideo = try await sourceAsset.loadTracks(withMediaType: .video).first else { throw PrismError.message("No video track is available.") }
        let sourceAudios = try await sourceAsset.loadTracks(withMediaType: .audio)
        let size = try await sourceVideo.load(.naturalSize)
        let transform = try await sourceVideo.load(.preferredTransform)
        let visible = CGRect(origin: .zero, size: size).applying(transform).standardized.size
        let crop = TimelineGeometry.cropRect(source: visible, normalized: document.crop, aspect: document.aspect)
        let maximum = quality == .compact ? 720 : quality == .hd ? 1080 : Int(crop.height)
        let output = RecordingMath.outputSize(source: crop.size, scale: 1, maxHeight: max(2, maximum))
        let composition = AVMutableComposition()
        guard let videoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid) else { throw PrismError.message("Could not create the editing timeline.") }
        videoTrack.preferredTransform = transform
        let audioTracks = sourceAudios.compactMap { _ in composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) }
        var cursor = CMTime.zero
        for cut in document.cuts {
            try Task.checkCancellation()
            let range = CMTimeRange(start: CMTime(seconds: cut.start, preferredTimescale: 60000), duration: CMTime(seconds: cut.duration, preferredTimescale: 60000))
            try videoTrack.insertTimeRange(range, of: sourceVideo, at: cursor)
            for (sourceAudio, targetAudio) in zip(sourceAudios, audioTracks) {
                let audioRange = try await sourceAudio.load(.timeRange)
                let available = CMTimeRangeGetIntersection(range, otherRange: audioRange)
                if available.duration.seconds > 0 { try targetAudio.insertTimeRange(available, of: sourceAudio, at: cursor + available.start - range.start) }
            }
            cursor = cursor + range.duration
        }
        let effects = TimelineEffects()
        var recipe = document; recipe.captions.sort { $0.start < $1.start }; recipe.pointers.sort { $0.time < $1.time }; recipe.shortcuts.sort { $0.time < $1.time }
        let sortedRecipe = recipe
        let applier: @Sendable (AVAsynchronousCIImageFilteringRequest) -> Void = { request in
            autoreleasepool {
                let zoom = document.zoom(at: request.compositionTime.seconds)
                let zoomWidth = crop.width / zoom.scale, zoomHeight = crop.height / zoom.scale
                let x = min(crop.maxX - zoomWidth, max(crop.minX, crop.minX + crop.width * zoom.x - zoomWidth / 2))
                let y = min(crop.maxY - zoomHeight, max(crop.minY, crop.minY + crop.height * (1 - zoom.y) - zoomHeight / 2))
                let region = CGRect(x: x, y: y, width: zoomWidth, height: zoomHeight)
                let image = request.sourceImage.cropped(to: region)
                    .transformed(by: CGAffineTransform(translationX: -region.minX, y: -region.minY))
                    .transformed(by: CGAffineTransform(scaleX: CGFloat(output.width) / region.width, y: CGFloat(output.height) / region.height))
                let result = effects.render(image, document: sortedRecipe, time: request.compositionTime.seconds, sourceSize: visible, region: region, output: CGSize(width: output.width, height: output.height))
                request.finish(with: result, context: nil)
            }
        }
        let videoComposition: AVMutableVideoComposition = try await withCheckedThrowingContinuation { continuation in
            AVMutableVideoComposition.videoComposition(with: composition, applyingCIFiltersWithHandler: applier) { video, error in
                if let video { continuation.resume(returning: video) }
                else { continuation.resume(throwing: error ?? PrismError.message("The video preview could not be created.")) }
            }
        }
        videoComposition.renderSize = CGSize(width: output.width, height: output.height)
        let nominal = try await sourceVideo.load(.nominalFrameRate)
        videoComposition.frameDuration = CMTime(value: 1, timescale: CMTimeScale(min(60, max(24, nominal.rounded()))))
        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = audioTracks.map { track in
            let parameters = AVMutableAudioMixInputParameters(track: track)
            let gain = Float(document.audioGain)
            parameters.setVolume(gain, at: .zero)
            let fadeIn = min(document.duration / 2, document.fadeIn), fadeOut = min(document.duration / 2, document.fadeOut)
            if fadeIn > 0 { parameters.setVolumeRamp(fromStartVolume: 0, toEndVolume: gain, timeRange: CMTimeRange(start: .zero, duration: CMTime(seconds: fadeIn, preferredTimescale: 60000))) }
            if fadeOut > 0 { parameters.setVolumeRamp(fromStartVolume: gain, toEndVolume: 0, timeRange: CMTimeRange(start: CMTime(seconds: document.duration - fadeOut, preferredTimescale: 60000), duration: CMTime(seconds: fadeOut, preferredTimescale: 60000))) }
            return parameters
        }
        return TimelineComposition(asset: composition, video: videoComposition, audio: audioMix)
    }
    static func export(source: URL, target: URL, document: TimelineDocument, format: VideoFormat, quality: ExportQuality = .original, progress: @escaping (Float) -> Void = { _ in }) async throws {
        guard source.standardizedFileURL.resolvingSymlinksInPath() != target.standardizedFileURL.resolvingSymlinksInPath() else { throw PrismError.message("Export a copy to preserve the original recording.") }
        let timeline = try await compose(source: source, document: document, quality: quality)
        guard let session = AVAssetExportSession(asset: timeline.asset, presetName: AVAssetExportPresetHighestQuality) else { throw PrismError.message("This timeline could not be exported.") }
        session.videoComposition = timeline.video; session.audioMix = timeline.audio; session.shouldOptimizeForNetworkUse = true
        let temporary = target.deletingLastPathComponent().appendingPathComponent(".prism-timeline-\(UUID()).\(format.ext)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let polling = Task { while !Task.isCancelled { progress(session.progress); do { try await Task.sleep(for: .milliseconds(200)) } catch { break } } }
        defer { polling.cancel() }
        try await withTaskCancellationHandler {
            try Task.checkCancellation(); try await session.export(to: temporary, as: format.fileType); try Task.checkCancellation()
        } onCancel: { session.cancelExport() }
        if FileManager.default.fileExists(atPath: target.path) { _ = try FileManager.default.replaceItemAt(target, withItemAt: temporary) }
        else { try FileManager.default.moveItem(at: temporary, to: target) }
        progress(1)
    }
}
