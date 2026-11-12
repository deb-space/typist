// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import SwiftUI

struct HistoryPage: View {
    @Environment(\.palette) private var palette
    private var history: DictationHistory { .shared }
    /// Sample entries for previews, instead of the real history.
    var sample: [DictationHistory.Entry]?
    private var entries: [DictationHistory.Entry] { sample ?? history.entries }
    private var settings: AppSettings { .shared }
    @State private var query = ""
    @State private var copiedID: UUID?
    @State private var addingToDictionary: DictationHistory.Entry?
    /// Entries switched away from the version that was inserted, by id: true shows the AI version.
    @State private var showsAI: [UUID: Bool] = [:]

    private var filtered: [DictationHistory.Entry] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return entries }
        return entries.filter { entry in
            [entry.text, entry.aiText, entry.withoutAI, entry.app].contains {
                ($0 ?? "").localizedCaseInsensitiveContains(needle)
            }
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
                    Text(entries.isEmpty ? "No dictations yet." : "Nothing matches “\(query)”.")
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
                if entry.aiText != nil {
                    versionPicker(entry)
                }
                Text(shownText(entry))
                    .font(.system(size: 14))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                if let rejection = entry.aiRejection, isShowingAI(entry) {
                    Text("Not inserted: \(rejection.explanation.lowercasedFirst)")
                        .font(.system(size: 12))
                        .foregroundStyle(palette.secondaryText)
                }
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
            if entry.aiText != nil {
                Button(isShowingAI(entry) ? "Show Without AI" : "Show With AI") { toggleVersion(entry) }
            }
            Button("Add to Dictionary…") { addingToDictionary = entry }
            Button("Delete", role: .destructive) { history.remove(entry) }
        }
        // VoiceOver reads the dictation once, with its actions, instead of a row of anonymous
        // "Copy" buttons.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            [
                entry.date.formatted(date: .abbreviated, time: .shortened), entry.app,
                entry.aiText == nil ? nil : (isShowingAI(entry) ? "with AI" : "without AI"), shownText(entry),
            ]
            .compactMap { $0 }.joined(separator: ", ")
        )
        .accessibilityActions {
            Button("Copy") { copy(entry) }
            if entry.aiText != nil {
                Button(isShowingAI(entry) ? "Show Without AI" : "Show With AI") { toggleVersion(entry) }
            }
            Button("Add to Dictionary") { addingToDictionary = entry }
            Button("Delete") { history.remove(entry) }
        }
    }

    /// The language most dictations are in; only other languages get a tag.
    private var usualLanguage: String? {
        Dictionary(grouping: entries.compactMap(\.language), by: { $0 })
            .max { $0.value.count < $1.value.count }?.key
    }

    // MARK: - Versions

    private func isShowingAI(_ entry: DictationHistory.Entry) -> Bool {
        showsAI[entry.id] ?? entry.usedAI
    }

    private func shownText(_ entry: DictationHistory.Entry) -> String {
        guard let aiText = entry.aiText else { return entry.text }
        return isShowingAI(entry) ? aiText : (entry.withoutAI ?? entry.text)
    }

    private func toggleVersion(_ entry: DictationHistory.Entry) {
        showsAI[entry.id] = !isShowingAI(entry)
    }

    /// "With AI · Without AI", with the inserted version marked.
    private func versionPicker(_ entry: DictationHistory.Entry) -> some View {
        HStack(spacing: 2) {
            ForEach([true, false], id: \.self) { ai in
                let selected = isShowingAI(entry) == ai
                let inserted = entry.usedAI == ai
                Button {
                    showsAI[entry.id] = ai
                } label: {
                    HStack(spacing: 4) {
                        Text(ai ? "With AI" : "Without AI")
                        if inserted {
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .semibold))
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(selected ? palette.text : palette.secondaryText)
                    .padding(.horizontal, 8)
                    .frame(height: 20)
                    .background(RoundedRectangle(cornerRadius: 5).fill(selected ? palette.control : .clear))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(
                    (ai ? "Cleaned up by \(entry.aiModel ?? "a language model")" : "Rules and your dictionary only")
                        + (inserted ? " · this version was inserted" : ""))
            }
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 7).fill(palette.input))
        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(palette.inputBorder))
        .padding(.bottom, 2)
    }

    private func copy(_ entry: DictationHistory.Entry) {
        DictationController.shared.copyToClipboard(shownText(entry))
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

extension String {
    fileprivate var lowercasedFirst: String { prefix(1).lowercased() + dropFirst() }
}

#Preview("History · Dark") {
    let now = Date()
    ScrollView {
        HistoryPage(sample: [
            DictationHistory.Entry(
                date: now, text: "Let's meet on Wednesday at the office.",
                rawText: "Let's meet on Tuesday, sorry, I mean Wednesday, at the office.", app: "Slack", language: "en",
                withoutAI: "Let's meet on Tuesday, sorry, I mean Wednesday, at the office.",
                aiText: "Let's meet on Wednesday at the office.", aiModel: "Gemma 4 E4B"),
            DictationHistory.Entry(
                date: now.addingTimeInterval(-300), text: "Write me an email to my e-mail", app: "Mail",
                language: "en", withoutAI: "Write me an email to my e-mail", aiText: "Write me an email.",
                aiModel: "Gemma 4 E4B", aiRejection: .droppedWords),
            DictationHistory.Entry(
                date: now.addingTimeInterval(-900), text: "Testing dictation through Typist", app: "Notes",
                language: "en"),
        ])
        .padding(44)
    }
    .frame(width: 860, height: 520)
    .background(ThemePalette.dark.window)
    .foregroundStyle(ThemePalette.dark.text)
    .environment(\.palette, .dark)
}
