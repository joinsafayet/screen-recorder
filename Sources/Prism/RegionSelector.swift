import AppKit

@MainActor
final class RegionSelector {
    static let shared = RegionSelector()
    private var panel: NSPanel?
    func select(on screen: NSScreen, initial: CGRect? = nil, aspect: CaptureAspect = .free, completion: @escaping (CGRect?) -> Void) {
        (panel?.contentView as? RegionSelectionView)?.completion?(nil)
        let panel = SelectionPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .screenSaver; panel.isOpaque = false; panel.backgroundColor = .clear
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let view = RegionSelectionView(frame: CGRect(origin: .zero, size: screen.frame.size))
        view.confirmOnRelease = false; view.aspect = aspect
        if let initial { view.setSelection(initial) }
        view.installControls()
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
    var confirmOnRelease = true
    var aspect: CaptureAspect = .free
    private var initial = CGRect.zero
    private var moving = false
    private var handle: RegionHandle?
    private var start: CGPoint?
    private var selection = CGRect.zero
    private var hint = "Drag to select an area  ·  Release to confirm  ·  Esc to cancel"
    func setSelection(_ rect: CGRect) { selection = RegionGeometry.fit(rect, in: bounds, aspect: aspect); needsDisplay = true }
    func installControls() {
        let bar = NSView(frame: CGRect(x: bounds.midX - 180, y: bounds.maxY - 120, width: 360, height: 36))
        let popup = NSPopUpButton(frame: CGRect(x: 0, y: 2, width: 100, height: 30))
        popup.addItems(withTitles: CaptureAspect.allCases.map(\.rawValue)); popup.selectItem(withTitle: aspect.rawValue)
        popup.target = self; popup.action = #selector(changeAspect(_:)); bar.addSubview(popup)
        let confirm = NSButton(title: "Use area ↩", target: self, action: #selector(confirmArea))
        confirm.frame = CGRect(x: 115, y: 2, width: 130, height: 30); confirm.bezelStyle = .rounded; bar.addSubview(confirm)
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelArea))
        cancel.frame = CGRect(x: 250, y: 2, width: 100, height: 30); cancel.bezelStyle = .rounded; bar.addSubview(cancel)
        addSubview(bar)
        hint = "Drag an area  ·  Move or resize it  ·  Enter to confirm  ·  Esc to cancel"
    }
    @objc private func changeAspect(_ sender: NSPopUpButton) { aspect = CaptureAspect(rawValue: sender.titleOfSelectedItem ?? "Free") ?? .free; setSelection(selection); window?.makeFirstResponder(self) }
    @objc private func confirmArea() { if selection.width >= 32 && selection.height >= 32 { finish(selection) } }
    @objc private func cancelArea() { finish(nil) }
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
            for item in RegionHandle.allCases {
                let point = item.point(in: selection)
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
        let point = convert(event.locationInWindow, from: nil)
        start = point; initial = selection
        handle = RegionHandle.allCases.first { let p = $0.point(in: selection); return !selection.isEmpty && hypot(p.x - point.x, p.y - point.y) < 10 }
        moving = handle == nil && !confirmOnRelease && selection.contains(point)
        if handle == nil && !moving { selection = .zero }
        needsDisplay = true
    }
    private func update(at point: CGPoint) {
        guard let start else { return }
        if let handle { selection = RegionGeometry.resize(initial, handle: handle, dx: point.x - start.x, dy: point.y - start.y, in: bounds, aspect: aspect) }
        else if moving { selection = RegionGeometry.move(initial, dx: point.x - start.x, dy: point.y - start.y, in: bounds) }
        else { selection = RegionGeometry.fit(RecordingMath.selectionRect(start: start, end: point, bounds: bounds), in: bounds, aspect: aspect) }
        needsDisplay = true
    }
    override func mouseDragged(with event: NSEvent) { update(at: convert(event.locationInWindow, from: nil)) }
    override func mouseUp(with event: NSEvent) {
        guard start != nil else { return }
        update(at: convert(event.locationInWindow, from: nil)); start = nil
        if selection.width >= 32 && selection.height >= 32 {
            if confirmOnRelease { finish(selection) }
        } else { hint = "Area too small  ·  Drag at least 32 × 32 pt  ·  Esc to cancel"; needsDisplay = true }
    }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { finish(nil); return }
        if event.keyCode == 36 { confirmArea(); return }
        let distance: CGFloat = event.modifierFlags.contains(.shift) ? 10 : 1
        switch event.keyCode {
        case 123: selection = RegionGeometry.move(selection, dx: -distance, dy: 0, in: bounds)
        case 124: selection = RegionGeometry.move(selection, dx: distance, dy: 0, in: bounds)
        case 125: selection = RegionGeometry.move(selection, dx: 0, dy: -distance, in: bounds)
        case 126: selection = RegionGeometry.move(selection, dx: 0, dy: distance, in: bounds)
        default: super.keyDown(with: event)
        }
        needsDisplay = true
    }
    private func finish(_ rect: CGRect?) {
        let callback = completion; completion = nil; callback?(rect)
    }
}
