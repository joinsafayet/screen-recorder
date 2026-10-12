import SwiftUI
import AppKit

/// Optical icons on a shared 24-point grid. System-only states keep native symbols.
enum PrismGlyph: String, CaseIterable {
    case capture, display, window, area, library, exports, settings, folder, storage
    case camera, microphone, audio, cut, zoom, marker, share, importVideo, trash
    case undo, redo, refresh, search, tutorial, motion, detail, everyday, animation, privacy
    case sidebarLeft, sidebarRight
    var title: String {
        switch self {
        case .capture: return "Record"
        case .display: return "Display"
        case .window: return "Window"
        case .area: return "Capture area"
        case .library: return "Recordings"
        case .exports: return "Export queue"
        case .settings: return "Settings"
        case .folder: return "Folder"
        case .storage: return "Storage"
        case .camera: return "Camera"
        case .microphone: return "Microphone"
        case .audio: return "Audio"
        case .cut: return "Split"
        case .zoom: return "Zoom"
        case .marker: return "Marker"
        case .share: return "Export"
        case .importVideo: return "Import"
        case .trash: return "Trash"
        case .undo: return "Undo"
        case .redo: return "Redo"
        case .refresh: return "Refresh"
        case .search: return "Search"
        case .tutorial: return "Tutorial"
        case .motion: return "Smooth motion"
        case .detail: return "Detail"
        case .everyday: return "Everyday"
        case .animation: return "Interface motion"
        case .privacy: return "Private"
        case .sidebarLeft: return "Sidebar"
        case .sidebarRight: return "Inspector"
        }
    }
    static func matching(_ symbol: String) -> Self? {
        switch symbol {
        case "record.circle": return .capture
        case "display": return .display
        case "macwindow", "macwindow.badge.plus": return .window
        case "viewfinder": return .area
        case "rectangle.stack", "rectangle.stack.badge.play", "film": return .library
        case "square.and.arrow.up.on.square": return .exports
        case "slider.horizontal.3": return .settings
        case "folder", "folder.fill": return .folder
        case "internaldrive", "internaldrive.fill": return .storage
        case "person.crop.circle", "person.crop.circle.fill": return .camera
        case "mic", "mic.fill": return .microphone
        case "speaker.wave.2", "waveform": return .audio
        case "scissors": return .cut
        case "plus.magnifyingglass": return .zoom
        case "bookmark": return .marker
        case "square.and.arrow.up": return .share
        case "square.and.arrow.down": return .importVideo
        case "trash": return .trash
        case "arrow.uturn.backward": return .undo
        case "arrow.uturn.forward": return .redo
        case "arrow.clockwise": return .refresh
        case "magnifyingglass": return .search
        case "person.bubble": return .tutorial
        case "bolt": return .motion
        case "4k.tv": return .detail
        case "prism.everyday": return .everyday
        case "sparkles": return .animation
        case "lock.shield": return .privacy
        case "sidebar.left": return .sidebarLeft
        case "sidebar.right": return .sidebarRight
        default: return nil
        }
    }
}

struct PrismIcon: View {
    let name: String
    var size: CGFloat = 16
    init(_ name: String, size: CGFloat = 16) { self.name = name; self.size = size }
    var body: some View {
        if let glyph = PrismGlyph.matching(name) {
            PrismGlyphShape(glyph: glyph, compact: size < 16)
                .stroke(style: StrokeStyle(lineWidth: max(1.05, min(2.7, size * 1.75 / 24)), lineCap: .round, lineJoin: .round))
                .frame(width: size, height: size)
                .accessibilityElement(children: .ignore).accessibilityLabel(glyph.title)
        } else {
            Image(systemName: name).symbolRenderingMode(.monochrome)
                .font(.system(size: size, weight: .regular)).frame(width: size, height: size)
        }
    }
}

struct PrismLabel: View {
    let title: String
    let symbol: String
    var size: CGFloat = 14
    init(_ title: String, systemImage: String, size: CGFloat = 14) { self.title = title; symbol = systemImage; self.size = size }
    var body: some View {
        HStack(spacing: 7) { PrismIcon(symbol, size: size).accessibilityHidden(true); Text(title) }
            .accessibilityElement(children: .combine)
    }
}

