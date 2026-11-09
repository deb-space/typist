// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import Foundation

/// A user's correction: what the model writes, and what it should be.
public struct Replacement: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    /// Matched as whole words, ignoring case. May be several words.
    public var from: String
    public var to: String

    public init(id: UUID = UUID(), from: String, to: String) {
        self.id = id
        self.from = from
        self.to = to
    }

    var isUsable: Bool {
        !from.trimmingCharacters(in: .whitespaces).isEmpty && !to.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

/// Rule-based cleanup of a transcript, before it is inserted. It runs without any model, so it
/// only fixes what is safe to fix by rules; rewriting is left to a language model.
public struct TextCleanup: Sendable {
    public var removesFillers: Bool
    public var removesStutters: Bool
    public var removesPhantomPhrases: Bool
    public var replacements: [Replacement]

    public init(
        removesFillers: Bool = true, removesStutters: Bool = true, removesPhantomPhrases: Bool = true,
        replacements: [Replacement] = []
    ) {
        self.removesFillers = removesFillers
        self.removesStutters = removesStutters
        self.removesPhantomPhrases = removesPhantomPhrases
        self.replacements = replacements
    }

    public func apply(to text: String) -> String {
        var result = text
        if removesPhantomPhrases { result = Self.removePhantomPhrases(result) }
        if removesFillers { result = Self.removeFillers(result) }
        if removesStutters { result = Self.removeStutters(result) }
        result = Self.applyReplacements(replacements.filter(\.isUsable), to: result)
        return Self.tidy(result)
    }

    // MARK: - Phantom phrases

    /// Lines Whisper is known to invent, mostly from subtitles in its training data. Only
    /// phrases nobody dictates on purpose: plain "Thank you." is left alone.
    static let phantomPhrases = [
        "продолжение следует",
        "субтитры сделал dimatorzok",
        "субтитры создавал dimatorzok",
        "субтитры делал dimatorzok",
        "редактор субтитров а.синецкая корректор а.егорова",
        "спасибо за просмотр",
        "подписывайтесь на канал",
        "подпишись на канал",
        "thanks for watching",
        "thank you for watching",
        "please subscribe",
        "subtitles by the amara.org community",
    ]

    /// Removes phantom phrases when they make up a whole sentence of the text.
    static func removePhantomPhrases(_ text: String) -> String {
        sentences(of: text)
            .filter { sentence in
                let key = sentence.lowercased()
                    .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                    .replacingOccurrences(of: "  ", with: " ")
                return !phantomPhrases.contains(key)
            }
            .joined(separator: " ")
    }

    /// Splits after `.`, `!`, `?` and `…`, keeping the punctuation with its sentence.
    static func sentences(of text: String) -> [String] {
        var result: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if ".!?…".contains(character) {
                let trimmed = current.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty, trimmed.rangeOfCharacter(from: .letters) != nil {
                    result.append(trimmed)
                    current = ""
                }
            }
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty {
            if rest.rangeOfCharacter(from: .letters) == nil, let last = result.popLast() {
                result.append(last + rest)
            } else {
                result.append(rest)
            }
        }
        return result
    }

    // MARK: - Fillers

    /// Hesitation sounds in English and Russian. Words that can carry meaning ("like", "ну",
    /// "типа") are left for a language model to judge.
    static let fillers: Set<String> = [
        "um", "umm", "uh", "uhh", "uhm", "erm", "er", "hmm", "mm", "mmm",
        "э", "ээ", "эээ", "эм", "ээм", "мм", "ммм", "хм", "хмм",
    ]

    static func removeFillers(_ text: String) -> String {
        let pattern =
            "(?i)(?<![\\p{L}\\p{N}])(" + fillers.sorted { $0.count > $1.count }.joined(separator: "|")
            + ")(?![\\p{L}\\p{N}])[,.…]*"
        return text.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
    }

    // MARK: - Stutters

    /// Short words that people repeat while thinking. Words that are repeated on purpose
    /// ("very very", "да да", "that that") are not in the list.
    static let stutterWords: Set<String> = [
        "i", "the", "a", "an", "we", "you", "it", "to", "and", "but", "my", "in", "of",
        "я", "мы", "ты", "вы", "он", "она", "они", "это", "и", "в", "на", "не", "но", "а", "с", "к", "у",
    ]

    static func removeStutters(_ text: String) -> String {
        let words = stutterWords.sorted { $0.count > $1.count }.joined(separator: "|")
        // "я я", "I, I", "the the the" → one word, keeping the first one's case.
        let pattern = "(?i)(?<![\\p{L}\\p{N}])(" + words + ")(?:[,]?\\s+\\1)+(?![\\p{L}\\p{N}])"
        return text.replacingOccurrences(of: pattern, with: "$1", options: .regularExpression)
    }

    // MARK: - Replacements

    static func applyReplacements(_ replacements: [Replacement], to text: String) -> String {
        // Longer phrases first, so "docker compose" wins over "docker".
        replacements.sorted { $0.from.count > $1.from.count }.reduce(text) { text, replacement in
            let words = replacement.from.trimmingCharacters(in: .whitespaces)
                .split(whereSeparator: \.isWhitespace)
                .map { NSRegularExpression.escapedPattern(for: String($0)) }
            let pattern = "(?i)(?<![\\p{L}\\p{N}])" + words.joined(separator: "\\s+") + "(?![\\p{L}\\p{N}])"
            let template = NSRegularExpression.escapedTemplate(for: replacement.to.trimmingCharacters(in: .whitespaces))
            return text.replacingOccurrences(of: pattern, with: template, options: .regularExpression)
        }
    }

    // MARK: - Tidy

    /// Fixes what the removals leave behind: double spaces, spaces before punctuation, stray
    /// leading commas, and a lowercase first letter.
    static func tidy(_ text: String) -> String {
        var result = text
        result = result.replacingOccurrences(of: "[ \\t]{2,}", with: " ", options: .regularExpression)
        result = result.replacingOccurrences(of: "\\s+([,.!?;:…])", with: "$1", options: .regularExpression)
        result = result.replacingOccurrences(of: ",{2,}", with: ",", options: .regularExpression)
        result = result.replacingOccurrences(of: "([.!?…])\\s*,", with: "$1", options: .regularExpression)
        result = result.trimmingCharacters(in: .whitespacesAndNewlines)
        while let first = result.first, ",;:".contains(first) {
            result = String(result.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        // A sentence that lost its first word to a filler starts with a lowercase letter.
        if let first = result.first, first.isLowercase {
            result = first.uppercased() + result.dropFirst()
        }
        return capitalizingSentenceStarts(result)
    }

    private static func capitalizingSentenceStarts(_ text: String) -> String {
        var result = ""
        var capitalizeNext = false
        for character in text {
            if capitalizeNext, character.isLetter {
                result += character.uppercased()
                capitalizeNext = false
                continue
            }
            if ".!?".contains(character) {
                capitalizeNext = true
            } else if !character.isWhitespace {
                capitalizeNext = false
            }
            result.append(character)
        }
        return result
    }
}
