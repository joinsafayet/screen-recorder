import SwiftUI
import AVKit

struct LibraryView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.prismReduceMotion) private var reduceMotion
    @ViewState<Recording?> private var selected = nil
    @ViewState<Recording?> private var deleting = nil
    @ViewState<Recording?> private var renaming = nil
    @ViewState<String> private var renameTitle = ""
    @ViewState<Bool> private var importing = false
    private let columns = [GridItem(.adaptive(minimum: 245, maximum: 400), spacing: 18)]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 25) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 9) {
                        Text("The good takes live here.").font(.system(size: 31, weight: .semibold)).tracking(-1.1)
                        Text("\(library.countLabel) · \(RecordingMath.clock(library.totalDuration)) captured · \(library.totalBytes.fileSize)")
                            .font(.system(size: 12)).foregroundStyle(Color.muted)
                    }
                    Spacer()
                    Button {
                        importing = true
                        Task { do { try await library.importVideos() } catch { model.error = error.localizedDescription }; importing = false }
                    } label: { Label(importing ? "Importing…" : "Import video", systemImage: "square.and.arrow.down") }.buttonStyle(QuietButton()).disabled(importing || model.phase.isActive || library.isBusy)
                }
                HStack(spacing: 12) {
                    HStack(spacing: 9) {
                        Image(systemName: "magnifyingglass").foregroundStyle(Color.muted)
                        TextField("Search recordings", text: $model.search).textFieldStyle(.plain).font(.system(size: 12))
                        if !model.search.isEmpty { Button { model.search = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(Color.muted).padding(3) }.buttonStyle(InteractiveButton(radius: 5)) }
                    }.padding(12).background(Color.surface, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.line)).frame(maxWidth: 350)
                    Spacer()
                    Button { model.favoritesOnly.toggle() } label: {
                        Label("Favorites", systemImage: model.favoritesOnly ? "star.fill" : "star").foregroundStyle(model.favoritesOnly ? Color.accent : Color.muted)
                    }.buttonStyle(QuietButton()).accessibilityValue(model.favoritesOnly ? "Selected" : "Off")
                    Picker("Sort recordings", selection: $model.librarySort) { ForEach(LibrarySort.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(width: 135)
                    Menu {
                        Button("Recover recordings", systemImage: "arrow.clockwise") { Task {
                            do { let count = try await library.recoverRecordings(); model.notify("Recovered \(count) recordings") }
                            catch { model.error = error.localizedDescription }
                        } }
                    } label: { Image(systemName: "ellipsis.circle").foregroundStyle(Color.muted) }.menuStyle(.borderlessButton).fixedSize().disabled(library.isBusy || model.phase.isActive)
                }
                if let notice = library.notice {
                    HStack { Image(systemName: "info.circle").foregroundStyle(Color.orange); Text(notice).font(.system(size: 11)).foregroundStyle(Color.muted); Spacer(); Button { library.notice = nil } label: { Image(systemName: "xmark").padding(4) }.buttonStyle(InteractiveButton(radius: 5)) }.card(padding: 14)
                }
                if library.isBusy { HStack { ProgressView().controlSize(.small); Text("Updating your library…").font(.system(size: 11)).foregroundStyle(Color.muted) } }
                if model.filteredRecordings.isEmpty {
                    VStack(spacing: 18) {
                        Image(systemName: library.recordings.isEmpty ? "rectangle.stack.badge.play" : "magnifyingglass").font(.system(size: 48, weight: .ultraLight)).foregroundStyle(Color.accent)
                            .frame(width: 110, height: 100).background(Color.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 25))
                        Text(library.recordings.isEmpty ? "A blank canvas, for now." : "No matching takes.").font(.system(size: 21, weight: .medium))
                        Text(library.recordings.isEmpty ? "Record your first walkthrough, big idea, or little discovery.\nWe’ll keep it here, ready to play, trim, and share." : "Try another search or turn off the favorites filter.")
                            .font(.system(size: 12)).foregroundStyle(Color.muted).multilineTextAlignment(.center).lineSpacing(5)
                        if library.recordings.isEmpty {
                            Button { model.destination = .studio } label: { Label("Create your first recording", systemImage: "record.circle") }.buttonStyle(PrimaryButton()).padding(.top, 8)
                        }
                    }.frame(maxWidth: .infinity).frame(minHeight: 450).card(padding: 30)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        ForEach(model.filteredRecordings) { recording in
                            VStack(alignment: .leading, spacing: 0) {
                                Button { selected = recording } label: {
                                    ZStack(alignment: .bottomTrailing) {
                                        RoundedRectangle(cornerRadius: 10).fill(Color.elevated)
                                        RecordingThumbnail(recording: recording)
                                        Image(systemName: "play.circle.fill").font(.system(size: 33)).foregroundStyle(.white.opacity(0.9)).shadow(radius: 5).frame(maxWidth: .infinity, maxHeight: .infinity)
                                        Text(RecordingMath.clock(recording.duration)).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.white).padding(6).background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 5)).padding(8)
                                    }.frame(height: 150).clipShape(RoundedRectangle(cornerRadius: 10))
                                }.buttonStyle(InteractiveButton(radius: 10)).accessibilityLabel("Play and trim \(recording.title)")
                                HStack(alignment: .top) {
                                    VStack(alignment: .leading, spacing: 7) {
                                        Text(recording.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                        Text(recording.createdAt.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 10)).foregroundStyle(Color.muted)
                                    }
                                    Spacer(minLength: 4)
                                    Menu {
                                        Button("Play & trim", systemImage: "play") { selected = recording }
                                        Button("Rename", systemImage: "pencil") { renameTitle = recording.title; renaming = recording }
                                        Button(recording.favorite ? "Remove favorite" : "Add to favorites", systemImage: "star") { model.report { try library.favorite(recording) } }
                                        Button("Show in Finder", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([library.fileURL(recording)]) }
                                        Divider()
                                        Button("Move to Trash", systemImage: "trash", role: .destructive) { deleting = recording }
                                    } label: { Image(systemName: "ellipsis").font(.system(size: 14)).foregroundStyle(Color.muted) }.menuStyle(.borderlessButton).fixedSize().disabled(library.isBusy)
                                }.padding(.top, 14)
                                HStack { Chip(title: "\(recording.width) × \(recording.height)", color: .muted); Spacer(); if recording.favorite { Image(systemName: "star.fill").foregroundStyle(Color.accent).font(.system(size: 10)) }; Text(recording.bytes.fileSize).font(.system(size: 10)).foregroundStyle(Color.muted) }.padding(.top, 13)
                            }.card(padding: 12)
                        }
                    }
                }
            }.padding(30)
                .animation(PrismMotion.selection(reduceMotion), value: model.favoritesOnly)
                .animation(PrismMotion.selection(reduceMotion), value: model.librarySort)
        }
        .onChange(of: model.destination) { _, destination in if destination != .library { selected = nil; renaming = nil; deleting = nil } }
        .sheet(item: $selected) { recording in RecordingDetail(recording: recording).environmentObject(model).environmentObject(library).preferredColorScheme(model.colorScheme) }
        .alert("Rename recording", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Recording name", text: $renameTitle)
            Button("Cancel", role: .cancel) { renaming = nil }
            Button("Save") { if let renaming { model.report { try library.rename(renaming, title: renameTitle) } }; renaming = nil }
        }
        .alert("Move this recording to Trash?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("Cancel", role: .cancel) { deleting = nil }
            Button("Move to Trash", role: .destructive) { if let deleting { model.report { try library.delete(deleting) } }; deleting = nil }
        } message: { Text("You can recover the video from your Mac’s Trash.") }
    }
}

