// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import Carbon.HIToolbox
import CoreGraphics

/// Finds which physical key produces a character in the current keyboard layout.
///
/// Virtual key codes are positions on an ANSI keyboard: code 9 is V only in QWERTY. In Dvorak
/// it is the period, so posting "⌘ + key 9" sends ⌘. (interrupt in a terminal) instead of ⌘V.
public enum KeyboardLayout {
    /// The key that produces `character` while Command is held, which is how apps match
    /// shortcuts. Layouts like "Dvorak – QWERTY ⌘" switch to QWERTY under Command, and
    /// non-Latin layouts such as Russian define their own Command mapping; both are covered.
    public static func keyCode(forShortcut character: Character) -> CGKeyCode? {
        keyCode(for: character, modifierState: UInt32(cmdKey >> 8))
    }

    public static func keyCode(for character: Character, modifierState: UInt32 = 0) -> CGKeyCode? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue()
        guard let bytes = CFDataGetBytePtr(data) else { return nil }
        let layout = UnsafeRawPointer(bytes).assumingMemoryBound(to: UCKeyboardLayout.self)
        let target = String(character).lowercased()

        for code in 0..<128 {
            var deadKeyState: UInt32 = 0
            var length = 0
            var characters = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(
                layout, UInt16(code), UInt16(kUCKeyActionDown), modifierState, UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeyState, characters.count, &length, &characters)
            if status == noErr, length > 0,
                String(utf16CodeUnits: characters, count: length).lowercased() == target
            {
                return CGKeyCode(code)
            }
        }
        return nil
    }

    /// Makes an enabled keyboard layout current. Returns the previous layout's ID, to restore it.
    @discardableResult
    public static func select(_ id: String) -> String? {
        let previous = currentLayoutID
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let sources = TISCreateInputSourceList(filter, false)?.takeRetainedValue() as? [TISInputSource],
            let source = sources.first
        else { return nil }
        TISSelectInputSource(source)
        return previous
    }

    /// The current layout's identifier, such as `com.apple.keylayout.Dvorak`.
    public static var currentLayoutID: String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let pointer = TISGetInputSourceProperty(source, kTISPropertyInputSourceID)
        else { return nil }
        return Unmanaged<CFString>.fromOpaque(pointer).takeUnretainedValue() as String
    }
}
