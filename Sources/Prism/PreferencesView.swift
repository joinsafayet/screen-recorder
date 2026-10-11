import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var library: LibraryStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 9) {
                    Text("Make yourself at home.").font(.system(size: 31, weight: .semibold)).tracking(-1.1)
                    Text("A workspace that works the way you do.").font(.system(size: 12)).foregroundStyle(Color.muted)
                }.padding(.bottom, 3)
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 20) {
                        SectionTitle(text: "Permissions")
                        permission(icon: "display", title: "Screen recording", detail: "Required to capture your screen and system audio.", granted: model.screenAccess) { Task { await model.requestScreenAccess() } }
                        Divider().overlay(Color.line)
                        permission(icon: "mic", title: "Microphone", detail: "Optional. Add voice and narration to your captures.", granted: model.microphoneAccess) { Task { await model.requestMicrophoneAccess() } }
                        Divider().overlay(Color.line)
                        permission(icon: "person.crop.circle", title: "Camera", detail: "Optional. A circular presenter bubble in your video.", granted: model.cameraAccess) { Task { await model.requestCameraAccess() } }
                        Button { model.refreshPermissions(); Task { await model.refreshSources() } } label: { Label("Check permissions again", systemImage: "arrow.clockwise") }.buttonStyle(QuietButton())
                        Text("If access was changed in System Settings, you may need to quit and reopen Prism.").font(.system(size: 10)).foregroundStyle(Color.muted).lineSpacing(3)
                    }.frame(maxWidth: .infinity, alignment: .leading).card()
                    VStack(alignment: .leading, spacing: 20) {
                        SectionTitle(text: "Appearance")
                        HStack(spacing: 9) {
                            ForEach(["Dark", "Light", "System"], id: \.self) { theme in
                                Button { model.theme = theme } label: {
                                    VStack(spacing: 10) {
                                        ZStack(alignment: .leading) {
                                            RoundedRectangle(cornerRadius: 6).fill(theme == "Light" ? Color.white : Color(red: 0.08, green: 0.13, blue: 0.20))
                                            if theme == "System" { Rectangle().fill(.white.opacity(0.9)).frame(width: 36).frame(maxWidth: .infinity, alignment: .trailing) }
                                            RoundedRectangle(cornerRadius: 4).fill(Color.accent.opacity(0.4)).frame(width: 15).padding(5)
                                            RoundedRectangle(cornerRadius: 2).fill(Color.accent.opacity(0.2)).frame(width: 30, height: 18).padding(.leading, 26)
                                        }.frame(width: 72, height: 45).clipShape(RoundedRectangle(cornerRadius: 6))
                                        Text(theme).font(.system(size: 11, weight: .medium)).foregroundStyle(model.theme == theme ? Color.accent : Color.muted)
                                    }.padding(7).selectionSurface(model.theme == theme, radius: 10)
                                }.buttonStyle(InteractiveButton(radius: 10))
                            }
                        }
                        Text("Graphite surfaces. Clear blue accents.").font(.system(size: 10)).foregroundStyle(Color.muted)
                        FeatureToggle(icon: "sparkles", title: "Interface motion", subtitle: "Smooth tabs and button feedback", value: $model.motionEnabled)
                        Text("Respects your Mac’s Reduce Motion setting.").font(.system(size: 10)).foregroundStyle(Color.muted)
                        Rectangle().fill(Color.line).frame(height: 1)
                        SectionTitle(text: "Capture behavior")
                        FeatureToggle(icon: "macwindow", title: "Hide main window", subtitle: "A clear workspace while recording", value: $model.settings.hideWindow)
                        FeatureToggle(icon: "rectangle.bottomthird.inset.filled", title: "Floating controls", subtitle: "Pause and stop from a small panel", value: $model.settings.showFloatingControls)
                    }.frame(width: 285).card()
                }
                VStack(alignment: .leading, spacing: 18) {
                    SectionTitle(text: "Save location")
                    HStack(spacing: 15) {
                        Image(systemName: "folder.fill").font(.system(size: 27, weight: .light)).foregroundStyle(Color.accent)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(library.folder.lastPathComponent).font(.system(size: 13, weight: .semibold))
                            Text(library.folder.path).font(.system(size: 11)).foregroundStyle(Color.muted).textSelection(.enabled)
                        }
                        Spacer()
                        Button(library.isBusy ? "Moving library…" : "Change folder") { Task { do { try await library.changeFolder() } catch { model.error = error.localizedDescription } } }.buttonStyle(QuietButton()).disabled(model.phase.isActive || library.isBusy)
                    }
                    Text("Your existing recordings move with your library when you choose another folder.").font(.system(size: 10)).foregroundStyle(Color.muted)
                }.card()
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 18) {
                        SectionTitle(text: "Audio & camera devices")
                        Picker("Microphone", selection: $model.settings.microphoneID) {
                            Text("System default").tag("")
                            ForEach(model.microphones, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
                        }.font(.system(size: 12))
                        Picker("Camera", selection: $model.settings.cameraID) {
                            Text("System default").tag("")
                            ForEach(model.cameras, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
                        }.font(.system(size: 12))
                        HStack { Text("System mix level").font(.system(size: 11)); Slider(value: $model.settings.systemGain, in: 0...1); Text("\(Int(model.settings.systemGain * 100))%").font(.system(size: 10, design: .monospaced)).frame(width: 35) }
                        HStack { Text("Voice mix level").font(.system(size: 11)); Slider(value: $model.settings.microphoneGain, in: 0...1); Text("\(Int(model.settings.microphoneGain * 100))%").font(.system(size: 10, design: .monospaced)).frame(width: 35) }
                        Text("Choose presenter size, position, and mirroring in the recorder. Audio gains apply when both sources are mixed.").font(.system(size: 10)).foregroundStyle(Color.muted).lineSpacing(3)
                    }.frame(maxWidth: .infinity, alignment: .leading).card().disabled(model.phase.isActive || library.isBusy)
                    VStack(alignment: .leading, spacing: 18) {
                        SectionTitle(text: "Keyboard shortcuts")
                        Toggle("Global shortcuts", isOn: $model.globalShortcuts).toggleStyle(.switch).controlSize(.small).font(.system(size: 12))
                        shortcut("Start / stop anywhere", keys: "⌃ ⌘ R")
                        shortcut("Pause / resume", keys: "⌃ ⌘ P")
                        shortcut("Add marker", keys: "⌃ ⌘ M")
                        shortcut("Open library", keys: "⌘ L")
                        shortcut("Preferences", keys: "⌘ ,")
                        Text("\(model.hotkeyStatus). Focused shortcuts: ⌘ ⇧ R to record, ⌘ ⇧ P to pause.").font(.system(size: 10)).foregroundStyle(Color.muted).lineSpacing(3)
                    }.frame(width: 285).card()
                }
            }.padding(30)
        }
    }
    private func permission(icon: String, title: String, detail: String, granted: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(granted ? Color.mint : Color.accent).frame(width: 28)
            VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(size: 12, weight: .semibold)); Text(detail).font(.system(size: 10)).foregroundStyle(Color.muted).fixedSize(horizontal: false, vertical: true) }
            Spacer(minLength: 5)
            if granted { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.mint) }
            else { Button("Allow", action: action).buttonStyle(QuietButton()) }
        }
    }
    private func shortcut(_ title: String, keys: String) -> some View {
        HStack { Text(title).font(.system(size: 11)).foregroundStyle(Color.muted); Spacer(); Text(keys).font(.system(size: 10, weight: .medium, design: .monospaced)).padding(.horizontal, 8).padding(.vertical, 5).background(Color.elevated, in: RoundedRectangle(cornerRadius: 5)) }
    }
}