struct RecordingDetail: View {
    let recording: Recording
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.prismReduceMotion) private var reduceMotion
    @ViewState<AVPlayer> private var player = AVPlayer()
    @ViewState<Double> private var start = 0.0
    @ViewState<Double> private var end = 0.0
    @ViewState<Bool> private var trimming = false
    @ViewState<Bool> private var exporting = false
    @ViewState<VideoFormat> private var format = .mp4
    @ViewState<String?> private var localError = nil
    @ViewState<ExportQuality> private var quality = .original
    @ViewState<Float> private var exportProgress = 0
    @ViewState<Task<Void, Never>?> private var exportTask = nil
    private var minimumGap: Double { min(0.1, recording.duration / 2) }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text(recording.title).font(.system(size: 19, weight: .semibold)).lineLimit(1)
                    Text("\(recording.source) · \(recording.width) × \(recording.height) · \(recording.bytes.fileSize)").font(.system(size: 11)).foregroundStyle(Color.muted)
                }
                Spacer()
                Button { player.pause(); dismiss() } label: { Image(systemName: "xmark").frame(width: 18, height: 18) }.buttonStyle(QuietButton()).disabled(exporting)
            }
            NativeVideoPlayer(player: player).frame(height: 340).clipShape(RoundedRectangle(cornerRadius: 12)).transaction { $0.animation = nil }
            if let markers = recording.markers, !markers.isEmpty {
                ScrollView(.horizontal) {
                    HStack(spacing: 8) {
                        ForEach(markers) { marker in
                            Button { player.seek(to: CMTime(seconds: marker.time, preferredTimescale: 600)) } label: {
                                Label("\(marker.title) · \(RecordingMath.clock(marker.time))", systemImage: "bookmark").font(.system(size: 10))
                            }.buttonStyle(QuietButton())
                        }
                        Button { do { try library.exportMarkers(recording) } catch { localError = error.localizedDescription } } label: { Image(systemName: "square.and.arrow.up") }.buttonStyle(QuietButton()).help("Export markers as CSV")
                    }
                }.frame(height: 36)
            }
            HStack {
                Button { trimming.toggle(); player.currentItem?.forwardPlaybackEndTime = trimming ? CMTime(seconds: end, preferredTimescale: 600) : .invalid } label: { Label(trimming ? "Cancel trim" : "Trim recording", systemImage: "scissors") }.buttonStyle(QuietButton()).disabled(exporting)
                Text(RecordingMath.clock(recording.duration)).font(.system(size: 12, design: .monospaced)).foregroundStyle(Color.muted)
                Spacer()
                Picker("Export quality", selection: $quality) { ForEach(ExportQuality.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(width: 160).disabled(exporting)
                Text("Export as").font(.system(size: 11)).foregroundStyle(Color.muted)
                Picker("Export format", selection: $format) { ForEach(VideoFormat.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(width: 85).disabled(exporting)
            }
            if trimming {
                VStack(alignment: .leading, spacing: 14) {
                    HStack { SectionTitle(text: "Keep only what matters"); Spacer(); Text("\(RecordingMath.clock(end - start)) selected").font(.system(size: 11, weight: .medium)).foregroundStyle(Color.accent) }
                    HStack {
                        Text("In").font(.system(size: 11)).frame(width: 28, alignment: .leading)
                        Slider(value: $start, in: 0...max(0.01, end - minimumGap)).onChange(of: start) { _, value in player.seek(to: CMTime(seconds: value, preferredTimescale: 600)) }
                        TextField("In seconds", value: Binding(get: { start }, set: { start = min(end - minimumGap, max(0, $0)) }), format: .number.precision(.fractionLength(2))).textFieldStyle(.roundedBorder).font(.system(size: 11, design: .monospaced)).frame(width: 70)
                    }
                    HStack {
                        Text("Out").font(.system(size: 11)).frame(width: 28, alignment: .leading)
                        Slider(value: $end, in: min(recording.duration, start + minimumGap)...recording.duration).onChange(of: end) { _, value in player.seek(to: CMTime(seconds: value, preferredTimescale: 600)); player.currentItem?.forwardPlaybackEndTime = CMTime(seconds: value, preferredTimescale: 600) }
                        TextField("Out seconds", value: Binding(get: { end }, set: { end = min(recording.duration, max(start + minimumGap, $0)) }), format: .number.precision(.fractionLength(2))).textFieldStyle(.roundedBorder).font(.system(size: 11, design: .monospaced)).frame(width: 70)
                    }
                    Button { player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero); player.currentItem?.forwardPlaybackEndTime = CMTime(seconds: end, preferredTimescale: 600); player.play() } label: { Label("Preview selection", systemImage: "play.fill") }.buttonStyle(QuietButton())
                }.card(padding: 15).disabled(exporting).transition(PrismMotion.reveal(reduceMotion))
            }
            HStack {
                Image(systemName: "doc.on.doc").foregroundStyle(Color.muted)
                Text("Exports a copy. Your original stays in your library.").font(.system(size: 11)).foregroundStyle(Color.muted)
                Spacer()
                if exporting {
                    VStack(alignment: .leading, spacing: 5) { ProgressView(value: Double(exportProgress)).frame(width: 115); Text("\(Int(exportProgress * 100))% exported").font(.system(size: 9)).foregroundStyle(Color.muted) }
                    Button("Cancel") { exportTask?.cancel() }.buttonStyle(QuietButton())
                } else {
                    ShareLink(item: library.fileURL(recording)) { Image(systemName: "square.and.arrow.up") }.buttonStyle(QuietButton()).help("Share original recording")
                }
                Button {
                    player.pause(); exporting = true; exportProgress = 0
                    exportTask = Task {
                        do { try await library.export(recording, range: trimming ? start...end : nil, format: format, quality: quality) { value in Task { @MainActor in exportProgress = value } } }
                        catch { if !Task.isCancelled { localError = error.localizedDescription } }
                        exporting = false; exportTask = nil
                    }
                } label: { Label(exporting ? "Exporting…" : trimming ? "Export trimmed copy" : "Export recording", systemImage: "square.and.arrow.up") }.buttonStyle(PrimaryButton()).disabled(exporting)
            }
        }.padding(26).frame(width: 900).background(Color.canvas).foregroundStyle(Color.ink).tint(.accent)
        .animation(PrismMotion.selection(reduceMotion), value: trimming)
        .onAppear { end = recording.duration; player.replaceCurrentItem(with: AVPlayerItem(url: library.fileURL(recording))) }
        .onDisappear { player.pause(); player.replaceCurrentItem(with: nil) }
        .alert("Export failed", isPresented: Binding(get: { localError != nil }, set: { if !$0 { localError = nil } })) { Button("OK") { localError = nil } } message: { Text(localError ?? "") }
        .interactiveDismissDisabled(exporting)
    }
}

/// Use AVKit's AppKit player directly, with stable native transport controls.
private struct NativeVideoPlayer: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.player = player; view.controlsStyle = .floating
        view.showsSharingServiceButton = false
        return view
    }
    func updateNSView(_ view: AVPlayerView, context: Context) { if view.player !== player { view.player = player } }
    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) { view.player = nil }
}


private struct RecordingThumbnail: View {
    let recording: Recording
    @EnvironmentObject private var library: LibraryStore
    @ViewState<NSImage?> private var image = nil
    var body: some View {
        Group {
            if let image { Image(nsImage: image).resizable().scaledToFit().padding(4) }
            else { Image(systemName: "film").font(.system(size: 25)).foregroundStyle(Color.muted).frame(maxWidth: .infinity, maxHeight: .infinity) }
        }.task(id: recording.id) { image = await library.thumbnail(for: recording) }
    }
}
