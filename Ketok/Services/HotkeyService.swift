import Foundation
import Carbon
import Combine

/// Manages global keyboard shortcuts
class HotkeyService: ObservableObject {
    static let shared = HotkeyService()

    @Published var isEnabled: Bool = false {
        didSet {
            if isEnabled { registerHotkey() } else { unregisterHotkey() }
            UserDefaults.standard.set(isEnabled, forKey: "com.ketok.hotkey.enabled")
        }
    }

    var onBuildTriggered: (() -> Void)?

    private var eventHandler: EventHandlerRef?
    private var hotkeyRef: EventHotKeyRef?
    private let hotkeyID = EventHotKeyID(signature: OSType(0x4150_4B42), id: 1) // "APKB"

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: "com.ketok.hotkey.enabled")
        if isEnabled { registerHotkey() }
    }

    /// Register Cmd+Shift+B as a global hotkey
    private func registerHotkey() {
        guard eventHandler == nil else { return }

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        // Install handler
        let status = InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, event, _) -> OSStatus in
                HotkeyService.shared.onBuildTriggered?()
                return noErr
            },
            1,
            &eventType,
            nil,
            &eventHandler
        )

        guard status == noErr else { return }

        // Register Cmd+Shift+B (keycode 11 = B)
        var id = hotkeyID
        RegisterEventHotKey(
            UInt32(kVK_ANSI_B),
            UInt32(cmdKey | shiftKey),
            id,
            GetApplicationEventTarget(),
            0,
            &hotkeyRef
        )
    }

    private func unregisterHotkey() {
        if let ref = hotkeyRef {
            UnregisterEventHotKey(ref)
            hotkeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    deinit {
        unregisterHotkey()
    }
}
