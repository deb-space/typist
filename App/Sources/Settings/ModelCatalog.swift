// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import Foundation
import TypistProviders

/// Speech models Typist can download and run on this Mac.
struct SpeechModel: Identifiable, Equatable {
    let variant: String
    let name: String
    let detail: String
    let downloadBytes: Int64

    var id: String { variant }

    static let all: [SpeechModel] = [
        SpeechModel(
            variant: WhisperKitTranscriber.defaultVariant, name: "Whisper large-v3-turbo · compressed",
            detail: "99 languages · about 1 s for a 6 s phrase", downloadBytes: 627_000_000),
        SpeechModel(
            variant: "openai_whisper-large-v3-v20240930", name: "Whisper large-v3-turbo · full precision",
            detail: "Slightly more accurate, slower to load", downloadBytes: 1_620_000_000),
    ]

    static func named(_ variant: String) -> SpeechModel {
        all.first { $0.variant == variant } ?? all[0]
    }

    static let directory = URL.applicationSupportDirectory.appending(path: "Typist/Models", directoryHint: .isDirectory)

    var folder: URL { WhisperKitTranscriber.folder(of: variant, in: Self.directory) }

    var isDownloaded: Bool { FileManager.default.fileExists(atPath: folder.path) }

    /// When the model was downloaded, the only time Typist goes online.
    var downloadedAt: Date? {
        try? folder.resourceValues(forKeys: [.creationDateKey]).creationDate
    }

    /// Bytes on disk, or nil if not downloaded.
    var sizeOnDisk: Int64? {
        guard isDownloaded else { return nil }
        return Self.allocatedSize(of: folder)
    }

    static func allocatedSize(of folder: URL) -> Int64? {
        guard
            let files = FileManager.default.enumerator(
                at: folder, includingPropertiesForKeys: [.totalFileAllocatedSizeKey])
        else { return nil }
        var total: Int64 = 0
        for case let url as URL in files {
            total += Int64(
                (try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}

/// Language models that can clean up dictated text on this Mac.
struct CleanupModel: Identifiable, Equatable {
    enum Badge { case recommended, bestQuality }

    let repo: String
    /// The reviewed commit; a new revision is a code change.
    let revision: String
    let name: String
    let detail: String
    let downloadBytes: Int64
    /// Measured peak while cleaning up a dictation.
    let memoryBytes: Int64
    let badge: Badge?

    var id: String { repo }

    static let all: [CleanupModel] = [
        CleanupModel(
            repo: "mlx-community/gemma-4-e4b-it-4bit", revision: "475b9088d29754a3379866cf5aeb6b41acd313c2",
            name: "Gemma 4 E4B", detail: "Google · about 0.2 s per phrase", downloadBytes: 5_180_000_000,
            memoryBytes: 4_930_000_000, badge: .recommended),
        CleanupModel(
            repo: "mlx-community/Qwen3.5-4B-MLX-4bit", revision: "32f3e8ecf65426fc3306969496342d504bfa13f3",
            name: "Qwen3.5 4B", detail: "Alibaba · lightest, more cautious edits", downloadBytes: 3_060_000_000,
            memoryBytes: 3_420_000_000, badge: nil),
        CleanupModel(
            repo: "mlx-community/Qwen3.5-9B-MLX-4bit", revision: "938d8919941c6e7efd3c7150eff7fe9d12afa631",
            name: "Qwen3.5 9B", detail: "Alibaba · best with long, tangled phrases · about 0.3 s per phrase",
            downloadBytes: 5_980_000_000, memoryBytes: 5_890_000_000, badge: .bestQuality),
    ]

    static let defaultModel = all[0]

    static func named(_ repo: String) -> CleanupModel {
        all.first { $0.repo == repo } ?? defaultModel
    }

    var folder: URL { MLXTextCleaner.folder(of: repo, in: SpeechModel.directory) }

    var isDownloaded: Bool { MLXTextCleaner.isDownloaded(repo, revision: revision, in: SpeechModel.directory) }

    /// Whether this Mac has comfortably more memory than the model needs next to Whisper and apps.
    var fitsThisMac: Bool {
        Int64(ProcessInfo.processInfo.physicalMemory) >= memoryBytes * 2 + 4_000_000_000
    }

    var sizeOnDisk: Int64? {
        guard isDownloaded else { return nil }
        return SpeechModel.allocatedSize(of: folder)
    }
}
