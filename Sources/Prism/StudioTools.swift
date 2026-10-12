import SwiftUI

struct StudioPresets: View {
    @EnvironmentObject private var model: AppModel
    var compact = false
    var body: some View {
        HStack(spacing: 10) {
            ForEach(RecordingPreset.allCases) { preset in
                let selected = preset.matches(model.settings)
                Button {
                    var settings = model.settings
                    preset.apply(to: &settings)
                    model.settings = settings
                } label: {
                    HStack(spacing: compact ? 6 : 10) {
                        PrismIcon(preset.icon, size: compact ? 14 : 18).foregroundStyle(Color.accent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(preset.rawValue).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.ink).lineLimit(1)
                            if !compact { Text(preset.detail).font(.system(size: 9)).foregroundStyle(Color.muted) }
                        }
                        Spacer(minLength: 0)
                        PrismIcon("checkmark.circle.fill", size: 12).foregroundStyle(Color.accent).opacity(selected ? 1 : 0)
                    }.padding(compact ? 10 : 13).frame(maxWidth: .infinity, alignment: .leading)
                        .selectionSurface(selected, radius: 11)
                }.buttonStyle(InteractiveButton(radius: 11)).help("Apply \(preset.rawValue) recording settings")
            }
        }
    }
}

struct PresenterOptions: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.prismReduceMotion) private var reduceMotion
    var body: some View {
        if model.settings.camera {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 7) { SectionTitle(text: "Presenter"); Text("Your camera, framed your way.").font(.system(size: 10)).foregroundStyle(Color.muted) }
                Spacer()
                Picker("Position", selection: $model.settings.presenterCorner) { ForEach(PresenterCorner.allCases) { Text($0.rawValue).tag($0) } }.frame(width: 200)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Size · \(Int(model.settings.presenterSize * 100))%").font(.system(size: 10)).foregroundStyle(Color.muted)
                    Slider(value: $model.settings.presenterSize, in: 0.12...0.4, step: 0.01).frame(width: 115)
                }
                Toggle("Mirror", isOn: $model.settings.mirrorCamera).toggleStyle(.switch).controlSize(.small).font(.system(size: 11))
            }.card(padding: 16).transition(PrismMotion.reveal(reduceMotion))
        }
    }
}

struct CaptureMonitor: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var telemetry: RecordingTelemetry
    var body: some View {
        let s = telemetry.statistics
        let pressure = s.droppedVideo > 0 || s.droppedAudio > 0
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) { Circle().fill(pressure ? Color.orange : Color.mint).frame(width: 6, height: 6); Text(model.phase.isCapturing ? "CAPTURE MONITOR" : "LAST TAKE").font(.system(size: 9, weight: .bold)).tracking(1.4) }
                Text(pressure ? "Encoder pressure detected" : s.frames > 0 ? "Frames are saving normally" : "Waiting for first frame…").font(.system(size: 11)).foregroundStyle(Color.muted)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 95), spacing: 14)], alignment: .leading, spacing: 14) {
            metric("Frames saved", "\(s.frames)")
            metric("Dropped frames", "\(s.droppedVideo)")
            metric("Audio drops", "\(s.droppedAudio)")
            metric("Frame processing", String(format: "%.1f ms", s.processingMilliseconds))
            metric("Capture", "\(s.width) × \(s.height)")
            }
        }.card(padding: 17)
        .help("Counts frames received by Prism. Static screens naturally produce fewer frames. Drops indicate encoder backpressure; choose a lower resolution or frame rate if they increase. Processing time excludes asynchronous encoding.")
    }
    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) { Text(title).font(.system(size: 9)).foregroundStyle(Color.muted); Text(value).font(.system(size: 13, weight: .medium, design: .monospaced)) }
    }
}

struct AudioMeter: View {
    @EnvironmentObject private var telemetry: RecordingTelemetry
    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<10) { index in
                Capsule().fill(Float(index) / 10 < telemetry.audioLevel ? (index > 7 ? Color.orange : Color.mint) : Color.line).frame(width: 3, height: 7 + CGFloat(index % 4) * 3)
            }
        }.frame(width: 48).help("Input audio activity")
    }
}

struct RecordingClock: View {
    @ObservedObject var telemetry: RecordingTelemetry
    var body: some View { Text(RecordingMath.clock(telemetry.elapsed)).monospacedDigit() }
}
