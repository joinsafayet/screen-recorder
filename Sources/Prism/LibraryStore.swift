import AppKit
import AVFoundation
import ImageIO
import Combine

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var recordings: [Recording] = []
    @Published private(set) var folder: URL
    @Published private(set) var isBusy = false
    @Published var notice: String?
    private let metadataURL: URL
    private var manifestWritable = true
    private let thumbnailCache = NSCache<NSURL, NSImage>()

    init(folder customFolder: URL? = nil, support customSupport: URL? = nil) {
        let support = customSupport ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Prism", isDirectory: true)
        try? FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        metadataURL = support.appendingPathComponent("library.json")
        let fallback = FileManager.default.urls(for: .moviesDirectory, in: .userDomainMask)[0].appendingPathComponent("Prism", isDirectory: true)
        folder = customFolder ?? URL(fileURLWithPath: UserDefaults.standard.string(forKey: "recordingFolder") ?? fallback.path, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        thumbnailCache.totalCostLimit = 32 * 1024 * 1024
        if FileManager.default.fileExists(atPath: metadataURL.path) {
            do { recordings = try JSONDecoder().decode([Recording].self, from: Data(contentsOf: metadataURL)) }
            catch {
                let backup = support.appendingPathComponent("library-backup-\(Int(Date().timeIntervalSince1970)).json")
                do { try FileManager.default.copyItem(at: metadataURL, to: backup) }
                catch { manifestWritable = false }
                notice = "The library index could not be read. Existing videos are preserved. Use Recover recordings to rebuild it."
            }
        }
    }

    func fileURL(_ recording: Recording) -> URL { folder.appendingPathComponent(recording.filename) }
    func thumbnailURL(_ recording: Recording) -> URL? { recording.thumbnail.map { metadataURL.deletingLastPathComponent().appendingPathComponent($0) } }
    var countLabel: String { "\(recordings.count) recording\(recordings.count == 1 ? "" : "s")" }
    var totalBytes: Int64 { recordings.reduce(0) { $0 + $1.bytes } }
    var totalDuration: Double { recordings.reduce(0) { $0 + $1.duration } }
    var availableBytes: Int64? { try? folder.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage }

    func availableCapacity() async -> Int64? {
        let destination = folder
        return await Task.detached(priority: .utility) { try? destination.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage }.value
    }

    private func commit(_ next: [Recording]) throws {
        guard manifestWritable else { throw PrismError.message("The library index cannot be updated safely. Check permissions for Application Support/Prism.") }
        try JSONEncoder().encode(next).write(to: metadataURL, options: .atomic)
        recordings = next
    }

    func newURL(format: VideoFormat) throws -> URL {
        guard !isBusy else { throw PrismError.message("Wait for your library operation to finish.") }
        guard manifestWritable else { throw PrismError.message("Check permissions for Application Support/Prism before recording.") }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let formatter = DateFormatter(); formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        return folder.appendingPathComponent("Prism \(formatter.string(from: Date())) \(UUID().uuidString.prefix(6)).\(format.ext)")
    }

    @discardableResult
    func add(url: URL, source: String, fps: Int, title: String? = nil, markers: [RecordingMarker] = []) async throws -> Recording {
        let support = metadataURL.deletingLastPathComponent()
        let recording = try await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: url)
            let duration = try await asset.load(.duration).seconds
            guard duration.isFinite, duration > 0, let track = try await asset.loadTracks(withMediaType: .video).first else { throw PrismError.message("This file contains no playable video.") }
            let size = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            let visibleSize = size.applying(transform)
            let rate = try await track.load(.nominalFrameRate)
            let bytes = (try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
            let id = UUID()
            var thumbnail: String?
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = CGSize(width: 640, height: 400)
            if let image = try? await generator.image(at: CMTime(seconds: min(1, duration / 2), preferredTimescale: 600)).image {
                let data = autoreleasepool { NSBitmapImageRep(cgImage: image).representation(using: .jpeg, properties: [.compressionFactor: 0.8]) }
                if let data {
                    let name = "\(id.uuidString).jpg"
                    if (try? data.write(to: support.appendingPathComponent(name), options: .atomic)) != nil { thumbnail = name }
                }
            }
            return Recording(id: id, filename: url.lastPathComponent, title: title ?? url.deletingPathExtension().lastPathComponent,
                createdAt: Date(), duration: duration, bytes: bytes, width: Int(abs(visibleSize.width)), height: Int(abs(visibleSize.height)),
                fps: fps > 0 ? fps : Int(rate.rounded()), source: source, thumbnail: thumbnail, markers: markers)
        }.value
        do { try commit([recording] + recordings) }
        catch { if let thumb = thumbnailURL(recording) { try? FileManager.default.removeItem(at: thumb) }; throw error }
        return recording
    }

    func thumbnail(for recording: Recording) async -> NSImage? {
        guard let url = thumbnailURL(recording) else { return nil }
        if let cached = thumbnailCache.object(forKey: url as NSURL) { return cached }
        let image = await Task.detached(priority: .utility) { () -> NSImage? in
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary) else { return nil }
            return NSImage(cgImage: image, size: .zero)
        }.value
        if let image { thumbnailCache.setObject(image, forKey: url as NSURL, cost: Int(image.size.width * image.size.height * 4)) }
        return image
    }

    func rename(_ recording: Recording, title: String) throws {
        guard let i = recordings.firstIndex(where: { $0.id == recording.id }) else { return }
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw PrismError.message("Give your recording a name.") }
        var next = recordings; next[i].title = title; try commit(next)
    }

    func favorite(_ recording: Recording) throws {
        guard let i = recordings.firstIndex(where: { $0.id == recording.id }) else { return }
        var next = recordings; next[i].favorite.toggle(); try commit(next)
    }

    func delete(_ recording: Recording) throws {
        guard !isBusy else { return }
        let url = fileURL(recording)
        var trashed: NSURL?
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.trashItem(at: url, resultingItemURL: &trashed) }
        do { try commit(recordings.filter { $0.id != recording.id }) }
        catch { if let trashed { try? FileManager.default.moveItem(at: trashed as URL, to: url) }; throw error }
        if let thumb = thumbnailURL(recording) { thumbnailCache.removeObject(forKey: thumb as NSURL); try? FileManager.default.removeItem(at: thumb) }
    }

    func changeFolder() async throws {
        guard !isBusy else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.canCreateDirectories = true; panel.message = "Choose a folder. Existing Prism recordings will move with your library."
        guard panel.runModal() == .OK, let newFolder = panel.url, newFolder.standardizedFileURL != folder.standardizedFileURL else { return }
        isBusy = true; defer { isBusy = false }
        let previous = folder; let files = recordings.map(\.filename)
        try await Task.detached(priority: .utility) {
            var moved: [(URL, URL)] = []
            do {
                for file in files {
                    let old = previous.appendingPathComponent(file), new = newFolder.appendingPathComponent(file)
                    guard FileManager.default.fileExists(atPath: old.path) else { continue }
                    try FileManager.default.moveItem(at: old, to: new); moved.append((old, new))
                }
            } catch {
                for (old, new) in moved.reversed() { try? FileManager.default.moveItem(at: new, to: old) }; throw error
            }
        }.value
        folder = newFolder; UserDefaults.standard.set(newFolder.path, forKey: "recordingFolder")
    }

    func importVideos() async throws {
        guard !isBusy else { return }
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.movie, .mpeg4Movie, .quickTimeMovie]; panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        isBusy = true; defer { isBusy = false }
        for source in panel.urls {
            let target = folder.appendingPathComponent("Imported \(UUID().uuidString.prefix(8)) \(source.lastPathComponent)")
            try await Task.detached(priority: .utility) { try FileManager.default.copyItem(at: source, to: target) }.value
            do { try await add(url: target, source: "Imported", fps: 0) }
            catch { try? FileManager.default.removeItem(at: target); throw error }
        }
    }

    /// Re-index finalized files after a crash or interrupted audio mix. Never delete unreadable captures.
    func recoverRecordings() async throws -> Int {
        guard !isBusy else { return 0 }; isBusy = true; defer { isBusy = false }
        let folder = folder
        let files = try await Task.detached(priority: .utility) {
            try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
                .filter { ["mp4", "mov"].contains($0.pathExtension.lowercased()) }
        }.value
        var known = Set(recordings.map(\.filename)); var recovered = 0
        let pending = await CaptureJournalStore.pending(in: folder)
        let recoveryStore = CaptureJournalStore(folder: folder)
        for journal in pending {
            if known.contains(journal.filename) { try? await recoveryStore.complete(journal.id); continue }
            guard let url = journal.mediaURL(in: folder) else { continue }
            do {
                let asset = AVURLAsset(url: url); let duration = try await asset.load(.duration).seconds
                let markers = journal.markers.filter { $0.time >= 0 && $0.time < duration }
                try await add(url: url, source: journal.source, fps: journal.settings.fps,
                    title: journal.title.isEmpty ? "Recovered recording" : journal.title + " — recovered", markers: markers)
                try await recoveryStore.complete(journal.id); known.insert(journal.filename); recovered += 1
            } catch { notice = "Some interrupted files have no readable fragment yet. They remain in your save folder." }
        }
        for url in files where !known.contains(url.lastPathComponent) {
            do { try await add(url: url, source: "Recovered", fps: 0); known.insert(url.lastPathComponent); recovered += 1 }
            catch { notice = "Some interrupted files could not be read. They remain in your save folder." }
        }
        return recovered
    }

    func export(_ recording: Recording, range: ClosedRange<Double>? = nil, format: VideoFormat = .mp4,
                quality: ExportQuality = .original, progress: @escaping (Float) -> Void = { _ in }) async throws {
        let panel = NSSavePanel(); panel.allowedContentTypes = format == .mp4 ? [.mpeg4Movie] : [.quickTimeMovie]
        panel.nameFieldStringValue = recording.title + (range == nil ? "" : " — trimmed") + "." + format.ext
        guard panel.runModal() == .OK, let target = panel.url else { return }
        try await VideoExporter.export(source: fileURL(recording), target: target, range: range, format: format, quality: quality, progress: progress)
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    func exportMarkers(_ recording: Recording) throws {
        let panel = NSSavePanel(); panel.nameFieldStringValue = recording.title + " — markers.csv"; panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let target = panel.url else { return }
        let rows = (recording.markers ?? []).map { String(format: "%.3f", $0.time) + ",\"" + $0.title.replacingOccurrences(of: "\"", with: "\"\"") + "\"" }
        try ("Seconds,Marker\n" + rows.joined(separator: "\n") + "\n").write(to: target, atomically: true, encoding: .utf8)
    }
}
