import Foundation
import Combine

/// Only the dock, meters, and capture monitor observe these frequently changing values.
@MainActor final class RecordingTelemetry: ObservableObject {
    @Published var elapsed = 0.0
    @Published var audioLevel: Float = 0
    @Published var statistics = CaptureStatistics()
    @Published var markers: [RecordingMarker] = []
    @Published var savingMessage = "Finalizing video…"
    func reset() { elapsed = 0; audioLevel = 0; statistics = CaptureStatistics(); markers = [] }
}
