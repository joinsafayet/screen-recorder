import Foundation

struct CaptureJournal: Codable, Equatable {
    var id = UUID()
    var filename: String
    var title: String
    var source: String
    var settings: CaptureSettings
    var createdAt = Date()
    var activeDuration: Double = 0
    var markers: [RecordingMarker] = []
    func mediaURL(in folder: URL) -> URL? {
        guard filename == URL(fileURLWithPath: filename).lastPathComponent,
              ["mp4", "mov"].contains(URL(fileURLWithPath: filename).pathExtension.lowercased()) else { return nil }
        let base = folder.standardizedFileURL.resolvingSymlinksInPath()
        let media = base.appendingPathComponent(filename).resolvingSymlinksInPath()
        return media.path.hasPrefix(base.path + "/") ? media : nil
    }
}

/// A serial utility queue orders checkpoint writes and final removal without blocking capture or UI.
final class CaptureJournalStore: @unchecked Sendable {
    let folder: URL
    private let queue = DispatchQueue(label: "prism.capture.journal", qos: .utility)
    init(folder: URL) { self.folder = folder }
    private var directory: URL { folder.appendingPathComponent(".prism-recovery", isDirectory: true) }
    private func url(_ id: UUID) -> URL { directory.appendingPathComponent(id.uuidString + ".json") }
    private func write(_ journal: CaptureJournal) throws {
        guard journal.mediaURL(in: folder) != nil else { throw PrismError.message("The recovery checkpoint has an invalid file location.") }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try JSONEncoder().encode(journal).write(to: url(journal.id), options: .atomic)
    }
    func begin(_ journal: CaptureJournal) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in queue.async {
            do { try self.write(journal); continuation.resume() } catch { continuation.resume(throwing: error) }
        } }
    }
    func checkpoint(_ journal: CaptureJournal) {
        queue.async { if FileManager.default.fileExists(atPath: self.url(journal.id).path) { try? self.write(journal) } }
    }
    func complete(_ id: UUID) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in queue.async {
            do { if FileManager.default.fileExists(atPath: self.url(id).path) { try FileManager.default.removeItem(at: self.url(id)) }; continuation.resume() }
            catch { continuation.resume(throwing: error) }
        } }
    }
    static func pending(in folder: URL) async -> [CaptureJournal] {
        await Task.detached(priority: .utility) {
            let directory = folder.appendingPathComponent(".prism-recovery", isDirectory: true)
            let urls = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
            return urls.compactMap { url -> CaptureJournal? in
                guard url.pathExtension == "json", let data = try? Data(contentsOf: url), let item = try? JSONDecoder().decode(CaptureJournal.self, from: data), item.mediaURL(in: folder) != nil else { return nil }
                return item
            }.sorted { $0.createdAt < $1.createdAt }
        }.value
    }
}
