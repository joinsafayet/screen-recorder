import AppKit
import CoreGraphics
import Carbon

struct PresentationCapture: Codable {
    var pointers: [PointerSample]
    var shortcuts: [ShortcutSample]
}
enum ShortcutFormatter {
    static func label(code: UInt16, flags: CGEventFlags) -> String? {
        guard flags.contains(.maskCommand) || flags.contains(.maskControl) || flags.contains(.maskAlternate) else { return nil }
        let keys: [UInt16: String] = [0:"A",1:"S",2:"D",3:"F",4:"H",5:"G",6:"Z",7:"X",8:"C",9:"V",11:"B",12:"Q",13:"W",14:"E",15:"R",16:"Y",17:"T",18:"1",19:"2",20:"3",21:"4",22:"6",23:"5",24:"=",25:"9",26:"7",27:"−",28:"8",29:"0",30:"]",31:"O",32:"U",33:"[",34:"I",35:"P",36:"↩",37:"L",38:"J",40:"K",45:"N",46:"M",48:"⇥",49:"Space",51:"⌫",53:"Esc",123:"←",124:"→",125:"↓",126:"↑"]
        guard let key = keys[code] else { return nil }
        return (flags.contains(.maskControl) ? "⌃" : "") + (flags.contains(.maskAlternate) ? "⌥" : "") + (flags.contains(.maskShift) ? "⇧" : "") + (flags.contains(.maskCommand) ? "⌘" : "") + " " + key
    }
}
@MainActor final class PresentationSession {
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var clock: (() -> Double)?
    private var pointers: [PointerSample] = []
    private var shortcuts: [ShortcutSample] = []
    static func checkPermission(enabled: Bool) throws {
        guard enabled else { return }
        if !CGPreflightListenEventAccess() {
            _ = CGRequestListenEventAccess()
            throw PrismError.message("Allow Prism in System Settings → Privacy & Security → Input Monitoring, then reopen Prism to display keyboard shortcuts.")
        }
    }
    func start(keys: Bool, clock: @escaping () -> Double) throws {
        _ = stop(); self.clock = clock
        guard keys else { return }
        let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue), callback: { _, type, event, user in
                guard type == .keyDown, !IsSecureEventInputEnabled(), let user,
                      let label = ShortcutFormatter.label(code: UInt16(event.getIntegerValueField(.keyboardEventKeycode)), flags: event.flags) else { return Unmanaged.passUnretained(event) }
                let session = Unmanaged<PresentationSession>.fromOpaque(user).takeUnretainedValue()
                Task { @MainActor in session.appendShortcut(label) }
                return Unmanaged.passUnretained(event)
            }, userInfo: Unmanaged.passUnretained(self).toOpaque())
        guard let port else { throw PrismError.message("Keyboard shortcut monitoring is unavailable. Check Input Monitoring permission.") }
        tap = port; source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }; CGEvent.tapEnable(tap: port, enable: true)
    }
    private func appendShortcut(_ text: String) {
        guard let clock, shortcuts.count < 10_000 else { return }
        let time = clock()
        guard time >= 0 else { return }
        if let last = shortcuts.last, last.text == text, time - last.time < 0.25 { return }
        shortcuts.append(ShortcutSample(time: time, text: text))
    }
    func samplePointer(time: Double, bounds: CGRect) {
        guard clock != nil, pointers.count < 100_000, bounds.width > 0, bounds.height > 0 else { return }
        let mouse = NSEvent.mouseLocation
        let point = CGPoint(x: mouse.x, y: CGDisplayBounds(CGMainDisplayID()).height - mouse.y)
        guard bounds.contains(point) else { return }
        let x = Double((point.x - bounds.minX) / bounds.width), y = Double((point.y - bounds.minY) / bounds.height)
        pointers.append(PointerSample(time: time, x: x, y: y))
    }
    var snapshot: PresentationCapture { PresentationCapture(pointers: pointers, shortcuts: shortcuts) }
    @discardableResult func stop() -> PresentationCapture {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }; source = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }; tap = nil
        clock = nil; let result = snapshot; pointers = []; shortcuts = []; return result
    }
}
