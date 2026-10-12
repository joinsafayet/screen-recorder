import AppKit
import AVFoundation
import CoreImage

@MainActor enum AppContext { static weak var model: AppModel? }
extension Verification {
    func testAdjustableRegionsAndSavedAreas() throws {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let area = CGRect(x: 70, y: 80, width: 320, height: 180)
        expect(RegionGeometry.move(area, dx: 1000, dy: -1000, in: bounds) == CGRect(x: 480, y: 0, width: 320, height: 180))
        for handle in RegionHandle.allCases {
            let resized = RegionGeometry.resize(area, handle: handle, dx: 100, dy: 100, in: bounds, aspect: .free)
            expect(bounds.contains(resized) && resized.width >= 32 && resized.height >= 32)
        }
        let portrait = RegionGeometry.fit(area, in: bounds, aspect: .portrait)
        expect(abs(portrait.width / portrait.height - 9 / 16) < 0.001 && bounds.contains(portrait))
        let saved = SavedRegion(name: "Tutorial", displayID: 10, rect: area)
        let restored = try JSONDecoder().decode(SavedRegion.self, from: JSONEncoder().encode(saved))
        expect(restored == saved)
    }
}

extension Verification {
    func testPreparationEstimatesAndAudioMeter() {
        var settings = CaptureSettings()
        let hd = PreparationEstimate.make(source: CGSize(width: 3840, height: 2160), scale: 1, settings: settings)
        expect(hd.width == 1920 && hd.height == 1080 && hd.bytesPerMinute > 60_000_000)
        settings.fps = 60
        let faster = PreparationEstimate.make(source: CGSize(width: 3840, height: 2160), scale: 1, settings: settings)
        expect(faster.bytesPerMinute > hd.bytesPerMinute * 19 / 10)
        expect(AudioActivity.rms([]) == 0 && AudioActivity.rms([0, 0, 0]) == 0)
        expect(abs(AudioActivity.rms([0.1, -0.1]) - 0.4) < 0.001)
        expect(AudioActivity.rms([1, -1]) == 1)
    }
}

extension Verification {
    func testRecoveryJournalOrderingAndPathValidation() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("prism-journal-\(UUID())")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = CaptureJournalStore(folder: folder)
        var journal = CaptureJournal(filename: "take.mov", title: "My take", source: "Window", settings: CaptureSettings())
        try await store.begin(journal)
        let pending = await CaptureJournalStore.pending(in: folder)
        expect(pending.count == 1 && pending[0].title == "My take")
        journal.activeDuration = 42; store.checkpoint(journal)
        try await store.complete(journal.id)
        store.checkpoint(journal)
        try await Task.sleep(for: .milliseconds(30))
        let remaining = await CaptureJournalStore.pending(in: folder)
        expect(remaining.isEmpty)
        let invalid = CaptureJournal(filename: "../outside.mov", title: "Unsafe", source: "Window", settings: CaptureSettings())
        expect(invalid.mediaURL(in: folder) == nil)
        do { try await store.begin(invalid); expect(false, "Reject journal traversal") } catch {}
    }
    @MainActor func testInterruptedFragmentIsPlayableAndRecoverable() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("prism-interrupted-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("interrupted.mov")
        let process = Process(); process.executableURL = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        process.arguments = ["--interrupted-fixture", url.path]
        process.standardOutput = Pipe(); process.standardError = Pipe(); try process.run()
        await Task.detached { process.waitUntilExit() }.value
        expect(process.terminationStatus == 0)
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        expect(duration > 8 && duration < 14, "A completed fragment must survive without finishWriting")
        let generator = AVAssetImageGenerator(asset: asset)
        let image = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image
        expect(image.width == 320)
        var settings = CaptureSettings(); settings.format = .mov
        let journal = CaptureJournal(filename: url.lastPathComponent, title: "Important demo", source: "Test window", settings: settings,
            activeDuration: 13, markers: [RecordingMarker(time: 1, title: "Kept"), RecordingMarker(time: 100, title: "Outside")])
        try await CaptureJournalStore(folder: folder).begin(journal)
        let library = LibraryStore(folder: folder, support: folder.appendingPathComponent("Index"))
        let count = try await library.recoverRecordings()
        expect(count == 1 && library.recordings[0].title == "Important demo — recovered")
        expect(library.recordings[0].markers?.count == 1)
        let remaining = await CaptureJournalStore.pending(in: folder)
        expect(remaining.isEmpty)
    }
}

