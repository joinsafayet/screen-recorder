import Foundation
import CoreGraphics
import AVFoundation

enum Destination: String, CaseIterable, Identifiable {
    case studio = "Recorder", library = "Recordings", exports = "Exports", settings = "Preferences"
    var id: String { rawValue }
    var icon: String {
        switch self { case .studio: return "record.circle"; case .library: return "rectangle.stack"; case .exports: return "square.and.arrow.up.on.square"; case .settings: return "slider.horizontal.3" }
    }
}

enum CaptureMode: String, CaseIterable, Identifiable, Codable {
    case display = "Entire screen", window = "Window", region = "Selected area"
    var id: String { rawValue }
    var icon: String {
        switch self { case .display: return "display"; case .window: return "macwindow"; case .region: return "viewfinder" }
    }
    var detail: String {
        switch self { case .display: return "Capture a full display"; case .window: return "Focus on one application"; case .region: return "Just the part you need" }
    }
}

enum Quality: String, CaseIterable, Identifiable, Codable {
    case compact = "Compact", balanced = "Balanced", high = "High quality", original = "Original"
    var id: String { rawValue }
    var maxHeight: Int {
        switch self { case .compact: return 720; case .balanced: return 1080; case .high: return 2160; case .original: return 4320 }
    }
    var bitratePerPixel: Double {
        switch self { case .compact: return 2.5; case .balanced: return 4; case .high: return 7; case .original: return 10 }
    }
    var description: String {
        switch self { case .compact: return "720p · smaller files"; case .balanced: return "1080p · everyday capture"; case .high: return "4K · crisp detail"; case .original: return "Native · every pixel" }
    }
}

enum VideoFormat: String, CaseIterable, Identifiable, Codable {
    case mp4 = "MP4", mov = "MOV"
    var id: String { rawValue }
    var ext: String { rawValue.lowercased() }
    var fileType: AVFileType { self == .mp4 ? .mp4 : .mov }
}

enum VideoCodec: String, CaseIterable, Identifiable, Codable {
    case automatic = "Automatic", h264 = "H.264", hevc = "HEVC"
    var id: String { rawValue }
    func resolved(for quality: Quality) -> AVVideoCodecType {
        self == .hevc || (self == .automatic && (quality == .high || quality == .original)) ? .hevc : .h264
    }
    func label(for quality: Quality) -> String { resolved(for: quality) == .hevc ? "HEVC" : "H.264" }
}

enum PresenterCorner: String, CaseIterable, Identifiable, Codable {
    case bottomRight = "Bottom right", bottomLeft = "Bottom left", topRight = "Top right", topLeft = "Top left"
    var id: String { rawValue }
    func rect(in size: CGSize, fraction: Double) -> CGRect {
        let diameter = min(size.width, size.height) * fraction
        let inset = min(size.width, size.height) * 0.045
        let left = self == .bottomLeft || self == .topLeft
        let top = self == .topLeft || self == .topRight
        return CGRect(x: left ? inset : size.width - diameter - inset,
                      y: top ? size.height - diameter - inset : inset, width: diameter, height: diameter)
    }
}

enum RecordingPreset: String, CaseIterable, Identifiable {
    case everyday = "Everyday", tutorial = "Tutorial", motion = "Smooth motion", detail = "Detail"
    var id: String { rawValue }
    var icon: String { switch self { case .everyday: return "prism.everyday"; case .tutorial: return "person.bubble"; case .motion: return "bolt"; case .detail: return "4k.tv" } }
    var detail: String { switch self { case .everyday: return "1080p · 30 fps"; case .tutorial: return "Voice + click highlights"; case .motion: return "1080p · 60 fps"; case .detail: return "4K · HEVC" } }
    func apply(to settings: inout CaptureSettings) {
        settings.quality = self == .detail ? .high : .balanced
        settings.fps = self == .motion ? 60 : 30
        settings.codec = self == .detail ? .hevc : .h264
        settings.microphone = self == .tutorial
        settings.highlightClicks = self == .tutorial
        settings.showCursor = true
    }
    func matches(_ settings: CaptureSettings) -> Bool {
        var expected = settings
        apply(to: &expected)
        return expected.quality == settings.quality && expected.fps == settings.fps
            && expected.codec.resolved(for: expected.quality) == settings.codec.resolved(for: settings.quality)
            && expected.microphone == settings.microphone && expected.highlightClicks == settings.highlightClicks
            && expected.showCursor == settings.showCursor
    }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case newest = "Newest first", oldest = "Oldest first", name = "Name", duration = "Longest first", size = "Largest first"
    var id: String { rawValue }
}

