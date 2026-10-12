import Foundation
import CoreGraphics

enum CaptureAspect: String, CaseIterable, Codable, Identifiable {
    case free = "Free", wide = "16:9", classic = "4:3", square = "1:1", portrait = "9:16"
    var id: String { rawValue }
    var ratio: CGFloat? {
        switch self { case .free: return nil; case .wide: return 16 / 9; case .classic: return 4 / 3; case .square: return 1; case .portrait: return 9 / 16 }
    }
}
struct SavedRegion: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var displayID: UInt32
    var rect: CGRect
}
enum RegionHandle: CaseIterable {
    case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
    func point(in r: CGRect) -> CGPoint {
        switch self {
        case .topLeft: return CGPoint(x: r.minX, y: r.maxY)
        case .top: return CGPoint(x: r.midX, y: r.maxY)
        case .topRight: return CGPoint(x: r.maxX, y: r.maxY)
        case .right: return CGPoint(x: r.maxX, y: r.midY)
        case .bottomRight: return CGPoint(x: r.maxX, y: r.minY)
        case .bottom: return CGPoint(x: r.midX, y: r.minY)
        case .bottomLeft: return CGPoint(x: r.minX, y: r.minY)
        case .left: return CGPoint(x: r.minX, y: r.midY)
        }
    }
}
enum RegionGeometry {
    static func fit(_ rect: CGRect, in bounds: CGRect, aspect: CaptureAspect = .free) -> CGRect {
        guard !rect.isNull, rect.width.isFinite, rect.height.isFinite, rect.minX.isFinite, rect.minY.isFinite else { return .zero }
        var width = min(bounds.width, max(0, rect.width)), height = min(bounds.height, max(0, rect.height))
        if let ratio = aspect.ratio {
            height = width / ratio
            if height > bounds.height { height = bounds.height; width = height * ratio }
        }
        return CGRect(x: min(bounds.maxX - width, max(bounds.minX, rect.minX)), y: min(bounds.maxY - height, max(bounds.minY, rect.minY)), width: width, height: height)
    }
    static func move(_ rect: CGRect, dx: CGFloat, dy: CGFloat, in bounds: CGRect) -> CGRect { fit(rect.offsetBy(dx: dx, dy: dy), in: bounds) }
    static func resize(_ rect: CGRect, handle: RegionHandle, dx: CGFloat, dy: CGFloat, in bounds: CGRect, aspect: CaptureAspect) -> CGRect {
        var x0 = rect.minX, x1 = rect.maxX, y0 = rect.minY, y1 = rect.maxY
        if [.left, .topLeft, .bottomLeft].contains(handle) { x0 = min(x1 - 32, x0 + dx) }
        if [.right, .topRight, .bottomRight].contains(handle) { x1 = max(x0 + 32, x1 + dx) }
        if [.bottom, .bottomLeft, .bottomRight].contains(handle) { y0 = min(y1 - 32, y0 + dy) }
        if [.top, .topLeft, .topRight].contains(handle) { y1 = max(y0 + 32, y1 + dy) }
        return fit(CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0), in: bounds, aspect: aspect)
    }
}
