import SwiftUI

struct AnnotationCanvas: View {
    let aspect: CGFloat
    let kind: AnnotationKind
    var commit: ([AnnotationPoint]) -> Void
    @ViewState<[AnnotationPoint]> private var points = []
    var body: some View {
        GeometryReader { geometry in
            let fit = fitRect(in: geometry.size)
            ZStack {
                Color.clear.contentShape(Rectangle())
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: CGPoint(x: fit.minX + first.x * fit.width, y: fit.minY + first.y * fit.height))
                    for point in points.dropFirst() { path.addLine(to: CGPoint(x: fit.minX + point.x * fit.width, y: fit.minY + point.y * fit.height)) }
                }.stroke(Color.accent, style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                Text(kind == .arrow ? "Drag to place an arrow" : "Draw over the frame")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(.white).padding(8).background(.black.opacity(0.55), in: Capsule())
                    .frame(maxHeight: .infinity, alignment: .top).padding(.top, 12).allowsHitTesting(false)
            }
            .gesture(DragGesture(minimumDistance: 2).onChanged { gesture in
                func point(_ location: CGPoint) -> AnnotationPoint { AnnotationPoint(x: min(1, max(0, (location.x - fit.minX) / fit.width)), y: min(1, max(0, (location.y - fit.minY) / fit.height))) }
                if points.isEmpty { points = [point(gesture.startLocation)] }
                let current = point(gesture.location)
                if kind == .arrow { points = [points[0], current] }
                else if points.count < 2000 { if let last = points.last, hypot(last.x - current.x, last.y - current.y) > 0.003 { points.append(current) } }
            }.onEnded { _ in if points.count > 1 { commit(points) }; points = [] })
        }
    }
    private func fitRect(in size: CGSize) -> CGRect {
        if size.width / size.height > aspect { let width = size.height * aspect; return CGRect(x: (size.width - width) / 2, y: 0, width: width, height: size.height) }
        let height = size.width / aspect; return CGRect(x: 0, y: (size.height - height) / 2, width: size.width, height: height)
    }
}
