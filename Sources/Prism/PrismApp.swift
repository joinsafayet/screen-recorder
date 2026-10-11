import SwiftUI
import AppKit

@main
struct PrismApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Prism", id: "prism-studio") {
            RootView().environmentObject(model).environmentObject(model.library).environmentObject(model.telemetry)
                .preferredColorScheme(model.colorScheme)
                .background(WindowReader { model.mainWindow = $0 })
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    let hadAccess = model.screenAccess
                    model.refreshPermissions()
                    if model.screenAccess && !hadAccess { Task { await model.refreshSources() } }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1240, height: 860)
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Recording") { model.destination = .studio; model.showMainWindow() }.keyboardShortcut("n")
            }
            CommandMenu("Recording") {
                Button(model.phase.isCapturing ? "Stop Recording" : "Start Recording") {
                    if model.phase.isCapturing { Task { await model.stopRecording() } }
                    else { model.startRecording() }
                }.keyboardShortcut("r", modifiers: [.command, .shift]).disabled(model.phase.isActive && !model.phase.isCapturing)
                Button(model.phase == .paused ? "Resume" : "Pause") { model.togglePause() }
                    .keyboardShortcut("p", modifiers: [.command, .shift]).disabled(!model.phase.isCapturing)
                Button("Add Marker") { model.addMarker() }.keyboardShortcut("m", modifiers: [.command, .shift]).disabled(!model.phase.isCapturing)
                Button("Recordings") { model.destination = .library; model.showMainWindow() }.keyboardShortcut("l")
            }
            CommandGroup(replacing: .appSettings) {
                Button("Preferences…") { model.destination = .settings; model.showMainWindow() }.keyboardShortcut(",")
            }
        }
        MenuBarExtra {
            VStack(alignment: .leading) {
                Text("Prism · \(model.phase.label)")
                if model.phase.isCapturing {
                    RecordingClock(telemetry: model.telemetry)
                    Button(model.phase == .paused ? "Resume Recording" : "Pause Recording") { model.togglePause() }
                    Button("Add Marker") { model.addMarker() }
                    Button("Stop & Save") { Task { await model.stopRecording() } }
                } else {
                    Button("New Recording") { model.destination = .studio; model.showMainWindow() }
                }
                Divider()
                Button("Open Prism") { model.showMainWindow() }
                Button("Quit Prism") {
                    if model.phase.isCapturing { Task { await model.stopRecording(); NSApp.terminate(nil) } }
                    else if !model.phase.isActive { NSApp.terminate(nil) }
                }.disabled(model.phase.isActive && !model.phase.isCapturing)
            }
        } label: {
            Image(systemName: model.phase.isCapturing ? "record.circle.fill" : "record.circle")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        AppContext.model?.showMainWindow(); return false
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if let model = AppContext.model, model.phase.isCapturing {
            Task { @MainActor in await model.stopRecording(); NSApp.reply(toApplicationShouldTerminate: true) }
            return .terminateLater
        }
        if AppContext.model?.phase.isActive == true { return .terminateCancel }
        return .terminateNow
    }
}

@MainActor enum AppContext { static weak var model: AppModel? }

struct WindowReader: NSViewRepresentable {
    var callback: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { if let window = view.window { window.title = "Prism"; window.titlebarAppearsTransparent = true; window.isMovableByWindowBackground = true; callback(window) } }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
