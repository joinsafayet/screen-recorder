import AppKit

@MainActor
final class RegionSelector {
    static let shared = RegionSelector()
    private var panel: NSPanel?
    func select(on screen: NSScreen, completion: @escaping (CGRect?) -> Void) {
        (panel?.contentView as? RegionSelectionView)?.completion?(nil)
        let panel = SelectionPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .screenSaver; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = RegionSelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.completion = { [weak self, weak panel, weak view] rect in
            guard let self, let panel, self.panel === panel else { return }
            view?.completion = nil
            panel.close(); self.panel = nil; completion(rect)
        }
        panel.contentView = view; self.panel = panel
        panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(view)
    }
}

final class SelectionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class RegionSelectionView: NSView {
    var completion: ((CGRect?) -> Void)?
    private var start: CGPoint?
    private var selection = CGRect.zero
    private var hint = "Drag to select an area  ·  Release to confirm  ·  Esc to cancel"
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.black.withAlphaComponent(0.55).setFill()
        let shade = NSBezierPath(rect: bounds)
        if !selection.isEmpty { shade.appendRect(selection); shade.windingRule = .evenOdd }
        shade.fill()
        if !selection.isEmpty {
            NSColor(red: 0.47, green: 0.68, blue: 1, alpha: 1).setStroke()
            let border = NSBezierPath(rect: selection.insetBy(dx: 1, dy: 1)); border.lineWidth = 2; border.stroke()
            NSColor.white.setFill()
            for point in [CGPoint(x: selection.minX, y: selection.minY), CGPoint(x: selection.maxX, y: selection.minY), CGPoint(x: selection.minX, y: selection.maxY), CGPoint(x: selection.maxX, y: selection.maxY)] {
                NSBezierPath(roundedRect: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6), xRadius: 2, yRadius: 2).fill()
            }
            let label = "\(Int(selection.width)) × \(Int(selection.height)) pt"
            drawLabel(label, centeredAt: CGPoint(x: selection.midX, y: max(16, selection.minY - 28)), size: 12)
        }
        drawLabel(hint, centeredAt: CGPoint(x: bounds.midX, y: bounds.maxY - 60), size: 14)
    }
    private func drawLabel(_ text: String, centeredAt point: CGPoint, size: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedSystemFont(ofSize: size, weight: .medium), .foregroundColor: NSColor.white]
        let size = (text as NSString).size(withAttributes: attributes)
        let x = min(bounds.maxX - size.width - 12, max(12, point.x - size.width / 2))
        let rect = CGRect(x: x - 10, y: point.y - 7, width: size.width + 20, height: size.height + 14)
        NSColor(red: 0.07, green: 0.10, blue: 0.15, alpha: 0.94).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
        (text as NSString).draw(at: CGPoint(x: x, y: point.y), withAttributes: attributes)
    }
    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil); selection = .zero
        hint = "Drag to select an area  ·  Release to confirm  ·  Esc to cancel"; needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let point = convert(event.locationInWindow, from: nil)
        selection = RecordingMath.selectionRect(start: start, end: point, bounds: bounds)
        needsDisplay = true
    }
    override func mouseUp(with event: NSEvent) {
        guard let start else { return }
        // The final mouse-up can be farther than the last coalesced drag event.
        selection = RecordingMath.selectionRect(start: start, end: convert(event.locationInWindow, from: nil), bounds: bounds)
        self.start = nil
        if selection.width >= 32 && selection.height >= 32 { finish(selection) }
        else { hint = "Area too small  ·  Drag at least 32 × 32 pt  ·  Esc to cancel"; needsDisplay = true }
    }
    override func keyDown(with event: NSEvent) { if event.keyCode == 53 { finish(nil) } }
    private func finish(_ rect: CGRect?) {
        let callback = completion; completion = nil; callback?(rect)
    }
}
