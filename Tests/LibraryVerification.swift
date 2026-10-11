import Foundation
import AVFoundation

extension Verification {
    @MainActor func testLibraryPersistenceRecoveryAndFailedWrites() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("prism-library-check-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Videos"), support = root.appendingPathComponent("Index")
        let store = LibraryStore(folder: folder, support: support)
        let video = folder.appendingPathComponent("Prism recovered take.mp4")
        var settings = CaptureSettings(); settings.systemAudio = false
        let writer = try RecordingWriter(url: video, size: (320, 180), settings: settings)
        writer.consume(try makeFrame(width: 320, height: 180, at: 10, value: 100), type: .screen)
        try await Task.sleep(for: .milliseconds(50)); try await writer.finish(activeDuration: 0.4)
        let originalVideo = try Data(contentsOf: video)
        let markers = [RecordingMarker(time: 0.2, title: "Explain the shortcut")]
        let recording = try await store.add(url: video, source: "Verification", fps: 30, title: "A professional take", markers: markers)
        try store.favorite(recording); try store.rename(recording, title: "Renamed take")
        let reopened = LibraryStore(folder: folder, support: support)
        expect(reopened.recordings.count == 1 && reopened.recordings[0].favorite)
        expect(reopened.recordings[0].markers == markers && reopened.recordings[0].title == "Renamed take")
        let thumbnail = await reopened.thumbnail(for: reopened.recordings[0])
        expect(thumbnail != nil)
        let index = support.appendingPathComponent("library.json")
        try Data("broken index".utf8).write(to: index)
        let recovering = LibraryStore(folder: folder, support: support)
        expect(recovering.notice != nil)
        let backups = try FileManager.default.contentsOfDirectory(atPath: support.path).filter { $0.hasPrefix("library-backup-") }
        expect(backups.count == 1)
        let brokenCapture = folder.appendingPathComponent("Prism interrupted.mp4")
        try Data("incomplete video".utf8).write(to: brokenCapture)
        let count = try await recovering.recoverRecordings()
        expect(count == 1 && recovering.recordings.count == 1)
        expect(FileManager.default.fileExists(atPath: brokenCapture.path), "Recovery must preserve unreadable files")
        let afterRecovery = try Data(contentsOf: video)
        expect(afterRecovery == originalVideo)
        let beforeFailure = recovering.recordings
        try FileManager.default.removeItem(at: index)
        try FileManager.default.createDirectory(at: index, withIntermediateDirectories: false)
        do { try recovering.rename(recovering.recordings[0], title: "Should not commit"); expect(false) } catch {}
        expect(recovering.recordings == beforeFailure, "A failed index write must not mutate the published library")
    }
}
