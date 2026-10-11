import Carbon
import Foundation

/// Carbon hot keys work across applications without Accessibility permission or event taps.
final class GlobalHotkeys {
    private var handler: EventHandlerRef?
    private var keys: [EventHotKeyRef] = []
    var action: ((UInt32) -> Void)?
    @discardableResult func register() -> Bool {
        unregister()
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let result = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var id = EventHotKeyID()
            let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                                           MemoryLayout<EventHotKeyID>.size, nil, &id)
            guard status == noErr else { return status }
            Unmanaged<GlobalHotkeys>.fromOpaque(context).takeUnretainedValue().action?(id.id)
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard result == noErr else { return false }
        for (index, code) in [kVK_ANSI_R, kVK_ANSI_P, kVK_ANSI_M].enumerated() {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: 0x5052534D, id: UInt32(index + 1))
            guard RegisterEventHotKey(UInt32(code), UInt32(cmdKey | controlKey), id, GetApplicationEventTarget(), 0, &ref) == noErr, let ref else {
                unregister(); return false
            }
            keys.append(ref)
        }
        return true
    }
    func unregister() {
        keys.forEach { UnregisterEventHotKey($0) }; keys.removeAll()
        if let handler { RemoveEventHandler(handler) }; handler = nil
    }
    deinit { unregister() }
}
