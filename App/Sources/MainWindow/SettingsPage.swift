// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import SwiftUI

struct SettingsPage: View {
    @Environment(\.palette) private var palette
    @Bindable private var settings = AppSettings.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            CardSection("Appearance") {
                HStack(spacing: 16) {
                    ForEach(AppSettings.Theme.allCases) { theme in
                        ThemeOption(theme: theme, isSelected: settings.theme == theme) {
                            settings.theme = theme
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 16)
            }

            CardSection("Shortcuts") {
                CardRow("Hold to talk", "Recording starts on press, so the first word is kept") {
                    Keycap("fn")
                }
                CardRow("Hands-free", "Also works while holding fn; press fn again to stop") {
                    HStack(spacing: 6) {
                        Keycap("fn")
                        Text("+").foregroundStyle(palette.secondaryText)
                        Keycap("Space")
                    }
                }
                CardRow("Cancel", "Only while recording; otherwise esc goes to the app", divider: false) {
                    Keycap("esc")
                }
            }

            CardSection("Recording") {
                CardRow("Stop hands-free after silence", "Paused while the microphone switches devices") {
                    HStack(spacing: 12) {
                        Slider(value: $settings.autostopSeconds, in: 2...15, step: 1)
                            .frame(width: 200)
                            .accessibilityLabel("Seconds of silence")
                        Text("\(Int(settings.autostopSeconds)) s")
                            .monospacedDigit()
                            .frame(width: 34, alignment: .trailing)
                    }
                }
                CardRow(
                    "Microphone",
                    "Choosing a microphone comes later. Switching to AirPods mid-sentence loses about 5 seconds"
                ) {
                    Text("Follows the system input").foregroundStyle(palette.secondaryText)
                }
                CardRow("Language", "Detection handles Russian, English and both in one sentence", divider: false) {
                    ThemedMenu(
                        options: AppSettings.languages.map { ($0.code, $0.name) }, selection: $settings.language,
                        label: "Language")
                }
            }

            CardSection("Inserting text") {
                CardRow(
                    "Restore the clipboard after pasting",
                    "Typist pastes with ⌘V and puts back what was on your clipboard"
                ) {
                    ThemedToggle(label: "Restore the clipboard after pasting", isOn: $settings.restoreClipboard)
                }
                CardRow("Password fields", "macOS blocks typing there", divider: false) {
                    Text("Copied instead").foregroundStyle(palette.secondaryText)
                }
            }

            CardSection("Overlay") {
                CardRow("Position") {
                    ThemedSegments(
                        options: AppSettings.OverlayPosition.allCases.map { ($0, $0.title) },
                        selection: $settings.overlayPosition)
                }
                CardRow("Show hints", "The line under the capsule") {
                    ThemedToggle(label: "Show hints", isOn: $settings.showHints)
                }
                CardRow("Sounds on start and finish", divider: false) {
                    ThemedToggle(label: "Sounds on start and finish", isOn: $settings.playSounds)
                }
            }
        }
    }
}

/// A clickable miniature of the window in a theme.
private struct ThemeOption: View {
    @Environment(\.palette) private var current
    let theme: AppSettings.Theme
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        let palette = theme.palette
        Button(action: select) {
            VStack(spacing: 8) {
                HStack(spacing: 0) {
                    palette.sidebar
                        .frame(width: 44)
                        .overlay(alignment: .top) {
                            VStack(spacing: 5) {
                                ForEach(0..<4, id: \.self) { index in
                                    Capsule()
                                        .fill(index == 0 ? palette.accent.opacity(0.5) : palette.text.opacity(0.18))
                                        .frame(height: 5)
                                }
                            }
                            .padding(8)
                        }
                    palette.window.overlay(alignment: .topLeading) {
                        VStack(alignment: .leading, spacing: 6) {
                            RoundedRectangle(cornerRadius: 4).fill(palette.card).frame(height: 26)
                            RoundedRectangle(cornerRadius: 4).fill(palette.card).frame(height: 16)
                            RoundedRectangle(cornerRadius: 4).fill(palette.card).frame(width: 60, height: 16)
                        }
                        .padding(8)
                    }
                }
                .frame(width: 168, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(
                            isSelected ? current.accent : current.controlBorder, lineWidth: isSelected ? 2 : 1))
                Text(theme.title)
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? current.text : current.secondaryText)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(theme.title) theme")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
