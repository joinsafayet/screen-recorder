import SwiftUI
import AppKit

/// Isolated visual verification host. Its clips, manifest, and defaults do not use the user's library.
@main struct UIReview {
    @MainActor static func main() {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.regular)
        let menu = NSMenu(); let item = NSMenuItem(); let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit UI Review", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q").target = NSApp
        item.submenu = appMenu; menu.addItem(item); NSApp.mainMenu = menu
        Task { @MainActor in
            do {
                let build = Bundle.main.bundleURL.deletingLastPathComponent()
                let root = build.appendingPathComponent("UI-review-assets")
                let folder = root.appendingPathComponent("Videos")
                let library = LibraryStore(folder: folder, support: root.appendingPathComponent("Index"))
                let video = folder.appendingPathComponent("Prism walkthrough.mp4")
                if !FileManager.default.fileExists(atPath: video.path) {
                    let sample = build.appendingPathComponent("Prism-live-1080p60.mp4")
                    try FileManager.default.copyItem(at: sample, to: video)
                }
                if library.recordings.isEmpty {
                    try await library.add(url: video, source: "Window capture", fps: 60, title: "Prism — product walkthrough",
                        markers: [RecordingMarker(time: 0.8, title: "Introduction"), RecordingMarker(time: 3.5, title: "Presenter settings"), RecordingMarker(time: 7.4, title: "Export your take")])
                }
                let model = AppModel(library: library, discoverSources: false)
                model.globalShortcuts = false; model.theme = "Dark"; model.accentChoice = "Blue"; model.motionEnabled = true; model.settings = CaptureSettings(); model.destination = .library
                let panel = NSPanel(contentRect: CGRect(x: 340, y: 100, width: 1240, height: 860), styleMask: [.titled, .resizable, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.animationBehavior = .none
                panel.title = "Prism UI Review"; panel.hidesOnDeactivate = false
                panel.contentView = NSHostingView(rootView: ReviewRoot(model: model))
                model.mainWindow = panel
                panel.contentView?.layoutSubtreeIfNeeded(); panel.displayIfNeeded(); panel.orderBack(nil)
                ReviewContext.panel = panel; ReviewContext.model = model
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                    let result = "frame=\(panel.frame) visible=\(panel.isVisible) alpha=\(panel.alphaValue) hidden=\(NSApp.isHidden) active=\(NSApp.isActive) content=\(String(describing: panel.contentView?.frame)) subviews=\(String(describing: panel.contentView?.subviews.map { String(describing: type(of: $0)) }))"
                    try? result.write(to: build.appendingPathComponent("UI-host-state.txt"), atomically: true, encoding: .utf8)
                    if CommandLine.arguments.contains("--render") { Task { @MainActor in await ReviewContext.renderAssets() } }
                }
            } catch { print("UI review failed: \(error)"); NSApp.terminate(nil) }
        }
        NSApp.run()
    }
}
private struct ReviewRoot: View {
    @ObservedObject var model: AppModel
    var body: some View {
        RootView().environmentObject(model).environmentObject(model.library).environmentObject(model.telemetry).preferredColorScheme(model.colorScheme)
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 5) {
                    if !CommandLine.arguments.contains("--render") {
                    Button("Compact size") { ReviewContext.panel?.setContentSize(CGSize(width: 940, height: 680)) }.buttonStyle(QuietButton())
                    Button("Full size") { ReviewContext.panel?.setContentSize(CGSize(width: 1240, height: 860)) }.buttonStyle(QuietButton())
                    Button("Run interaction test") { ReviewContext.stress() }.buttonStyle(QuietButton())
                    }
                }.padding(6)
            }
    }
}
@MainActor enum ReviewContext {
    static var panel: NSPanel?; static var model: AppModel?
    static func renderAssets() async {
        guard let model, let panel else { return }
        let build = Bundle.main.bundleURL.deletingLastPathComponent()
        func capture(_ name: String) {
            guard let view = panel.contentView, let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
            view.layoutSubtreeIfNeeded(); view.cacheDisplay(in: view.bounds, to: bitmap)
            if let data = bitmap.representation(using: .png, properties: [:]) { try? data.write(to: build.appendingPathComponent(name + ".png")) }
        }
        for destination in [Destination.studio, .library, .settings, .exports] {
            model.destination = destination
            try? await Task.sleep(for: .milliseconds(500))
            capture("Prism3-render-" + destination.rawValue)
        }
        panel.setContentSize(CGSize(width: 940, height: 680))
        for destination in [Destination.studio, .library, .settings] {
            model.destination = destination
            try? await Task.sleep(for: .milliseconds(500)); capture("Prism3-compact-" + destination.rawValue)
        }
        panel.setContentSize(CGSize(width: 1240, height: 860))
        model.theme = "Light"; model.destination = .settings
        try? await Task.sleep(for: .milliseconds(500)); capture("Prism3-render-Light")
        model.theme = "Dark"
        if let recording = model.library.recordings.first {
            panel.setContentSize(CGSize(width: 1060, height: 730))
            panel.contentView = NSHostingView(rootView: TimelineEditor(recording: recording).environmentObject(model).environmentObject(model.library).preferredColorScheme(.dark))
            try? await Task.sleep(for: .seconds(1)); capture("Prism3-render-Editor")
        }
        panel.setContentSize(CGSize(width: 1240, height: 860))
        panel.contentView = NSHostingView(rootView: ReviewRoot(model: model))
        try? await Task.sleep(for: .milliseconds(500))
        stress()
        try? "Finished owned-view raster review".write(to: build.appendingPathComponent("UI-render-status.txt"), atomically: true, encoding: .utf8)
    }
    static func stress() {
        guard let model else { return }
        Task { @MainActor in
            let settings = model.settings, theme = model.theme, motion = model.motionEnabled, accent = model.accentChoice
            var longest = 0.0, total = 0.0, longestLayout = 0.0, totalLayout = 0.0
            let began = ProcessInfo.processInfo.systemUptime
            for index in 0..<120 {
                let start = ProcessInfo.processInfo.systemUptime
                switch index % 6 {
                case 0: model.destination = Destination.allCases[(index / 6) % Destination.allCases.count]
                case 1: model.settings.mode = CaptureMode.allCases[(index / 6) % 3]
                case 2: model.settings.fps = [24, 30, 60][(index / 6) % 3]
                case 3: model.accentChoice = AccentPalette.allCases[(index / 6) % 4].rawValue
                case 4: model.motionEnabled.toggle()
                default: model.theme = index % 12 == 5 ? "Light" : "Dark"
                }
                panel?.contentView?.layoutSubtreeIfNeeded(); panel?.displayIfNeeded()
                let layout = (ProcessInfo.processInfo.systemUptime - start) * 1000; longestLayout = max(longestLayout, layout); totalLayout += layout
                do { try await Task.sleep(for: .milliseconds(55)) } catch { break }
                let interval = (ProcessInfo.processInfo.systemUptime - start) * 1000; longest = max(longest, interval); total += interval
            }
            model.settings = settings; model.theme = theme; model.motionEnabled = motion; model.accentChoice = accent; model.destination = .studio
            let locked = (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? NSNumber
            let result: [String: Any] = ["changes": 120, "duration": ProcessInfo.processInfo.systemUptime - began, "meanIntervalMs": total / 120, "longestIntervalMs": longest, "meanMutationAndLayoutMs": totalLayout / 120, "longestMutationAndLayoutMs": longestLayout, "requestedIntervalMs": 55, "desktopLocked": locked?.boolValue ?? false, "scope": "Main-actor single-action tab, option, appearance, motion changes and owned view layout. Display rendering needs an unlocked desktop."]
            let file = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("Interaction-performance-report.json")
            try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: file)
            model.notify("Interaction test complete · 120 changes")
        }
    }
}
@MainActor enum AppContext { static weak var model: AppModel? }
