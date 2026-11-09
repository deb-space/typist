// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import AppKit
import SwiftUI

struct ModelsPage: View {
    @Environment(\.palette) private var palette
    private var dictation: DictationController { .shared }
    private var settings: AppSettings { .shared }
    @State private var sizes: [String: Int64] = [:]
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            CardSection("Speech recognition on this Mac") {
                ForEach(SpeechModel.all) { model in
                    row(model)
                }
                CardRow("Parakeet TDT v3", "Faster, 25 European languages · being benchmarked", divider: false) {
                    Chip(text: "Coming later")
                }
            }

            CardSection("Your own endpoints") {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "cloud").foregroundStyle(palette.outside)
                    Text(
                        "A Whisper server at home, Ollama, or a cloud API with your own key. It comes with text cleanup, and the overlay will mark it in amber whenever audio or text goes there. Until then Typist uses the network only to download the models above."
                    )
                    .font(.system(size: 13))
                    .foregroundStyle(palette.text.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 16)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Text cleanup")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(palette.secondaryText)
                Text(
                    "Removing “um”, repeats and self-corrections with a small local model comes next. Until then Typist inserts exactly what Whisper heard."
                )
                .font(.system(size: 13))
                .foregroundStyle(palette.secondaryText)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 12).fill(palette.card))
                .overlay(
                    RoundedRectangle(cornerRadius: 12).strokeBorder(
                        palette.inputBorder, style: StrokeStyle(dash: [5, 4])))
            }
        }
        .task(id: dictation.modelStatus) { await measure() }
        .alert("Couldn’t delete the model", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private func row(_ model: SpeechModel) -> some View {
        let inUse = model.variant == settings.modelVariant
        let size = sizes[model.variant]
        let detail = [
            model.detail,
            size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
                ?? "\(model.downloadSize) download",
        ]
        .joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 0) {
            CardRow(model.name, detail) {
                HStack(spacing: 8) {
                    if inUse {
                        status
                    } else if size != nil {
                        Button("Use") { dictation.selectModel(model) }.buttonStyle(.themed)
                        Button("Delete") { delete(model) }.buttonStyle(.themedDestructive)
                    } else {
                        Button("Download and Use") { dictation.selectModel(model) }.buttonStyle(.themedPrimary)
                    }
                    if size != nil {
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([model.folder])
                        } label: {
                            Image(systemName: "folder").font(.system(size: 12))
                        }
                        .buttonStyle(.themed)
                        .help("Show in Finder")
                        .accessibilityLabel("Show in Finder")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var status: some View {
        switch dictation.modelStatus {
        case .downloading(let fraction):
            ProgressView(value: fraction).frame(width: 120)
            Text("\(Int(fraction * 100))%").monospacedDigit().foregroundStyle(palette.secondaryText)
        case .loading, .idle:
            ProgressView().controlSize(.small)
            Text("Loading").foregroundStyle(palette.secondaryText)
        case .ready:
            Chip(text: "In use", highlighted: true)
        case .failed:
            Text("Failed").foregroundStyle(palette.danger)
            Button("Retry") { dictation.prepareModel() }.buttonStyle(.themed)
        }
    }

    private func measure() async {
        let models = SpeechModel.all
        let measured = await Task.detached {
            Dictionary(
                uniqueKeysWithValues: models.compactMap { model in model.sizeOnDisk.map { (model.variant, $0) } })
        }.value
        sizes = measured
    }

    private func delete(_ model: SpeechModel) {
        do {
            try dictation.deleteModel(model)
            sizes[model.variant] = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
