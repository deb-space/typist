// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import AppKit
import TypistInput

/// Spike 0.3: inserts text into the focused app with one method, checks the result and quits.
///
///     open -n -g Typist.app --args --spike-insert pasteboard|accessibility|typing \
///         --text-file <path> --label <name> [--delay 2] [--then-save] [--verify-file <path>] \
///         [--chunk 16] [--restore-ms 250] [--expect-bundle <bundle-id>] [--focus-shortcut 1]
///         [--typing-variant hid|session|pid|privateSource] [--enhanced-ui] [--layout <input-source-id>]
///
/// `-g` keeps the target app in front. Each run appends one JSON line to
/// `~/Library/Application Support/Typist/Spikes/insertion/results.jsonl`.
@MainActor
enum InsertionSpikeAutomation {
    struct Result: Codable {
        var label: String
        var method: InsertionMethod
        var date: Date
        var trusted: Bool
        var accessibilityTree: String?
        var before: FocusInfo
        var report: InsertionReport?
        var after: FocusInfo?
        /// Whether the text was found, and where: "value", "title", "file". Empty when no
        /// check was possible.
        var foundIn: [String]
        /// How many times the text appears in the best check, to catch double insertion.
        var occurrences: Int?
        var verdict: String
        var clipboardBefore: String?
        var clipboardAfter: String?
    }

    static func runIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        func value(_ name: String) -> String? {
            arguments.firstIndex(of: name).flatMap { arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil }
        }
        guard let methodName = value("--spike-insert"), let method = InsertionMethod(rawValue: methodName),
            let textPath = value("--text-file"), let text = try? String(contentsOfFile: textPath, encoding: .utf8)
        else { return }
        let label = value("--label") ?? "unnamed"
        let delay = value("--delay").flatMap(Double.init) ?? 2
        let chunk = value("--chunk").flatMap(Int.init) ?? 16
        let restore = value("--restore-ms").flatMap(Int.init) ?? 250
        let verifyFile = value("--verify-file")
        let thenSave = arguments.contains("--then-save")
        let focusShortcut = value("--focus-shortcut").flatMap(\.first)
        if let variant = value("--typing-variant").flatMap(TextInserter.TypingVariant.init) {
            TextInserter.typingVariant = variant
        }
        let enhancedUI = arguments.contains("--enhanced-ui")
        let layout = value("--layout")
        // Safety: never type into whatever else happens to be in front.
        let expectedBundle = value("--expect-bundle")

        Task {
            try? await Task.sleep(for: .seconds(delay))
            if let focusShortcut, NSWorkspace.shared.frontmostApplication?.bundleIdentifier == expectedBundle {
                TextInserter.postShortcut(focusShortcut)
                try? await Task.sleep(for: .milliseconds(600))
            }
            if enhancedUI, let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier {
                FocusInspector.enableEnhancedUserInterface(pid: pid)
                try? await Task.sleep(for: .milliseconds(800))
            }
            var previousLayout: String?
            if let layout, NSWorkspace.shared.frontmostApplication?.bundleIdentifier == expectedBundle {
                previousLayout = KeyboardLayout.select(layout)
                try? await Task.sleep(for: .milliseconds(300))
            }
            let before = FocusInspector.inspect()
            var result = Result(
                label: label, method: method, date: Date(), trusted: FocusInspector.isTrusted, before: before,
                foundIn: [], verdict: "not run",
                clipboardBefore: NSPasteboard.general.string(forType: .string))
            if let pid = before.pid {
                result.accessibilityTree = FocusInspector.enableAccessibilityTree(pid: pid)
            }

            if let expectedBundle, before.bundleID != expectedBundle {
                result.verdict = "skipped: \(before.bundleID ?? "unknown") in front, expected \(expectedBundle)"
            } else if result.trusted {
                result.report = await TextInserter.insert(
                    text, method: method, restoreDelay: .milliseconds(restore), typingChunk: chunk)
                try? await Task.sleep(for: .milliseconds(500))
                if thenSave {
                    TextInserter.postSave()
                    try? await Task.sleep(for: .milliseconds(800))
                }
                let after = FocusInspector.inspect()
                result.after = after
                verify(text: text, after: after, verifyFile: verifyFile, into: &result)
            } else {
                result.verdict = "not trusted"
            }
            result.clipboardAfter = NSPasteboard.general.string(forType: .string)
            if let previousLayout { KeyboardLayout.select(previousLayout) }
            append(result)
            NSApplication.shared.terminate(nil)
        }
    }

    private static func verify(text: String, after: FocusInfo, verifyFile: String?, into result: inout Result) {
        let needle = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var counts: [String: Int] = [:]
        if let value = after.value {
            counts["value"] = occurrences(of: needle, in: value)
        }
        // The browser test page mirrors its field into the title as "VAL:<percent-encoded>".
        if let title = after.windowTitle, let range = title.range(of: "VAL:") {
            let encoded = String(title[range.upperBound...]).components(separatedBy: " — ").first ?? ""
            counts["title"] = occurrences(of: needle, in: encoded.removingPercentEncoding ?? encoded)
        }
        if let verifyFile, let contents = try? String(contentsOfFile: verifyFile, encoding: .utf8) {
            counts["file"] = occurrences(of: needle, in: contents)
        }
        result.foundIn = counts.filter { $0.value > 0 }.map(\.key).sorted()
        result.occurrences = counts.values.max()
        if counts.isEmpty {
            result.verdict = "unverified"
        } else if let best = result.occurrences, best == 1 {
            result.verdict = "inserted"
        } else if let best = result.occurrences, best > 1 {
            result.verdict = "inserted \(best) times"
        } else {
            result.verdict = "not found"
        }
    }

    private static func occurrences(of needle: String, in haystack: String) -> Int {
        // Terminals and some editors turn the newline into \r or drop it, so compare line by line.
        let normalized = haystack.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(
            of: "\r", with: "\n")
        return normalized.components(separatedBy: needle).count - 1
    }

    private static func append(_ result: Result) {
        let directory = AudioSpikeModel.spikesDirectory.appending(path: "insertion", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "results.jsonl")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard var line = try? encoder.encode(result) else { return }
        line.append(0x0A)
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(line)
            try? handle.close()
        } else {
            try? line.write(to: url)
        }
    }
}
