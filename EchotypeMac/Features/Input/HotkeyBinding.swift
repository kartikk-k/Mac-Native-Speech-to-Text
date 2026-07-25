//
//  HotkeyBinding.swift
//  Echotype Mac
//
//  Created by Kartik Khorwal on 4/8/26.
//
//  The user-configurable hold-to-record hotkey. Two kinds:
//    • .fn        — the Globe/Fn key (default; hold-to-talk via flagsChanged).
//    • .key(code, modifiers) — any regular key with optional modifiers, held to
//      record (keyDown starts, keyUp stops). E.g. ⌥Space, Right-⌘, F13.
//
//  Stored in UserDefaults as a compact string so HotkeyMonitor and the Settings
//  capture UI agree on the binding.
//

import Foundation
import Carbon.HIToolbox
import AppKit

struct HotkeyBinding: Equatable {
    /// Fn/Globe uses modifier-hold semantics; a keyCode uses keyDown/keyUp hold.
    var isFn: Bool
    /// Virtual keycode of the trigger key (ignored when `isFn`).
    var keyCode: Int64
    /// Required modifier flags (device-independent), e.g. .option. Empty allowed.
    var modifiers: CGEventFlags

    static let fn = HotkeyBinding(isFn: true, keyCode: 0, modifiers: [])

    // MARK: - Display

    /// Human-readable label, e.g. "Fn (Globe)", "⌥ Space", "Right ⌘".
    var displayName: String {
        if isFn { return "Fn (Globe)" }
        let mods = HotkeyBinding.modifierSymbols(modifiers)
        let key = HotkeyBinding.keyName(for: keyCode)
        return mods.isEmpty ? key : "\(mods) \(key)"
    }

    // MARK: - Persistence (compact string: "fn"  or  "key:<code>:<rawflags>")

    var storageString: String {
        if isFn { return "fn" }
        return "key:\(keyCode):\(modifiers.rawValue)"
    }

    init(isFn: Bool, keyCode: Int64, modifiers: CGEventFlags) {
        self.isFn = isFn
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init?(storage: String) {
        if storage == "fn" { self = .fn; return }
        let parts = storage.split(separator: ":")
        guard parts.count == 3, parts[0] == "key",
              let code = Int64(parts[1]), let raw = UInt64(parts[2]) else { return nil }
        self = HotkeyBinding(isFn: false, keyCode: code, modifiers: CGEventFlags(rawValue: raw))
    }

    // MARK: - Helpers

    /// Only the modifier flags we care about (ignore caps lock, numeric pad, etc).
    static let relevantModifiers: CGEventFlags = [.maskCommand, .maskShift, .maskAlternate, .maskControl]

    static func modifierSymbols(_ flags: CGEventFlags) -> String {
        var s = ""
        if flags.contains(.maskControl) { s += "⌃" }
        if flags.contains(.maskAlternate) { s += "⌥" }
        if flags.contains(.maskShift) { s += "⇧" }
        if flags.contains(.maskCommand) { s += "⌘" }
        return s
    }

    static func keyName(for keyCode: Int64) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "Return"
        case kVK_Tab: return "Tab"
        case kVK_Escape: return "Esc"
        case kVK_F1: return "F1"; case kVK_F2: return "F2"; case kVK_F3: return "F3"
        case kVK_F4: return "F4"; case kVK_F5: return "F5"; case kVK_F6: return "F6"
        case kVK_F7: return "F7"; case kVK_F8: return "F8"; case kVK_F9: return "F9"
        case kVK_F10: return "F10"; case kVK_F11: return "F11"; case kVK_F12: return "F12"
        case kVK_F13: return "F13"; case kVK_F14: return "F14"; case kVK_F15: return "F15"
        case kVK_ANSI_Grave: return "`"
        default:
            // Try to map to the printed character for letter/number keys.
            if let ch = HotkeyBinding.character(for: keyCode) { return ch.uppercased() }
            return "Key \(keyCode)"
        }
    }

    /// Best-effort character for a keycode using the current keyboard layout.
    private static func character(for keyCode: Int64) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = unsafeBitCast(layoutData, to: CFData.self)
        let keyLayout = unsafeBitCast(CFDataGetBytePtr(data), to: UnsafePointer<UCKeyboardLayout>.self)
        var deadKeys: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let err = UCKeyTranslate(keyLayout, UInt16(keyCode), UInt16(kUCKeyActionDisplay), 0,
                                 UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysBit),
                                 &deadKeys, chars.count, &length, &chars)
        guard err == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length)
    }
}
