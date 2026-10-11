import SwiftUI
import AppKit

/// Isolated visual verification host. Its clips, manifest, and defaults do not use the user's library.
@main struct UIReview {
    @MainActor static func main() {
        _ = NSApplication.shared; NSApp.setActivationPolicy(.accessory)
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
                model.globalShortcuts = false; model.theme = "Dark"; model.destination = .library
                let panel = NSPanel(contentRect: CGRect(x: 340, y: 100, width: 1240, height: 860), styleMask: [.titled, .resizable, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
                panel.title = "Prism UI Review"; panel.hidesOnDeactivate = false
                panel.contentView = NSHostingView(rootView: ReviewRoot(model: model))
                model.mainWindow = panel
                panel.orderBack(nil)
                ReviewContext.panel = panel; ReviewContext.model = model
            } catch { print("UI review failed: \(error)"); NSApp.terminate(nil) }
        }
        NSApp.run()
    }
}
private struct ReviewRoot: View {
    @ObservedObject var model: AppModel
    var body: some View {
        RootView().environmentObject(model).environmentObject(model.library).environmentObject(model.telemetry).preferredColorScheme(model.colorScheme)
    }
}
@MainActor enum ReviewContext { static var panel: NSPanel?; static var model: AppModel? }
@MainActor enum AppContext { static weak var model: AppModel? }
