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

    var body: some View {
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
        }
    }
}
