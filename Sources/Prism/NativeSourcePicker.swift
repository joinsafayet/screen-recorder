import AppKit
import ScreenCaptureKit

@MainActor
final class NativeSourcePicker: NSObject, SCContentSharingPickerObserver {
    static let shared = NativeSourcePicker()
    private var completion: ((Result<SCContentFilter, Error>?) -> Void)?
    override init() { super.init(); SCContentSharingPicker.shared.add(self) }
    func present(_ completion: @escaping (Result<SCContentFilter, Error>?) -> Void) {
        self.completion = completion
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = [.singleDisplay, .singleWindow]
        configuration.excludedBundleIDs = [Bundle.main.bundleIdentifier ?? "com.prism.screenstudio"]
        configuration.allowsChangingSelectedContent = false
        let picker = SCContentSharingPicker.shared
        picker.defaultConfiguration = configuration; picker.isActive = true; picker.present()
    }
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        Task { @MainActor [weak self] in let callback = self?.completion; self?.completion = nil; callback?(nil) }
    }
    nonisolated func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        Task { @MainActor [weak self] in let callback = self?.completion; self?.completion = nil; callback?(.success(filter)) }
    }
    nonisolated func contentSharingPickerStartDidFailWithError(_ error: Error) {
        Task { @MainActor [weak self] in let callback = self?.completion; self?.completion = nil; callback?(.failure(error)) }
    }
}
