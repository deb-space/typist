// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import AppKit
import TypistAudio
import TypistProviders

/// Transcribes audio files with the on-device model and quits, to check the pipeline without a
/// microphone:
///
///     open Typist.app --args --transcribe-files <file>... --transcribe-output <result.txt>
@MainActor
enum TranscriptionCheck {
    static func runIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let start = arguments.firstIndex(of: "--transcribe-files"),
            let outputIndex = arguments.firstIndex(of: "--transcribe-output"),
            arguments.indices.contains(outputIndex + 1)
        else { return }
        let files = arguments[(start + 1)...].prefix { !$0.hasPrefix("--") }
        let output = URL(filePath: arguments[outputIndex + 1])

        Task {
            var lines: [String] = []
            let transcriber = WhisperKitTranscriber(
                modelsDirectory: URL.applicationSupportDirectory.appending(
                    path: "Typist/Models", directoryHint: .isDirectory))
            let prepareStart = Date()
            do {
                try await transcriber.prepare { _ in }
                lines.append(String(format: "model ready in %.1f s", Date().timeIntervalSince(prepareStart)))
                for path in files {
                    let samples = try AudioFileSamples.load(URL(filePath: path))
                    let transcript = try await transcriber.transcribe(samples, language: nil)
                    lines.append(
                        String(
                            format: "%@ | %.1f s audio | %.2f s | %@ | %@", (path as NSString).lastPathComponent,
                            transcript.audioSeconds, transcript.processingSeconds, transcript.language ?? "?",
                            transcript.text))
                }
            } catch {
                lines.append("error: \(error)")
            }
            try? (lines.joined(separator: "\n") + "\n").write(to: output, atomically: true, encoding: .utf8)
            NSApplication.shared.terminate(nil)
        }
    }
}
