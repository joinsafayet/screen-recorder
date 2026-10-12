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
    @ViewState<Bool> private var selecting = false
    @ViewState<Set<UUID>> private var selectedIDs = []
    @ViewState<Bool> private var organizing = false
    @ViewState<Bool> private var trashingSelected = false
    @ViewState<String> private var projectName = ""
    @ViewState<String> private var tagNames = ""
    @ViewState<OutputPreset> private var batchPreset = .current
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
                    Button(selecting ? "Done" : "Select") { selecting.toggle(); if !selecting { selectedIDs = [] } }.buttonStyle(QuietButton()).disabled(model.phase.isActive || library.isBusy)
                    Button {
                        importing = true
                        Task { do { try await library.importVideos() } catch { model.error = error.localizedDescription }; importing = false }
                    } label: { PrismLabel(importing ? "Importing…" : "Import video", systemImage: "square.and.arrow.down") }.buttonStyle(QuietButton()).disabled(importing || model.phase.isActive || library.isBusy)
                }
                HStack(spacing: 12) {
                    HStack(spacing: 9) {
                        PrismIcon("magnifyingglass", size: 16).foregroundStyle(Color.muted)
                        TextField("Search recordings", text: $model.search).textFieldStyle(.plain).font(.system(size: 12))
                        if !model.search.isEmpty { Button { model.search = "" } label: { PrismIcon("xmark.circle.fill", size: 16).foregroundStyle(Color.muted).padding(3) }.buttonStyle(InteractiveButton(radius: 5)) }
                    }.padding(12).background(Color.surface, in: RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.line)).frame(maxWidth: 350)
                    Spacer()
                    Picker("Project", selection: $model.projectFilter) { Text("All projects").tag(""); ForEach(library.projects, id: \.self) { Text($0).tag($0) } }.labelsHidden().frame(width: 130)
                    Button { model.favoritesOnly.toggle() } label: {
                        PrismLabel("Favorites", systemImage: model.favoritesOnly ? "star.fill" : "star").foregroundStyle(model.favoritesOnly ? Color.accent : Color.muted)
                    }.buttonStyle(QuietButton()).accessibilityValue(model.favoritesOnly ? "Selected" : "Off")
                    Picker("Sort recordings", selection: $model.librarySort) { ForEach(LibrarySort.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(width: 135)
                    Menu {
                        Button("Recover recordings", systemImage: "arrow.clockwise") { Task {
                            do { let count = try await library.recoverRecordings(); model.notify("Recovered \(count) recordings") }
                            catch { model.error = error.localizedDescription }
                        } }
                    } label: { PrismIcon("ellipsis.circle", size: 16).foregroundStyle(Color.muted) }.menuStyle(.borderlessButton).fixedSize().disabled(library.isBusy || model.phase.isActive)
                }
                if selecting {
                    VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        Text("\(selectedIDs.count) selected").font(.system(size: 11, weight: .semibold))
                        Button("All visible") { selectedIDs = Set(model.filteredRecordings.map(\.id)) }.buttonStyle(QuietButton())
                        Button("Organize") { projectName = ""; tagNames = ""; organizing = true }.buttonStyle(QuietButton()).disabled(selectedIDs.isEmpty)
                        Button("Favorite") { model.report { try library.setFavorite(ids: selectedIDs, value: true) } }.buttonStyle(QuietButton()).disabled(selectedIDs.isEmpty)
                        Spacer()
                    }
                    HStack(spacing: 10) {
                        Picker("Output preset", selection: $batchPreset) { ForEach(OutputPreset.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden().frame(width: 130)
                        Button("Export selected…") { batchExport() }.buttonStyle(QuietButton()).disabled(selectedIDs.isEmpty || model.phase.isActive)
                        Spacer()
                        Button { trashingSelected = true } label: { PrismIcon("trash", size: 16) }.buttonStyle(QuietButton()).disabled(selectedIDs.isEmpty)
                    }
                    }.card(padding: 12)
                }
                if let notice = library.notice {
                    HStack { PrismIcon("info.circle", size: 16).foregroundStyle(Color.orange); Text(notice).font(.system(size: 11)).foregroundStyle(Color.muted); Spacer(); Button { library.notice = nil } label: { PrismIcon("xmark", size: 16).padding(4) }.buttonStyle(InteractiveButton(radius: 5)) }.card(padding: 14)
                }
                if library.isBusy { HStack { ProgressView().controlSize(.small); Text("Updating your library…").font(.system(size: 11)).foregroundStyle(Color.muted) } }
                if model.filteredRecordings.isEmpty {
                    VStack(spacing: 18) {
                        PrismIcon(library.recordings.isEmpty ? "rectangle.stack.badge.play" : "magnifyingglass", size: 48).foregroundStyle(Color.accent)
                            .frame(width: 110, height: 100).background(Color.accent.opacity(0.06), in: RoundedRectangle(cornerRadius: 25))
                        Text(library.recordings.isEmpty ? "A blank canvas, for now." : "No matching takes.").font(.system(size: 21, weight: .medium))
                        Text(library.recordings.isEmpty ? "Record your first walkthrough, big idea, or little discovery.\nWe’ll keep it here, ready to play, trim, and share." : "Try another search or turn off the favorites filter.")
                            .font(.system(size: 12)).foregroundStyle(Color.muted).multilineTextAlignment(.center).lineSpacing(5)
                        if library.recordings.isEmpty {
                            Button { model.destination = .studio } label: { PrismLabel("Create your first recording", systemImage: "record.circle") }.buttonStyle(PrimaryButton()).padding(.top, 8)
                        }
                    }.frame(maxWidth: .infinity).frame(minHeight: 450).card(padding: 30)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                        ForEach(model.filteredRecordings) { recording in
                            VStack(alignment: .leading, spacing: 0) {
                                Button { if selecting { if selectedIDs.contains(recording.id) { selectedIDs.remove(recording.id) } else { selectedIDs.insert(recording.id) } } else { selected = recording } } label: {
                                    ZStack(alignment: .bottomTrailing) {
                                        RoundedRectangle(cornerRadius: 10).fill(Color.elevated)
                                        RecordingThumbnail(recording: recording)
                                        PrismIcon("play.circle.fill", size: 33).foregroundStyle(.white.opacity(0.9)).shadow(radius: 5).frame(maxWidth: .infinity, maxHeight: .infinity)
                                        Text(RecordingMath.clock(recording.duration)).font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(.white).padding(6).background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 5)).padding(8)
                                        if selecting { PrismIcon(selectedIDs.contains(recording.id) ? "checkmark.circle.fill" : "circle", size: 22).foregroundStyle(selectedIDs.contains(recording.id) ? Color.accent : Color.white).padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading) }
                                    }.frame(height: 150).clipShape(RoundedRectangle(cornerRadius: 10))
                                }.buttonStyle(InteractiveButton(radius: 10)).disabled(model.phase.isActive).accessibilityLabel("Play and trim \(recording.title)")
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
                                    } label: { PrismIcon("ellipsis", size: 14).foregroundStyle(Color.muted) }.menuStyle(.borderlessButton).fixedSize().disabled(library.isBusy)
                                }.padding(.top, 14)
                                HStack { Chip(title: "\(recording.width) × \(recording.height)", color: .muted); Spacer(); if recording.favorite { PrismIcon("star.fill", size: 16).foregroundStyle(Color.accent).font(.system(size: 10)) }; Text(recording.bytes.fileSize).font(.system(size: 10)).foregroundStyle(Color.muted) }.padding(.top, 13)
                                if let project = recording.project { Text(project).font(.system(size: 10, weight: .medium)).foregroundStyle(Color.accent).padding(.top, 8) }
                                if let tags = recording.tags, !tags.isEmpty { Text(tags.joined(separator: " · ")).font(.system(size: 9)).foregroundStyle(Color.muted).lineLimit(1).padding(.top, 5) }
                            }.card(padding: 12)
                        }
                    }
                }
            }.padding(30)
                .animation(PrismMotion.selection(reduceMotion), value: model.favoritesOnly)
                .animation(PrismMotion.selection(reduceMotion), value: model.librarySort)
        }
        .onChange(of: model.destination) { _, destination in if destination != .library { selected = nil; renaming = nil; deleting = nil } }
        .alert("Organize selected recordings", isPresented: $organizing) {
            TextField("Project", text: $projectName); TextField("Tags, separated by commas", text: $tagNames)
            Button("Cancel", role: .cancel) {}
            Button("Save") { model.report { try library.organize(ids: selectedIDs, project: projectName, tags: tagNames) } }
        }
        .alert("Move selected recordings to Trash?", isPresented: $trashingSelected) {
            Button("Cancel", role: .cancel) {}
            Button("Move to Trash", role: .destructive) { let ids = selectedIDs; Task { do { try await library.trash(ids: ids); selectedIDs = [] } catch { model.error = error.localizedDescription } } }
        }
        .sheet(item: $selected) { recording in TimelineEditor(recording: recording).environmentObject(model).environmentObject(library).preferredColorScheme(model.colorScheme) }
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
    private func batchExport() {
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.canCreateDirectories = true; panel.message = "Choose a folder for edited copies. Your originals remain in the library."
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let recordings = library.recordings.filter { selectedIDs.contains($0.id) }
        Task { do { try await model.exports.enqueue(recordings: recordings, folder: folder, preset: batchPreset); model.exports.start(); model.destination = .exports } catch { model.error = error.localizedDescription } }
    }

}

/// Use AVKit's AppKit player directly, with stable native transport controls.
struct NativeVideoPlayer: NSViewRepresentable {
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
            else { PrismIcon("film", size: 25).foregroundStyle(Color.muted).frame(maxWidth: .infinity, maxHeight: .infinity) }
        }.task(id: recording.id) { image = await library.thumbnail(for: recording) }
    }
}
