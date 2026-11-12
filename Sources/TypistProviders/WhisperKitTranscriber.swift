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

    /// Where WhisperKit keeps a downloaded variant under `modelsDirectory`.
    public static func folder(of variant: String, in modelsDirectory: URL) -> URL {
        modelsDirectory.appending(
            path: "models/argmaxinc/whisperkit-coreml/\(variant)", directoryHint: .isDirectory)
    }

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

    /// Transcribes a long recording into timed segments, or into single words with `words`.
    /// `onProgress` gets the share of the audio done so far.
    public func transcribeTimed(
        _ samples: [Float], language: String?, prompt: String?, words: Bool = false,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> (segments: [TimedText], language: String?) {
        guard let whisper else { throw TranscriberError.notReady }
        var options = DecodingOptions(
            task: .transcribe, language: language, temperature: 0, usePrefillPrompt: true,
            detectLanguage: language == nil, skipSpecialTokens: true, withoutTimestamps: false,
            wordTimestamps: words, chunkingStrategy: .vad)
        // Whisper skips a whole 30 s window it judges silent. Meeting tracks are often quiet (a
        // call at low volume, the microphone between your phrases), and that dropped minutes of
        // speech. Text invented on real silence is removed later by the cleanup rules and, on the
        // microphone, by the echo filter.
        options.noSpeechThreshold = nil
        options.logProbThreshold = nil
        options.firstTokenLogProbThreshold = nil
        // No retries at higher temperature: they sample at random and came back as a translation
        // into English or not at all, differently on every run. Greedy decoding is the same every
        // time; the loops it sometimes makes are collapsed afterwards.
        options.temperatureFallbackCount = 0
        // Cut at pauses (VAD): word times line up with the speakers better than sequential 30 s
        // windows, and nothing is lost once silent-window skipping is off (below).
        if let prompt, !prompt.isEmpty, let tokenizer = whisper.tokenizer {
            options.promptTokens = Array(
                tokenizer.encode(text: " " + prompt)
                    .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
                    .prefix(200))
        }
        let seconds = Double(samples.count) / 16_000
        let results = try await whisper.transcribe(
            audioArray: samples, decodeOptions: options,
            segmentCallback: { segments in
                if let end = segments.map(\.end).max(), seconds > 0 { onProgress(min(1, Double(end) / seconds)) }
            })
        if words {
            return (
                TimedText.spreadingStackedWords(Self.words(of: results.flatMap(\.segments))), results.first?.language
            )
        }
        let segments = results.flatMap(\.segments).map {
            TimedText(
                start: Double($0.start), end: Double($0.end),
                text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines),
                averageLogProbability: Double($0.avgLogprob), noSpeechProbability: Double($0.noSpeechProb))
        }
        return (segments.sorted { $0.start < $1.start }, results.first?.language)
    }

    /// The words of all segments in time order. Whisper capitalizes the first word of every
    /// segment; mid-sentence, only names and acronyms keep their capital.
    static func words(of segments: [TranscriptionSegment]) -> [TimedText] {
        var result: [TimedText] = []
        for segment in segments.sorted(by: { $0.start < $1.start }) {
            for (index, word) in (segment.words ?? []).enumerated() {
                var text = word.word
                if index == 0, let previous = result.last?.text, !"..!?…".contains(previous.last ?? "."),
                    let first = text.trimmingCharacters(in: .whitespaces).first, first.isUppercase
                {
                    let trimmed = text.trimmingCharacters(in: .whitespaces)
                    let wordOnly = trimmed.prefix { $0.isLetter || $0 == "'" }
                    if wordOnly != "I", !wordOnly.hasPrefix("I'"), wordOnly.filter(\.isUppercase).count == 1 {
                        text = " " + first.lowercased() + trimmed.dropFirst()
                    }
                }
                result.append(TimedText(start: Double(word.start), end: Double(word.end), text: text))
            }
        }
        return result
    }

    public func transcribe(_ samples: [Float], language: String?, prompt: String?) async throws -> Transcript {
        guard let whisper else { throw TranscriberError.notReady }
        let start = Date()
        var options = DecodingOptions(
            task: .transcribe, language: language, temperature: 0, usePrefillPrompt: true,
            detectLanguage: language == nil,
            skipSpecialTokens: true, withoutTimestamps: true)
        if let prompt, !prompt.isEmpty, let tokenizer = whisper.tokenizer {
            // Whisper's "previous text" prompt: terms in it are recognized more often.
            // Whisper keeps at most about half its 448-token context for the prompt; anything longer
            // is cut by the model anyway, so cut it here, keeping the start (the most used terms).
            options.promptTokens = Array(
                tokenizer.encode(text: " " + prompt)
                    .filter { $0 < tokenizer.specialTokens.specialTokenBegin }
                    .prefix(200))
        }
        let results = try await whisper.transcribe(audioArray: samples, decodeOptions: options)
        let text = results.map(\.text).joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return Transcript(
            text: text, language: results.first?.language, audioSeconds: Double(samples.count) / 16_000,
            processingSeconds: Date().timeIntervalSince(start))
    }
}
