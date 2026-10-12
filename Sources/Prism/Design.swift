import SwiftUI

// Use the established State property wrapper explicitly. The macOS 27 CLI SDK
// also exports a State macro whose plugin is only bundled with full Xcode.
typealias ViewState<Value> = SwiftUI.State<Value>

enum AccentPalette: String, CaseIterable, Identifiable {
    case blue = "Blue", teal = "Teal", amber = "Amber", coral = "Coral"
    var id: String { rawValue }
    var dark: UInt32 { switch self { case .blue: return 0x78AEFF; case .teal: return 0x66D8C8; case .amber: return 0xE9BD70; case .coral: return 0xF79D91 } }
    var light: UInt32 { switch self { case .blue: return 0x2465CB; case .teal: return 0x167366; case .amber: return 0x8E5E13; case .coral: return 0xB34E42 } }
}

extension Color {
    private static var selectedPalette: AccentPalette { AccentPalette(rawValue: UserDefaults.standard.string(forKey: "accentChoice") ?? "Blue") ?? .blue }
    static var accent: Color { adaptive(dark: selectedPalette.dark, light: selectedPalette.light) }
    static var action: Color { adaptive(dark: selectedPalette.light, light: selectedPalette.light) }
    static func swatch(_ palette: AccentPalette) -> Color { adaptive(dark: palette.dark, light: palette.light) }
    static let mint = adaptive(dark: 0x63D4BC, light: 0x167A67)
    static let canvas = adaptive(dark: 0x0E131B, light: 0xF3F6FB)
    static let sidebar = adaptive(dark: 0x111822, light: 0xF8FAFD)
    static let surface = adaptive(dark: 0x171F2B, light: 0xFFFFFF)
    static let elevated = adaptive(dark: 0x202D3F, light: 0xEAF0F8)
    static let ink = adaptive(dark: 0xEEF4FE, light: 0x17283F)
    static let muted = adaptive(dark: 0x97A9C1, light: 0x63748D)
    static let line = adaptive(dark: 0x2B394D, light: 0xDCE4F0)
    static let previewBase = Color(red: 0.04, green: 0.08, blue: 0.14)
    static let brandBlue = Color(red: 0.204, green: 0.420, blue: 0.922)
    static let brandCyan = Color(red: 0.208, green: 0.737, blue: 0.647)
    private static func adaptive(dark: UInt32, light: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(red: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
}

/// Animations are short, interruptible, and tied to interaction. No idle render loop.
enum PrismMotion {
    static func feedback(_ reduce: Bool) -> Animation? { reduce ? nil : .easeOut(duration: 0.14) }
    static func selection(_ reduce: Bool) -> Animation? { reduce ? nil : .smooth(duration: 0.26) }
    static func page(_ reduce: Bool) -> Animation? { reduce ? nil : .easeInOut(duration: 0.20) }
    static func reveal(_ reduce: Bool) -> AnyTransition {
        reduce ? .identity : .opacity.combined(with: .offset(y: 6))
    }
}
private struct PrismReduceMotionKey: EnvironmentKey {
    static let defaultValue = false
}
extension EnvironmentValues {
    var prismReduceMotion: Bool {
        get { self[PrismReduceMotionKey.self] }
        set { self[PrismReduceMotionKey.self] = newValue }
    }
}

struct SelectionSurface: ViewModifier {
    let selected: Bool
    var radius: CGFloat = 12
    @Environment(\.prismReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.background(selected ? Color.accent.opacity(0.12) : Color.surface, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(selected ? Color.accent.opacity(0.75) : Color.line, lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: radius))
            .animation(PrismMotion.selection(reduceMotion), value: selected)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct Card: ViewModifier {
    var padding: CGFloat = 20
    func body(content: Content) -> some View {
        content.padding(padding).background(Color.surface, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.line, lineWidth: 1))
    }
}
extension View {
    func card(padding: CGFloat = 20) -> some View { modifier(Card(padding: padding)) }
    func selectionSurface(_ selected: Bool, radius: CGFloat = 12) -> some View { modifier(SelectionSurface(selected: selected, radius: radius)) }
}

struct SectionTitle: View {
    let text: String
    var body: some View { Text(text.uppercased()).font(.system(size: 10, weight: .bold)).tracking(1.8).foregroundStyle(Color.muted) }
}
struct Chip: View {
    let title: String
    var icon: String? = nil
    var color: Color = .muted
    var body: some View {
        HStack(spacing: 5) {
            if let icon { PrismIcon(icon, size: 10) }
            Text(title).font(.system(size: 10, weight: .semibold))
        }.foregroundStyle(color).padding(.horizontal, 9).padding(.vertical, 6)
            .background(color.opacity(0.09), in: Capsule()).overlay(Capsule().stroke(color.opacity(0.15)))
    }
}
struct AnimatedSymbol: View {
    let name: String
    var size: CGFloat = 16
    @Environment(\.prismReduceMotion) private var reduceMotion
    var body: some View {
        if PrismGlyph.matching(name) != nil {
            ZStack { PrismIcon(name, size: size).id(name).transition(reduceMotion ? .identity : .opacity) }
                .animation(PrismMotion.feedback(reduceMotion), value: name)
        } else {
            Image(systemName: name).symbolRenderingMode(.monochrome).font(.system(size: size))
                .contentTransition(reduceMotion ? .identity : .symbolEffect(.replace))
                .animation(PrismMotion.feedback(reduceMotion), value: name)
        }
    }
}
struct PrimaryButton: ButtonStyle {
    var color: Color = .action
    func makeBody(configuration: Configuration) -> some View {
        ButtonFeedback(pressed: configuration.isPressed, radius: 11, fill: color, hover: .white.opacity(0.10)) {
            configuration.label.font(.system(size: 13, weight: .semibold)).foregroundStyle(Color.white)
                .padding(.horizontal, 22).padding(.vertical, 14)
        }
    }
}
struct QuietButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        ButtonFeedback(pressed: configuration.isPressed, radius: 8, fill: .elevated, hover: .accent.opacity(0.08)) {
            configuration.label.font(.system(size: 12, weight: .medium)).foregroundStyle(Color.ink)
                .padding(.horizontal, 12).padding(.vertical, 9)
        }
    }
}
struct InteractiveButton: ButtonStyle {
    var radius: CGFloat = 12
    func makeBody(configuration: Configuration) -> some View {
        ButtonFeedback(pressed: configuration.isPressed, radius: radius, fill: .clear, hover: .accent.opacity(0.055)) {
            configuration.label
        }
    }
}
private struct ButtonFeedback<Label: View>: View {
    let pressed: Bool
    let radius: CGFloat
    let fill: Color
    let hover: Color
    @ViewBuilder var label: () -> Label
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    @Environment(\.prismReduceMotion) private var reduceMotion
    @ViewState<Bool> private var hovered = false
    var body: some View {
        label()
            .background(fill, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius).fill(hover.opacity(enabled && hovered ? 1 : 0)).allowsHitTesting(false))
            .overlay(RoundedRectangle(cornerRadius: radius).stroke(Color.accent.opacity(focused && enabled ? 0.8 : 0), lineWidth: 2).padding(-3).allowsHitTesting(false))
            // The hit target stays still while only the visual content compresses.
            .scaleEffect(pressed && enabled && !reduceMotion ? 0.98 : 1)
            .opacity(enabled ? (pressed ? 0.82 : 1) : 0.42)
            .contentShape(RoundedRectangle(cornerRadius: radius))
            .onHover { hovered = $0 }
            .allowsWindowActivationEvents(true)
            .animation(PrismMotion.feedback(reduceMotion), value: pressed)
            .animation(PrismMotion.feedback(reduceMotion), value: hovered)
            .animation(PrismMotion.feedback(reduceMotion), value: enabled)
    }
}
struct FeatureToggle: View {
    var icon: String
    var title: String
    var subtitle: String
    @Binding var value: Bool
    @Environment(\.prismReduceMotion) private var reduceMotion
    var body: some View {
        HStack(spacing: 12) {
            PrismIcon(icon, size: 16).foregroundStyle(value ? Color.accent : Color.muted)
                .frame(width: 34, height: 36).background(Color.elevated, in: RoundedRectangle(cornerRadius: 9))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color.ink)
                Text(subtitle).font(.system(size: 10)).foregroundStyle(Color.muted)
            }
            Spacer(minLength: 8)
            Toggle(title, isOn: $value).labelsHidden().toggleStyle(.switch).controlSize(.small).tint(.accent)
        }
        .animation(PrismMotion.selection(reduceMotion), value: value)
    }
}

