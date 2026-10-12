import SwiftUI
import AppKit
import AVFoundation

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
                let docs = CommandLine.arguments.contains("--docs")
                let root = docs ? URL(fileURLWithPath: "/tmp/Prism-Documentation") : build.appendingPathComponent("UI-review-assets")
                let folder = root.appendingPathComponent("Videos")
                let library = LibraryStore(folder: folder, support: root.appendingPathComponent("Index"))
                let video = folder.appendingPathComponent("Prism walkthrough.mp4")
                if !FileManager.default.fileExists(atPath: video.path) {
                    _ = try await DocumentationMedia.makeVideo(at: video)
                }
                if library.recordings.isEmpty {
                    try await library.add(url: video, source: "Sample capture", fps: 30, title: "Prism — product walkthrough",
                        markers: [RecordingMarker(time: 0.8, title: "Frame your source"), RecordingMarker(time: 3, title: "Edit your take"), RecordingMarker(time: 5.1, title: "Export a copy")])
                }
                let model = AppModel(library: library, discoverSources: false)
                model.globalShortcuts = false; model.theme = "Dark"; model.accentChoice = "Blue"; model.motionEnabled = true; model.settings = CaptureSettings(); model.destination = .library
                if docs {
                    // Display a sample workspace in this isolated, noninteractive documentation host.
                    model.displayID = 0; model.screenAccess = true
                    let generator = AVAssetImageGenerator(asset: AVURLAsset(url: video)); generator.appliesPreferredTrackTransform = true
                    let frame = try await generator.image(at: CMTime(seconds: 1, preferredTimescale: 600)).image
                    model.preview = NSImage(cgImage: frame, size: CGSize(width: frame.width, height: frame.height))
                    if let recording = library.recordings.first {
                        var document = TimelineDocument(recordingID: recording.id, duration: recording.duration)
                        document.cuts = [TimelineCut(start: 0, end: 1.8), TimelineCut(start: 2.4, end: min(5.8, recording.duration))]
                        try await library.saveEdits(recording, document: document)
                    }
                }
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
            .allowsHitTesting(!CommandLine.arguments.contains("--docs"))
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
        let docs = CommandLine.arguments.contains("--docs")
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
        if docs {
            model.theme = "Light"; model.destination = .studio
            try? await Task.sleep(for: .milliseconds(500)); capture("Prism3-render-Studio-Light")
            model.theme = "Dark"
            panel.setContentSize(CGSize(width: 1600, height: 480))
            for light in [false, true] {
                panel.contentView = NSHostingView(rootView: RepositoryHero().preferredColorScheme(light ? .light : .dark))
                try? await Task.sleep(for: .milliseconds(500)); capture(light ? "Prism-repository-hero-light" : "Prism-repository-hero-dark")
            }
            panel.setContentSize(CGSize(width: 1240, height: 860))
            panel.contentView = NSHostingView(rootView: ReviewRoot(model: model))
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
        panel.setContentSize(CGSize(width: 1060, height: 850))
        for light in [false, true] {
            panel.contentView = NSHostingView(rootView: BrandIconReview().preferredColorScheme(light ? .light : .dark))
            try? await Task.sleep(for: .milliseconds(500)); capture(light ? "Prism-brand-icons-Light" : "Prism-brand-icons-Dark")
        }
        if let recording = model.library.recordings.first {
            panel.setContentSize(CGSize(width: 1060, height: 730))
            panel.contentView = NSHostingView(rootView: DocumentationEditor(recording: recording, poster: docs ? model.preview : nil).environmentObject(model).environmentObject(model.library).preferredColorScheme(.dark))
            try? await Task.sleep(for: .seconds(1)); capture("Prism3-render-Editor")
        }
        panel.contentView = NSHostingView(rootView: AboutView().preferredColorScheme(.dark))
        panel.setContentSize(CGSize(width: 500, height: 480))
        try? await Task.sleep(for: .milliseconds(500)); capture("Prism3-render-About")
        panel.setContentSize(CGSize(width: 1240, height: 860))
        panel.contentView = NSHostingView(rootView: ReviewRoot(model: model))
        try? await Task.sleep(for: .milliseconds(500))
        if !docs { stress() }
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
private struct DocumentationEditor: View {
    let recording: Recording
    let poster: NSImage?
    var body: some View {
        TimelineEditor(recording: recording).overlay(alignment: .topLeading) {
            if let poster {
                // A decoded sample still replaces the unavailable offscreen AVPlayer layer.
                Image(nsImage: poster).resizable().scaledToFit().frame(width: 649, height: 302)
                    .background(Color.black).clipShape(RoundedRectangle(cornerRadius: 12)).offset(x: 24, y: 86).allowsHitTesting(false).accessibilityHidden(true)
            }
        }
    }
}
private struct BrandIconReview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 18) {
                PrismBrandBadge(size: 80)
                VStack(alignment: .leading, spacing: 7) {
                    Text("Prism").font(.system(size: 34, weight: .semibold)).tracking(-0.7)
                    Text("CAPTURE / EDIT / PRESENT").font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(Color.muted)
                }
                Spacer()
                Text("30 native vectors\n12 / 18 / 28 pt").font(.system(size: 12)).foregroundStyle(Color.muted).multilineTextAlignment(.trailing)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: 6), spacing: 14) {
                ForEach(PrismGlyph.allCases, id: \.self) { glyph in
                    VStack(spacing: 15) {
                        HStack(alignment: .center, spacing: 15) {
                            ForEach([CGFloat(12), 18, 28], id: \.self) { size in
                                PrismGlyphShape(glyph: glyph, compact: size < 16)
                                    .stroke(style: StrokeStyle(lineWidth: max(1.05, min(2.7, size * 1.75 / 24)), lineCap: .round, lineJoin: .round))
                                    .frame(width: size, height: size)
                            }
                        }.foregroundStyle(Color.ink)
                        Text(glyph.title).font(.system(size: 10, weight: .medium)).foregroundStyle(Color.muted).lineLimit(1)
                    }.frame(maxWidth: .infinity).frame(height: 84).card(padding: 12)
                }
            }
            Text("Shared geometry · Optical simplification · Monochrome controls · No idle loops").font(.system(size: 11)).foregroundStyle(Color.muted)
        }.padding(32).frame(width: 1060, height: 850, alignment: .topLeading).background(Color.canvas).foregroundStyle(Color.ink)
    }
}
@MainActor enum AppContext { static weak var model: AppModel? }
