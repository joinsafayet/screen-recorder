import SwiftUI

enum AppInfo {
    static let projectURL = URL(string: "https://github.com/joinsafayet/screen-recorder")!
    static let releasesURL = projectURL.appendingPathComponent("releases")
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "3.0.1" }
    static var build: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "6" }
    static var architecture: String {
        #if arch(arm64)
        "Apple Silicon"
        #else
        "Intel"
        #endif
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 22) {
            HStack { Spacer(); Button { dismiss() } label: { PrismIcon("xmark") }.buttonStyle(QuietButton()).accessibilityLabel("Close About Prism") }
            PrismBrandBadge(size: 88)
            VStack(spacing: 9) {
                Text("Prism").font(.system(size: 34, weight: .semibold)).tracking(-0.8)
                Text("Recording, editing, and presentation.").font(.system(size: 13)).foregroundStyle(Color.muted)
                Text("Version \(AppInfo.version) · Build \(AppInfo.build)").font(.system(size: 11)).foregroundStyle(Color.muted).textSelection(.enabled)
            }
            HStack(spacing: 8) { Chip(title: "macOS 15+", icon: "display"); Chip(title: AppInfo.architecture, icon: "cpu"); Chip(title: "Local storage", icon: "lock.shield", color: .mint) }
            Divider().overlay(Color.line)
            HStack(spacing: 12) {
                Link(destination: AppInfo.projectURL) { PrismLabel("View project", systemImage: "arrow.up.right") }.buttonStyle(QuietButton())
                Link(destination: AppInfo.releasesURL) { PrismLabel("Downloads & updates", systemImage: "square.and.arrow.down") }.buttonStyle(PrimaryButton())
            }
            Text("Your videos and edits stay in your local library.").font(.system(size: 11)).foregroundStyle(Color.muted)
        }.padding(28).frame(width: 500).background(Color.canvas).foregroundStyle(Color.ink).tint(.accent)
    }
}