struct RootView: View {
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @ViewState<Bool> private var sidebarVisible = true
    private var reduceMotion: Bool { systemReduceMotion || !model.motionEnabled }
    var body: some View {
        HSplitView {
            if sidebarVisible { SidebarView().frame(minWidth: 180, idealWidth: 210, maxWidth: 260) }
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    Button { sidebarVisible.toggle() } label: { PrismIcon("sidebar.left", size: 16) }.buttonStyle(InteractiveButton(radius: 5)).help("Toggle sidebar").keyboardShortcut("s", modifiers: [.command, .option])
                    Text("WORKSPACE").font(.system(size: 9, weight: .bold)).tracking(1.5).foregroundStyle(Color.muted)
                    PrismIcon("chevron.right", size: 8).foregroundStyle(Color.muted.opacity(0.5))
                    Text(model.destination.rawValue).font(.system(size: 11, weight: .medium)).foregroundStyle(Color.ink)
                    Spacer()
                    if model.phase.isActive { Chip(title: model.phase.label, icon: "circle.fill", color: model.phase == .paused ? .orange : .accent) }
                    else { Chip(title: "All on your Mac", icon: "lock.shield", color: .mint) }
                }.padding(.horizontal, 30).frame(height: 54)
                Rectangle().fill(Color.line).frame(height: 1)
                // Keep scroll positions and search/editor state when changing tabs.
                // Outgoing pages stop receiving input immediately, even mid-animation.
                ZStack {
                    page(.studio) { StudioView() }
                    page(.library) { LibraryView() }
                    page(.exports) { ExportQueueView() }
                    page(.settings) { PreferencesView() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .animation(PrismMotion.page(reduceMotion), value: model.destination)
            }.background(Color.canvas)
        }
        .frame(minWidth: sidebarVisible ? 940 : 760, minHeight: 680).foregroundStyle(Color.ink)
        .tint(.accent)
        .overlay(alignment: .bottom) {
            if let toast = model.toast {
                HStack(spacing: 10) { PrismIcon("checkmark.circle.fill", size: 16).foregroundStyle(Color.mint); Text(toast).font(.system(size: 12, weight: .medium)) }
                    .padding(16).background(Color.elevated, in: Capsule()).overlay(Capsule().stroke(Color.line)).shadow(color: .black.opacity(0.15), radius: 20)
                    .padding(.bottom, 20).allowsHitTesting(false)
                    .transition(PrismMotion.reveal(reduceMotion))
            }
        }
        .animation(PrismMotion.selection(reduceMotion), value: model.toast)
        .alert("Something needs your attention", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK", role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
        .onAppear { AppContext.model = model; model.openStudioWindow = { [openWindow] in openWindow(id: "prism-studio") } }
        .onChange(of: model.destination) { _, destination in model.mainWindow?.makeFirstResponder(nil); if destination != .studio { Task { await model.stopPreparation() } } }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { notification in
            if let window = notification.object as? NSWindow, window === model.mainWindow { model.mainWindow = nil }
        }
        .environment(\.prismReduceMotion, reduceMotion)
        .environmentObject(model.preparation)
        .environmentObject(model.exports)
    }
    private func page<Content: View>(_ destination: Destination, @ViewBuilder content: () -> Content) -> some View {
        content().frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(model.destination == destination ? 1 : 0)
            .offset(y: model.destination == destination || reduceMotion ? 0 : 5)
            .allowsHitTesting(model.destination == destination)
            .accessibilityHidden(model.destination != destination)
            .zIndex(model.destination == destination ? 1 : 0)
    }
}

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var library: LibraryStore
    @Environment(\.prismReduceMotion) private var reduceMotion
    @Namespace private var navigation
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 11) {
                PrismBrandBadge()
                VStack(alignment: .leading, spacing: 4) {
                    Text("Prism").font(.system(size: 23, weight: .semibold)).tracking(-0.6)
                    Text("SCREEN STUDIO").font(.system(size: 8, weight: .bold)).tracking(2).foregroundStyle(Color.muted)
                }
            }.padding(.bottom, 38)
            SectionTitle(text: "Create").padding(.horizontal, 10).padding(.bottom, 14)
            ForEach([Destination.studio, .library, .exports]) { item in navItem(item) }
            SectionTitle(text: "Workspace").padding(.horizontal, 10).padding(.top, 30).padding(.bottom, 14)
            navItem(.settings)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([library.folder])
            } label: {
                HStack(spacing: 11) { PrismIcon("folder", size: 16).frame(width: 20); Text("Save folder").font(.system(size: 12)); Spacer(); PrismIcon("arrow.up.right", size: 9) }
                    .foregroundStyle(Color.muted).padding(12)
            }.buttonStyle(InteractiveButton(radius: 9))
            Spacer(minLength: 28)
            VStack(alignment: .leading, spacing: 12) {
                HStack { PrismIcon("internaldrive", size: 16).foregroundStyle(Color.accent); Text("Your local library").font(.system(size: 11, weight: .semibold)) }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(library.totalBytes.fileSize).font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text("saved").font(.system(size: 10)).foregroundStyle(Color.muted)
                }
                Text("\(library.countLabel) · Yours to keep.").font(.system(size: 10)).foregroundStyle(Color.muted)
            }.frame(maxWidth: .infinity, alignment: .leading).card(padding: 14).padding(.bottom, 18)
            HStack(spacing: 9) {
                Circle().fill(model.screenAccess ? Color.mint : Color.orange).frame(width: 6, height: 6)
                Text(model.screenAccess ? "Ready for your next idea" : "Screen access needed").font(.system(size: 10)).foregroundStyle(Color.muted)
            }.padding(.horizontal, 5)
            Text("PRISM  3.0").font(.system(size: 8, weight: .medium)).tracking(2).foregroundStyle(Color.muted.opacity(0.5)).padding(.horizontal, 5).padding(.top, 18)
        }.padding(.horizontal, 18).padding(.top, 58).padding(.bottom, 24).background(Color.sidebar)
    }
    private func navItem(_ item: Destination) -> some View {
        Button { model.destination = item } label: {
            HStack(spacing: 11) {
                PrismIcon(item.icon, size: 18).accessibilityHidden(true).frame(width: 20)
                Text(item.rawValue).font(.system(size: 12, weight: .semibold))
                Spacer()
                if item == .library { Text("\(library.recordings.count)").font(.system(size: 10, weight: .semibold)).padding(.horizontal, 7).padding(.vertical, 3).background(Color.line, in: Capsule()) }
            }.foregroundStyle(model.destination == item ? Color.accent : Color.muted)
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    if model.destination == item {
                        RoundedRectangle(cornerRadius: 9).fill(Color.accent.opacity(0.14))
                            .overlay(alignment: .leading) { Capsule().fill(Color.accent).frame(width: 3, height: 18).padding(.leading, 1) }
                            .matchedGeometryEffect(id: "navigation", in: navigation)
                    }
                }
                .contentShape(RoundedRectangle(cornerRadius: 9))
        }.buttonStyle(InteractiveButton(radius: 9)).padding(.bottom, 5)
            .animation(PrismMotion.selection(reduceMotion), value: model.destination)
            .accessibilityAddTraits(model.destination == item ? .isSelected : [])
    }
}
