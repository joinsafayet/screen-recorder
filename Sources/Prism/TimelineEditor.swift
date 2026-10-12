import SwiftUI
import AVKit

struct TimelineEditor: View {
    let recording: Recording
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @StateObject private var history: TimelineHistory
    @ViewState<AVPlayer> private var player = AVPlayer()
    @ViewState<Double> private var playhead = 0
    @ViewState<UUID?> private var selectedCut = nil
    @ViewState<String> private var inspector = "Cuts"
    @ViewState<VideoFormat> private var format = .mp4
    @ViewState<ExportQuality> private var quality = .original
    @ViewState<Bool> private var exporting = false
    @ViewState<Float> private var progress = 0
    @ViewState<String?> private var issue = nil
    @ViewState<Any?> private var observer = nil
    @ViewState<Task<Void, Never>?> private var exportTask = nil
    @ViewState<Task<Void, Never>?> private var saveTask = nil
    init(recording: Recording) {
        self.recording = recording
        _history = StateObject(wrappedValue: TimelineHistory(TimelineDocument(recordingID: recording.id, duration: recording.duration)))
    }
    private var selectedIndex: Int? { history.document.cuts.firstIndex { $0.id == selectedCut } }
    var body: some View {
        VStack(spacing: 18) {
            header
            HSplitView {
                VStack(alignment: .leading, spacing: 14) {
                    NativeVideoPlayer(player: player).frame(minHeight: 280, maxHeight: .infinity).clipShape(RoundedRectangle(cornerRadius: 12))
                    timeline
                    HStack(spacing: 8) {
                        Button { history.change { selectedCut = $0.split(at: playhead) ?? selectedCut } } label: { Label("Split", systemImage: "scissors") }.buttonStyle(QuietButton())
                        Button { removeSelected() } label: { Image(systemName: "trash") }.buttonStyle(QuietButton()).disabled(history.document.cuts.count <= 1 || selectedIndex == nil)
                        Button { history.undo() } label: { Image(systemName: "arrow.uturn.backward") }.buttonStyle(QuietButton()).disabled(!history.canUndo)
                        Button { history.redo() } label: { Image(systemName: "arrow.uturn.forward") }.buttonStyle(QuietButton()).disabled(!history.canRedo)
                        Spacer()
                        Text("\(RecordingMath.clock(playhead)) / \(RecordingMath.clock(history.document.duration))").font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.muted)
                    }.disabled(exporting)
                    if let markers = recording.markers, !markers.isEmpty {
                        ScrollView(.horizontal) { HStack(spacing: 7) {
                            ForEach(markers) { marker in
                                Button(marker.title) { seekToSource(marker.time) }.buttonStyle(QuietButton())
                            }
                            Button { do { try library.exportMarkers(recording) } catch { issue = error.localizedDescription } } label: { Image(systemName: "square.and.arrow.up") }.buttonStyle(QuietButton()).help("Export markers as CSV")
                        } }.frame(height: 34)
                    }
                }.frame(minWidth: 560).padding(.trailing, 12)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Picker("Editing inspector", selection: $inspector) { ForEach(["Cuts", "Frame", "Audio"], id: \.self) { Text($0).tag($0) } }.pickerStyle(.segmented)
                        inspectorContent
                    }.padding(16)
                }.frame(minWidth: 265, idealWidth: 290, maxWidth: 350).background(Color.surface, in: RoundedRectangle(cornerRadius: 14)).disabled(exporting)
            }
            footer
        }.padding(24).frame(width: 1060, height: 730).background(Color.canvas).foregroundStyle(Color.ink).tint(.accent)
        .task {
            do { if let saved = try await library.loadEdits(recording) { history.load(saved) } } catch { issue = error.localizedDescription }
            selectedCut = history.document.cuts.first?.id
            observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.1, preferredTimescale: 600), queue: .main) { time in playhead = time.seconds }
        }
        .task(id: history.revision) { await rebuildPreview() }
        .onChange(of: model.phase) { _, phase in if phase.isActive { player.pause() } }
        .onChange(of: history.revision) { _, _ in
            saveTask?.cancel()
            let document = history.document
            saveTask = Task { do { try await Task.sleep(for: .milliseconds(500)); try await library.saveEdits(recording, document: document) } catch is CancellationError {} catch { issue = error.localizedDescription } }
        }
        .onDisappear {
            player.pause(); if let observer { player.removeTimeObserver(observer) }; observer = nil; player.replaceCurrentItem(with: nil)
            saveTask?.cancel(); exportTask?.cancel()
            let document = history.document
            Task { do { try await library.saveEdits(recording, document: document) } catch { model.error = error.localizedDescription } }
        }
        .alert("Editor needs attention", isPresented: Binding(get: { issue != nil }, set: { if !$0 { issue = nil } })) { Button("OK") { issue = nil } } message: { Text(issue ?? "") }
        .interactiveDismissDisabled(exporting)
    }
    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 6) {
                Text(recording.title).font(.system(size: 20, weight: .semibold)).lineLimit(1)
                Text("\(recording.width) × \(recording.height) · \(recording.bytes.fileSize) · Edits save automatically").font(.system(size: 11)).foregroundStyle(Color.muted)
            }
            Spacer()
            Button { player.pause(); dismiss() } label: { Image(systemName: "xmark").frame(width: 18, height: 18) }.buttonStyle(QuietButton()).disabled(exporting).accessibilityLabel("Close editor")
        }
    }
    private var timeline: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { SectionTitle(text: "Timeline · \(history.document.cuts.count) sections"); Spacer(); Text("\(RecordingMath.clock(history.document.duration)) edited").font(.system(size: 10)).foregroundStyle(Color.accent) }
            GeometryReader { geometry in
                HStack(spacing: 3) {
                    ForEach(history.document.cuts) { cut in
                        Button { selectedCut = cut.id; seekToCut(cut.id) } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Image(systemName: "film").font(.system(size: 11))
                                Text(String(format: "%.2f–%.2fs", cut.start, cut.end)).font(.system(size: 9, design: .monospaced)).lineLimit(1)
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(9)
                                .frame(width: max(30, (geometry.size.width - CGFloat(max(0, history.document.cuts.count - 1)) * 3) * cut.duration / max(0.01, history.document.duration)), height: 52)
                                .selectionSurface(selectedCut == cut.id, radius: 8)
                        }.buttonStyle(InteractiveButton(radius: 8)).accessibilityLabel("Section from \(cut.start) to \(cut.end) seconds")
                    }
                }
            }.frame(height: 52)
            Slider(value: Binding(get: { min(history.document.duration, max(0, playhead)) }, set: { playhead = $0; player.seek(to: CMTime(seconds: $0, preferredTimescale: 60000), toleranceBefore: .zero, toleranceAfter: .zero) }), in: 0...max(0.01, history.document.duration)).accessibilityLabel("Timeline playhead")
        }
    }
    @ViewBuilder private var inspectorContent: some View {
        switch inspector {
        case "Cuts": cutsInspector
        case "Frame": frameInspector
        default: audioInspector
        }
    }
    private var cutsInspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(text: "Selected section")
            if let index = selectedIndex {
                HStack { Text("In seconds"); Spacer(); TextField("In seconds", value: cutBinding(history.document.cuts[index].id, isEnd: false), format: .number.precision(.fractionLength(2))).frame(width: 80).textFieldStyle(.roundedBorder) }
                HStack { Text("Out seconds"); Spacer(); TextField("Out seconds", value: cutBinding(history.document.cuts[index].id, isEnd: true), format: .number.precision(.fractionLength(2))).frame(width: 80).textFieldStyle(.roundedBorder) }
                HStack {
                    Button("Move earlier") { history.change { $0.cuts.swapAt(index, index - 1) } }.buttonStyle(QuietButton()).disabled(index == 0)
                    Button("Later") { history.change { $0.cuts.swapAt(index, index + 1) } }.buttonStyle(QuietButton()).disabled(index + 1 == history.document.cuts.count)
                }
            } else { Text("Choose a section in the timeline.").foregroundStyle(Color.muted) }
            Button { history.change { let cut = TimelineCut(start: 0, end: recording.duration); $0.cuts.append(cut); selectedCut = cut.id } } label: { Label("Add source section", systemImage: "plus") }.buttonStyle(QuietButton())
            Text("Split at the playhead, remove a section, or adjust its exact in/out points. Your original stays intact.").font(.system(size: 11)).foregroundStyle(Color.muted).lineSpacing(4)
        }.font(.system(size: 12))
    }
    private var frameInspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(text: "Canvas and crop")
            Picker("Aspect ratio", selection: Binding(get: { history.document.aspect }, set: { value in history.change { $0.aspect = value } })) { ForEach(CaptureAspect.allCases) { Text($0.rawValue).tag($0) } }
            cropControl("Left", keyPath: \.origin.x, limit: 0...max(0, 1 - history.document.crop.width))
            cropControl("Top", keyPath: \.origin.y, limit: 0...max(0, 1 - history.document.crop.height))
            cropControl("Width", keyPath: \.size.width, limit: 0.05...max(0.05, 1 - history.document.crop.minX))
            cropControl("Height", keyPath: \.size.height, limit: 0.05...max(0.05, 1 - history.document.crop.minY))
            Button("Reset crop") { history.change { $0.crop = CGRect(x: 0, y: 0, width: 1, height: 1); $0.aspect = .free } }.buttonStyle(QuietButton())
            Divider().overlay(Color.line)
            SectionTitle(text: "Zoom keyframes")
            Button { history.change { $0.zooms.append(ZoomKeyframe(time: min($0.duration, playhead))) } } label: { Label("Add zoom at playhead", systemImage: "plus.magnifyingglass") }.buttonStyle(QuietButton())
            ForEach(history.document.zooms) { key in
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text(String(format: "At %.2fs", key.time)); Spacer(); Button { history.change { $0.zooms.removeAll { $0.id == key.id } } } label: { Image(systemName: "xmark") }.buttonStyle(InteractiveButton(radius: 4)) }
                    Slider(value: zoomBinding(key.id, \.scale), in: 1...4) { Text("Zoom scale") }
                    Text(String(format: "%.1f×", key.scale)).foregroundStyle(Color.accent)
                    Slider(value: zoomBinding(key.id, \.x), in: 0...1) { Text("Horizontal focus") }
                    Slider(value: zoomBinding(key.id, \.y), in: 0...1) { Text("Vertical focus") }
                }.font(.system(size: 11)).card(padding: 10)
            }
        }.font(.system(size: 12))
    }
    private var audioInspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            SectionTitle(text: "Audio envelope")
            Text("Volume · \(Int(history.document.audioGain * 100))%").font(.system(size: 12))
            Slider(value: Binding(get: { history.document.audioGain }, set: { value in history.change { $0.audioGain = value } }), in: 0...1)
            Stepper("Fade in · \(String(format: "%.1f", history.document.fadeIn))s", value: Binding(get: { history.document.fadeIn }, set: { value in history.change { $0.fadeIn = value } }), in: 0...min(10, history.document.duration / 2), step: 0.1)
            Stepper("Fade out · \(String(format: "%.1f", history.document.fadeOut))s", value: Binding(get: { history.document.fadeOut }, set: { value in history.change { $0.fadeOut = value } }), in: 0...min(10, history.document.duration / 2), step: 0.1)
            Text("The fades and volume apply to the edited preview and exported copy.").font(.system(size: 11)).foregroundStyle(Color.muted).lineSpacing(4)
        }.font(.system(size: 12))
    }
    private var footer: some View {
        HStack(spacing: 12) {
            Label("Your original is preserved", systemImage: "doc.on.doc").font(.system(size: 11)).foregroundStyle(Color.muted)
            Spacer()
            if exporting { ProgressView(value: Double(progress)).frame(width: 90); Button("Cancel") { exportTask?.cancel() }.buttonStyle(QuietButton()) }
            else { ShareLink(item: library.fileURL(recording)) { Image(systemName: "square.and.arrow.up") }.buttonStyle(QuietButton()).help("Share original") }
            Picker("Quality", selection: $quality) { ForEach(ExportQuality.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(width: 150).disabled(exporting)
            Picker("Format", selection: $format) { ForEach(VideoFormat.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(width: 70).disabled(exporting)
            Button { export() } label: { Label(exporting ? "Exporting…" : "Export edited copy", systemImage: "square.and.arrow.up") }.buttonStyle(PrimaryButton()).disabled(exporting)
        }
    }
    private func cutBinding(_ id: UUID, isEnd: Bool) -> Binding<Double> {
        Binding<Double>(get: {
            guard let cut = history.document.cuts.first(where: { $0.id == id }) else { return 0 }
            return isEnd ? cut.end : cut.start
        }, set: { value in
            guard value.isFinite else { return }
            history.change { document in
                guard let index = document.cuts.firstIndex(where: { $0.id == id }) else { return }
                if isEnd { document.cuts[index].end = min(recording.duration, max(document.cuts[index].start + 0.01, value)) }
                else { document.cuts[index].start = min(document.cuts[index].end - 0.01, max(0, value)) }
            }
        })
    }
    private func cropControl(_ title: String, keyPath: WritableKeyPath<CGRect, CGFloat>, limit: ClosedRange<Double>) -> some View {
        HStack {
            Text(title).frame(width: 42, alignment: .leading)
            Slider(value: Binding(get: { Double(history.document.crop[keyPath: keyPath]) }, set: { value in history.change { $0.crop[keyPath: keyPath] = CGFloat(value) } }), in: limit)
            Text("\(Int(history.document.crop[keyPath: keyPath] * 100))%").monospacedDigit().frame(width: 34)
        }.font(.system(size: 11))
    }
    private func zoomBinding(_ id: UUID, _ keyPath: WritableKeyPath<ZoomKeyframe, Double>) -> Binding<Double> {
        Binding(get: { history.document.zooms.first { $0.id == id }?[keyPath: keyPath] ?? 1 }, set: { value in history.change { document in if let index = document.zooms.firstIndex(where: { $0.id == id }) { document.zooms[index][keyPath: keyPath] = value } } })
    }
    private func removeSelected() { guard let index = selectedIndex, history.document.cuts.count > 1 else { return }; history.change { $0.cuts.remove(at: index); let duration = $0.duration; $0.zooms.removeAll { $0.time > duration }; selectedCut = $0.cuts[min(index, $0.cuts.count - 1)].id } }
    private func seekToCut(_ id: UUID) {
        var time = 0.0
        for cut in history.document.cuts { if cut.id == id { player.seek(to: CMTime(seconds: time, preferredTimescale: 60000)); return }; time += cut.duration }
    }
    private func seekToSource(_ time: Double) {
        var offset = 0.0
        for cut in history.document.cuts { if time >= cut.start && time <= cut.end { player.seek(to: CMTime(seconds: offset + time - cut.start, preferredTimescale: 60000)); return }; offset += cut.duration }
        issue = "That marker is outside the sections kept in this timeline."
    }
    private func rebuildPreview() async {
        let document = history.document, revision = history.revision
        do {
            try await Task.sleep(for: .milliseconds(160))
            let timeline = try await TimelineRenderer.compose(source: library.fileURL(recording), document: document, quality: .hd)
            guard !Task.isCancelled, revision == history.revision else { return }
            let time = min(document.duration, max(0, player.currentTime().seconds.isFinite ? player.currentTime().seconds : 0)), playing = player.rate > 0
            let item = AVPlayerItem(asset: timeline.asset); item.videoComposition = timeline.video; item.audioMix = timeline.audio
            player.replaceCurrentItem(with: item); await player.seek(to: CMTime(seconds: time, preferredTimescale: 60000)); if playing { player.play() }
        } catch is CancellationError {} catch { if !Task.isCancelled { issue = error.localizedDescription } }
    }
    private func export() {
        player.pause(); exporting = true; progress = 0
        let document = history.document
        exportTask = Task {
            do { try await library.exportTimeline(recording, document: document, format: format, quality: quality) { value in Task { @MainActor in progress = value } } }
            catch { if !Task.isCancelled { issue = error.localizedDescription } }
            exporting = false; exportTask = nil
        }
    }
}
