import AppKit
import AVFoundation

@MainActor enum AppContext { static weak var model: AppModel? }
extension Verification {
    func testAdjustableRegionsAndSavedAreas() throws {
        let bounds = CGRect(x: 0, y: 0, width: 800, height: 600)
        let area = CGRect(x: 70, y: 80, width: 320, height: 180)
        expect(RegionGeometry.move(area, dx: 1000, dy: -1000, in: bounds) == CGRect(x: 480, y: 0, width: 320, height: 180))
        for handle in RegionHandle.allCases {
            let resized = RegionGeometry.resize(area, handle: handle, dx: 100, dy: 100, in: bounds, aspect: .free)
            expect(bounds.contains(resized) && resized.width >= 32 && resized.height >= 32)
        }
        let portrait = RegionGeometry.fit(area, in: bounds, aspect: .portrait)
        expect(abs(portrait.width / portrait.height - 9 / 16) < 0.001 && bounds.contains(portrait))
        let saved = SavedRegion(name: "Tutorial", displayID: 10, rect: area)
        let restored = try JSONDecoder().decode(SavedRegion.self, from: JSONEncoder().encode(saved))
        expect(restored == saved)
    }
}

extension Verification {
    func testPreparationEstimatesAndAudioMeter() {
        var settings = CaptureSettings()
        let hd = PreparationEstimate.make(source: CGSize(width: 3840, height: 2160), scale: 1, settings: settings)
        expect(hd.width == 1920 && hd.height == 1080 && hd.bytesPerMinute > 60_000_000)
        settings.fps = 60
        let faster = PreparationEstimate.make(source: CGSize(width: 3840, height: 2160), scale: 1, settings: settings)
        expect(faster.bytesPerMinute > hd.bytesPerMinute * 19 / 10)
        expect(AudioActivity.rms([]) == 0 && AudioActivity.rms([0, 0, 0]) == 0)
        expect(abs(AudioActivity.rms([0.1, -0.1]) - 0.4) < 0.001)
        expect(AudioActivity.rms([1, -1]) == 1)
    }
}
