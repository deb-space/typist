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
        guard isDownloaded,
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
