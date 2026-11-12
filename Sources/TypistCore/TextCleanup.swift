// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import Foundation

/// An entry of the personal dictionary: what the model writes, and what it should be.
public struct Replacement: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// A word or name to spell right. Also given to speech recognition as a hint.
        case term
        /// A short phrase that expands into longer text. Not given to speech recognition.
        case snippet
    }

    public var id: UUID
    public var kind: Kind
    /// Matched as whole words, ignoring case. May be several words. A term may leave it empty
    /// and only serve as a hint.
    public var from: String
    public var to: String

    public init(id: UUID = UUID(), kind: Kind = .term, from: String, to: String) {
        self.id = id
        self.kind = kind
        self.from = from
        self.to = to
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        // Entries saved before snippets existed have no kind.
        kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .term
        from = try container.decode(String.self, forKey: .from)
        to = try container.decode(String.self, forKey: .to)
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
    /// Turns spoken "new line" and "new paragraph" into line breaks.
    public var formatsLineBreaks: Bool
    public var replacements: [Replacement]

    public init(
        removesFillers: Bool = true, removesStutters: Bool = true, removesPhantomPhrases: Bool = true,
        formatsLineBreaks: Bool = true, replacements: [Replacement] = []
    ) {
        self.removesFillers = removesFillers
        self.removesStutters = removesStutters
        self.removesPhantomPhrases = removesPhantomPhrases
        self.formatsLineBreaks = formatsLineBreaks
        self.replacements = replacements
    }

    public func apply(to text: String) -> String {
        applyCountingUses(to: text).text
    }

    /// Like ``apply(to:)``, and also reports how many times each dictionary entry matched.
    public func applyCountingUses(to text: String) -> (text: String, uses: [UUID: Int]) {
        applyDictionary(to: applyRules(to: text))
    }

    /// The first step: phantom phrases, fillers, stutters, spacing and capitals.
    public func applyRules(to text: String) -> String {
        var result = text
        if removesPhantomPhrases { result = Self.removePhantomPhrases(result) }
        if removesFillers { result = Self.removeFillers(result) }
        if removesStutters { result = Self.removeStutters(result) }
        result = Self.tidy(result)
        // After tidying, which would capitalize and trim around the breaks differently.
        if formatsLineBreaks { result = Self.applyLineBreakCommands(result) }
        return result
    }

    /// The last step, after the rules and any AI cleanup, so the dictionary's text is inserted
    /// exactly as written: tidying would turn "iPhone" at the start into "IPhone" and
    /// "gmail.com" into "gmail.Com".
    public func applyDictionary(to text: String) -> (text: String, uses: [UUID: Int]) {
        var uses: [UUID: Int] = [:]
        let result = Self.applyReplacements(replacements.filter(\.isUsable), to: text, uses: &uses)
        return (result, uses)
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

    /// Removes phantom phrases when they make up a whole sentence of the text. Text without
    /// them is returned untouched.
    static func removePhantomPhrases(_ text: String) -> String {
        let parts = sentences(of: text)
        let kept = parts.filter { sentence in
            let key = sentence.lowercased()
                .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
                .replacingOccurrences(of: "  ", with: " ")
            return !phantomPhrases.contains(key)
        }
        return kept.count == parts.count ? text : kept.joined(separator: " ")
    }

    /// Splits after `.`, `!`, `?` and `…` that end a sentence: followed by whitespace or the end
    /// of the text, so "gmail.com" and "v1.2" stay whole.
    static func sentences(of text: String) -> [String] {
        var result: [String] = []
        var current = ""
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            current.append(character)
            let atEnd = index + 1 == characters.count
            let nextIsSpace = !atEnd && characters[index + 1].isWhitespace
            let nextIsTerminator = !atEnd && ".!?…".contains(characters[index + 1])
            if ".!?…".contains(character), atEnd || nextIsSpace, !nextIsTerminator {
                let trimmed = current.trimmingCharacters(in: .whitespaces)
                if !trimmed.isEmpty { result.append(trimmed) }
                current = ""
            }
        }
        let rest = current.trimmingCharacters(in: .whitespaces)
        if !rest.isEmpty { result.append(rest) }
        return result
    }

    // MARK: - Line breaks

    /// Spoken commands and what they insert.
    static let lineBreakCommands: [(phrase: String, insert: String)] = [
        ("new paragraph", "\n\n"), ("next paragraph", "\n\n"), ("new line", "\n"), ("next line", "\n"),
    ]

    /// Replaces "new line" and "new paragraph" said on their own: at the start or end, or set off by
    /// punctuation, which is how Whisper writes a pause. "A new line of products" stays text.
    /// The comma Whisper put before the command and any punctuation after it go; a period, "?" or
    /// "!" before it ends the sentence and stays.
    static func applyLineBreakCommands(_ text: String) -> String {
        let phrases = lineBreakCommands.map { $0.phrase.replacingOccurrences(of: " ", with: "\\s+") }
        let pattern = "(?i)(?<![\\p{L}\\p{N}])(" + phrases.joined(separator: "|") + ")(?![\\p{L}\\p{N}])"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let pause = CharacterSet(charactersIn: ",.;:")
        var result = text
        // From the end, so earlier ranges stay valid.
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed() {
            guard let range = Range(match.range, in: result) else { continue }
            let spoken = result[range].lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
            guard let insert = lineBreakCommands.first(where: { $0.phrase == spoken })?.insert else { continue }
            // Widen over the pause before and after the command.
            var start = range.lowerBound
            while start > result.startIndex, result[result.index(before: start)].isWhitespace {
                start = result.index(before: start)
            }
            let before = start > result.startIndex ? result[result.index(before: start)] : nil
            var end = range.upperBound
            while end < result.endIndex, result[end].unicodeScalars.allSatisfy(pause.contains) || result[end] == " " {
                end = result.index(after: end)
            }
            let after = end < result.endIndex ? result[end] : nil
            let standsAlone =
                before == nil || after == nil || before.map { ",.;:!?…\n".contains($0) } == true
                || result[range.upperBound..<end].contains { ",.;:".contains($0) }
            guard standsAlone else { continue }
            // A comma before the command is the pause; a period ends the sentence and stays.
            if let before, ",;".contains(before) {
                start = result.index(before: start)
            }
            var tail = String(result[end...])
            if let first = tail.first, first.isLowercase { tail = first.uppercased() + tail.dropFirst() }
            result = String(result[..<start]) + insert + tail
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
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

    static func applyReplacements(_ replacements: [Replacement], to text: String, uses: inout [UUID: Int]) -> String {
        // Longer phrases first, so "docker compose" wins over "docker".
        var result = text
        for replacement in replacements.sorted(by: { $0.from.count > $1.from.count }) {
            let words = replacement.from.trimmingCharacters(in: .whitespaces)
                .split(whereSeparator: \.isWhitespace)
                .map { NSRegularExpression.escapedPattern(for: String($0)) }
            let pattern = "(?i)(?<![\\p{L}\\p{N}])" + words.joined(separator: "\\s+") + "(?![\\p{L}\\p{N}])"
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(result.startIndex..., in: result)
            let count = regex.numberOfMatches(in: result, range: range)
            guard count > 0 else { continue }
            uses[replacement.id, default: 0] += count
            let template = NSRegularExpression.escapedTemplate(
                for: replacement.to.trimmingCharacters(in: .whitespaces))
            result = regex.stringByReplacingMatches(in: result, range: range, withTemplate: template)
        }
        return result
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

    /// Uppercases the first letter after ". ", "! " or "? ". A period without a space after it
    /// (gmail.com, v1.2) does not end a sentence.
    private static func capitalizingSentenceStarts(_ text: String) -> String {
        enum State { case inSentence, afterTerminator, armed }
        var result = ""
        var state = State.inSentence
        for character in text {
            switch state {
            case .armed where character.isLetter:
                result += character.uppercased()
                state = .inSentence
                continue
            case .afterTerminator:
                state = character.isWhitespace ? .armed : .inSentence
            case .armed where !character.isWhitespace:
                state = .inSentence
            default:
                break
            }
            if ".!?".contains(character) { state = .afterTerminator }
            result.append(character)
        }
        return result
    }
}
