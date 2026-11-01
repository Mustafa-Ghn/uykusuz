import Carbon.HIToolbox
import Foundation

/// One system-wide shortcut (fork addition). The system tells the app when
/// this one combination is pressed and sees to the rest, so no other key
/// reaches the app and no permission is asked. Another app holding the
/// combination is a registration that fails.
@MainActor
final class GlobalHotKey {
    var onPress: (@MainActor () -> Void)?

    private let keyCode: UInt32
    private let modifiers: UInt32
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    /// `keyCode` a `kVK_` constant, `modifiers` Carbon's (`controlKey`, ...).
    init(keyCode: Int, modifiers: Int) {
        self.keyCode = UInt32(keyCode)
        self.modifiers = UInt32(modifiers)
    }

    /// Whether it now is as asked: off always, on unless it could not be had.
    func set(_ on: Bool) -> Bool {
        guard on else {
            if let hotKey { UnregisterEventHotKey(hotKey) }
            hotKey = nil
            return true
        }
        guard hotKey == nil else { return true }
        guard installHandler() else { return false }
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(keyCode, modifiers, EventHotKeyID(signature: 0x55796B7A, id: 1), GetApplicationEventTarget(), 0, &ref)
        guard status == noErr, let ref else {
            Log.error("hot key: could not register it (status \(status))")
            return false
        }
        hotKey = ref
        return true
    }

    private func installHandler() -> Bool {
        guard handler == nil else { return true }
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return noErr }
            let me = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
            // The application event target runs on the main thread.
            MainActor.assumeIsolated { me.onPress?() }
            return noErr
        }, 1, &pressed, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else {
            Log.error("hot key: could not install its handler (status \(status))")
            return false
        }
        return true
    }
}
