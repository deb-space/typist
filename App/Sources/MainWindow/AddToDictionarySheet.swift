// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import SwiftUI
import TypistCore

/// Adds a term from a dictation: click the words Whisper got wrong, type how to write them.
/// The dictation in History is corrected too.
struct AddToDictionarySheet: View {
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss
    let entry: DictationHistory.Entry

    @State private var selected: Set<Int> = []
    @State private var heardAs = ""
    @State private var writeAs = ""

    private var words: [String] { entry.text.split(whereSeparator: \.isWhitespace).map(String.init) }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Add to Dictionary").font(.system(size: 18, weight: .semibold))
                Text("Click the words Whisper got wrong, then type how to write them.")
                    .foregroundStyle(palette.secondaryText)
            }

            FlowLayout(spacing: 6) {
                ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                    let isSelected = selected.contains(index)
                    Button(word) { toggle(index) }
                        .buttonStyle(.plain)
                        .font(.system(size: 14))
                        .foregroundStyle(isSelected ? palette.onAccent : palette.text)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6).fill(isSelected ? palette.accent : palette.control)
                        )
                        .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .card()

            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Heard as").font(.system(size: 12)).foregroundStyle(palette.secondaryText)
                    ThemedField(placeholder: "кубернетус", text: $heardAs)
                }
                Image(systemName: "arrow.right").foregroundStyle(palette.secondaryText).padding(.top, 18)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Write as").font(.system(size: 12)).foregroundStyle(palette.secondaryText)
                    ThemedField(placeholder: "Kubernetes", text: $writeAs)
                }
            }

            Text("Typist will fix this dictation in History and spell it right from now on.")
                .font(.system(size: 12.5))
                .foregroundStyle(palette.secondaryText)

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(.themed)
                    .keyboardShortcut(.cancelAction)
                Button("Add") { add() }
                    .buttonStyle(.themedPrimary)
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        heardAs.trimmingCharacters(in: .whitespaces).isEmpty
                            || writeAs.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 540)
        .background(palette.window)
        .foregroundStyle(palette.text)
        .preferredColorScheme(palette.scheme)
    }

    private func toggle(_ index: Int) {
        if selected.contains(index) { selected.remove(index) } else { selected.insert(index) }
        heardAs = selected.sorted()
            .map { words[$0].trimmingCharacters(in: .punctuationCharacters.union(.symbols)) }
            .joined(separator: " ")
    }

    private func add() {
        let replacement = Replacement(
            kind: .term, from: heardAs.trimmingCharacters(in: .whitespaces),
            to: writeAs.trimmingCharacters(in: .whitespaces))
        AppSettings.shared.replacements.append(replacement)
        let fixed = TextCleanup(
            removesFillers: false, removesStutters: false, removesPhantomPhrases: false, replacements: [replacement]
        ).applyCountingUses(to: entry.text)
        DictationHistory.shared.correct(entry, to: fixed.text)
        AppSettings.shared.recordUses(fixed.uses)
        dismiss()
    }
}

/// Lays out children in rows, wrapping like text.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row {
        var indices: [Int] = []
        var y: CGFloat = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            var row = rows[rows.count - 1]
            if !row.indices.isEmpty, row.width + spacing + size.width > width {
                let y = row.y + row.height + spacing
                rows.append(Row(y: y))
                row = rows[rows.count - 1]
            }
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

#Preview("Add to Dictionary · Light") {
    AddToDictionarySheet(
        entry: DictationHistory.Entry(
            date: Date(), text: "Необходимо установить кубернатор с хельм докерамоджекс.", app: "iTerm2",
            language: "ru")
    )
    .environment(\.palette, .light)
}
