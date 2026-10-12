import SwiftUI

struct PreparationPanel: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var preparation: PreparationMonitor
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionTitle(text: "Before your take")
                Spacer()
                if preparation.running { Chip(title: "Live inputs", icon: "circle.fill", color: .mint) }
                Button { if preparation.running { Task { await model.stopPreparation() } } else { model.beginPreparation() } } label: {
                    PrismLabel(preparation.running ? "Stop preview" : model.preparingPreview ? "Preparing…" : "Test setup", systemImage: preparation.running ? "stop.circle" : "waveform")
                }.buttonStyle(QuietButton()).disabled(model.phase.isActive || model.preparingPreview)
            }
            HStack(spacing: 18) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(model.outputEstimate.width) × \(model.outputEstimate.height) · \(model.settings.fps) fps").font(.system(size: 12, weight: .semibold))
                    Text("Estimated \((model.outputEstimate.bytesPerMinute * Int64(model.estimateMinutes)).fileSize) for \(model.estimateMinutes) min").font(.system(size: 10)).foregroundStyle(Color.muted)
                }
                Spacer()
                Picker("Estimate length", selection: $model.estimateMinutes) { ForEach([5, 10, 30, 60], id: \.self) { Text("\($0) min").tag($0) } }.labelsHidden().frame(width: 90)
            }
            if let free = model.freeSpace { PrismLabel("\(free.fileSize) available in your save folder", systemImage: "internaldrive").font(.system(size: 10)).foregroundStyle(free > 500_000_000 ? Color.muted : Color.orange) }
            if preparation.running {
                if model.settings.microphone { level("Microphone", preparation.microphoneLevel) }
                if model.settings.systemAudio { level("System audio", preparation.systemLevel) }
            }
            if let issue = preparation.issue { Text(issue).font(.system(size: 10)).foregroundStyle(.orange) }
            HStack {
                Text("Device tests run only when you start the preview.").font(.system(size: 10)).foregroundStyle(Color.muted)
                Spacer()
                Button { model.startRecording(testSeconds: 5) } label: { PrismLabel("5-second test take", systemImage: "record.circle") }.buttonStyle(QuietButton()).disabled(!model.canCapture || model.phase.isActive)
            }
        }.card(padding: 14)
    }
    private func level(_ title: String, _ value: Float) -> some View {
        HStack(spacing: 12) {
            Text(title).font(.system(size: 10)).foregroundStyle(Color.muted).frame(width: 85, alignment: .leading)
            GeometryReader { geometry in
                Capsule().fill(Color.line)
                Capsule().fill(value > 0.9 ? Color.orange : Color.mint).frame(width: geometry.size.width * CGFloat(value))
            }.frame(height: 5)
            Text(value > 0.02 ? "Active" : "Quiet").font(.system(size: 9)).foregroundStyle(Color.muted).frame(width: 35)
        }
    }
}

struct PreparationAction: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var preparation: PreparationMonitor
    var body: some View {
        Button { if preparation.running { Task { await model.stopPreparation() } } else { model.beginPreparation() } } label: {
            PrismLabel(preparation.running ? "Stop preview" : "Test setup", systemImage: "waveform")
        }.buttonStyle(QuietButton()).disabled(model.phase.isActive || model.preparingPreview)
    }
}
