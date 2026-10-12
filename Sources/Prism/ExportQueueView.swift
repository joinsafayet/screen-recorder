import SwiftUI

struct ExportQueueView: View {
    @EnvironmentObject private var queue: ExportQueue
    @EnvironmentObject private var model: AppModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Export workspace").font(.system(size: 28, weight: .semibold))
                        Text("\(queue.pendingCount) pending · One export at a time · Originals preserved").font(.system(size: 12)).foregroundStyle(Color.muted)
                    }
                    Spacer()
                    Button(queue.running ? "Pause queue" : "Start exports") { if queue.running { queue.pause() } else { queue.start() } }.buttonStyle(PrimaryButton()).disabled(queue.captureActive || queue.pendingCount == 0)
                    Button("Clear finished") { queue.clearFinished() }.buttonStyle(QuietButton())
                }
                if queue.captureActive { Label("Exports pause during recording to keep capture responsive.", systemImage: "pause.circle").font(.system(size: 12)).foregroundStyle(Color.accent).card(padding: 15) }
                if let issue = queue.issue { Text(issue).font(.system(size: 12)).foregroundStyle(.orange).card(padding: 15) }
                if queue.jobs.isEmpty {
                    VStack(spacing: 15) { Image(systemName: "square.and.arrow.up.on.square").font(.system(size: 44, weight: .light)).foregroundStyle(Color.accent); Text("Your next exports start here.").font(.system(size: 20, weight: .medium)); Text("Select recordings in the library or queue an edited copy from the timeline.").font(.system(size: 12)).foregroundStyle(Color.muted) }.frame(maxWidth: .infinity, minHeight: 350).card(padding: 24)
                }
                LazyVStack(spacing: 12) {
                    ForEach(queue.jobs) { job in
                        HStack(spacing: 16) {
                            Image(systemName: job.status == .completed ? "checkmark.circle.fill" : job.status == .failed ? "exclamationmark.circle" : "film").font(.system(size: 24)).foregroundStyle(job.status == .completed ? Color.mint : Color.accent)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(job.title).font(.system(size: 13, weight: .semibold))
                                Text(URL(fileURLWithPath: job.targetPath).lastPathComponent).font(.system(size: 10)).foregroundStyle(Color.muted).lineLimit(1)
                                if let error = job.error { Text(error).font(.system(size: 10)).foregroundStyle(.orange) }
                                if job.status == .running { ProgressView(value: Double(job.progress)).frame(maxWidth: 260) }
                            }
                            Spacer()
                            Text(job.status == .running ? "\(Int(job.progress * 100))%" : job.status.rawValue.capitalized).font(.system(size: 11, weight: .medium)).foregroundStyle(Color.muted)
                            if [.waiting, .running].contains(job.status) { Button("Cancel") { queue.cancel(job.id) }.buttonStyle(QuietButton()) }
                            if [.failed, .cancelled].contains(job.status) { Button("Retry") { queue.retry(job.id) }.buttonStyle(QuietButton()) }
                            if job.status == .completed { Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: job.targetPath)]) } label: { Image(systemName: "folder") }.buttonStyle(QuietButton()) }
                        }.card(padding: 18)
                    }
                }
                Text("Pausing preserves existing files. The active job restarts when you resume. Your queued edits survive app restarts.").font(.system(size: 11)).foregroundStyle(Color.muted)
            }.padding(30)
        }
    }
}
