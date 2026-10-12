import SwiftUI
import ScreenCaptureKit

struct StudioView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.prismReduceMotion) private var reduceMotion
    @ViewState<Bool> private var inspectorVisible = true
    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack(spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Recording studio").font(.system(size: 25, weight: .semibold)).tracking(-0.7)
                        Text("Frame your idea. Make it yours.").font(.system(size: 11)).foregroundStyle(Color.muted)
                    }
                    Spacer(minLength: 12)
                    HStack(spacing: 8) {
                        Image(systemName: "pencil.line").foregroundStyle(Color.muted)
                        TextField("Name this recording…", text: $model.sessionTitle).textFieldStyle(.plain).font(.system(size: 12))
                    }.padding(10).frame(width: 210).background(Color.surface, in: RoundedRectangle(cornerRadius: 9)).disabled(model.phase.isActive)
                    Button { Task { await model.refreshSources() } } label: { Image(systemName: "arrow.clockwise").frame(width: 16, height: 16) }
                        .buttonStyle(QuietButton()).disabled(model.loadingSources || model.phase.isActive).help("Refresh capture sources")
                    PreparationAction()
                    Button { inspectorVisible.toggle() } label: { Image(systemName: "sidebar.right").frame(width: 16, height: 16) }
                        .buttonStyle(QuietButton()).help("Show or hide recording inspector")
                }.padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 16)
                StudioPresets().disabled(model.phase.isActive).padding(.horizontal, 24).padding(.bottom, 16)
                HSplitView {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            SectionTitle(text: "Capture source")
                            CaptureModeSelector().disabled(model.phase.isActive)
                            SourcePreview(height: min(420, max(240, geometry.size.height - 360)))
                            CaptureSourcePicker().disabled(model.phase.isActive)
                            Label(model.pickedFilter?.style == .display ? "Prism hides during capture. Use the menu bar to pause or stop." : "Prism and its controls stay outside your capture.", systemImage: "lock.shield")
                                .font(.system(size: 10)).foregroundStyle(Color.muted)
                            PreparationPanel()
                            if model.phase.isCapturing || model.telemetry.statistics.frames > 0 { CaptureMonitor() }
                        }.padding(18)
                    }.frame(minWidth: 410, maxWidth: .infinity).background(Color.surface, in: RoundedRectangle(cornerRadius: 16))
                    if inspectorVisible {
                        RecordingInspector().frame(minWidth: 270, idealWidth: 300, maxWidth: 360)
                    }
                }.padding(.horizontal, 24).padding(.bottom, 16)
                Divider().overlay(Color.line)
                RecordDock().padding(.horizontal, 24).padding(.vertical, 12)
            }
        }
    }
}

struct CaptureModeSelector: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        HStack(spacing: 7) {
            ForEach(CaptureMode.allCases) { mode in
                Button { model.settings.mode = mode } label: {
                    HStack(spacing: 7) {
                        Image(systemName: mode.icon).font(.system(size: 14))
                        Text(mode.rawValue).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    }.foregroundStyle(model.settings.mode == mode ? Color.accent : Color.muted)
                        .frame(maxWidth: .infinity).padding(.vertical, 12).selectionSurface(model.settings.mode == mode, radius: 9)
                }.buttonStyle(InteractiveButton(radius: 9)).help(mode.detail)
            }
        }
    }
}

