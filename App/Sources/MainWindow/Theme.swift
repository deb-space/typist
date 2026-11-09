// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import AppKit
import SwiftUI

/// Every color the main window paints with, per theme.
struct ThemePalette {
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

    /// Neutral grays, close to the system's dark appearance.
    static let dark = ThemePalette(
        window: Color(white: 0.118), sidebar: Color(white: 0.09), card: Color(white: 0.16), border: Color(white: 0.22),
        input: Color(white: 0.09), inputBorder: Color(white: 0.27), control: Color(white: 0.21),
        controlBorder: Color(white: 0.30), text: Color(white: 0.92), secondaryText: Color(white: 0.66),
        selection: Color.white.opacity(0.10))

    /// Ink-navy surfaces from the deb.space palette.
    static let darkBlue = ThemePalette(
        window: Color(hex: 0x161C2B), sidebar: Color(hex: 0x121622), card: Color(hex: 0x1D2436),
        border: Color(hex: 0x262F45), input: Color(hex: 0x121622), inputBorder: Color(hex: 0x2E3852),
        control: Color(hex: 0x232B3F), controlBorder: Color(hex: 0x323C56), text: Color(hex: 0xE8EBF2),
        secondaryText: Color(hex: 0xA3ACBD), selection: Color(hex: 0x9DB1FF).opacity(0.14))
}

extension AppSettings.Theme {
    var palette: ThemePalette { self == .dark ? .dark : .darkBlue }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }

    /// Audio is moving; also the selection and toggle color.
    static let typistAccent = Color(hex: 0x9DB1FF)
    /// Audio or text leaves this Mac.
    static let typistOutside = Color(hex: 0xE0B062)
    static let typistDanger = Color(hex: 0xF2A091)
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
