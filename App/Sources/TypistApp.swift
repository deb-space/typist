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

        Window("Typist", id: MainWindowRouter.windowID) {
            MainWindowView()
        }
        .defaultSize(width: 1000, height: 720)
        // As in the design: no title bar, the window buttons sit over the sidebar.
        .windowStyle(.hiddenTitleBar)
        .windowBackgroundDragBehavior(.enabled)

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

    private func openMain(_ section: MainSection) {
        MainWindowRouter.shared.selection = section
        openWindow(id: MainWindowRouter.windowID)
        NSApplication.shared.activate()
    }

    var body: some View {
        Button("Open Typist…") {
            openMain(.home)
        }
        .keyboardShortcut("o")

        Divider()

        Text(dictation.modelStatusText)
        if case .failed = dictation.modelStatus {
            Button("Retry Model Download") {
                dictation.prepareModel()
            }
        }
        if AppSettings.shared.aiCleanupEnabled {
            Text("AI cleanup · \(dictation.cleanupStatusText)")
            if case .failed = dictation.cleanupStatus {
                Button("Retry AI Model Download") {
                    dictation.prepareCleaner()
                }
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
            Button("Show History…") {
                openMain(.history)
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

        Button("Settings…") {
            openMain(.settings)
        }
        .keyboardShortcut(",")

        Menu("Developer") {
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
            Button("Audio Spike…") {
                openWindow(id: WindowID.audioSpike)
                NSApplication.shared.activate()
            }
        }

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
            CleanupCheck.runIfRequested()
            MainWindowSnapshots.runIfRequested()
            // Spike runs and Xcode previews launch extra copies of the app; only a normal launch
            // takes the hotkey and loads the model.
            let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
            if !isPreview,
                !ProcessInfo.processInfo.arguments.contains(where: {
                    $0.hasPrefix("--spike") || $0.hasPrefix("--overlay") || $0.hasPrefix("--transcribe")
                        || $0.hasPrefix("--cleanup")
                        || $0.hasPrefix("--window")
                })
            {
                HotkeyController.shared.start()
                DictationController.shared.prepareModel()
            }
        }
    }
}