struct RecordingInspector: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.prismReduceMotion) private var reduceMotion
    @ViewState<Bool> private var videoExpanded = true
    @ViewState<Bool> private var audioExpanded = true
    @ViewState<Bool> private var cameraExpanded = true
    @ViewState<Bool> private var behaviourExpanded = false
    @Namespace private var frameRate
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack { SectionTitle(text: "Recording inspector"); Spacer(); Image(systemName: "slider.horizontal.3").foregroundStyle(Color.muted) }
                DisclosureGroup("Video", isExpanded: $videoExpanded) {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("Quality", selection: $model.settings.quality) { ForEach(Quality.allCases) { Text($0.description).tag($0) } }.labelsHidden()
                        HStack { Text("Frame rate").font(.system(size: 11)).foregroundStyle(Color.muted); Spacer(); Text("fps").font(.system(size: 10)).foregroundStyle(Color.muted) }
                        HStack(spacing: 4) {
                            ForEach([24, 30, 60], id: \.self) { fps in
                                Button { model.settings.fps = fps } label: {
                                    Text("\(fps)").font(.system(size: 12, weight: .semibold)).foregroundStyle(model.settings.fps == fps ? Color.accent : Color.muted)
                                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                                        .background {
                                            if model.settings.fps == fps { RoundedRectangle(cornerRadius: 7).fill(Color.accent.opacity(0.17)).matchedGeometryEffect(id: "fps", in: frameRate) }
                                        }.contentShape(RoundedRectangle(cornerRadius: 7))
                                }.buttonStyle(InteractiveButton(radius: 7)).accessibilityLabel("\(fps) frames per second")
                            }
                        }.padding(3).background(Color.canvas, in: RoundedRectangle(cornerRadius: 10)).animation(PrismMotion.selection(reduceMotion), value: model.settings.fps)
                        Picker("Codec", selection: $model.settings.codec) { ForEach(VideoCodec.allCases) { Text($0.rawValue).tag($0) } }
                        Picker("Format", selection: $model.settings.format) { ForEach(VideoFormat.allCases) { Text($0.rawValue).tag($0) } }
                    }.padding(.top, 12)
                }
                Divider().overlay(Color.line)
                DisclosureGroup("Audio", isExpanded: $audioExpanded) {
                    VStack(spacing: 14) {
                        FeatureToggle(icon: "speaker.wave.2", title: "System audio", subtitle: "Sounds from your Mac", value: $model.settings.systemAudio)
                        FeatureToggle(icon: "mic", title: "Microphone", subtitle: "Your voice and narration", value: $model.settings.microphone)
                        if model.settings.microphone {
                            Picker("Microphone", selection: $model.settings.microphoneID) { Text("System default").tag(""); ForEach(model.microphones, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) } }.labelsHidden()
                        }
                    }.padding(.top, 12)
                }
                Divider().overlay(Color.line)
                DisclosureGroup("Camera", isExpanded: $cameraExpanded) {
                    VStack(alignment: .leading, spacing: 14) {
                        FeatureToggle(icon: "person.crop.circle", title: "Presenter bubble", subtitle: "Put a face to your story", value: $model.settings.camera)
                        if model.settings.camera {
                            Picker("Camera", selection: $model.settings.cameraID) { Text("System default").tag(""); ForEach(model.cameras, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) } }.labelsHidden()
                            Picker("Position", selection: $model.settings.presenterCorner) { ForEach(PresenterCorner.allCases) { Text($0.rawValue).tag($0) } }
                            HStack { Text("Size"); Slider(value: $model.settings.presenterSize, in: 0.12...0.4, step: 0.01); Text("\(Int(model.settings.presenterSize * 100))%").monospacedDigit() }.font(.system(size: 11))
                            Toggle("Mirror camera", isOn: $model.settings.mirrorCamera).toggleStyle(.switch).controlSize(.small)
                        }
                    }.padding(.top, 12)
                }
                Divider().overlay(Color.line)
                DisclosureGroup("Capture behaviour", isExpanded: $behaviourExpanded) {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("Countdown", selection: $model.settings.countdown) { Text("None").tag(0); ForEach([3, 5, 10], id: \.self) { Text("\($0) seconds").tag($0) } }
                        Toggle("Show cursor", isOn: $model.settings.showCursor)
                        Toggle("Click highlights", isOn: $model.settings.highlightClicks)
                        Picker("Auto stop", selection: $model.settings.stopAfterMinutes) { Text("Until I stop").tag(0); ForEach([1, 5, 10, 15, 30, 60], id: \.self) { Text("\($0) minutes").tag($0) } }
                        Toggle("Hide main window", isOn: $model.settings.hideWindow)
                        Toggle("Floating controls", isOn: $model.settings.showFloatingControls)
                    }.padding(.top, 12).toggleStyle(.switch).controlSize(.small)
                }
            }.font(.system(size: 12, weight: .medium)).padding(18).disabled(model.phase.isActive)
                .animation(PrismMotion.selection(reduceMotion), value: model.settings.camera)
                .animation(PrismMotion.selection(reduceMotion), value: model.settings.microphone)
        }.background(Color.surface, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct SourcePreview: View {
    @EnvironmentObject private var preparation: PreparationMonitor
    var height: CGFloat = 249
    @EnvironmentObject private var model: AppModel
    @Environment(\.prismReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color.previewBase)
            if let preview = preparation.screenImage ?? model.preview {
                Image(nsImage: preview).resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 12)).padding(8)
            } else {
                GeometryReader { geo in
                    ZStack {
                        LinearGradient(colors: [Color(red: 0.07, green: 0.15, blue: 0.25), .previewBase], startPoint: .topLeading, endPoint: .bottomTrailing)
                        Path { path in
                            for x in stride(from: CGFloat(0), through: geo.size.width, by: 32) { path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x, y: geo.size.height)) }
                            for y in stride(from: CGFloat(0), through: geo.size.height, by: 32) { path.move(to: CGPoint(x: 0, y: y)); path.addLine(to: CGPoint(x: geo.size.width, y: y)) }
                        }.stroke(Color.brandBlue.opacity(0.07), lineWidth: 0.5)
                    }
                }.clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(spacing: 13) {
                    AnimatedSymbol(name: model.screenAccess ? model.settings.mode.icon : "display").font(.system(size: 33, weight: .ultraLight)).foregroundStyle(Color.accent)
                        .frame(width: 72, height: 64).background(Color.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 17)).overlay(RoundedRectangle(cornerRadius: 17).stroke(Color.accent.opacity(0.18)))
                    Text(model.screenAccess ? "Choose your perspective" : "Your next great take starts here").font(.system(size: 15, weight: .medium)).foregroundStyle(.white)
                    Text(model.screenAccess ? "Select a source below to preview it." : "Allow screen access to see your capture preview.").font(.system(size: 10)).foregroundStyle(.white.opacity(0.5))
                    if !model.screenAccess {
                        Button { Task { await model.requestScreenAccess() } } label: { Label("Allow screen access", systemImage: "arrow.up.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.accent).padding(5) }.buttonStyle(InteractiveButton(radius: 6)).padding(.top, 3)
                    } else if model.settings.mode == .region && model.region == nil {
                        Button("Select an area") { model.selectRegion() }.buttonStyle(QuietButton())
                    }
                }
            }
            if model.settings.camera, let image = preparation.cameraImage {
                GeometryReader { geometry in
                    let d = min(geometry.size.width, geometry.size.height) * model.settings.presenterSize
                    let left = model.settings.presenterCorner == .bottomLeft || model.settings.presenterCorner == .topLeft
                    let top = model.settings.presenterCorner == .topLeft || model.settings.presenterCorner == .topRight
                    Image(nsImage: image).resizable().scaledToFill().frame(width: d, height: d).clipShape(Circle())
                        .scaleEffect(x: model.settings.mirrorCamera ? -1 : 1, y: 1).overlay(Circle().stroke(.white.opacity(0.7), lineWidth: 2))
                        .position(x: left ? d / 2 + 18 : geometry.size.width - d / 2 - 18, y: top ? d / 2 + 38 : geometry.size.height - d / 2 - 38)
                }.allowsHitTesting(false)
            }
            VStack {
                HStack {
                    HStack(spacing: 5) { Circle().fill(model.phase == .recording ? Color.red : Color.accent).frame(width: 5, height: 5); Text(model.phase.isCapturing ? "SOURCE SNAPSHOT" : preparation.running ? "LIVE SETUP · 2 FPS" : "CAPTURE PREVIEW").font(.system(size: 8, weight: .bold)).tracking(1) }
                        .foregroundStyle(.white.opacity(0.8)).padding(8).background(.black.opacity(0.3), in: Capsule())
                    Spacer()
                    if model.loadingPreview { ProgressView().controlSize(.mini).tint(.white) }
                    Text("\(model.settings.fps) FPS").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundStyle(.white.opacity(0.7)).padding(8).background(.black.opacity(0.3), in: Capsule())
                }
                Spacer()
                HStack { Spacer(); Image(systemName: model.settings.mode.icon).font(.system(size: 10)); Text(model.sourceName).font(.system(size: 10, weight: .medium)).lineLimit(1) }
                    .foregroundStyle(.white.opacity(0.8)).padding(8).background(.black.opacity(0.35), in: Capsule()).fixedSize().frame(maxWidth: .infinity, alignment: .trailing)
            }.padding(13)
            if case .countdown(let seconds) = model.phase {
                Color.black.opacity(0.45).clipShape(RoundedRectangle(cornerRadius: 12))
                Text("\(seconds)").font(.system(size: 76, weight: .thin, design: .rounded)).foregroundStyle(.white)
                    .contentTransition(.numericText(countsDown: true))
                    .animation(PrismMotion.selection(reduceMotion), value: seconds)
            }
        }.frame(height: height)
    }
}

