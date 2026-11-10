// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import AppKit
import SwiftUI
import TypistCore
import UniformTypeIdentifiers

struct DictionaryPage: View {
    @Environment(\.palette) private var palette
    @Bindable private var settings = AppSettings.shared
    @State private var query = ""
    @State private var message: (title: String, text: String)?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(spacing: 10) {
                ThemedField(placeholder: "Search the dictionary", text: $query)
                    .accessibilityLabel("Search the dictionary")
                Button("Import…") { importFile() }.buttonStyle(.themed)
                Button("Export…") { exportFile() }
                    .buttonStyle(.themed)
                    .disabled(settings.replacements.isEmpty)
            }

            section(
                .term, title: "Terms", add: "Add Term",
                hint:
                    "Names and terms to spell right. Typist hints them to Whisper, and replaces “heard as” with “write as” when it still gets them wrong. “Heard as” can stay empty."
            )
            section(
                .snippet, title: "Snippets", add: "Add Snippet",
                hint: "Say the phrase and Typist inserts the text instead. Snippets are not hinted to Whisper.")
        }
        .alert(message?.title ?? "", isPresented: .constant(message != nil)) {
            Button("OK") { message = nil }
        } message: {
            Text(message?.text ?? "")
        }
    }

    private func entries(_ kind: Replacement.Kind) -> [Replacement] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        return settings.replacements.filter { entry in
            entry.kind == kind
                && (needle.isEmpty || entry.from.localizedCaseInsensitiveContains(needle)
                    || entry.to.localizedCaseInsensitiveContains(needle))
        }
    }

    private func section(_ kind: Replacement.Kind, title: String, add: String, hint: String) -> some View {
        let shown = entries(kind)
        return CardSection("\(title) · \(settings.replacements.filter { $0.kind == kind }.count)") {
            VStack(alignment: .leading, spacing: 12) {
                Text(hint)
                    .font(.system(size: 12.5))
                    .foregroundStyle(palette.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                if shown.isEmpty, !query.isEmpty {
                    Text("Nothing matches “\(query)”.").foregroundStyle(palette.secondaryText)
                }
                ForEach(shown) { entry in
                    if kind == .term { termRow(entry) } else { snippetRow(entry) }
                }
                Button(add) {
                    query = ""
                    settings.replacements.append(Replacement(kind: kind, from: "", to: ""))
                }
                .buttonStyle(.themed)
            }
            .padding(.vertical, 16)
        }
    }

    private func termRow(_ entry: Replacement) -> some View {
        let id = entry.id
        return HStack(spacing: 10) {
            ThemedField(placeholder: "Heard as: кубернетус", text: binding(id, \.from))
                .accessibilityLabel("Heard as")
            Image(systemName: "arrow.right").font(.system(size: 11)).foregroundStyle(palette.secondaryText)
            ThemedField(placeholder: "Write as: Kubernetes", text: binding(id, \.to))
                .accessibilityLabel("Write as")
            uses(id)
            removeButton(entry)
        }
    }

    private func snippetRow(_ entry: Replacement) -> some View {
        let id = entry.id
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ThemedField(placeholder: "Say: my address", text: binding(id, \.from))
                    .accessibilityLabel("Phrase to say")
                uses(id)
                removeButton(entry)
            }
            ThemedTextEditor(text: binding(id, \.to), placeholder: "Text to insert")
                .frame(height: 64)
                .accessibilityLabel("Text to insert")
        }
        .padding(.bottom, 6)
    }

    private func uses(_ id: UUID) -> some View {
        let count = settings.dictionaryUses[id] ?? 0
        return Chip(text: count == 0 ? "unused" : "\(count)×", highlighted: count > 0)
            .help(count == 0 ? "Not applied yet" : "Applied \(count) times")
            .frame(minWidth: 56)
    }

    private func removeButton(_ entry: Replacement) -> some View {
        let id = entry.id
        return Button {
            // Capture the id first: reading the entry while the array is being mutated is an
            // exclusivity violation and crashes.
            settings.replacements.removeAll { $0.id == id }
        } label: {
            Image(systemName: "trash").font(.system(size: 12))
        }
        .buttonStyle(.themedSmall)
        .help("Remove")
        .accessibilityLabel("Remove \(entry.to.isEmpty ? entry.from : entry.to)")
    }

    /// A binding to one field of an entry, found by id, so removing a row never leaves a text
    /// field pointing at a stale index.
    private func binding(_ id: UUID, _ field: WritableKeyPath<Replacement, String>) -> Binding<String> {
        Binding(
            get: { settings.replacements.first { $0.id == id }?[keyPath: field] ?? "" },
            set: { value in
                guard let index = settings.replacements.firstIndex(where: { $0.id == id }) else { return }
                settings.replacements[index][keyPath: field] = value
            })
    }

    // MARK: - Import and export

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let imported = try DictionaryFile.parse(Data(contentsOf: url)).filter {
                !$0.to.trimmingCharacters(in: .whitespaces).isEmpty
            }
            let existing = Set(settings.replacements.map(Self.key))
            let new = imported.filter { !existing.contains(Self.key($0)) }
            settings.replacements.append(contentsOf: new)
            let skipped = imported.count - new.count
            message = (
                "Imported \(new.count) \(new.count == 1 ? "entry" : "entries")",
                skipped > 0 ? "\(skipped) already in the dictionary were skipped." : "From \(url.lastPathComponent)."
            )
        } catch {
            message = ("Couldn’t import \(url.lastPathComponent)", String(describing: error))
        }
    }

    private static func key(_ entry: Replacement) -> String {
        [entry.kind.rawValue, entry.from.lowercased(), entry.to].joined(separator: "\u{1F}")
    }

    private func exportFile() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Typist Dictionary.json"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try DictionaryFile.export(settings.replacements).write(to: url, options: .atomic)
        } catch {
            message = ("Couldn’t export the dictionary", error.localizedDescription)
        }
    }
}

/// A multi-line text field drawn in the theme's input colors.
struct ThemedTextEditor: View {
    @Environment(\.palette) private var palette
    @Binding var text: String
    let placeholder: String

    var body: some View {
        TextEditor(text: $text)
            .font(.system(size: 14))
            .scrollContentBackground(.hidden)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 9).fill(palette.input))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(palette.inputBorder))
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(.system(size: 14))
                        .foregroundStyle(palette.secondaryText)
                        .padding(.horizontal, 13)
                        .padding(.vertical, 6)
                        .allowsHitTesting(false)
                }
            }
    }
}

#Preview("Dictionary · Dark Blue") {
    ScrollView {
        DictionaryPage().padding(44)
    }
    .frame(width: 760, height: 560)
    .background(ThemePalette.darkBlue.window)
    .foregroundStyle(ThemePalette.darkBlue.text)
    .environment(\.palette, .darkBlue)
    .preferredColorScheme(.dark)
}
