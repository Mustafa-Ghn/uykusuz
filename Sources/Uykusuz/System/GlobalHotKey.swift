import Carbon.HIToolbox
import Foundation

/// One system-wide shortcut (fork addition). The system tells the app when
/// this one combination is pressed and sees to the rest, so no other key
/// reaches the app and no permission is asked. It is registered as exclusive,
/// so an app holding the combination the same way makes the registration fail.
/// macOS says nothing of an app holding it any other way: both then hear it.
@MainActor
final class GlobalHotKey {
    var onPress: (@MainActor () -> Void)?
    /// Every shortcut's handler is told of every press in the app, so each
    /// knows its own by this.
    let hotKeyID: EventHotKeyID

    private static var lastID: UInt32 = 0
    private let keyCode: UInt32
    private let modifiers: UInt32
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?

    /// `keyCode` a `kVK_` constant, `modifiers` Carbon's (`controlKey`, ...).
    init(keyCode: Int, modifiers: Int) {
        self.keyCode = UInt32(keyCode)
        self.modifiers = UInt32(modifiers)
        Self.lastID += 1
        hotKeyID = EventHotKeyID(signature: 0x55796B7A, id: Self.lastID)
    }

    /// The handler holds this object without retaining it.
    isolated deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
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
        let status = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), OptionBits(kEventHotKeyExclusive), &ref)
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
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var read = EventHotKeyID()
            guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &read) == noErr else {
                return OSStatus(eventNotHandledErr)
            }
            let id = read
            let me = Unmanaged<GlobalHotKey>.fromOpaque(context).takeUnretainedValue()
            // The application event target runs on the main thread.
            return MainActor.assumeIsolated {
                // Not this one: the next handler is the one it is for.
                guard id.signature == me.hotKeyID.signature, id.id == me.hotKeyID.id else { return OSStatus(eventNotHandledErr) }
                me.onPress?()
                return noErr
            }
        }, 1, &pressed, Unmanaged.passUnretained(self).toOpaque(), &handler)
        guard status == noErr else {
            Log.error("hot key: could not install its handler (status \(status))")
            return false
        }
        return true
    }
}