struct CaptureSourcePicker: View {
    @ViewState<Bool> private var savingRegion = false
    @ViewState<String> private var regionName = ""
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: model.settings.mode.icon).foregroundStyle(Color.accent)
                if model.pickedFilter != nil {
                    Text(model.pickedSourceName).font(.system(size: 12)).lineLimit(1)
                    Button("Clear") { model.pickedFilter = nil; Task { await model.refreshPreview() } }.buttonStyle(QuietButton())
                } else if model.settings.mode == .window {
                    Picker("Window", selection: $model.windowID) {
                        if model.windows.isEmpty { Text("No windows available").tag(Optional<CGWindowID>.none) }
                        ForEach(model.windows, id: \.windowID) { window in Text("\(window.owningApplication?.applicationName ?? "App") — \(window.title ?? "Untitled")").tag(Optional(window.windowID)) }
                    }.labelsHidden()
                } else {
                    Picker("Display", selection: $model.displayID) {
                        if model.displays.isEmpty { Text(model.displayName).tag(model.displayID) }
                        ForEach(model.displays, id: \.displayID) { display in Text("Display \(display.displayID) · \(display.width) × \(display.height)").tag(display.displayID) }
                    }.labelsHidden()
                }
                Spacer()
                if model.settings.mode == .region {
                    Button(model.region == nil ? "Select area" : "Reselect") { model.selectRegion() }.buttonStyle(QuietButton())
                } else {
                    Chip(title: model.settings.quality == .original ? "NATIVE" : "≤ \(model.settings.quality.maxHeight)p", color: .accent)
                }
            }
            HStack(spacing: 10) {
                Button { model.chooseSystemSource() } label: { Label("Choose with macOS", systemImage: "macwindow.badge.plus") }.buttonStyle(QuietButton())
                if model.settings.mode == .region {
                    Picker("Aspect", selection: $model.regionAspect) { ForEach(CaptureAspect.allCases) { Text($0.rawValue).tag($0) } }.frame(width: 100)
                    Menu("Saved areas") {
                        ForEach(model.savedRegions) { saved in Button(saved.name) { model.restoreRegion(saved) } }
                        Button("Save current area…") { regionName = "My capture area"; savingRegion = true }.disabled(model.region == nil)
                        if !model.savedRegions.isEmpty { Divider(); Button("Remove saved areas", role: .destructive) { model.savedRegions = [] } }
                    }.font(.system(size: 11))
                }
            }
            if model.settings.mode == .window && model.windows.isEmpty { Text("Refresh sources after granting screen access.").font(.system(size: 10)).foregroundStyle(Color.muted) }
        }
        .alert("Save capture area", isPresented: $savingRegion) {
            TextField("Area name", text: $regionName)
            Button("Cancel", role: .cancel) {}
            Button("Save") { model.saveCurrentRegion(name: regionName) }
        }
    }
}

