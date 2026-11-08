// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import AppKit
import SwiftUI

enum OverlayPalette {
    static let base = Color(red: 0x12 / 255, green: 0x16 / 255, blue: 0x22 / 255)
    static let text = Color(red: 0xE8 / 255, green: 0xEB / 255, blue: 0xF2 / 255)
    static let secondary = Color(red: 0xC9 / 255, green: 0xCF / 255, blue: 0xDB / 255)
    /// Audio is moving.
    static let accent = Color(red: 0x9D / 255, green: 0xB1 / 255, blue: 0xFF / 255)
    /// Audio or text leaves the Mac.
    static let outside = Color(red: 0xE0 / 255, green: 0xB0 / 255, blue: 0x62 / 255)
    static let problem = Color(red: 0xF2 / 255, green: 0xA0 / 255, blue: 0x91 / 255)
}

/// The dictation capsule and its hint line, bottom-aligned in the overlay panel.
struct OverlayView: View {
    let model: OverlayModel

    var body: some View {
        VStack(spacing: 8) {
            if model.phase != .hidden {
                capsule
                if model.showsHints, let hint = model.hint {
                    Text(hint)
                        .font(.system(size: 12))
                        .foregroundStyle(OverlayPalette.text)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(OverlayPalette.base.opacity(0.72), in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        // Room for the capsule's shadow, which the panel edge would clip.
        .padding(.bottom, 24)
        .animation(.easeOut(duration: 0.18), value: model.phase)
    }

    private var capsule: some View {
        HStack(spacing: 8) {
            content
        }
        .padding(.horizontal, 14)
        .frame(minWidth: 96, minHeight: 34, maxHeight: 34)
        .background(OverlayPalette.base.opacity(0.95), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.10)))
        .shadow(color: .black.opacity(0.4), radius: 14, y: 8)
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .hidden:
            EmptyView()
        case .listening:
            Waveform(levels: model.levels)
            if model.isHandsFree {
                TimelineView(.periodic(from: model.startedAt, by: 1)) { context in
                    Text(Self.timer(from: model.startedAt, to: context.date))
                        .font(.system(size: 12).monospacedDigit())
                        .foregroundStyle(OverlayPalette.secondary)
                }
            }
            if model.isRemote { remoteBadge }
        case .processing:
            ProcessingWave()
            if model.isRemote { remoteBadge }
        case .inserted:
            Image(systemName: "checkmark")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(OverlayPalette.accent)
        case .cancelled:
            Image(systemName: "xmark")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(OverlayPalette.secondary)
        case .copied:
            Image(systemName: "doc.on.doc")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(OverlayPalette.text)
            Text("Copied · ⌘V to paste").font(.system(size: 12)).foregroundStyle(OverlayPalette.text)
        case .fallback:
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(OverlayPalette.outside)
            Text("Used on-device model").font(.system(size: 12)).foregroundStyle(OverlayPalette.text)
        case .needsMicrophone:
            Image(systemName: "mic.slash")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(OverlayPalette.problem)
            Text("No mic access").font(.system(size: 12)).foregroundStyle(OverlayPalette.text)
            Button("Open Settings") {
                if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
                    NSWorkspace.shared.open(url)
                }
            }
            .buttonStyle(SettingsButtonStyle())
        }
    }

    private var remoteBadge: some View {
        Image(systemName: "cloud")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(OverlayPalette.outside)
            .accessibilityLabel("Sent to an external endpoint")
    }

    private var accessibilityLabel: String {
        switch model.phase {
        case .hidden: ""
        case .listening: model.isRemote ? "Listening, sending audio to an external endpoint" : "Listening"
        case .processing: "Processing"
        case .inserted: "Inserted"
        case .cancelled: "Cancelled"
        case .copied: "Copied to clipboard. Press Command V to paste"
        case .fallback: "Endpoint did not answer. Used the on-device model"
        case .needsMicrophone: "No microphone access"
        }
    }

    static func timer(from start: Date, to now: Date) -> String {
        let seconds = max(0, Int(now.timeIntervalSince(start)))
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }
}

/// Live microphone levels, newest on the right.
private struct Waveform: View {
    let levels: [Float]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(levels.indices, id: \.self) { index in
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(OverlayPalette.accent)
                    .frame(width: 3, height: 3 + 15 * CGFloat(levels[index]))
            }
        }
        .frame(height: 20)
        .animation(.linear(duration: 0.06), value: levels)
    }
}

/// Dimmed bars with a small wave running through them, the same width as the waveform.
private struct ProcessingWave: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 2) {
                ForEach(0..<OverlayModel.barCount, id: \.self) { index in
                    let wave = reduceMotion ? 0 : max(0, sin(time * 6 - Double(index) * 0.6))
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(OverlayPalette.accent)
                        .frame(width: 3, height: 3 + 5 * wave)
                }
            }
            .frame(height: 20)
            .opacity(0.55)
        }
    }
}

private struct SettingsButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(OverlayPalette.base)
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(OverlayPalette.text.opacity(configuration.isPressed ? 0.8 : 1), in: Capsule())
    }
}
