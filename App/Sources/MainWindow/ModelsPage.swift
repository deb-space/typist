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
            CardSection("Speech models") {
                ForEach(SpeechModel.all) { model in
                    row(model)
                }
                CardRow("Parakeet TDT v3", "Faster, 25 European languages · being benchmarked", divider: false) {
                    Chip(text: "Coming later")
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                CardSection("AI cleanup models") {
                    ForEach(Array(CleanupModel.all.enumerated()), id: \.element.id) { index, model in
                        cleanupRow(model, last: index == CleanupModel.all.count - 1)
                    }
                }
                Text(
                    "AI cleanup runs after the rules and your dictionary: it applies self-corrections like “five, no, six” and fixes grammar and punctuation. The model stays in memory while you dictate and is unloaded after 15 minutes without dictation. Turn it off in Settings."
                )
                .font(.system(size: 12))
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
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
        }
        .task(id: dictation.modelStatus) { await measure() }
        .task(id: dictation.cleanupStatus) { await measure() }
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
                ?? ByteCountFormatter.string(fromByteCount: model.downloadBytes, countStyle: .file) + " download",
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
                        Button("Download and Use") { dictation.selectModel(model) }.buttonStyle(.themed)
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
        let cleanupModels = CleanupModel.all
        let measured = await Task.detached {
            Dictionary(
                uniqueKeysWithValues: models.compactMap { model in model.sizeOnDisk.map { (model.variant, $0) } }
                    + cleanupModels.compactMap { model in model.sizeOnDisk.map { (model.repo, $0) } })
        }.value
        sizes = measured
    }

    private func cleanupRow(_ model: CleanupModel, last: Bool) -> some View {
        let selected = model.repo == settings.cleanupModelRepo
        let inUse = selected && settings.aiCleanupEnabled
        let size = sizes[model.repo]
        let bytes = { (count: Int64) in ByteCountFormatter.string(fromByteCount: count, countStyle: .file) }
        var detail = [
            model.detail,
            size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }
                ?? ByteCountFormatter.string(fromByteCount: model.downloadBytes, countStyle: .file) + " download",
            "about \(bytes(model.memoryBytes)) of memory",
        ]
        .joined(separator: " · ")
        if !model.fitsThisMac {
            detail +=
                "\nThis Mac has \(bytes(Int64(ProcessInfo.processInfo.physicalMemory))) of memory: other apps may slow down"
        }
        return CardRow(model.name, detail, divider: !last) {
            HStack(spacing: 8) {
                switch model.badge {
                case .recommended: Chip(text: "Recommended")
                case .bestQuality: Chip(text: "Best quality")
                case nil: EmptyView()
                }
                if inUse {
                    cleanupStatus
                } else if size != nil {
                    Button("Use") { dictation.selectCleanupModel(model) }.buttonStyle(.themed)
                    if !selected {
                        Button("Delete") { deleteCleanup(model) }.buttonStyle(.themedDestructive)
                    }
                } else {
                    Button("Download and Use") { dictation.selectCleanupModel(model) }.buttonStyle(.themed)
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

    @ViewBuilder
    private var cleanupStatus: some View {
        switch dictation.cleanupStatus {
        case .downloading(let fraction):
            ProgressView(value: fraction).frame(width: 120)
            Text("\(Int(fraction * 100))%").monospacedDigit().foregroundStyle(palette.secondaryText)
        case .loading:
            ProgressView().controlSize(.small)
            Text("Loading").foregroundStyle(palette.secondaryText)
        case .idle where !dictation.currentCleanupModel.isDownloaded:
            Text("Downloads after the speech model").foregroundStyle(palette.secondaryText)
        case .ready, .idle:
            // Idle: downloaded and unloaded until the next dictation.
            Chip(text: "In use", highlighted: true)
        case .failed:
            Text("Failed").foregroundStyle(palette.danger)
            Button("Retry") { dictation.prepareCleaner() }.buttonStyle(.themed)
        }
    }

    private func deleteCleanup(_ model: CleanupModel) {
        do {
            try dictation.deleteCleanupModel(model)
            sizes[model.repo] = nil
        } catch {
            self.error = error.localizedDescription
        }
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

#Preview("Models · Dark Blue") {
    ScrollView {
        ModelsPage().padding(44)
    }
    .frame(width: 860, height: 900)
    .background(ThemePalette.darkBlue.window)
    .foregroundStyle(ThemePalette.darkBlue.text)
    .environment(\.palette, .darkBlue)
}
