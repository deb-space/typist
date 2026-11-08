// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

/// The result of turning speech into text.
public struct Transcript: Sendable, Equatable {
    public var text: String
    /// ISO 639-1 code of the detected or requested language.
    public var language: String?
    public var audioSeconds: Double
    public var processingSeconds: Double

    public init(text: String, language: String?, audioSeconds: Double, processingSeconds: Double) {
        self.text = text
        self.language = language
        self.audioSeconds = audioSeconds
        self.processingSeconds = processingSeconds
    }

    public var wordCount: Int { text.split(whereSeparator: \.isWhitespace).count }
}

/// A speech-to-text engine, on this Mac or behind an endpoint the user configured.
public protocol TranscriptionProvider: Sendable {
    /// - Parameter samples: 16 kHz mono audio in -1...1.
    func transcribe(_ samples: [Float]) async throws -> Transcript
}