struct RecordingMarker: Codable, Equatable, Identifiable {
    var id = UUID()
    var time: Double
    var title: String
}

struct CaptureStatistics: Sendable {
    var frames = 0
    var droppedVideo = 0
    var droppedAudio = 0
    var processingMilliseconds = 0.0
    var peakProcessingMilliseconds = 0.0
    var bytes: Int64 = 0
    var width = 0
    var height = 0
    var targetFPS = 30
}

enum ExportQuality: String, CaseIterable, Identifiable, Codable {
    case original = "Original quality", full = "High quality", hd = "1080p", compact = "720p · smaller file"
    var id: String { rawValue }
    func preset(trimmed: Bool) -> String {
        switch self {
        case .original: return trimmed ? AVAssetExportPresetHighestQuality : AVAssetExportPresetPassthrough
        case .full: return AVAssetExportPresetHighestQuality
        case .hd: return AVAssetExportPreset1920x1080
        case .compact: return AVAssetExportPreset1280x720
        }
    }
}

struct CaptureSettings: Codable, Equatable {
    var mode: CaptureMode = .display
    var quality: Quality = .balanced
    var format: VideoFormat = .mp4
    var fps = 30
    var systemAudio = true
    var microphone = false
    var microphoneID: String = ""
    var camera = false
    var cameraID: String = ""
    var showCursor = true
    var countdown = 3
    var stopAfterMinutes = 0
    var hideWindow = true
    var showFloatingControls = true
    var codec: VideoCodec = .automatic
    var highlightClicks = false
    var showKeystrokes = false
    var cursorSpotlight = false
    var presenterCorner: PresenterCorner = .bottomRight
    var presenterSize = 0.23
    var mirrorCamera = true
    var systemGain: Float = 0.85
    var microphoneGain: Float = 0.85

    init() {}
    // Older installations keep their settings when new options are introduced.
    enum CodingKeys: String, CodingKey {
        case mode, quality, format, fps, systemAudio, microphone, microphoneID, camera, cameraID, showCursor, countdown, stopAfterMinutes, hideWindow, showFloatingControls, codec, highlightClicks, showKeystrokes, cursorSpotlight, presenterCorner, presenterSize, mirrorCamera, systemGain, microphoneGain
    }
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decodeIfPresent(CaptureMode.self, forKey: .mode) ?? mode
        quality = try c.decodeIfPresent(Quality.self, forKey: .quality) ?? quality
        format = try c.decodeIfPresent(VideoFormat.self, forKey: .format) ?? format
        let savedFPS = try c.decodeIfPresent(Int.self, forKey: .fps) ?? fps
        fps = [24, 30, 60].contains(savedFPS) ? savedFPS : 30
        systemAudio = try c.decodeIfPresent(Bool.self, forKey: .systemAudio) ?? systemAudio
        microphone = try c.decodeIfPresent(Bool.self, forKey: .microphone) ?? microphone
        microphoneID = try c.decodeIfPresent(String.self, forKey: .microphoneID) ?? microphoneID
        camera = try c.decodeIfPresent(Bool.self, forKey: .camera) ?? camera
        cameraID = try c.decodeIfPresent(String.self, forKey: .cameraID) ?? cameraID
        showCursor = try c.decodeIfPresent(Bool.self, forKey: .showCursor) ?? showCursor
        countdown = max(0, min(10, try c.decodeIfPresent(Int.self, forKey: .countdown) ?? countdown))
        stopAfterMinutes = max(0, try c.decodeIfPresent(Int.self, forKey: .stopAfterMinutes) ?? stopAfterMinutes)
        hideWindow = try c.decodeIfPresent(Bool.self, forKey: .hideWindow) ?? hideWindow
        showFloatingControls = try c.decodeIfPresent(Bool.self, forKey: .showFloatingControls) ?? showFloatingControls
        codec = try c.decodeIfPresent(VideoCodec.self, forKey: .codec) ?? codec
        highlightClicks = try c.decodeIfPresent(Bool.self, forKey: .highlightClicks) ?? highlightClicks
        showKeystrokes = try c.decodeIfPresent(Bool.self, forKey: .showKeystrokes) ?? showKeystrokes
        cursorSpotlight = try c.decodeIfPresent(Bool.self, forKey: .cursorSpotlight) ?? cursorSpotlight
        presenterCorner = try c.decodeIfPresent(PresenterCorner.self, forKey: .presenterCorner) ?? presenterCorner
        presenterSize = min(0.4, max(0.12, try c.decodeIfPresent(Double.self, forKey: .presenterSize) ?? presenterSize))
        mirrorCamera = try c.decodeIfPresent(Bool.self, forKey: .mirrorCamera) ?? mirrorCamera
        systemGain = min(1, max(0, try c.decodeIfPresent(Float.self, forKey: .systemGain) ?? systemGain))
        microphoneGain = min(1, max(0, try c.decodeIfPresent(Float.self, forKey: .microphoneGain) ?? microphoneGain))
    }
}