struct PrismGlyphShape: Shape {
    let glyph: PrismGlyph
    var compact = false
    func path(in rect: CGRect) -> Path {
        var p = Path()
        func line(_ points: [(CGFloat, CGFloat)]) {
            guard let first = points.first else { return }
            p.move(to: CGPoint(x: first.0, y: first.1))
            for point in points.dropFirst() { p.addLine(to: CGPoint(x: point.0, y: point.1)) }
        }
        func box(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat = 2.5) {
            p.addRoundedRect(in: CGRect(x: x, y: y, width: w, height: h), cornerSize: CGSize(width: radius, height: radius))
        }
        func circle(_ x: CGFloat, _ y: CGFloat, _ radius: CGFloat) { p.addEllipse(in: CGRect(x: x-radius, y: y-radius, width: radius*2, height: radius*2)) }
        switch glyph {
        case .capture:
            line([(8,3),(5,3),(3,5),(3,8)]); line([(16,3),(19,3),(21,5),(21,8)])
            line([(3,16),(3,19),(5,21),(8,21)]); line([(16,21),(19,21),(21,19),(21,16)])
            circle(12,12,4)
        case .display:
            box(2.5,3.5,19,13,2); line([(8,21),(16,21)]); line([(12,16.5),(12,21)])
        case .window:
            box(3,4,18,16); line([(3,8.5),(21,8.5)]); line([(6,6.3),(6.1,6.3)]); line([(9,6.3),(9.1,6.3)])
        case .area:
            line([(8,3),(3,3),(3,8)]); line([(16,3),(21,3),(21,8)])
            line([(3,16),(3,21),(8,21)]); line([(16,21),(21,21),(21,16)])
            line([(10,12),(14,12)]); line([(12,10),(12,14)])
        case .library:
            box(3,7,18,14,2); line([(5,4),(19,4)])
            if !compact { line([(7,1.5),(17,1.5)]); line([(10,11),(15,14),(10,17),(10,11)]) }
        case .exports:
            line([(3,13),(3,20),(21,20),(21,13)]); line([(12,16),(12,2.5)])
            line([(7,7.5),(12,2.5),(17,7.5)]); line([(6,23),(18,23)])
        case .settings:
            line([(3,6),(7,6)]); line([(11,6),(21,6)]); circle(9,6,2)
            line([(3,12),(13,12)]); line([(17,12),(21,12)]); circle(15,12,2)
            line([(3,18),(6,18)]); line([(10,18),(21,18)]); circle(8,18,2)
        case .folder:
            p.move(to: CGPoint(x:3,y:8)); p.addLine(to: CGPoint(x:3,y:5)); p.addQuadCurve(to: CGPoint(x:5,y:3), control: CGPoint(x:3,y:3))
            p.addLine(to: CGPoint(x:10,y:3)); p.addLine(to: CGPoint(x:12,y:6)); p.addLine(to: CGPoint(x:19,y:6))
            p.addQuadCurve(to: CGPoint(x:21,y:8), control: CGPoint(x:21,y:6))
            p.addLine(to: CGPoint(x:21,y:18)); p.addQuadCurve(to: CGPoint(x:19,y:20), control: CGPoint(x:21,y:20))
            p.addLine(to: CGPoint(x:5,y:20)); p.addQuadCurve(to: CGPoint(x:3,y:18), control: CGPoint(x:3,y:20)); p.addLine(to: CGPoint(x:3,y:8)); line([(3,9),(21,9)])
        case .storage:
            box(3,5,18,15,2); line([(3,14),(21,14)]); line([(6,17),(6.1,17)]); line([(9,17),(9.1,17)]); line([(7,2),(17,2)])
        case .camera:
            box(2.5,6,14,13,2); line([(16.5,10),(21.5,7),(21.5,18),(16.5,15)])
            circle(8,12.5,2.5)
        case .microphone:
            box(8,2,8,13,4); p.move(to: CGPoint(x:5,y:10)); p.addLine(to: CGPoint(x:5,y:12))
            p.addCurve(to: CGPoint(x:19,y:12), control1: CGPoint(x:5,y:21), control2: CGPoint(x:19,y:21)); p.addLine(to: CGPoint(x:19,y:10))
            line([(12,18.5),(12,22)]); line([(8,22),(16,22)])
        case .audio:
            line([(3,10),(3,14)]); line([(7.5,6),(7.5,18)]); line([(12,2.5),(12,21.5)]); line([(16.5,7.5),(16.5,16.5)]); line([(21,10),(21,14)])
        case .cut:
            circle(6,18,3); circle(6,6,3); line([(8.5,7.5),(21,20)]); line([(8.5,16.5),(21,4)])
        case .zoom, .search:
            circle(10,10,6.5); line([(15,15),(21,21)])
            if glyph == .zoom { line([(7,10),(13,10)]); line([(10,7),(10,13)]) }
        case .marker:
            line([(6,21),(6,3),(18,3),(18,21),(12,17),(6,21)])
        case .share, .importVideo:
            line([(3,12),(3,20),(21,20),(21,12)])
            if glyph == .share { line([(12,15),(12,2)]); line([(7,7),(12,2),(17,7)]) }
            else { line([(12,2),(12,15)]); line([(7,10),(12,15),(17,10)]) }
        case .trash:
            line([(3,6),(21,6)]); line([(8,6),(8,3),(16,3),(16,6)])
            line([(5,6),(6,21),(18,21),(19,6)]); line([(10,10),(10,17)]); line([(14,10),(14,17)])
        case .undo, .redo:
            let mirror: CGFloat = glyph == .redo ? -1 : 1
            func x(_ value: CGFloat) -> CGFloat { 12 + (value-12)*mirror }
            line([(x(8),3),(x(3),8),(x(8),13)])
            p.move(to: CGPoint(x:x(3),y:8)); p.addLine(to: CGPoint(x:x(13),y:8))
            p.addCurve(to: CGPoint(x:x(13),y:21), control1: CGPoint(x:x(23),y:8), control2: CGPoint(x:x(23),y:21))
            p.addLine(to: CGPoint(x:x(9),y:21))
        case .refresh:
            p.addArc(center: CGPoint(x:12,y:12), radius: 8.5, startAngle: .degrees(-50), endAngle: .degrees(275), clockwise: false)
            line([(13.5,5.5),(17.5,5.5),(17.5,1.5)])
        case .tutorial:
            box(2.5,3,19,14,3); line([(8,17),(6,21),(13,17)])
            circle(12,8,2); p.move(to: CGPoint(x:8,y:14)); p.addQuadCurve(to: CGPoint(x:16,y:14), control: CGPoint(x:12,y:9))
        case .motion:
            line([(4,5),(13,5)]); line([(2,10),(9,10)]); line([(4,15),(9,15)])
            line([(15,2),(10,13),(15,13),(13,22),(22,9),(16,9),(15,2)])
        case .detail:
            box(2.5,4,19,15,2); line([(8,22),(16,22)])
            if compact { box(8,8,8,7,1) }
            else { line([(7,10),(7,8),(10,8)]); line([(14,8),(17,8),(17,10)]); line([(7,13),(7,15),(10,15)]); line([(14,15),(17,15),(17,13)]) }
        case .everyday:
            box(3,4,18,16,3); circle(12,12,4.5); line([(18,6.5),(18.1,6.5)])
        case .animation:
            p.addArc(center: CGPoint(x:12,y:12), radius:8, startAngle:.degrees(-130), endAngle:.degrees(-10), clockwise:false)
            p.addArc(center: CGPoint(x:12,y:12), radius:8, startAngle:.degrees(50), endAngle:.degrees(170), clockwise:false)
            line([(17,5),(20,10),(15,9)]); line([(7,19),(4,14),(9,15)])
        case .privacy:
            line([(12,2),(21,6),(20,14),(17,19),(12,22),(7,19),(4,14),(3,6),(12,2)])
            line([(8,12),(11,15),(16,9)])
        case .sidebarLeft, .sidebarRight:
            box(2.5,4,19,16,2)
            let x: CGFloat = glyph == .sidebarLeft ? 9 : 15
            line([(x,4),(x,20)])
            let start: CGFloat = glyph == .sidebarLeft ? 5 : 17.5
            line([(start,8),(start+1.5,8)]); line([(start,11),(start+1.5,11)])
        }
        return p.applying(CGAffineTransform(scaleX: rect.width/24, y: rect.height/24).concatenating(CGAffineTransform(translationX: rect.minX, y: rect.minY)))
    }
}