extension Verification {
    @MainActor func testTimelineHistoryGeometryAndValidation() throws {
        let id = UUID(); let history = TimelineHistory(TimelineDocument(recordingID: id, duration: 10))
        history.change { _ = $0.split(at: 4) }
        expect(history.document.cuts.count == 2 && history.document.duration == 10)
        history.change { $0.cuts.removeFirst() }
        expect(history.document.duration == 6 && history.document.sourceTime(at: 1) == 5)
        history.undo(); expect(history.document.cuts.count == 2)
        history.undo(); expect(history.document.cuts.count == 1)
        history.redo(); expect(history.document.cuts.count == 2)
        let crop = TimelineGeometry.cropRect(source: CGSize(width: 1920, height: 1080), normalized: CGRect(x: 0, y: 0, width: 1, height: 1), aspect: .portrait)
        expect(abs(crop.width / crop.height - 9 / 16) < 0.001)
        var document = history.document; document.zooms = [ZoomKeyframe(time: 0, scale: 1), ZoomKeyframe(time: 4, scale: 3)]
        expect(abs(document.zoom(at: 2).scale - 2) < 0.001)
        try document.validate(sourceDuration: 10)
        document.cuts[0].end = 100
        do { try document.validate(sourceDuration: 10); expect(false, "Reject ranges outside the original") } catch {}
    }
    @MainActor func testTimelineExportCutsCropAndEditPersistence() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("prism-timeline-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.mp4"), target = folder.appendingPathComponent("edited.mov")
        var settings = CaptureSettings(); settings.systemAudio = false
        let writer = try RecordingWriter(url: source, size: (320, 180), settings: settings)
        for i in 0..<60 { writer.consume(try frame(at: 10 + Double(i) / 20), type: .screen); try await Task.sleep(for: .milliseconds(3)) }
        try await writer.finish(activeDuration: 3)
        let original = try Data(contentsOf: source)
        let library = LibraryStore(folder: folder, support: folder.appendingPathComponent("Index"))
        let recording = try await library.add(url: source, source: "Fixture", fps: 20)
        var document = TimelineDocument(recordingID: recording.id, duration: recording.duration)
        document.cuts = [TimelineCut(start: 0.2, end: 0.7), TimelineCut(start: 1.5, end: 2.2)]
        document.annotations = [TimelineAnnotation(kind: .arrow, start: 0, end: 1.2, points: [AnnotationPoint(x: 0.2, y: 0.5), AnnotationPoint(x: 0.8, y: 0.5)], color: 0x00FF00)]
        document.aspect = .square; document.zooms = [ZoomKeyframe(time: 0, scale: 1.2)]
        try await library.saveEdits(recording, document: document)
        let restored = try await library.loadEdits(recording); expect(restored == document)
        try await TimelineRenderer.export(source: source, target: target, document: document, format: .mov)
        let asset = AVURLAsset(url: target)
        let duration = try await asset.load(.duration).seconds
        expect(abs(duration - 1.2) < 0.1)
        let track = try await asset.loadTracks(withMediaType: .video)[0]
        let size = try await track.load(.naturalSize); expect(size == CGSize(width: 180, height: 180))
        let generator = AVAssetImageGenerator(asset: asset)
        let image = try await generator.image(at: CMTime(seconds: 0.3, preferredTimescale: 600)).image
        expect(image.width == 180 && image.height == 180)
        let after = try Data(contentsOf: source); expect(after == original)
        let unchanged = try Data(contentsOf: target)
        let task = Task { try await TimelineRenderer.export(source: source, target: target, document: document, format: .mov) }
        task.cancel(); do { try await task.value; expect(false, "Cancelled edits must not replace a destination") } catch {}
        let afterCancel = try Data(contentsOf: target); expect(afterCancel == unchanged)
    }
}