struct RecordDock: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var telemetry: RecordingTelemetry
    @EnvironmentObject private var library: LibraryStore
    var body: some View {
        HStack(spacing: 16) {
            ZStack { Circle().fill(Color.accent.opacity(0.1)); AnimatedSymbol(name: model.phase.isCapturing ? "waveform" : "record.circle").font(.system(size: 20)).foregroundStyle(Color.accent) }.frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 5) {
                Text(model.phase.isCapturing ? "\(model.phase.label)  ·  \(RecordingMath.clock(telemetry.elapsed))" : model.phase.label).font(.system(size: 13, weight: .semibold)).monospacedDigit()
                Text(model.phase == .saving ? telemetry.savingMessage : model.phase.isCapturing ? "\(telemetry.markers.count) markers · Capture monitor tracks encoder pressure" : "Saves to \(library.folder.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))")
                    .font(.system(size: 10)).foregroundStyle(Color.muted).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 0)
            if model.phase.isCapturing {
                AudioMeter()
                Button { model.addMarker() } label: { Image(systemName: "bookmark").frame(width: 20) }.buttonStyle(QuietButton()).help("Add marker · Control Command M")
                Button { model.togglePause() } label: { AnimatedSymbol(name: model.phase == .paused ? "play.fill" : "pause.fill").frame(width: 20) }.buttonStyle(QuietButton())
                Button { Task { await model.stopRecording() } } label: { Label("Stop & save", systemImage: "stop.fill") }.buttonStyle(PrimaryButton(color: .red))
            } else if model.phase == .saving {
                ProgressView().controlSize(.small)
                Text("Saving your take").font(.system(size: 12)).foregroundStyle(Color.muted)
            } else if case .countdown = model.phase {
                Button("Cancel countdown") { model.cancelCountdown() }.buttonStyle(QuietButton())
            } else {
                Button {
                    if model.canCapture { model.startRecording() } else { Task { await model.requestScreenAccess() } }
                } label: {
                    HStack(spacing: 12) { Image(systemName: "record.circle"); Text(model.canCapture ? "Start recording" : "Set up recording"); if model.canCapture { Text("⌘ ⇧ R").font(.system(size: 10)).opacity(0.7) } }
                }.buttonStyle(PrimaryButton()).disabled(model.phase.isActive || library.isBusy)
            }
        }.card(padding: 18)
    }
}

