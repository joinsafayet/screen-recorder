import Foundation
import Combine

enum OutputPreset: String, CaseIterable, Codable, Identifiable {
    case current = "Current edit", wide = "Widescreen", portrait = "Portrait", square = "Square", small = "Small file"
    var id: String { rawValue }
    var aspect: CaptureAspect? { switch self { case .current, .small: return nil; case .wide: return .wide; case .portrait: return .portrait; case .square: return .square } }
    var quality: ExportQuality { self == .small ? .compact : self == .portrait ? .full : self == .current ? .original : .hd }
}
struct SavedOutputPreset: Codable, Identifiable {
    var id = UUID()
    var name: String
    var aspect: CaptureAspect
    var quality: ExportQuality
    var format: VideoFormat
}
enum ExportJobStatus: String, Codable { case waiting, running, completed, failed, cancelled }
struct ExportJob: Codable, Identifiable {
    var id = UUID()
    var recordingID: UUID
    var title: String
    var targetPath: String
    var document: TimelineDocument
    var quality: ExportQuality
    var format: VideoFormat
    var status: ExportJobStatus = .waiting
    var progress: Float = 0
    var error: String?
}

@MainActor final class ExportQueue: ObservableObject {
    @Published private(set) var jobs: [ExportJob] = []
    @Published private(set) var running = false
    @Published private(set) var captureActive = false
    @Published var issue: String?
    private let library: LibraryStore
    private let file: URL
    private let disk = DispatchQueue(label: "prism.export.queue.storage", qos: .utility)
    private var task: Task<Void, Never>?
    private var writable = true
    init(library: LibraryStore) {
        self.library = library; file = library.supportDirectory.appendingPathComponent("export-queue.json")
        if FileManager.default.fileExists(atPath: file.path) {
            do { jobs = try JSONDecoder().decode([ExportJob].self, from: Data(contentsOf: file)); for index in jobs.indices where jobs[index].status == .running { jobs[index].status = .waiting; jobs[index].progress = 0 } }
            catch {
                let backup = file.deletingLastPathComponent().appendingPathComponent("export-queue-backup-\(UUID()).json")
                do { try FileManager.default.copyItem(at: file, to: backup) } catch { writable = false }
                issue = "The export queue could not be read. Its index was preserved; recording originals are unaffected."
            }
        }
    }
    var pendingCount: Int { jobs.filter { $0.status == .waiting || $0.status == .running }.count }
    func enqueue(recordings: [Recording], folder: URL, preset: OutputPreset) async throws {
        guard writable else { throw PrismError.message("The export queue cannot be saved safely.") }
        guard jobs.count + recordings.count <= 500 else { throw PrismError.message("Clear finished jobs before adding more exports.") }
        var added: [ExportJob] = []
        for recording in recordings {
            var document = try await library.loadEdits(recording) ?? TimelineDocument(recordingID: recording.id, duration: recording.duration)
            if let aspect = preset.aspect { document.aspect = aspect }
            let title = recording.title.map { "/\\:\n\r".contains($0) ? "_" : $0 }
            let filename = String(title.prefix(100)) + " — " + preset.rawValue + " " + String(UUID().uuidString.prefix(6)) + ".mp4"
            added.append(ExportJob(recordingID: recording.id, title: recording.title, targetPath: folder.appendingPathComponent(filename).path, document: document, quality: preset.quality, format: .mp4))
        }
        jobs.append(contentsOf: added); persist(); if running { drain() }
    }
    func enqueue(recording: Recording, target: URL, document: TimelineDocument, quality: ExportQuality, format: VideoFormat) throws {
        guard writable else { throw PrismError.message("The export queue cannot be saved safely.") }
        try document.validate(sourceDuration: recording.duration)
        try library.validateExportTarget(target)
        guard target.resolvingSymlinksInPath() != library.fileURL(recording).resolvingSymlinksInPath() else { throw PrismError.message("Choose a copy location to preserve the original.") }
        jobs.append(ExportJob(recordingID: recording.id, title: recording.title, targetPath: target.path, document: document, quality: quality, format: format)); persist(); if running { drain() }
    }
    func start() { guard !captureActive, writable else { return }; running = true; drain() }
    func pause() { running = false; task?.cancel() }
    func flush() async { await withCheckedContinuation { continuation in disk.async { continuation.resume() } } }
    func waitUntilIdle() async { let current = task; await current?.value }
    func setCaptureActive(_ active: Bool) { captureActive = active; if active { task?.cancel() } else if running { drain() } }
    func cancel(_ id: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == id }), jobs[index].status == .waiting || jobs[index].status == .running else { return }
        let active = jobs[index].status == .running; jobs[index].status = .cancelled; persist(); if active { task?.cancel() }
    }
    func retry(_ id: UUID) { guard let index = jobs.firstIndex(where: { $0.id == id }), [.failed, .cancelled].contains(jobs[index].status) else { return }; jobs[index].status = .waiting; jobs[index].progress = 0; jobs[index].error = nil; persist(); if running { drain() } }
    func clearFinished() { jobs.removeAll { [.completed, .cancelled].contains($0.status) }; persist() }
    private func persist() {
        guard writable else { return }
        let snapshot = jobs, file = file
        disk.async { [weak self] in
            do { try JSONEncoder().encode(snapshot).write(to: file, options: .atomic) }
            catch { Task { @MainActor [weak self] in self?.issue = "The export queue could not be saved. \(error.localizedDescription)"; self?.pause() } }
        }
    }
    private func drain() {
        guard task == nil, running, !captureActive, jobs.contains(where: { $0.status == .waiting }) else { return }
        task = Task { [weak self] in
            guard let self else { return }
            while running && !captureActive && !Task.isCancelled, let index = jobs.firstIndex(where: { $0.status == .waiting }) {
                let job = jobs[index]; jobs[index].status = .running; jobs[index].progress = 0; persist()
                do {
                    guard let recording = library.recordings.first(where: { $0.id == job.recordingID }) else { throw PrismError.message("The source recording is no longer in your library.") }
                    try library.validateExportTarget(URL(fileURLWithPath: job.targetPath))
                    try await TimelineRenderer.export(source: library.fileURL(recording), target: URL(fileURLWithPath: job.targetPath), document: job.document, format: job.format, quality: job.quality) { value in
                        Task { @MainActor in if let i = self.jobs.firstIndex(where: { $0.id == job.id }), self.jobs[i].status == .running { self.jobs[i].progress = value } }
                    }
                    if let i = jobs.firstIndex(where: { $0.id == job.id }) { jobs[i].status = .completed; jobs[i].progress = 1 }
                } catch {
                    if let i = jobs.firstIndex(where: { $0.id == job.id }), jobs[i].status != .cancelled {
                        jobs[i].status = Task.isCancelled ? .waiting : .failed; jobs[i].progress = 0; jobs[i].error = Task.isCancelled ? nil : error.localizedDescription
                    }
                }
                persist()
            }
            task = nil
            if running && !captureActive && jobs.contains(where: { $0.status == .waiting }) { drain() }
        }
    }
}
