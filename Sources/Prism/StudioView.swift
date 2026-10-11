import SwiftUI
import ScreenCaptureKit

struct StudioView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.prismReduceMotion) private var reduceMotion
    @Namespace private var frameRate
    var body: some View {
        VStack(spacing: 0) {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("Your recording studio.").font(.system(size: 31, weight: .semibold)).tracking(-1.1)
                        Text("Make clear walkthroughs, polished demos, and your next great take.").font(.system(size: 12)).foregroundStyle(Color.muted)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 10) {
                        Button { Task { await model.refreshSources() } } label: {
                            Label(model.loadingSources ? "Refreshing…" : "Refresh sources", systemImage: "arrow.clockwise")
                        }.buttonStyle(QuietButton()).disabled(model.loadingSources || model.phase.isActive)
                        HStack(spacing: 8) {
                            Image(systemName: "pencil.line").foregroundStyle(Color.muted)
                            TextField("Name this recording…", text: $model.sessionTitle).textFieldStyle(.plain).font(.system(size: 11)).frame(width: 155).accessibilityLabel("Recording title")
                        }.padding(9).background(Color.surface, in: RoundedRectangle(cornerRadius: 8)).overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.line)).disabled(model.phase.isActive)
                    }
                }
                StudioPresets().disabled(model.phase.isActive)
                if model.phase.isCapturing || model.telemetry.statistics.frames > 0 { CaptureMonitor() }
                VStack(alignment: .leading, spacing: 12) {
                    SectionTitle(text: "01  /  What are we capturing?")
                    HStack(spacing: 12) {
                        ForEach(CaptureMode.allCases) { mode in
                            Button {
                                model.settings.mode = mode
                            } label: {
                                HStack(spacing: 13) {
                                    Image(systemName: mode.icon).font(.system(size: 22, weight: .light)).frame(width: 30)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(mode.rawValue).font(.system(size: 12, weight: .semibold))
                                        Text(mode.detail).font(.system(size: 10)).foregroundStyle(Color.muted)
                                    }
                                    Spacer(minLength: 0)
                                    AnimatedSymbol(name: model.settings.mode == mode ? "checkmark.circle.fill" : "circle").font(.system(size: 14)).foregroundStyle(model.settings.mode == mode ? Color.accent : Color.line)
                                }.foregroundStyle(model.settings.mode == mode ? Color.accent : Color.ink)
                                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                                    .selectionSurface(model.settings.mode == mode)
                            }.buttonStyle(InteractiveButton())
                        }
                    }.disabled(model.phase.isActive)
                }
                HStack(alignment: .top, spacing: 18) {
                    VStack(alignment: .leading, spacing: 16) {
                        SourcePreview()
                        CaptureSourcePicker().disabled(model.phase.isActive)
                        HStack(spacing: 6) {
                            Image(systemName: "info.circle").font(.system(size: 11))
                            Text("Prism’s window and floating controls stay out of your capture.").font(.system(size: 10))
                        }.foregroundStyle(Color.muted)
                    }.frame(maxWidth: .infinity).card(padding: 18)
                    VStack(alignment: .leading, spacing: 11) {
                        HStack { SectionTitle(text: "02  /  Make it yours"); Spacer(); Image(systemName: "slider.horizontal.3").foregroundStyle(Color.muted).font(.system(size: 12)) }
                        VStack(alignment: .leading, spacing: 9) {
                            Text("Video quality").font(.system(size: 11, weight: .medium)).foregroundStyle(Color.muted)
                            Picker("Quality", selection: $model.settings.quality) {
                                ForEach(Quality.allCases) { q in Text(q.description).tag(q) }
                            }.labelsHidden().pickerStyle(.menu).frame(maxWidth: .infinity, alignment: .leading)
                        }
                        VStack(alignment: .leading, spacing: 9) {
                            HStack { Text("Frame rate").font(.system(size: 11, weight: .medium)).foregroundStyle(Color.muted); Spacer(); Text("fps").font(.system(size: 10)).foregroundStyle(Color.muted) }
                            HStack(spacing: 5) {
                                ForEach([24, 30, 60], id: \.self) { fps in
                                    Button { model.settings.fps = fps } label: {
                                        Text("\(fps)").font(.system(size: 12, weight: .semibold)).foregroundStyle(model.settings.fps == fps ? Color.accent : Color.muted)
                                            .frame(maxWidth: .infinity).padding(.vertical, 9)
                                            .background {
                                                if model.settings.fps == fps {
                                                    RoundedRectangle(cornerRadius: 7).fill(Color.accent.opacity(0.17))
                                                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(Color.accent.opacity(0.4)))
                                                        .matchedGeometryEffect(id: "fps", in: frameRate)
                                                }
                                            }
                                            .contentShape(RoundedRectangle(cornerRadius: 7))
                                            .accessibilityLabel("\(fps) frames per second")
                                            .accessibilityAddTraits(model.settings.fps == fps ? .isSelected : [])
                                    }.buttonStyle(InteractiveButton(radius: 7))
                                }
                            }.padding(3).background(Color.canvas, in: RoundedRectangle(cornerRadius: 10))
                                .animation(PrismMotion.selection(reduceMotion), value: model.settings.fps)
                        }
                        Rectangle().fill(Color.line).frame(height: 1)
                        FeatureToggle(icon: "speaker.wave.2", title: "System audio", subtitle: "Sounds from your Mac", value: $model.settings.systemAudio)
                        FeatureToggle(icon: "mic", title: "Microphone", subtitle: "Add your narration", value: $model.settings.microphone)
                        FeatureToggle(icon: "person.crop.circle", title: "Camera bubble", subtitle: "Put a face to your story", value: $model.settings.camera)
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Codec").font(.system(size: 10)).foregroundStyle(Color.muted)
                                Picker("Codec", selection: $model.settings.codec) { ForEach(VideoCodec.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(width: 130)
                            }
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Format").font(.system(size: 10)).foregroundStyle(Color.muted)
                                Picker("File format", selection: $model.settings.format) { ForEach(VideoFormat.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(width: 90)
                            }
                        }
                    }.frame(width: 265).card(padding: 16).disabled(model.phase.isActive)
                }
                PresenterOptions().disabled(model.phase.isActive)
                HStack(spacing: 20) {
                    HStack(spacing: 10) {
                        Image(systemName: "timer").foregroundStyle(Color.accent)
                        VStack(alignment: .leading, spacing: 3) { Text("A moment to get ready").font(.system(size: 11, weight: .semibold)); Text("Countdown before recording").font(.system(size: 10)).foregroundStyle(Color.muted) }
                        Picker("Countdown", selection: $model.settings.countdown) { Text("None").tag(0); Text("3 sec").tag(3); Text("5 sec").tag(5); Text("10 sec").tag(10) }.labelsHidden().frame(width: 84)
                    }
                    Rectangle().fill(Color.line).frame(width: 1, height: 30)
                    HStack(spacing: 10) {
                        Image(systemName: "cursorarrow").foregroundStyle(Color.accent)
                        Text("Show cursor").font(.system(size: 11, weight: .semibold))
                        Toggle("Show cursor", isOn: $model.settings.showCursor).labelsHidden().toggleStyle(.switch).controlSize(.small)
                    }
                    Toggle("Click highlights", isOn: $model.settings.highlightClicks).toggleStyle(.switch).controlSize(.small).font(.system(size: 11))
                    Spacer(minLength: 0)
                    Menu {
                        Picker("Auto stop", selection: $model.settings.stopAfterMinutes) {
                            Text("Until I stop").tag(0); ForEach([1, 5, 10, 15, 30, 60], id: \.self) { Text("\($0) minutes").tag($0) }
                        }
                    } label: { Label(model.settings.stopAfterMinutes == 0 ? "Auto stop" : "Stop at \(model.settings.stopAfterMinutes)m", systemImage: "stopwatch").font(.system(size: 11)).foregroundStyle(Color.muted) }.menuStyle(.borderlessButton).fixedSize()
                }.card(padding: 15).disabled(model.phase.isActive)
                HStack(alignment: .top, spacing: 16) {
                    Tip(icon: "command", title: "Stay in your flow", text: "⌃ ⌘ R to start or stop anywhere.\n⌃ ⌘ M to mark a moment.")
                    Tip(icon: "scissors", title: "Keep the good parts", text: "Trim your clips and export a copy\nfrom your recording library.")
                    Tip(icon: "lock.shield", title: "Made for your Mac", text: "No uploads. No subscriptions.\nYour recordings stay with you.")
                }.padding(.top, 2)
            }.padding(.horizontal, 30).padding(.vertical, 24)
                .animation(PrismMotion.selection(reduceMotion), value: model.settings.camera)
        }
        Rectangle().fill(Color.line).frame(height: 1)
        RecordDock().padding(.horizontal, 30).padding(.vertical, 15).background(Color.canvas)
        }
    }
}

struct SourcePreview: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.prismReduceMotion) private var reduceMotion
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12).fill(Color.previewBase)
            if let preview = model.preview {
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
            VStack {
                HStack {
                    HStack(spacing: 5) { Circle().fill(model.phase == .recording ? Color.red : Color.accent).frame(width: 5, height: 5); Text(model.phase.isCapturing ? "SOURCE SNAPSHOT" : "CAPTURE PREVIEW").font(.system(size: 8, weight: .bold)).tracking(1) }
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
        }.frame(height: 249)
    }
}

struct CaptureSourcePicker: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: model.settings.mode.icon).foregroundStyle(Color.accent)
                if model.settings.mode == .window {
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
            if model.settings.mode == .window && model.windows.isEmpty { Text("Refresh sources after granting screen access.").font(.system(size: 10)).foregroundStyle(Color.muted) }
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
                    if model.screenAccess { model.startRecording() } else { Task { await model.requestScreenAccess() } }
                } label: {
                    HStack(spacing: 12) { Image(systemName: "record.circle"); Text(model.screenAccess ? "Start recording" : "Set up recording"); if model.screenAccess { Text("⌘ ⇧ R").font(.system(size: 10)).opacity(0.7) } }
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
