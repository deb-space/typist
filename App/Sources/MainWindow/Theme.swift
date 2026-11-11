// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import AppKit
import SwiftUI

/// Every color the main window paints with, per theme.
struct ThemePalette {
    let scheme: ColorScheme
    let window: Color
    let sidebar: Color
    let card: Color
    let border: Color
    let input: Color
    let inputBorder: Color
    let control: Color
    let controlBorder: Color
    let text: Color
    let secondaryText: Color
    let selection: Color
    /// Icons, toggles, the selection ring and primary buttons.
    let accent: Color
    /// Text on a light accent tint, such as an "In use" chip.
    let accentText: Color
    /// Text on a solid accent background.
    let onAccent: Color
    /// Something leaves this Mac, or needs a look.
    let outside: Color
    let danger: Color
    let keycap: Color
    let keycapText: Color
    let keycapShadow: Color

    /// Neutral grays, close to the system's dark appearance.
    static let dark = ThemePalette(
        scheme: .dark, window: Color(white: 0.118), sidebar: Color(white: 0.09), card: Color(white: 0.16),
        border: Color(white: 0.22), input: Color(white: 0.09), inputBorder: Color(white: 0.27),
        control: Color(white: 0.21), controlBorder: Color(white: 0.30), text: Color(white: 0.92),
        secondaryText: Color(white: 0.66), selection: Color.white.opacity(0.10), accent: Color(hex: 0x9DB1FF),
        accentText: Color(hex: 0xC3CFFF), onAccent: Color(hex: 0x121622), outside: Color(hex: 0xE0B062),
        danger: Color(hex: 0xF2A091), keycap: Color(white: 0.25), keycapText: Color(white: 0.92),
        keycapShadow: Color(white: 0.05))

    /// Ink-navy surfaces from the deb.space palette.
    static let darkBlue = ThemePalette(
        scheme: .dark, window: Color(hex: 0x161C2B), sidebar: Color(hex: 0x121622), card: Color(hex: 0x1D2436),
        border: Color(hex: 0x262F45), input: Color(hex: 0x121622), inputBorder: Color(hex: 0x2E3852),
        control: Color(hex: 0x232B3F), controlBorder: Color(hex: 0x323C56), text: Color(hex: 0xE8EBF2),
        secondaryText: Color(hex: 0xA3ACBD), selection: Color(hex: 0x9DB1FF).opacity(0.14),
        accent: Color(hex: 0x9DB1FF), accentText: Color(hex: 0xC3CFFF), onAccent: Color(hex: 0x121622),
        outside: Color(hex: 0xE0B062), danger: Color(hex: 0xF2A091), keycap: Color(hex: 0x2A3350),
        keycapText: Color(hex: 0xE8EBF2), keycapShadow: Color(hex: 0x0E1220))

    /// Light surfaces with the same blue family; accents are deeper so they read on white.
    static let light = ThemePalette(
        scheme: .light, window: Color(hex: 0xF5F6F9), sidebar: Color(hex: 0xECEEF3), card: Color(hex: 0xFFFFFF),
        border: Color(hex: 0xE2E5EC), input: Color(hex: 0xFFFFFF), inputBorder: Color(hex: 0xCDD3DF),
        control: Color(hex: 0xF0F2F6), controlBorder: Color(hex: 0xD3D8E2), text: Color(hex: 0x1D2330),
        secondaryText: Color(hex: 0x5A6375), selection: Color(hex: 0x3D57C9).opacity(0.10),
        accent: Color(hex: 0x3D57C9), accentText: Color(hex: 0x2E46B0), onAccent: .white,
        outside: Color(hex: 0xB7791F), danger: Color(hex: 0xB83A26), keycap: .white,
        keycapText: Color(hex: 0x1D2330), keycapShadow: Color(hex: 0xC7CDD8))
}

extension AppSettings.Theme {
    var palette: ThemePalette {
        switch self {
        case .dark: .dark
        case .darkBlue: .darkBlue
        case .light: .light
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = ThemePalette.dark
}

extension EnvironmentValues {
    var palette: ThemePalette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}
