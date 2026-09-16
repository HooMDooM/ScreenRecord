import AppKit
import Carbon.HIToolbox

struct Shortcut: Equatable {
    var keyCode: Int
    var modifiers: NSEvent.ModifierFlags

    var carbonModifiers: UInt32 {
        var value: UInt32 = 0
        if modifiers.contains(.command) { value |= UInt32(cmdKey) }
        if modifiers.contains(.shift) { value |= UInt32(shiftKey) }
        if modifiers.contains(.option) { value |= UInt32(optionKey) }
        if modifiers.contains(.control) { value |= UInt32(controlKey) }
        return value
    }

    var isValid: Bool {
        !modifiers.intersection([.command, .control, .option]).isEmpty
    }

    var display: String {
        var text = ""
        if modifiers.contains(.control) { text += "⌃" }
        if modifiers.contains(.option) { text += "⌥" }
        if modifiers.contains(.shift) { text += "⇧" }
        if modifiers.contains(.command) { text += "⌘" }
        return text + Shortcut.name(for: keyCode)
    }

    static func name(for keyCode: Int) -> String {
        if let special = specialNames[keyCode] { return special }
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else {
            return "?"
        }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        var deadKeyState: UInt32 = 0
        var length = 0
        var characters = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return OSStatus(paramErr)
            }
            return UCKeyTranslate(layout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                                  UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeyState, characters.count, &length, &characters)
        }
        guard status == noErr, length > 0 else { return "?" }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }

    private static let specialNames: [Int: String] = [
        kVK_Space: "Space", kVK_Return: "⏎", kVK_Tab: "⇥", kVK_Escape: "esc",
        kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3",
        kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8",
        kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"
    ]
}

/// Registers the global shortcuts and re-registers them when the user edits one.
@MainActor
final class HotKeyManager {
    static let shared = HotKeyManager()

    enum Action: UInt32 {
        case record = 1
        case screenshot = 2
    }

    var onTrigger: ((Action) -> Void)?

    private var refs: [UInt32: EventHotKeyRef] = [:]
    private var handlerInstalled = false

    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
            var hotKeyID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                              nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
            let raw = hotKeyID.id
            DispatchQueue.main.async {
                guard let action = Action(rawValue: raw) else { return }
                HotKeyManager.shared.onTrigger?(action)
            }
            return noErr
        }, 1, &eventType, nil, nil)
    }

    func apply(_ shortcut: Shortcut, to action: Action) {
        installHandler()
        unregister(action)
        guard shortcut.isValid else { return }
        var ref: EventHotKeyRef?
        let identifier = EventHotKeyID(signature: OSType(0x53524543), id: action.rawValue) // 'SREC'
        let status = RegisterEventHotKey(UInt32(shortcut.keyCode), shortcut.carbonModifiers,
                                         identifier, GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref {
            refs[action.rawValue] = ref
        }
    }

    func unregister(_ action: Action) {
        if let ref = refs.removeValue(forKey: action.rawValue) {
            UnregisterEventHotKey(ref)
        }
    }
}
