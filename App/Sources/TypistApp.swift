// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import SwiftUI

@main
struct TypistApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate

    var body: some Scene {
        MenuBarExtra("Typist", systemImage: "waveform") {
            MenuContent()
        }

        Settings {
            SettingsView()
        }

        Window("Audio Spike", id: WindowID.audioSpike) {
            AudioSpikeView()
        }
        .windowResizability(.contentMinSize)
    }
}

enum WindowID {
    static let audioSpike = "audio-spike"
}

private struct MenuContent: View {
    @Environment(\.openWindow) private var openWindow

    private var overlay: OverlayController { .shared }
    private var hotkey: HotkeyController { .shared }
    private var dictation: DictationController { .shared }
    private var history: DictationHistory { .shared }

    static func preview(_ text: String) -> String {
        let line = text.replacingOccurrences(of: "\n", with: " ")
        return line.count > 60 ? String(line.prefix(57)) + "…" : line
    }

    var body: some View {
        Text(dictation.modelStatusText)
        if case .failed = dictation.modelStatus {
            Button("Retry Model Download") {
                dictation.prepareModel()
            }
        }
        if !history.entries.isEmpty {
            Section("Recent — click to insert again") {
                ForEach(history.entries.prefix(5)) { entry in
                    Button(Self.preview(entry.text)) {
                        dictation.reinsert(entry)
                    }
                }
            }
            if let last = history.entries.first {
                Button("Copy Last Dictation") {
                    dictation.copyToClipboard(last.text)
                }
            }
            Button("Clear History") {
                history.clear()
            }
            Divider()
        }

        if hotkey.isRunning {
            Text("Hold fn to dictate · fn+Space for hands-free")
        } else {
            Button("Enable fn Hotkey…") {
                hotkey.enable()
            }
        }

        Divider()

        Button(overlay.isTestDictating ? "Stop Test Dictation" : "Test Dictation") {
            overlay.toggleTestDictation()
        }
        if overlay.isTestDictating {
            Button("Cancel Test Dictation") {
                overlay.cancelTestDictation()
            }
        }
        Button("Show All Overlay States") {
            overlay.showAllStates()
        }

        Divider()

        Button("Audio Spike…") {
            openWindow(id: WindowID.audioSpike)
            NSApplication.shared.activate()
        }

        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",")

        Divider()

        Button("Quit Typist") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated {
            AudioSpikeAutomation.runIfRequested()
            OverlaySnapshots.runIfRequested()
            InsertionSpikeAutomation.runIfRequested()
            TranscriptionCheck.runIfRequested()
            // Spike runs launch extra copies of the app; only a normal launch takes the hotkey.
            if !ProcessInfo.processInfo.arguments.contains(where: {
                $0.hasPrefix("--spike") || $0.hasPrefix("--overlay") || $0.hasPrefix("--transcribe")
            }) {
                HotkeyController.shared.start()
                DictationController.shared.prepareModel()
            }
        }
    }
}