enum PrismBrand {
    static let mark: NSImage? = Bundle.main.url(forResource: "PrismMark", withExtension: "png").flatMap(NSImage.init(contentsOf:))
    static let statusMark: NSImage = {
        if let mark, let copy = mark.copy() as? NSImage { copy.isTemplate = true; copy.size = CGSize(width: 18, height: 18); return copy }
        return NSImage(systemSymbolName: "record.circle", accessibilityDescription: "Prism")!
    }()
}

struct PrismBrandBadge: View {
    var size: CGFloat = 42
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size*0.26).fill(LinearGradient(colors: [Color(red:0.10,green:0.18,blue:0.31), Color(red:0.05,green:0.10,blue:0.19)], startPoint: .topLeading, endPoint: .bottomTrailing))
            if let mark = PrismBrand.mark {
                Image(nsImage: mark).resizable().interpolation(.high).scaledToFit().padding(size*0.04)
            } else { Text("P").font(.system(size:size*0.66,weight:.bold,design:.rounded)).foregroundStyle(Color.brandBlue) }
        }.frame(width:size,height:size)
            .overlay(RoundedRectangle(cornerRadius:size*0.26).stroke(.white.opacity(0.12),lineWidth:0.7))
            .shadow(color:.black.opacity(0.12),radius:6,y:3).accessibilityHidden(true)
    }
}
