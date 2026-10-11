import AppKit
import SwiftUI
import ScreenCaptureKit
import AVFoundation

@MainActor
final class AppModel: ObservableObject {
    @Published var destination: Destination = .studio
    @Published var settings: CaptureSettings {
        didSet {
            if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: "captureSettings") }
            if oldValue.mode != settings.mode || oldValue.showCursor != settings.showCursor { schedulePreview() }
        }
    }
    @Published var phase: CapturePhase = .idle
    let telemetry = RecordingTelemetry()
    var elapsed: Double { telemetry.elapsed }
    @Published var sessionTitle = ""
    @Published var librarySort: LibrarySort = .newest
    @Published var hotkeyStatus = ""
    @Published var globalShortcuts: Bool = UserDefaults.standard.object(forKey: "globalShortcuts") as? Bool ?? true {
        didSet { UserDefaults.standard.set(globalShortcuts, forKey: "globalShortcuts"); configureHotkeys() }
    }
    private let hotkeys = GlobalHotkeys()
    @Published var screenAccess = CGPreflightScreenCaptureAccess()
    @Published var microphoneAccess = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
    @Published var cameraAccess = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
    @Published var displays: [SCDisplay] = []
    @Published var windows: [SCWindow] = []
    @Published var displayID: CGDirectDisplayID = CGMainDisplayID() {
        didSet { if oldValue != displayID { region = nil; schedulePreview() } }
    }
    @Published var windowID: CGWindowID? {
        didSet { if oldValue != windowID { schedulePreview() } }
    }
    @Published var region: CGRect?
    @Published var preview: NSImage?
    @Published var loadingPreview = false
    @Published var loadingSources = false
    @Published var error: String?
    @Published var toast: String?
    @Published var search = ""
    @Published var favoritesOnly = false
    @Published var microphones: [AVCaptureDevice] = []
    @Published var cameras: [AVCaptureDevice] = []
    @Published var theme: String = UserDefaults.standard.string(forKey: "theme") ?? "Dark" {
        didSet { UserDefaults.standard.set(theme, forKey: "theme") }
    }
    @Published var motionEnabled: Bool = UserDefaults.standard.object(forKey: "motionEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(motionEnabled, forKey: "motionEnabled") }
    }
    let library: LibraryStore
    private var engine: CaptureEngine?
    private var timer: Timer?
    private var activeStart: TimeInterval?
    private var accumulated = 0.0
    private var countdownTask: Task<Void, Never>?
    private var floatingPanel: NSPanel?
    private var outputURL: URL?
    private var recordingSettings: CaptureSettings?
    private var captureSourceName = ""
    private var lastDiskCheck = 0.0
    private var capturedTitle = ""
    private var previewRequest = UUID()
    private var previewTask: Task<Void, Never>?
    private var captureID: UUID?
    private var startupCaptureError: Error?
    weak var mainWindow: NSWindow?
    var openStudioWindow: (() -> Void)?

    init(library: LibraryStore? = nil, discoverSources: Bool = true) {
        self.library = library ?? LibraryStore()
        settings = UserDefaults.standard.data(forKey: "captureSettings").flatMap { try? JSONDecoder().decode(CaptureSettings.self, from: $0) } ?? CaptureSettings()
        configureHotkeys()
        refreshPermissions()
        if screenAccess && discoverSources { Task { await refreshSources() } }
    }

    var displayName: String {
        NSScreen.screens.first { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID }?.localizedName ?? "Display"
    }
    var selectedDisplay: SCDisplay? { displays.first { $0.displayID == displayID } ?? displays.first }
    var selectedWindow: SCWindow? { windows.first { $0.windowID == windowID } }
    var sourceName: String {
        if settings.mode == .window { return selectedWindow?.title ?? "Choose a window" }
        if settings.mode == .region, let region { return "\(Int(region.width)) × \(Int(region.height)) area" }
        return displayName
    }
    var recordingCount: Int { library.recordings.count }
    var colorScheme: ColorScheme? { theme == "System" ? nil : theme == "Light" ? .light : .dark }
    var filteredRecordings: [Recording] {
        let matches = library.recordings.filter { (!favoritesOnly || $0.favorite) && (search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.source.localizedCaseInsensitiveContains(search)) }
        return matches.sorted { a, b in
            switch librarySort {
            case .newest: return a.createdAt > b.createdAt
            case .oldest: return a.createdAt < b.createdAt
            case .name: return a.title.localizedStandardCompare(b.title) == .orderedAscending
            case .duration: return a.duration > b.duration
            case .size: return a.bytes > b.bytes
            }
        }
    }

    func refreshPermissions() {
        screenAccess = CGPreflightScreenCaptureAccess()
        microphoneAccess = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        cameraAccess = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
        microphones = AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone, .external], mediaType: .audio, position: .unspecified).devices
        cameras = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera, .external], mediaType: .video, position: .unspecified).devices
    }

    func requestScreenAccess() async {
        screenAccess = CGRequestScreenCaptureAccess()
        if screenAccess { await refreshSources() }
        else { openPrivacy("ScreenCapture") }
    }

    func requestMicrophoneAccess() async {
        microphoneAccess = await AVCaptureDevice.requestAccess(for: .audio)
        refreshPermissions()
        if !microphoneAccess { openPrivacy("Microphone") }
    }

    func requestCameraAccess() async {
        cameraAccess = await AVCaptureDevice.requestAccess(for: .video)
        refreshPermissions()
        if !cameraAccess { openPrivacy("Camera") }
    }

    func openPrivacy(_ category: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_\(category)") { NSWorkspace.shared.open(url) }
    }

    func refreshSources() async {
        guard screenAccess, !phase.isActive, !loadingSources else { return }
        loadingSources = true
        defer { loadingSources = false }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: true)
            displays = content.displays
            windows = content.windows.filter { $0.owningApplication?.processID != ProcessInfo.processInfo.processIdentifier && $0.frame.width > 80 && $0.frame.height > 60 && !($0.title ?? "").isEmpty }
                .sorted { ($0.owningApplication?.applicationName ?? "") < ($1.owningApplication?.applicationName ?? "") }
            if !displays.contains(where: { $0.displayID == displayID }), let first = displays.first { displayID = first.displayID; region = nil }
            if !windows.contains(where: { $0.windowID == windowID }) { windowID = windows.first?.windowID }
            await refreshPreview()
        } catch { self.error = "Could not load capture sources. \(error.localizedDescription)" }
    }

    private func makeFilter() async throws -> (SCContentFilter, SCDisplay?, CGSize) {
        // Snapshot the selection before awaiting shareable content. A later click
        // must not combine an old filter with a new mode or region.
        let mode = settings.mode
        let region = region
        let display = selectedDisplay
        if mode == .window {
            guard let window = selectedWindow else { throw PrismError.message("Select a window to record.") }
            let filter = SCContentFilter(desktopIndependentWindow: window)
            return (filter, nil, filter.contentRect.size)
        }
        guard let display else { throw PrismError.message("No display is available. Refresh your capture sources.") }
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        let ownApplications = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
        let filter = SCContentFilter(display: display, excludingApplications: ownApplications, exceptingWindows: [])
        if mode == .region {
            guard let region, region.width >= 32, region.height >= 32 else { throw PrismError.message("Select an area before recording.") }
            return (filter, display, region.size)
        }
        return (filter, display, filter.contentRect.size)
    }

    private func schedulePreview() {
        previewTask?.cancel()
        previewRequest = UUID(); preview = nil; loadingPreview = false
        guard screenAccess, !phase.isActive else { return }
        previewTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(90)) } catch { return }
            guard let self, !Task.isCancelled else { return }
            await self.refreshPreview()
        }
    }

    func refreshPreview() async {
        guard screenAccess, !phase.isActive else { return }
        let request = UUID(); previewRequest = request
        let mode = settings.mode, region = region, showsCursor = settings.showCursor
        preview = nil; loadingPreview = true
        defer { if previewRequest == request { loadingPreview = false } }
        do {
            let (filter, display, sourceSize) = try await makeFilter()
            guard previewRequest == request, !Task.isCancelled else { return }
            let config = SCStreamConfiguration()
            let output = RecordingMath.outputSize(source: sourceSize, scale: 1, maxHeight: 480)
            config.width = output.width; config.height = output.height; config.showsCursor = showsCursor
            if mode == .region, let region, let display { config.sourceRect = RecordingMath.captureRect(selection: region, displayHeight: display.frame.height) }
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            if previewRequest == request && !phase.isActive { preview = NSImage(cgImage: image, size: sourceSize) }
        } catch { /* A region or window may not yet be selected. The empty state remains actionable. */ }
    }

    func selectRegion() {
        guard !phase.isActive else { return }
        guard let screen = NSScreen.screens.first(where: { ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID }) else { return }
        let selectedDisplayID = displayID
        RegionSelector.shared.select(on: screen) { [weak self] rect in
            guard let self, let rect, !self.phase.isActive, self.displayID == selectedDisplayID, self.settings.mode == .region else { return }
            self.region = rect; self.schedulePreview()
        }
    }

    func startRecording() {
        guard !phase.isActive, !library.isBusy else { return }
        startupCaptureError = nil
        phase = .preparing
        countdownTask = Task { [self] in
            phase = .preparing
            do {
                refreshPermissions()
                guard screenAccess else { throw PrismError.message("Allow Screen Recording access first. You can do this in Preferences → Permissions.") }
                if settings.microphone, !microphoneAccess {
                    microphoneAccess = await AVCaptureDevice.requestAccess(for: .audio)
                    guard microphoneAccess else { throw PrismError.message("Microphone access is needed for your selected audio setup.") }
                }
                if settings.camera, !cameraAccess {
                    cameraAccess = await AVCaptureDevice.requestAccess(for: .video)
                    guard cameraAccess else { throw PrismError.message("Camera access is needed for the presenter bubble.") }
                }
                let freeBytes = library.availableBytes
                guard freeBytes == nil || freeBytes! > 500_000_000 else { throw PrismError.message("Free at least 500 MB in your save location before recording.") }
                let (filter, display, size) = try await makeFilter()
                let options = settings
                let output = RecordingMath.outputSize(source: size, scale: Double(filter.pointPixelScale), maxHeight: options.quality.maxHeight)
                let config = SCStreamConfiguration()
                config.width = output.width; config.height = output.height
                config.minimumFrameInterval = CMTime(value: 1, timescale: CMTimeScale(options.fps))
                config.pixelFormat = options.camera || options.highlightClicks ? kCVPixelFormatType_32BGRA : kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange
                config.queueDepth = 3; config.showsCursor = options.showCursor
                config.showMouseClicks = options.highlightClicks
                config.preservesAspectRatio = true
                config.capturesAudio = options.systemAudio; config.excludesCurrentProcessAudio = true
                config.sampleRate = 48000; config.channelCount = 2
                config.captureMicrophone = options.microphone
                if !options.microphoneID.isEmpty { config.microphoneCaptureDeviceID = options.microphoneID }
                if options.mode == .region, let region, let display { config.sourceRect = RecordingMath.captureRect(selection: region, displayHeight: display.frame.height) }
                config.scalesToFit = true
                captureSourceName = sourceName
                capturedTitle = sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                telemetry.reset()
                for second in stride(from: options.countdown, through: 1, by: -1) {
                    try Task.checkCancellation(); phase = .countdown(second)
                    try await Task.sleep(for: .seconds(1))
                }
                try Task.checkCancellation()
                phase = .preparing
                let url = try library.newURL(format: options.format)
                outputURL = url; recordingSettings = options
                let capture = CaptureEngine()
                let id = UUID(); captureID = id
                capture.onError = { [weak self] error in Task { @MainActor in
                    guard let self, self.captureID == id else { return }
                    if self.phase.isCapturing { self.error = error.localizedDescription; await self.stopRecording() }
                    else { self.startupCaptureError = error }
                } }
                capture.onAudioLevel = { [weak self] value in Task { @MainActor in
                    guard self?.captureID == id, self?.phase == .recording else { return }; self?.telemetry.audioLevel = value
                } }
                capture.onStatistics = { [weak self] value in Task { @MainActor in
                    guard self?.captureID == id else { return }; self?.telemetry.statistics = value
                } }
                engine = capture
                try await capture.start(filter: filter, configuration: config, url: url, settings: options)
                if let startupCaptureError { throw startupCaptureError }
                accumulated = 0; telemetry.elapsed = 0; activeStart = ProcessInfo.processInfo.systemUptime; phase = .recording
                if options.hideWindow { mainWindow?.orderOut(nil) }
                if options.showFloatingControls { showFloatingControls() }
                timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in Task { @MainActor in self?.tick() } }
            } catch is CancellationError { phase = .idle }
            catch {
                captureID = nil
                try? await engine?.stop(activeDuration: 0)
                engine = nil; outputURL = nil; recordingSettings = nil
                phase = .idle; self.error = error.localizedDescription; showMainWindow()
            }
        }
    }

    func cancelCountdown() {
        guard case .countdown = phase else { return }
        countdownTask?.cancel(); countdownTask = nil
    }

    private func tick() {
        let now = ProcessInfo.processInfo.systemUptime
        let current = accumulated + (activeStart.map { now - $0 } ?? 0)
        if Int(current) != Int(telemetry.elapsed) { telemetry.elapsed = current }
        if now - lastDiskCheck > 5 {
            lastDiskCheck = now
            if let bytes = library.availableBytes, bytes < 150_000_000, phase.isCapturing {
                error = "Recording stopped because the save disk is almost full."
                Task { await stopRecording() }; return
            }
        }
        if let limit = recordingSettings?.stopAfterMinutes, limit > 0, elapsed >= Double(limit * 60), phase.isCapturing {
            Task { await stopRecording() }
        }
    }

    func togglePause() {
        if phase == .recording {
            tick(); accumulated = activeDuration; telemetry.elapsed = accumulated; activeStart = nil; phase = .paused; engine?.pause(true); telemetry.audioLevel = 0
        } else if phase == .paused { activeStart = ProcessInfo.processInfo.systemUptime; phase = .recording; engine?.pause(false) }
    }

    func stopRecording() async {
        guard phase.isCapturing else { return }
        telemetry.elapsed = activeDuration; phase = .saving; captureID = nil; activeStart = nil; timer?.invalidate(); timer = nil
        floatingPanel?.close(); floatingPanel = nil
        showMainWindow()
        do {
            telemetry.savingMessage = "Finalizing video…"
            try await engine?.stop(activeDuration: elapsed)
            if let engine { telemetry.statistics = engine.finalStatistics }
            if let url = outputURL {
                if recordingSettings?.microphone == true && recordingSettings?.systemAudio == true {
                    telemetry.savingMessage = "Mixing your audio…"
                    do {
                        try await AudioMixer.mixTracks(at: url, format: recordingSettings?.format ?? .mp4,
                            systemGain: recordingSettings?.systemGain ?? 0.85, microphoneGain: recordingSettings?.microphoneGain ?? 0.85)
                    } catch {
                        self.error = "Audio mixing failed. Your original video was saved with separate system and microphone tracks. \(error.localizedDescription)"
                    }
                }
                telemetry.savingMessage = "Adding to your library…"
                let recording = try await library.add(url: url, source: captureSourceName, fps: recordingSettings?.fps ?? 30,
                    title: capturedTitle.isEmpty ? nil : capturedTitle, markers: telemetry.markers)
                destination = .library; notify("Saved \(RecordingMath.clock(recording.duration)) of your best work.")
            }
        } catch {
            self.error = "\(error.localizedDescription)\n\nIf a video was written, it is still in \(library.folder.path)."
        }
        engine = nil; outputURL = nil; recordingSettings = nil; telemetry.audioLevel = 0; phase = .idle
    }

    private var activeDuration: Double { accumulated + (activeStart.map { ProcessInfo.processInfo.systemUptime - $0 } ?? 0) }

    func addMarker() {
        guard phase.isCapturing else { return }
        telemetry.markers.append(RecordingMarker(time: activeDuration, title: "Marker \(telemetry.markers.count + 1)"))
        notify("Marker \(telemetry.markers.count) added")
    }

    func configureHotkeys() {
        hotkeys.action = { [weak self] id in Task { @MainActor in
            guard let self else { return }
            switch id {
            case 1: if self.phase.isCapturing { await self.stopRecording() } else if !self.phase.isActive { self.startRecording() }
            case 2: self.togglePause()
            case 3: self.addMarker()
            default: break
            }
        } }
        if globalShortcuts { hotkeyStatus = hotkeys.register() ? "Available from every app" : "A shortcut is already in use. Disable it in the other app, then toggle this setting." }
        else { hotkeys.unregister(); hotkeyStatus = "Global shortcuts are off" }
    }

    func showMainWindow() {
        if let mainWindow { mainWindow.orderFront(nil) }
        else { openStudioWindow?() }
    }
    func notify(_ message: String) {
        toast = message
        Task { try? await Task.sleep(for: .seconds(5)); if toast == message { toast = nil } }
    }
    func report(_ operation: () throws -> Void) { do { try operation() } catch { self.error = error.localizedDescription } }

    private func showFloatingControls() {
        let panel = NSPanel(contentRect: CGRect(x: 0, y: 0, width: 365, height: 70), styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
        panel.isFloatingPanel = true; panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.hasShadow = true; panel.isMovableByWindowBackground = true; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: FloatingControls().environmentObject(self).environmentObject(telemetry).preferredColorScheme(.dark))
        if let screen = NSScreen.main { panel.setFrameOrigin(CGPoint(x: screen.visibleFrame.midX - 182, y: screen.visibleFrame.minY + 32)) }
        panel.orderFrontRegardless(); floatingPanel = panel
    }
}

