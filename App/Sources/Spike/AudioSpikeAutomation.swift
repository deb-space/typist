// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import AppKit
import TypistAudio

/// Runs a spike recording from launch arguments and quits, for repeatable tests:
///
///     open Typist.app --args --spike-record tap --seconds 10 \
///         [--source <bundle-id>] [--mic off|engine|sck] [--voice-processing] \
///         [--tracking fixed|updateDescription|bundleIDs]
///
/// The session folder path is written to `~/Library/Application Support/Typist/Spikes/latest.txt`.
@MainActor
enum AudioSpikeAutomation {
    static func runIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        func value(_ name: String) -> String? {
            arguments.firstIndex(of: name).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        }
        guard let methodName = value("--spike-record"), let method = AudioSpikeModel.Method(rawValue: methodName)
        else { return }

        let model = AudioSpikeModel.shared
        model.refresh()
        model.method = method
        model.micMode = value("--mic").flatMap(AudioSpikeModel.MicMode.init) ?? .off
        model.voiceProcessing = arguments.contains("--voice-processing")
        model.tracking = value("--tracking").flatMap(ProcessTapCapture.Tracking.init) ?? .updateDescription
        model.targetBundleID = value("--source")
        let seconds = value("--seconds").flatMap(Double.init) ?? 10

        Task {
            await model.start()
            if model.isRecording {
                try? await Task.sleep(for: .seconds(seconds))
                await model.stop()
            }
            NSApplication.shared.terminate(nil)
        }
    }
}
