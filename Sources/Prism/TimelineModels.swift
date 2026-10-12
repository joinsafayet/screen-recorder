import Foundation
import CoreGraphics
import Combine

struct TimelineCut: Codable, Equatable, Identifiable {
    var id = UUID()
    var start: Double
    var end: Double
    var duration: Double { max(0, end - start) }
}
struct ZoomKeyframe: Codable, Equatable, Identifiable {
    var id = UUID()
    var time: Double
    var scale: Double = 1.5
    var x: Double = 0.5
    var y: Double = 0.5
}
struct AnnotationPoint: Codable, Equatable { var x: Double; var y: Double }
enum AnnotationKind: String, Codable, CaseIterable, Identifiable {
    case arrow = "Arrow", drawing = "Drawing", text = "Text", spotlight = "Spotlight", caption = "Caption", shortcut = "Shortcut"
    var id: String { rawValue }
}
struct TimelineAnnotation: Codable, Equatable, Identifiable {
    var id = UUID()
    var kind: AnnotationKind
    var start: Double
    var end: Double
    var points: [AnnotationPoint] = []
    var text: String = ""
    var color: UInt32 = 0x78AEFF
    var thickness: Double = 0.006
}
struct CaptionCue: Codable, Equatable, Identifiable {
    var id = UUID()
    var start: Double
    var end: Double
    var text: String
}
struct PointerSample: Codable, Equatable { var time: Double; var x: Double; var y: Double }
struct ShortcutSample: Codable, Equatable { var time: Double; var text: String }

struct TimelineDocument: Codable, Equatable {
    var version = 1
    var recordingID: UUID
    var cuts: [TimelineCut]
    var aspect: CaptureAspect = .free
    var crop = CGRect(x: 0, y: 0, width: 1, height: 1)
    var zooms: [ZoomKeyframe] = []
    var audioGain: Double = 1
    var fadeIn: Double = 0
    var fadeOut: Double = 0
    var annotations: [TimelineAnnotation] = []
    var captions: [CaptionCue] = []
    var showCaptions = true
    var showShortcuts = true
    var spotlight = false
    var pointers: [PointerSample] = []
    var shortcuts: [ShortcutSample] = []
    init(recordingID: UUID, duration: Double) { self.recordingID = recordingID; cuts = [TimelineCut(start: 0, end: duration)] }
    var duration: Double { cuts.reduce(0) { $0 + $1.duration } }
    func sourceTime(at outputTime: Double) -> Double {
        var offset = 0.0
        for cut in cuts {
            if outputTime <= offset + cut.duration { return cut.start + max(0, outputTime - offset) }
            offset += cut.duration
        }
        return cuts.last?.end ?? 0
    }
    mutating func split(at time: Double) -> UUID? {
        var offset = 0.0
        for (index, cut) in cuts.enumerated() {
            let local = time - offset
            if local > 0.05 && local < cut.duration - 0.05 {
                let second = TimelineCut(start: cut.start + local, end: cut.end)
                cuts[index].end = second.start; cuts.insert(second, at: index + 1); return second.id
            }
            offset += cut.duration
        }
        return nil
    }
    func validate(sourceDuration: Double) throws {
        guard version == 1, !cuts.isEmpty, cuts.count <= 500,
              cuts.allSatisfy({ $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end <= sourceDuration + 0.001 && $0.duration >= 0.01 }),
              [crop.minX, crop.minY, crop.width, crop.height].allSatisfy({ $0.isFinite }),
              crop.minX >= 0, crop.minY >= 0, crop.width > 0, crop.height > 0, crop.maxX <= 1.001, crop.maxY <= 1.001,
              audioGain.isFinite, (0...1).contains(audioGain), fadeIn.isFinite, fadeOut.isFinite, fadeIn >= 0, fadeOut >= 0,
              annotations.count <= 2000, annotations.allSatisfy({ $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end > $0.start && $0.thickness.isFinite && $0.thickness > 0 && $0.thickness <= 0.1 && $0.points.count <= 2000 && $0.points.allSatisfy { $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) } }),
              pointers.count <= 100000, pointers.allSatisfy({ $0.time.isFinite && $0.time >= 0 && $0.x.isFinite && $0.y.isFinite && (0...1).contains($0.x) && (0...1).contains($0.y) }),
              shortcuts.count <= 10000, shortcuts.allSatisfy({ $0.time.isFinite && $0.time >= 0 && $0.text.count <= 50 }),
              captions.count <= 20000, captions.allSatisfy({ $0.start.isFinite && $0.end.isFinite && $0.start >= 0 && $0.end > $0.start && $0.end <= sourceDuration + 0.001 }),
              zooms.allSatisfy({ $0.time.isFinite && $0.time >= 0 && $0.time <= duration && (1...4).contains($0.scale) && (0...1).contains($0.x) && (0...1).contains($0.y) }) else {
            throw PrismError.message("The editing timeline contains an invalid range or crop.")
        }
    }
    func zoom(at time: Double) -> (scale: Double, x: Double, y: Double) {
        let sorted = zooms.sorted { $0.time < $1.time }
        guard let first = sorted.first else { return (1, 0.5, 0.5) }
        if time <= first.time { return (first.scale, first.x, first.y) }
        for (a, b) in zip(sorted, sorted.dropFirst()) where time <= b.time {
            let t = min(1, max(0, (time - a.time) / max(0.001, b.time - a.time)))
            let smooth = t * t * (3 - 2 * t)
            return (a.scale + (b.scale - a.scale) * smooth, a.x + (b.x - a.x) * smooth, a.y + (b.y - a.y) * smooth)
        }
        let last = sorted.last!; return (last.scale, last.x, last.y)
    }
}

@MainActor final class TimelineHistory: ObservableObject {
    @Published private(set) var document: TimelineDocument
    @Published private(set) var revision = 0
    private var undoStack: [TimelineDocument] = [], redoStack: [TimelineDocument] = []
    init(_ document: TimelineDocument) { self.document = document }
    var canUndo: Bool { !undoStack.isEmpty }; var canRedo: Bool { !redoStack.isEmpty }
    func load(_ document: TimelineDocument) { self.document = document; undoStack = []; redoStack = []; revision += 1 }
    func change(_ update: (inout TimelineDocument) -> Void) {
        var next = document; update(&next)
        let duration = next.duration
        next.zooms.removeAll { $0.time > duration }
        next.annotations.removeAll { $0.start >= duration }
        for index in next.annotations.indices { next.annotations[index].end = min(duration, next.annotations[index].end) }
        next.fadeIn = min(next.fadeIn, duration / 2); next.fadeOut = min(next.fadeOut, duration / 2)
        guard next != document else { return }
        undoStack.append(document); if undoStack.count > 50 { undoStack.removeFirst() }
        redoStack = []; document = next; revision += 1
    }
    func undo() { guard let previous = undoStack.popLast() else { return }; redoStack.append(document); document = previous; revision += 1 }
    func redo() { guard let next = redoStack.popLast() else { return }; undoStack.append(document); document = next; revision += 1 }
}

enum TimelineGeometry {
    static func cropRect(source: CGSize, normalized: CGRect, aspect: CaptureAspect) -> CGRect {
        var r = CGRect(x: normalized.minX * source.width, y: (1 - normalized.maxY) * source.height, width: normalized.width * source.width, height: normalized.height * source.height)
        if let ratio = aspect.ratio {
            if r.width / r.height > ratio { let width = r.height * ratio; r.origin.x += (r.width - width) / 2; r.size.width = width }
            else { let height = r.width / ratio; r.origin.y += (r.height - height) / 2; r.size.height = height }
        }
        return r
    }
}
