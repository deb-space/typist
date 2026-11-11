// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import AVFoundation
import AppKit
import SwiftUI
import TypistInput

struct PrivacyPage: View {
    @Environment(\.palette) private var palette
    @Bindable private var settings = AppSettings.shared
    private var history: DictationHistory { .shared }
    @State private var permissions: [PermissionRow] = []
    @State private var confirmingDelete = false

    private var lastNetworkUse: String {
        guard let date = SpeechModel.all.compactMap(\.downloadedAt).max() else { return "None yet" }
        return "Last: model download, " + date.formatted(.dateTime.day().month())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            CardSection {
                CardRow(
                    "Network use",
                    "Audio and text never leave this Mac. Typist only goes online to download the models you choose.",
                    divider: false
                ) {
                    Text(lastNetworkUse).foregroundStyle(palette.secondaryText)
                }
            }

            CardSection("History") {
                CardRow("Keep dictations") {
                    ThemedMenu(
                        options: AppSettings.HistoryRetention.allCases.map { ($0, $0.title) },
                        selection: $settings.historyRetention, label: "Keep dictations")
                }
                CardRow("Stored in", "~/Library/Application Support/Typist") {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([
                            URL.applicationSupportDirectory.appending(path: "Typist")
                        ])
                    }
                    .buttonStyle(.themed)
                }
                CardRow("\(history.entries.count) dictations in history", divider: false) {
                    if confirmingDelete {
                        HStack(spacing: 8) {
                            Button("Keep") { confirmingDelete = false }.buttonStyle(.themed)
                            Button("Delete") {
                                history.clear()
                                confirmingDelete = false
                            }
                            .buttonStyle(.themedDestructive)
                        }
                    } else {
                        Button("Delete All History…") { confirmingDelete = true }
                            .buttonStyle(.themedDestructive)
                            .disabled(history.entries.isEmpty)
                    }
                }
            }
            .onChange(of: settings.historyRetention) { history.prune() }

            CardSection("Permissions") {
                ForEach(permissions) { permission in
                    CardRow(permission.name, permission.purpose, divider: permission.id != permissions.last?.id) {
                        HStack(spacing: 10) {
                            Chip(text: permission.status, highlighted: permission.granted)
                            Button("Open Settings") { SystemSettings.open(permission.settingsAnchor) }
                                .buttonStyle(.themed)
                        }
                    }
                }
            }
        }
        .task {
            // Permissions change in System Settings while this page is open.
            while !Task.isCancelled {
                permissions = PermissionRow.current()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

struct PermissionRow: Identifiable {
    let name: String
    let purpose: String
    let status: String
    let granted: Bool
    let settingsAnchor: String
    /// Dictation does not work without it.
    var required = true

    var id: String { name }

    @MainActor
    static func current() -> [PermissionRow] {
        // macOS 27 shows the Accessibility permission as "Device Control".
        let controlName =
            ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 ? "Device Control" : "Accessibility"
        let microphone = AVAudioApplication.shared.recordPermission
        return [
            PermissionRow(
                name: "Microphone", purpose: "To hear you",
                status: microphone == .granted ? "Allowed" : microphone == .denied ? "Denied" : "Not asked yet",
                granted: microphone == .granted, settingsAnchor: "Privacy_Microphone"),
            PermissionRow(
                name: controlName, purpose: "To paste text into other apps",
                status: FocusInspector.isTrusted ? "Allowed" : "Not allowed", granted: FocusInspector.isTrusted,
                settingsAnchor: "Privacy_Accessibility"),
            PermissionRow(
                name: "Input Monitoring", purpose: "To notice fn in any app",
                status: HotkeyService.hasInputMonitoring ? "Allowed" : "Not allowed",
                granted: HotkeyService.hasInputMonitoring, settingsAnchor: "Privacy_ListenEvent"),
            PermissionRow(
                name: "System Audio Recording", purpose: "For meetings: the other side of the call",
                status: "Asked later", granted: false, settingsAnchor: "Privacy", required: false),
        ]
    }
}
