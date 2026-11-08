// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import Foundation
import TypistCore
import WhisperKit

/// On-device speech-to-text with Whisper models converted to CoreML by Argmax (WhisperKit).
public actor WhisperKitTranscriber: TranscriptionProvider {
    public enum State: Sendable, Equatable {
        case idle
        case downloading(Double)
        case loading
        case ready
        case failed(String)
    }

    public enum TranscriberError: Error, CustomStringConvertible {
        case notReady
        public var description: String { "the speech model is not loaded" }
    }

    /// OpenAI Whisper large-v3-turbo with quantized weights, about 630 MB.
    /// The full-precision model is `openai_whisper-large-v3-v20240930` (1.6 GB).
    public static let defaultVariant = "openai_whisper-large-v3-v20240930_626MB"

    public let variant: String
    private let modelsDirectory: URL
    private var whisper: WhisperKit?
    private var isPreparing = false

    public init(variant: String = defaultVariant, modelsDirectory: URL) {
        self.variant = variant
        self.modelsDirectory = modelsDirectory
    }

    /// Downloads the model if needed and loads it. Safe to call again: later calls wait for the
    /// first one to finish.
    public func prepare(onState: @escaping @Sendable (State) -> Void) async throws {
        while isPreparing { try await Task.sleep(for: .milliseconds(200)) }
        if whisper != nil {
            onState(.ready)
            return
        }
        isPreparing = true
        defer { isPreparing = false }
        do {
            onState(.downloading(0))
            try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
            // Files already on disk are not downloaded again.
            let folder = try await WhisperKit.download(variant: variant, downloadBase: modelsDirectory) { progress in
                onState(.downloading(progress.fractionCompleted))
            }
            onState(.loading)
            let config = WhisperKitConfig(
                modelFolder: folder.path, verbose: false, logLevel: .error, prewarm: true, load: true, download: false)
            whisper = try await WhisperKit(config)
            onState(.ready)
        } catch {
            onState(.failed(String(describing: error)))
            throw error
        }
    }

    public func transcribe(_ samples: [Float]) async throws -> Transcript {
        guard let whisper else { throw TranscriberError.notReady }
        let start = Date()
        let options = DecodingOptions(
            task: .transcribe, language: nil, temperature: 0, usePrefillPrompt: true, detectLanguage: true,
            skipSpecialTokens: true, withoutTimestamps: true)
        let results = try await whisper.transcribe(audioArray: samples, decodeOptions: options)
        let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return Transcript(
            text: text, language: results.first?.language, audioSeconds: Double(samples.count) / 16_000,
            processingSeconds: Date().timeIntervalSince(start))
    }
}
