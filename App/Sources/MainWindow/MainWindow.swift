// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import AppKit
import Observation
import SwiftUI

enum MainSection: String, CaseIterable, Identifiable {
    case home, history, dictionary, models, meetings, settings, privacy

    var id: Self { self }

    var title: String {
        switch self {
        case .home: "Home"
        case .history: "History"
        case .dictionary: "Dictionary"
        case .models: "Models"
        case .meetings: "Meetings"
        case .settings: "Settings"
        case .privacy: "Privacy"
        }
    }

    var subtitle: String {
        switch self {
        case .home: "Dictation is ready. Everything runs on this Mac."
        case .history: "Every dictation, in case insertion went to the wrong place."
        case .dictionary: "Words Whisper should spell right, and phrases that expand into longer text."
        case .models: "Speech recognition on this Mac."
        case .meetings: "Coming soon."
        case .settings: "Appearance, shortcuts, recording and how text gets into apps."
        case .privacy: "What is stored, for how long, and which permissions Typist has."
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .history: "clock.arrow.circlepath"
        case .dictionary: "character.book.closed"
        case .models: "square.stack.3d.up"
        case .meetings: "video"
        case .settings: "gearshape"
        case .privacy: "lock.shield"
        }
    }
}

/// Which page the main window shows, so the menu bar can open it at a given page.
@MainActor @Observable
final class MainWindowRouter {
    static let shared = MainWindowRouter()
    static let windowID = "main"

    var selection: MainSection = .home
}

/// The main window, drawn after the design mockup: no title bar, the window buttons sit in the
/// sidebar, and each page starts with its own large title.
struct MainWindowView: View {
    private var router: MainWindowRouter { .shared }
    private var palette: ThemePalette { AppSettings.shared.theme.palette }

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(router.selection.title).font(.system(size: 24, weight: .semibold))
                        Text(router.selection.subtitle)
                            .font(.system(size: 14))
                            .foregroundStyle(palette.secondaryText)
                    }
                    page(router.selection)
                }
                .padding(.horizontal, 44)
                .padding(.top, 36)
                .padding(.bottom, 48)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollContentBackground(.hidden)
            .background(palette.window)
        }
        .ignoresSafeArea()
        .foregroundStyle(palette.text)
        .environment(\.palette, palette)
        .tint(palette.accent)
        .preferredColorScheme(palette.scheme)
        .frame(minWidth: 860, minHeight: 600)
        .onAppear {
            // Show in the Dock and ⌘-Tab while the window is open.
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
        }
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    @ViewBuilder
    private func page(_ section: MainSection) -> some View {
        switch section {
        case .home: HomePage()
        case .history: HistoryPage()
        case .dictionary: DictionaryPage()
        case .models: ModelsPage()
        case .meetings: MeetingsPage()
        case .settings: SettingsPage()
        case .privacy: PrivacyPage()
        }
    }
}

private struct Sidebar: View {
    @Environment(\.palette) private var palette
    private var router: MainWindowRouter { .shared }
    private var dictation: DictationController { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Image(systemName: "waveform")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .frame(width: 30, height: 30)
                    .background(RoundedRectangle(cornerRadius: 8).fill(palette.card))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.border))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Typist").font(.system(size: 15, weight: .semibold))
                    Text(status).font(.system(size: 12)).foregroundStyle(palette.secondaryText)
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 18)

            ForEach(MainSection.allCases) { section in
                let selected = router.selection == section
                Button {
                    router.selection = section
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: section.systemImage)
                            .font(.system(size: 14))
                            .foregroundStyle(palette.accent)
                            .frame(width: 18)
                        Text(section.title)
                            .foregroundStyle(selected ? palette.text : palette.text.opacity(0.85))
                        Spacer()
                        if section == .meetings {
                            Text("Soon")
                                .font(.system(size: 11))
                                .foregroundStyle(palette.secondaryText)
                                .padding(.horizontal, 7)
                                .padding(.vertical, 1)
                                .background(Capsule().fill(palette.control))
                        }
                    }
                    .font(.system(size: 14))
                    .padding(.horizontal, 10)
                    .frame(height: 34)
                    .background(RoundedRectangle(cornerRadius: 8).fill(selected ? palette.selection : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }

            Spacer()
            Text("Version 0.1.0 · GPL-3.0")
                .font(.system(size: 12))
                .foregroundStyle(palette.secondaryText)
                .padding(.horizontal, 8)
        }
        // Room for the window buttons, which sit over the sidebar.
        .padding(.top, 50)
        .padding(.horizontal, 12)
        .padding(.bottom, 16)
        .frame(width: 220)
        .frame(maxHeight: .infinity)
        .background(palette.sidebar)
        .overlay(alignment: .trailing) { palette.border.frame(width: 1) }
    }

    private var status: String {
        switch dictation.modelStatus {
        case .ready: "Ready · on this Mac"
        case .downloading(let fraction): "Downloading \(Int(fraction * 100))%"
        case .loading, .idle: "Loading model…"
        case .failed: "Model failed"
        }
    }
}

enum SystemSettings {
    static func open(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    static func openKeyboard() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}