extension Verification {
    func testShortcutFilteringAndCaptionRemapping() {
        expect(ShortcutFormatter.label(code: 0, flags: []) == nil, "Do not capture plain typing")
        expect(ShortcutFormatter.label(code: 0, flags: [.maskShift]) == nil)
        expect(ShortcutFormatter.label(code: 8, flags: [.maskCommand]) == "⌘ C")
        expect(ShortcutFormatter.label(code: 15, flags: [.maskCommand, .maskControl]) == "⌃⌘ R")
        var document = TimelineDocument(recordingID: UUID(), duration: 10)
        document.cuts = [TimelineCut(start: 2, end: 4), TimelineCut(start: 6, end: 8)]
        document.captions = [CaptionCue(start: 1, end: 3, text: "First"), CaptionCue(start: 6.5, end: 7.5, text: "Second")]
        let cues = CaptionService.editedCues(document: document)
        expect(cues.count == 2 && cues[0].start == 0 && cues[0].end == 1 && cues[1].start == 2.5)
        let text = CaptionService.srt(cues)
        expect(text.contains("00:00:02,500 --> 00:00:03,500") && text.contains("Second"))
    }
    func testPresentationRasterAndPointerInterpolation() throws {
        let size = CGSize(width: 320, height: 180)
        let base = CIImage(color: CIColor(red: 1, green: 0, blue: 0)).cropped(to: CGRect(origin: .zero, size: size))
        var document = TimelineDocument(recordingID: UUID(), duration: 5)
        document.annotations = [TimelineAnnotation(kind: .arrow, start: 0, end: 3, points: [AnnotationPoint(x: 0.2, y: 0.5), AnnotationPoint(x: 0.8, y: 0.5)], color: 0x00FF00, thickness: 0.03)]
        let result = TimelineEffects().render(base, document: document, time: 1, sourceSize: size, region: CGRect(origin: .zero, size: size), output: size)
        let image = CIContext().createCGImage(result, from: result.extent)!
        var bytes = [UInt8](repeating: 0, count: 320 * 180 * 4)
        bytes.withUnsafeMutableBytes { storage in
            let context = CGContext(data: storage.baseAddress, width: 320, height: 180, bitsPerComponent: 8, bytesPerRow: 320 * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.draw(image, in: CGRect(origin: .zero, size: size))
        }
        let offset = (90 * 320 + 160) * 4
        expect(bytes[offset + 1] > 150 && bytes[offset] < 100, "Draw the editable arrow into the video frame")
        let pointer = TimelineEffects.pointer(at: 0.125, samples: [PointerSample(time: 0, x: 0.2, y: 0.4), PointerSample(time: 0.25, x: 0.8, y: 0.6)])
        expect(abs((pointer?.x ?? 0) - 0.5) < 0.001)
        expect(TimelineEffects.pointer(at: 10, samples: [PointerSample(time: 0, x: 0.2, y: 0.4)]) == nil)
    }
}

extension Verification {
    @MainActor func testLibraryOrganizationAndBatchFavorites() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("prism-organization-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.mp4")
        var settings = CaptureSettings(); settings.systemAudio = false
        let writer = try RecordingWriter(url: source, size: (320, 180), settings: settings)
        writer.consume(try frame(at: 10), type: .screen); try await Task.sleep(for: .milliseconds(30)); try await writer.finish(activeDuration: 0.5)
        let library = LibraryStore(folder: folder, support: folder.appendingPathComponent("Index"))
        let recording = try await library.add(url: source, source: "Fixture", fps: 30)
        try library.organize(ids: [recording.id], project: " Course ", tags: "Swift, tutorial, Swift, ")
        try library.setFavorite(ids: [recording.id], value: true)
        let restored = LibraryStore(folder: folder, support: folder.appendingPathComponent("Index"))
        expect(restored.recordings[0].project == "Course" && restored.recordings[0].tags == ["Swift", "tutorial"] && restored.recordings[0].favorite)
        do { try library.validateExportTarget(source); expect(false, "Protect every library original") } catch {}
    }
    @MainActor func testExportQueueCapturePriorityAndPersistence() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("prism-queue-\(UUID())")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appendingPathComponent("source.mp4"), target = folder.appendingPathComponent("copy.mp4")
        var settings = CaptureSettings(); settings.systemAudio = false
        let writer = try RecordingWriter(url: source, size: (320, 180), settings: settings)
        for index in 0..<30 { writer.consume(try frame(at: 10 + Double(index) / 30), type: .screen); try await Task.sleep(for: .milliseconds(3)) }
        try await writer.finish(activeDuration: 1)
        let original = try Data(contentsOf: source)
        let library = LibraryStore(folder: folder, support: folder.appendingPathComponent("Index"))
        let recording = try await library.add(url: source, source: "Fixture", fps: 30)
        var document = TimelineDocument(recordingID: recording.id, duration: recording.duration); document.aspect = .square
        let queue = ExportQueue(library: library)
        try queue.enqueue(recording: recording, target: target, document: document, quality: .compact, format: .mp4)
        queue.setCaptureActive(true); queue.start()
        try await Task.sleep(for: .milliseconds(50)); expect(queue.jobs[0].status == .waiting && !FileManager.default.fileExists(atPath: target.path))
        queue.setCaptureActive(false); queue.start(); await queue.waitUntilIdle(); await queue.flush()
        expect(queue.jobs[0].status == .completed && queue.jobs[0].progress == 1)
        let track = try await AVURLAsset(url: target).loadTracks(withMediaType: .video)[0]
        let size = try await track.load(.naturalSize); expect(size.width == size.height)
        let restored = ExportQueue(library: library); expect(restored.jobs.count == 1 && restored.jobs[0].status == .completed)
        let after = try Data(contentsOf: source); expect(after == original)
    }
}
