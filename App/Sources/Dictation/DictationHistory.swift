// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import Foundation
import Observation
import TypistCore

/// Recent dictations, kept on this Mac only, so text is never lost when insertion goes wrong.
@MainActor @Observable
final class DictationHistory {
    struct Entry: Codable, Identifiable, Equatable {
        var id = UUID()
        var date: Date
        var text: String
        /// What the model heard, when cleanup changed it.
        var rawText: String?
        /// The app the text was inserted into.
        var app: String?
        var language: String?
        /// The text after the rules and the dictionary, without AI cleanup. Set when AI cleanup ran.
        var withoutAI: String?
        /// The language model's version, inserted or not.
        var aiText: String?
        /// The name of the model that made ``aiText``.
        var aiModel: String?
        /// Why ``aiText`` was not inserted; nil when it was.
        var aiRejection: AICleanup.Rejection?

        /// Whether the inserted text is the AI version.
        var usedAI: Bool { aiText != nil && aiRejection == nil }
    }

    static let shared = DictationHistory()
    static let limit = 50

    private(set) var entries: [Entry] = []
    @ObservationIgnored private let url = URL.applicationSupportDirectory.appending(path: "Typist/history.json")

    init() {
        if let data = try? Data(contentsOf: url) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = (try? decoder.decode([Entry].self, from: data)) ?? []
        }
        prune()
    }

    func add(_ entry: Entry) {
        guard AppSettings.shared.historyRetention != .never else { return }
        entries.insert(entry, at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
        prune()
        save()
    }

    /// Replaces an entry's text, keeping what the model originally heard.
    func correct(_ entry: Entry, to text: String) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }), entries[index].text != text else { return }
        if entries[index].rawText == nil { entries[index].rawText = entries[index].text }
        entries[index].text = text
        save()
    }

    func remove(_ entry: Entry) {
        entries.removeAll { $0.id == entry.id }
        save()
    }

    /// Drops entries older than the retention setting.
    func prune() {
        guard let days = AppSettings.shared.historyRetention.days else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let kept = entries.filter { $0.date >= cutoff }
        guard kept.count != entries.count else { return }
        entries = kept
        save()
    }

    func clear() {
        entries = []
        save()
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try encoder.encode(entries).write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            // History is a convenience; dictation keeps working without it.
        }
    }
}
