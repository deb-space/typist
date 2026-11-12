// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import FluidAudio
import Foundation
import TypistCore

/// Splits a recording by speaker on this Mac: pyannote community-1 segmentation and WeSpeaker
/// embeddings on the Neural Engine, VBx clustering, through FluidAudio (spike 0.4).
public enum FluidDiarizer {
    /// Downloads the models into `modelsDirectory` on first use (about 30 MB), then finds who
    /// speaks when. `onProgress` gets the share done.
    public static func diarize(
        _ samples: [Float], modelsDirectory: URL, onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> [SpeakerTurn] {
        let manager = OfflineDiarizerManager(config: .default)
        try await manager.prepareModels(directory: modelsDirectory)
        let result = try await manager.process(audio: samples) { done, total in
            if total > 0 { onProgress(Double(done) / Double(total)) }
        }
        return result.segments.map {
            SpeakerTurn(start: Double($0.startTimeSeconds), end: Double($0.endTimeSeconds), speaker: $0.speakerId)
        }
    }
}
