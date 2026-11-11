// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import SwiftUI

struct HistoryPage: View {
    @Environment(\.palette) private var palette
    private var history: DictationHistory { .shared }
    private var settings: AppSettings { .shared }
    @State private var query = ""
    @State private var copiedID: UUID?
    @State private var addingToDictionary: DictationHistory.Entry?

    private var filtered: [DictationHistory.Entry] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return history.entries }
        return history.entries.filter {
            $0.text.localizedCaseInsensitiveContains(needle) || ($0.app ?? "").localizedCaseInsensitiveContains(needle)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ThemedField(placeholder: "Search dictations", text: $query)
                    .accessibilityLabel("Search history")
                Text(filtered.count == 1 ? "1 dictation" : "\(filtered.count) dictations")
                    .font(.system(size: 13))
                    .foregroundStyle(palette.secondaryText)
                    .monospacedDigit()
            }
            LazyVStack(spacing: 0) {
                if filtered.isEmpty {
                    Text(history.entries.isEmpty ? "No dictations yet." : "Nothing matches “\(query)”.")
                        .foregroundStyle(palette.secondaryText)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 28)
                }
                ForEach(filtered) { entry in
                    row(entry, last: entry.id == filtered.last?.id)
                }
            }
            .card()
            Text(retentionNote).font(.system(size: 12)).foregroundStyle(palette.secondaryText)
        }
        .sheet(item: $addingToDictionary) { entry in
            AddToDictionarySheet(entry: entry).environment(\.palette, palette)
        }
    }

    private func row(_ entry: DictationHistory.Entry, last: Bool) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.date, format: .dateTime.day().month().hour().minute())
                    .foregroundStyle(palette.text.opacity(0.85))
                Text(
                    [entry.app, entry.language == usualLanguage ? nil : entry.language?.uppercased()]
                        .compactMap { $0 }.joined(separator: " · ")
                )
                .foregroundStyle(palette.secondaryText)
            }
            .font(.system(size: 12))
            .frame(width: 120, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.text)
                    .font(.system(size: 14))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                if let raw = entry.rawText {
                    Text("Heard: \(raw)")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondaryText)
                        .textSelection(.enabled)
                        .help("What Whisper wrote before cleanup and your dictionary")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 6) {
                Button(copiedID == entry.id ? "Copied" : "Copy") { copy(entry) }
                    .buttonStyle(.themedSmall)
                Button {
                    addingToDictionary = entry
                } label: {
                    Image(systemName: "character.book.closed").font(.system(size: 12))
                }
                .buttonStyle(.themedSmall)
                .help("Add to Dictionary")
                .accessibilityLabel("Add to Dictionary")
                Button {
                    history.remove(entry)
                } label: {
                    Image(systemName: "trash").font(.system(size: 12))
                }
                .buttonStyle(.themedSmall)
                .help("Delete")
                .accessibilityLabel("Delete")
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) {
            if !last { palette.border.frame(height: 1) }
        }
        .contextMenu {
            Button("Copy") { copy(entry) }
            Button("Add to Dictionary…") { addingToDictionary = entry }
            Button("Delete", role: .destructive) { history.remove(entry) }
        }
        // VoiceOver reads the dictation once, with its actions, instead of a row of anonymous
        // "Copy" buttons.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            [entry.date.formatted(date: .abbreviated, time: .shortened), entry.app, entry.text]
                .compactMap { $0 }.joined(separator: ", ")
        )
        .accessibilityActions {
            Button("Copy") { copy(entry) }
            Button("Add to Dictionary") { addingToDictionary = entry }
            Button("Delete") { history.remove(entry) }
        }
    }

    /// The language most dictations are in; only other languages get a tag.
    private var usualLanguage: String? {
        Dictionary(grouping: history.entries.compactMap(\.language), by: { $0 })
            .max { $0.value.count < $1.value.count }?.key
    }

    private func copy(_ entry: DictationHistory.Entry) {
        DictationController.shared.copyToClipboard(entry.text)
        copiedID = entry.id
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copiedID == entry.id { copiedID = nil }
        }
    }

    private var retentionNote: String {
        switch settings.historyRetention {
        case .forever: "Kept on this Mac until you delete it. Change it in Privacy."
        case .month: "Kept on this Mac for 30 days. Change it in Privacy."
        case .week: "Kept on this Mac for 7 days. Change it in Privacy."
        case .never: "History is off: new dictations are not kept. Change it in Privacy."
        }
    }
}
