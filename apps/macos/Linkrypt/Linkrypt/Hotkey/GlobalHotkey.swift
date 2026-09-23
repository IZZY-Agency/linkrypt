import Carbon.HIToolbox
import AppKit

/// Registers a process-global ⌥⇧V hotkey via Carbon `RegisterEventHotKey`,
/// which needs no Accessibility / Input Monitoring permission. Calls `onFire`
/// on the main queue.
final class GlobalHotkey: @unchecked Sendable {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let onFire: @Sendable () -> Void
    /// Both Carbon calls succeeded. False = the shortcut is taken by another
    /// app or the handler couldn't be installed; ⌥⇧V will do nothing.
    private(set) var isRegistered = false

    init(onFire: @escaping @Sendable () -> Void) {
        self.onFire = onFire
        register()
    }

    private func register() {
        let hotKeyID = EventHotKeyID(signature: OSType(0x4C4B5256), id: 1) // 'LKRV'
        let mods = UInt32(optionKey | shiftKey)
        let hotKeyIDCopy = hotKeyID
        let registerStatus = RegisterEventHotKey(UInt32(kVK_ANSI_V), mods, hotKeyIDCopy, GetApplicationEventTarget(), 0, &ref)

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        let callback: EventHandlerUPP = { _, _, userData -> OSStatus in
            guard let userData else { return OSStatus(noErr) }
            let me = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
            let fire = me.onFire
            DispatchQueue.main.async { fire() }
            return OSStatus(noErr)
        }
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), callback, 1, &spec, ctx, &handler)
        isRegistered = registerStatus == noErr && handlerStatus == noErr
    }

    deinit {
        if let ref { UnregisterEventHotKey(ref) }
        if let handler { RemoveEventHandler(handler) }
    }
}
