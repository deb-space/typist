// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import Foundation
import Observation

/// Recent dictations, kept on this Mac only, so text is never lost when insertion goes wrong.
@MainActor @Observable
final class DictationHistory {
    struct Entry: Codable, Identifiable, Equatable {
        var id = UUID()
        var date: Date
        var text: String
        /// The app the text was inserted into.
        var app: String?
        var language: String?
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
    }

    func add(_ entry: Entry) {
        entries.insert(entry, at: 0)
        if entries.count > Self.limit { entries.removeLast(entries.count - Self.limit) }
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
