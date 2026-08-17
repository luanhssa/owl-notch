import Carbon.HIToolbox
import Foundation

/// A single, fixed global keyboard shortcut (⌥⌘O) that fires from anywhere,
/// even when Owl isn't the frontmost app (GH issue #44) — used to
/// toggle/summon the notch panel on demand instead of only reacting to
/// state changes or a direct click.
///
/// Uses the Carbon Hot Key API rather than an `NSEvent` global monitor: it
/// registers a real system-wide hotkey rather than just observing every
/// keystroke, so it doesn't need Input Monitoring/Accessibility
/// permission — keeping Owl's permission footprint as small as everywhere
/// else in the app.
///
/// Fixed for now, not yet configurable — the issue that introduced this
/// asks for a configurable shortcut, but there's nowhere to configure it
/// until the Preferences window (#34) exists. Worth revisiting then.
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let onPress: () -> Void

    /// ⌥⌘O — "O" for Owl, and Option+Command combinations are rarely
    /// claimed by macOS itself or by common apps, keeping collision risk low.
    private static let keyCode = UInt32(kVK_ANSI_O)
    private static let modifiers = UInt32(optionKey | cmdKey)
    private static let hotKeyID = EventHotKeyID(signature: OSType(0x4F776C48), id: 1) // 'OwlH'

    init(onPress: @escaping () -> Void) {
        self.onPress = onPress
        register()
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
    }

    private func register() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, event, userData -> OSStatus in
                guard let userData, let event else { return OSStatus(eventNotHandledErr) }
                var receivedID = EventHotKeyID()
                let status = GetEventParameter(
                    event,
                    EventParamName(kEventParamDirectObject),
                    EventParamType(typeEventHotKeyID),
                    nil,
                    MemoryLayout<EventHotKeyID>.size,
                    nil,
                    &receivedID
                )
                guard status == noErr, receivedID.id == GlobalHotKey.hotKeyID.id else {
                    return OSStatus(eventNotHandledErr)
                }
                Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue().onPress()
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandlerRef
        )

        let status = RegisterEventHotKey(Self.keyCode, Self.modifiers, Self.hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if status != noErr {
            NSLog("Owl: failed to register global hotkey (status \(status)) — ⌥⌘O may already be claimed by another app")
        }
    }
}
