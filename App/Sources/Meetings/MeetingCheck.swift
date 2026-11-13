// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import AppKit

/// Transcribes a recorded meeting and quits, to check the pipeline without the window:
///
///     open Typist.app --args --meeting-transcribe <folder name> --meeting-output <transcript.txt>
///     open Typist.app --args --meeting-import <audio or video file> --meeting-output <transcript.txt>
@MainActor
enum MeetingCheck {
    static func runIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        func value(_ name: String) -> String? {
            arguments.firstIndex(of: name).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        }
        guard let output = value("--meeting-output") else { return }
        let importing = value("--meeting-import")
        guard importing != nil || value("--meeting-transcribe") != nil else { return }
        let transcriber = MeetingTranscriber.shared
        Task {
            var report = ""
            var id = value("--meeting-transcribe") ?? ""
            if let importing {
                let start = Date()
                id = await MeetingRecorder.shared.importFiles([URL(filePath: importing)]) ?? ""
                report += String(format: "import: %.1f s\n", Date().timeIntervalSince(start))
            }
            if let record = MeetingRecorder.shared.recordings.first(where: { $0.id == id }) {
                let start = Date()
                transcriber.transcribe(record)
                while let status = transcriber.status[id] {
                    if case .failed(let message) = status {
                        report = "error: \(message)"
                        break
                    }
                    try? await Task.sleep(for: .milliseconds(500))
                }
                if let transcript = transcriber.transcript(of: record) {
                    report +=
                        String(
                            format: "%.1f s for %.0f s of audio, %d lines, %d echo lines dropped, language %@\n\n",
                            Date().timeIntervalSince(start), record.seconds, transcript.lines.count,
                            transcript.echoLinesDropped, transcript.language ?? "?")
                        + transcript.plainText()
                }
            } else {
                report += MeetingRecorder.shared.importError ?? "error: no meeting \(id)"
            }
            try? (report + "\n").write(toFile: output, atomically: true, encoding: .utf8)
            NSApplication.shared.terminate(nil)
        }
    }
}
