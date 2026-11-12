// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import AppKit
import TypistCore
import TypistProviders

/// Runs AI cleanup on dictations from a file and quits, to compare models without dictating:
///
///     open Typist.app --args --cleanup-cases <cases.json> --cleanup-output <result.json>
///         [--cleanup-model <repo>] [--cleanup-glossary "Kubernetes, Helm"]
///
/// `cases.json` is an array of strings. The model is downloaded if needed, into the same folder
/// the app uses.
@MainActor
enum CleanupCheck {
    struct Row: Codable {
        var input: String
        var rules: String
        var output: String
        var rejection: AICleanup.Rejection?
        var seconds: Double
    }

    struct Report: Codable {
        var model: String
        var loadSeconds: Double
        var rows: [Row]
        var error: String?
    }

    static func runIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        func value(_ name: String) -> String? {
            arguments.firstIndex(of: name).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        }
        guard let casesPath = value("--cleanup-cases"), let outputPath = value("--cleanup-output") else { return }
        let model = CleanupModel.named(value("--cleanup-model") ?? CleanupModel.defaultModel.repo)
        let glossary = (value("--cleanup-glossary") ?? "").components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }

        Task {
            var report = Report(model: model.repo, loadSeconds: 0, rows: [])
            do {
                let cases = try JSONDecoder().decode([String].self, from: Data(contentsOf: URL(filePath: casesPath)))
                let cleaner = MLXTextCleaner(
                    repo: model.repo, revision: model.revision, modelsDirectory: SpeechModel.directory)
                let loadStart = Date()
                try await cleaner.prepare { _ in }
                report.loadSeconds = Date().timeIntervalSince(loadStart)
                let rules = TextCleanup()
                // Warm up the GPU kernels, as the first dictation after loading would.
                _ = try await cleaner.clean("Test.", glossary: glossary, timeout: .seconds(30))
                for text in cases {
                    let ruled = rules.applyRules(to: text)
                    let start = Date()
                    let output = try await cleaner.clean(ruled, glossary: glossary, timeout: .seconds(30))
                    let seconds = Date().timeIntervalSince(start)
                    report.rows.append(
                        Row(
                            input: text, rules: ruled, output: output,
                            rejection: AICleanup.check(source: ruled, output: output, glossary: glossary),
                            seconds: seconds))
                }
            } catch {
                report.error = String(describing: error)
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
            try? encoder.encode(report).write(to: URL(filePath: outputPath))
            NSApplication.shared.terminate(nil)
        }
    }
}
