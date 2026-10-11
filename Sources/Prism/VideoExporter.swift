import AVFoundation

enum VideoExporter {
    static func export(source: URL, target: URL, range: ClosedRange<Double>?, format: VideoFormat,
                       quality: ExportQuality = .original, progress: @escaping (Float) -> Void = { _ in }) async throws {
        guard target.standardizedFileURL.resolvingSymlinksInPath() != source.standardizedFileURL.resolvingSymlinksInPath() else { throw PrismError.message("Choose a different location to keep the original recording.") }
        let temporary = target.deletingLastPathComponent().appendingPathComponent(".prism-export-\(UUID().uuidString).\(format.ext)")
        defer { try? FileManager.default.removeItem(at: temporary) }
        let asset = AVURLAsset(url: source)
        let duration = try await asset.load(.duration).seconds
        guard let session = AVAssetExportSession(asset: asset, presetName: quality.preset(trimmed: range != nil)) else { throw PrismError.message("This video could not be exported.") }
        if let range {
            guard range.lowerBound.isFinite, range.upperBound.isFinite, range.lowerBound >= 0, range.upperBound <= duration + 0.001, range.upperBound > range.lowerBound else { throw PrismError.message("Select a valid trim range.") }
            session.timeRange = CMTimeRange(start: CMTime(seconds: range.lowerBound, preferredTimescale: 600), end: CMTime(seconds: range.upperBound, preferredTimescale: 600))
        }
        session.shouldOptimizeForNetworkUse = true
        progress(0)
        let polling = Task {
            while !Task.isCancelled {
                progress(session.progress)
                do { try await Task.sleep(for: .milliseconds(200)) } catch { break }
            }
        }
        defer { polling.cancel() }
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await session.export(to: temporary, as: format.fileType)
            try Task.checkCancellation()
        } onCancel: { session.cancelExport() }
        if FileManager.default.fileExists(atPath: target.path) { _ = try FileManager.default.replaceItemAt(target, withItemAt: temporary) }
        else { try FileManager.default.moveItem(at: temporary, to: target) }
        progress(1)
    }
}
