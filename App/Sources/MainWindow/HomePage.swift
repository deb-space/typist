// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import SwiftUI

struct HomePage: View {
    @Environment(\.palette) private var palette
    @Bindable private var settings = AppSettings.shared
    private var dictation: DictationController { .shared }
    private var hotkey: HotkeyController { .shared }
    private var history: DictationHistory { .shared }
    @State private var tryIt = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            statusCard
            VStack(alignment: .leading, spacing: 8) {
                Text("Try it here")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.secondaryText)
                TextEditor(text: $tryIt)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .frame(height: 80)
                    .background(RoundedRectangle(cornerRadius: 10).fill(palette.input))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(palette.inputBorder))
                    .accessibilityLabel("Try dictation here")
            }
            if showsGlobeTip { globeTip }
            recent
        }
    }

    private var statusCard: some View {
        HStack(alignment: .center, spacing: 24) {
            Image(systemName: "mic")
                .font(.system(size: 24, weight: .medium))
                .foregroundStyle(Color.typistAccent)
                .frame(width: 56, height: 56)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.typistAccent.opacity(0.14)))
            VStack(alignment: .leading, spacing: 8) {
                Text(headline).font(.system(size: 18, weight: .semibold))
                HStack(spacing: 6) {
                    Text("Hold")
                    Keycap("fn")
                    Text("in any app and speak, release to insert.")
                }
                HStack(spacing: 6) {
                    Text("For long dictation press")
                    Keycap("fn")
                    Text("+")
                    Keycap("Space")
                }
                Text(dictation.modelStatusText + " · runs on this Mac · nothing leaves it")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondaryText)
                if !hotkey.isRunning {
                    Button("Enable the fn Shortcut…") { hotkey.enable() }
                        .buttonStyle(.themed)
                }
            }
            .font(.system(size: 14))
            .foregroundStyle(palette.text.opacity(0.9))
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(radius: 14)
    }

    private var headline: String {
        switch dictation.modelStatus {
        case .ready: hotkey.isRunning ? "Ready to dictate" : "The fn shortcut needs permission"
        case .downloading(let fraction): "Downloading the speech model… \(Int(fraction * 100))%"
        case .loading, .idle: "Loading the speech model…"
        case .failed: "The speech model failed to load"
        }
    }

    /// macOS runs the globe key action on a tap of fn. It is "Change Input Source" unless set otherwise.
    private var showsGlobeTip: Bool {
        guard !settings.dismissedGlobeTip else { return false }
        let usage = UserDefaults(suiteName: "com.apple.HIToolbox")?.object(forKey: "AppleFnUsageType") as? Int
        return usage != 0
    }

    private var globeTip: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: "globe").foregroundStyle(Color.typistOutside).padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                Text("A quick tap on fn switches your keyboard layout").font(.system(size: 14, weight: .semibold))
                Text(
                    "That is the globe key setting in macOS, and Typist leaves taps alone, so dictation works as is. If you would rather use a double press for hands-free, set the globe key to “Do Nothing”."
                )
                .font(.system(size: 13))
                .foregroundStyle(palette.text.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Button("Open Keyboard Settings") { SystemSettings.openKeyboard() }
                        .buttonStyle(.themed)
                    Button("Got It") { settings.dismissedGlobeTip = true }
                        .buttonStyle(.themedQuiet)
                }
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.typistOutside.opacity(0.10)))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.typistOutside.opacity(0.35)))
    }

    private var recent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Recent")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.secondaryText)
                Spacer()
                Button("Show All") { MainWindowRouter.shared.selection = .history }
                    .buttonStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(Color.typistAccent)
            }
            VStack(spacing: 0) {
                if history.entries.isEmpty {
                    Text("Nothing dictated yet.")
                        .foregroundStyle(palette.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 22)
                } else {
                    let entries = Array(history.entries.prefix(3))
                    ForEach(entries) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 16) {
                            Text(entry.date, format: .relative(presentation: .named))
                                .font(.system(size: 12))
                                .foregroundStyle(palette.secondaryText)
                                .frame(width: 110, alignment: .leading)
                            Text(entry.text)
                                .font(.system(size: 14))
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .overlay(alignment: .bottom) {
                            if entry.id != entries.last?.id { palette.border.frame(height: 1) }
                        }
                    }
                }
            }
            .card()
        }
    }
}

struct MeetingsPage: View {
    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Meeting notes are on the way").font(.system(size: 17, weight: .semibold))
            Text("Typist will record your calls without a bot joining them, on this Mac.")
                .foregroundStyle(palette.text.opacity(0.85))
            VStack(alignment: .leading, spacing: 10) {
                Text("· Two tracks, you and everyone else, from Zoom, Meet, Teams and FaceTime")
                Text("· Speaker names that it remembers from one meeting to the next")
                Text("· Summary, decisions and action items, with the audio kept to check any line")
            }
            .foregroundStyle(palette.text.opacity(0.85))
            Text("Recording both sides is already tested; transcription and speakers are next.")
                .font(.system(size: 13))
                .foregroundStyle(palette.secondaryText)
        }
        .font(.system(size: 14))
        .padding(28)
        .frame(maxWidth: 640, alignment: .leading)
        .card(radius: 14)
    }
}