struct Recording: Identifiable, Codable, Equatable {
    var id: UUID
    var filename: String
    var title: String
    var createdAt: Date
    var duration: Double
    var bytes: Int64
    var width: Int
    var height: Int
    var fps: Int
    var source: String
    var favorite: Bool = false
    var thumbnail: String?
    var markers: [RecordingMarker]?
    var pointers: [PointerSample]?
    var shortcuts: [ShortcutSample]?
    var captureSpotlight: Bool?
    var presentationFile: String?
    var project: String?
    var tags: [String]?
}

enum CapturePhase: Equatable {
    case idle, preparing, countdown(Int), recording, paused, saving
    var isActive: Bool { self != .idle }
    var isCapturing: Bool { self == .recording || self == .paused }
    var label: String {
        switch self { case .idle: return "Ready to record"; case .preparing: return "Preparing capture"; case .countdown(let n): return "Starting in \(n)"; case .recording: return "Recording"; case .paused: return "Paused"; case .saving: return "Saving recording" }
    }
}

enum RecordingMath {
    static func selectionRect(start: CGPoint, end: CGPoint, bounds: CGRect) -> CGRect {
        let a = CGPoint(x: min(bounds.maxX, max(bounds.minX, start.x)), y: min(bounds.maxY, max(bounds.minY, start.y)))
        let b = CGPoint(x: min(bounds.maxX, max(bounds.minX, end.x)), y: min(bounds.maxY, max(bounds.minY, end.y)))
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }
    static func outputSize(source: CGSize, scale: Double, maxHeight: Int) -> (width: Int, height: Int) {
        let w = max(2, source.width * scale), h = max(2, source.height * scale)
        let ratio = min(1, Double(maxHeight) / h)
        return (max(2, Int(w * ratio) / 2 * 2), max(2, Int(h * ratio) / 2 * 2))
    }
    // AppKit selection coordinates are bottom-left; ScreenCaptureKit uses top-left, in points.
    static func captureRect(selection: CGRect, displayHeight: CGFloat) -> CGRect {
        CGRect(x: selection.minX, y: displayHeight - selection.maxY, width: selection.width, height: selection.height)
    }
    static func clock(_ duration: Double) -> String {
        let seconds = max(0, Int(duration))
        return seconds >= 3600 ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60) : String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}

extension Int64 {
    var fileSize: String { ByteCountFormatter.string(fromByteCount: self, countStyle: .file) }
}

enum PrismError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case .message(let message) = self { return message }; return nil }
}