private struct Tip: View {
    let icon: String, title: String, text: String
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.system(size: 15, weight: .light)).foregroundStyle(Color.muted).frame(width: 20).padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) { Text(title).font(.system(size: 11, weight: .medium)); Text(text).font(.system(size: 10)).foregroundStyle(Color.muted).lineSpacing(3) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct FloatingControls: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var telemetry: RecordingTelemetry
    var body: some View {
        HStack(spacing: 17) {
            Circle().fill(model.phase == .paused ? Color.orange : .red).frame(width: 8, height: 8)
            Text(RecordingMath.clock(telemetry.elapsed)).font(.system(size: 16, weight: .medium, design: .monospaced)).foregroundStyle(.white).frame(width: 75)
            Button { model.togglePause() } label: { AnimatedSymbol(name: model.phase == .paused ? "play.fill" : "pause.fill").frame(width: 24, height: 30) }.buttonStyle(InteractiveButton(radius: 6)).foregroundStyle(.white).help("Pause / Resume")
            Button { model.addMarker() } label: { Image(systemName: "bookmark").frame(width: 24, height: 30) }.buttonStyle(InteractiveButton(radius: 6)).foregroundStyle(.white).help("Add marker")
            Rectangle().fill(.white.opacity(0.15)).frame(width: 1, height: 20)
            Button { Task { await model.stopRecording() } } label: { Image(systemName: "stop.fill").foregroundStyle(.white).frame(width: 30, height: 30).background(Color.red, in: RoundedRectangle(cornerRadius: 8)) }.buttonStyle(InteractiveButton(radius: 8)).help("Stop & Save")
            Button { model.showMainWindow() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").foregroundStyle(.white.opacity(0.5)).font(.system(size: 12)).frame(width: 24, height: 30) }.buttonStyle(InteractiveButton(radius: 6)).help("Show Prism")
        }.padding(18).background(Color.previewBase, in: RoundedRectangle(cornerRadius: 18)).overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.12)))
    }
}
