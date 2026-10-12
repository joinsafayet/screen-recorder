import AppKit
import AVFoundation

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
