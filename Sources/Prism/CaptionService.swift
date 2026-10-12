import AVFoundation
import Speech

private final class SpeechResultLatch: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<SFSpeechRecognitionResult, Error>?
    private var storedTask: SFSpeechRecognitionTask?
    private var terminal: Result<SFSpeechRecognitionResult, Error>?
    var task: SFSpeechRecognitionTask? {
        get { lock.lock(); defer { lock.unlock() }; return storedTask }
        set { lock.lock(); storedTask = newValue; let finished = terminal != nil; lock.unlock(); if finished { newValue?.cancel() } }
    }
    func install(_ value: CheckedContinuation<SFSpeechRecognitionResult, Error>) { lock.lock(); let result = terminal; if result == nil { continuation = value }; lock.unlock(); if let result { value.resume(with: result) } }
    func finish(_ result: Result<SFSpeechRecognitionResult, Error>) {
        lock.lock(); guard terminal == nil else { lock.unlock(); return }; terminal = result; let pending = continuation; continuation = nil; lock.unlock(); pending?.resume(with: result)
    }
    func cancel() { task?.cancel(); finish(.failure(CancellationError())) }
}
enum CaptionService {
    static func generate(source: URL, locale: Locale, progress: @escaping (Double) -> Void) async throws -> [CaptionCue] {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.supportsOnDeviceRecognition else {
            throw PrismError.message("On-device speech recognition is unavailable for this language on your Mac. You can add captions manually. Audio is never sent to a server.")
        }
        let status = await withCheckedContinuation { continuation in SFSpeechRecognizer.requestAuthorization { continuation.resume(returning: $0) } }
        guard status == .authorized else { throw PrismError.message("Allow Speech Recognition in System Settings to generate captions locally.") }
        let asset = AVURLAsset(url: source); let duration = try await asset.load(.duration).seconds
        guard !(try await asset.loadTracks(withMediaType: .audio)).isEmpty else { throw PrismError.message("This recording has no audio. Add captions manually instead.") }
        var cues: [CaptionCue] = []
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("prism-captions-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        var offset = 0.0
        while offset < duration {
            try Task.checkCancellation()
            guard let exporter = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else { throw PrismError.message("The audio could not be prepared for captions.") }
            let length = min(45, duration - offset), chunk = folder.appendingPathComponent("part.m4a")
            try? FileManager.default.removeItem(at: chunk)
            exporter.timeRange = CMTimeRange(start: CMTime(seconds: offset, preferredTimescale: 60000), duration: CMTime(seconds: length, preferredTimescale: 60000))
            try await withTaskCancellationHandler { try await exporter.export(to: chunk, as: .m4a) } onCancel: { exporter.cancelExport() }
            let result = try await recognize(chunk, using: recognizer)
            var words: [String] = [], start = 0.0, end = 0.0
            for segment in result.bestTranscription.segments {
                if words.isEmpty { start = segment.timestamp }
                words.append(segment.substring); end = segment.timestamp + max(0.12, segment.duration)
                if words.count >= 6 || end - start >= 3 {
                    cues.append(CaptionCue(start: offset + start, end: min(duration, offset + end), text: words.joined(separator: locale.language.languageCode?.identifier == "ja" ? "" : " "))); words = []
                }
            }
            if !words.isEmpty { cues.append(CaptionCue(start: offset + start, end: min(duration, offset + end), text: words.joined(separator: " "))) }
            offset += length; progress(offset / duration)
        }
        return cues
    }
    private static func recognize(_ url: URL, using recognizer: SFSpeechRecognizer) async throws -> SFSpeechRecognitionResult {
        let latch = SpeechResultLatch()
        let timeout = Task { do { try await Task.sleep(for: .seconds(90)); latch.finish(.failure(PrismError.message("Local recognition timed out. Try a shorter recording or add captions manually."))); latch.task?.cancel() } catch {} }
        defer { timeout.cancel() }
        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                latch.install(continuation)
                let request = SFSpeechURLRecognitionRequest(url: url); request.requiresOnDeviceRecognition = true; request.shouldReportPartialResults = false
                latch.task = recognizer.recognitionTask(with: request) { result, error in
                    if let result, result.isFinal { latch.finish(.success(result)) }
                    else if let error { latch.finish(.failure(error)) }
                }
            }
        } onCancel: { latch.cancel() }
    }
    static func editedCues(document: TimelineDocument) -> [CaptionCue] {
        var result: [CaptionCue] = [], offset = 0.0
        for cut in document.cuts {
            for cue in document.captions {
                let start = max(cut.start, cue.start), end = min(cut.end, cue.end)
                if end > start { result.append(CaptionCue(start: offset + start - cut.start, end: offset + end - cut.start, text: cue.text)) }
            }
            offset += cut.duration
        }
        return result.sorted { $0.start < $1.start }
    }
    static func srt(_ cues: [CaptionCue]) -> String {
        func clock(_ seconds: Double) -> String {
            let milliseconds = max(0, Int((seconds * 1000).rounded()))
            return String(format: "%02d:%02d:%02d,%03d", milliseconds / 3_600_000, milliseconds / 60_000 % 60, milliseconds / 1000 % 60, milliseconds % 1000)
        }
        return cues.enumerated().map { "\($0.offset + 1)\n\(clock($0.element.start)) --> \(clock($0.element.end))\n\($0.element.text)\n" }.joined(separator: "\n")
    }
}
