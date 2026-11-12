// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import Foundation

/// A piece of recognized speech with its place on the meeting's timeline, in seconds.
public struct TimedText: Sendable, Codable, Equatable {
    public var start: Double
    public var end: Double
    public var text: String
    /// The recognizer's average log probability per token: near 0 is sure, below −1 is a guess.
    public var averageLogProbability: Double?
    /// The recognizer's estimate that the stretch has no speech at all.
    public var noSpeechProbability: Double?

    public init(
        start: Double, end: Double, text: String, averageLogProbability: Double? = nil,
        noSpeechProbability: Double? = nil
    ) {
        self.start = start
        self.end = end
        self.text = text
        self.averageLogProbability = averageLogProbability
        self.noSpeechProbability = noSpeechProbability
    }

    /// Whisper's word alignment sometimes gives several words at the start of a window the same
    /// instant. Spreads each such stack over the time until the next word, by length, so every
    /// word has a span to check for echo and to place on a speaker.
    public static func spreadingStackedWords(_ words: [TimedText]) -> [TimedText] {
        var result = words
        var index = 0
        while index < result.count {
            var last = index
            while last + 1 < result.count, result[last + 1].start <= result[index].start + 0.01 { last += 1 }
            let stacked = last > index || result[index].end - result[index].start < 0.02
            if stacked {
                let start = result[index].start
                let limit = last + 1 < result.count ? result[last + 1].start : max(result[last].end, start)
                // At most about 0.4 s per word, so a stack before a long pause doesn't stretch over it.
                let end = min(limit, start + 0.4 * Double(last - index + 1))
                let lengths = result[index...last].map { Double(max(1, $0.text.count)) }
                let total = lengths.reduce(0, +)
                var time = start
                for (offset, length) in lengths.enumerated() where end > start {
                    let span = (end - start) * length / total
                    result[index + offset].start = time
                    result[index + offset].end = time + span
                    time += span
                }
            }
            index = last + 1
        }
        return result
    }

    /// The same text moved along the timeline.
    public func shifted(by seconds: Double) -> TimedText {
        var moved = self
        moved.start += seconds
        moved.end += seconds
        return moved
    }
}

/// A stretch of a recording where one person speaks, from speaker diarization.
public struct SpeakerTurn: Sendable, Codable, Equatable {
    public var start: Double
    public var end: Double
    /// The diarizer's label; only equality matters.
    public var speaker: String

    public init(start: Double, end: Double, speaker: String) {
        self.start = start
        self.end = end
        self.speaker = speaker
    }
}

/// The transcript of a recorded meeting: who said what, and when.
///
/// The microphone track is "you" and the call app's track is "the other side". Without
/// headphones the microphone also picks up the other side from the speakers, so lines that
/// repeat what the other side said at the same moment are dropped as echo.
public struct MeetingTranscript: Sendable, Codable, Equatable {
    /// Who said a line: you, or someone on the other side, numbered in order of first words.
    public struct Speaker: Sendable, Codable, Hashable {
        public let rawValue: String

        public init(rawValue: String) { self.rawValue = rawValue }

        public static let me = Speaker(rawValue: "me")
        /// The other side, when it was not split by person.
        public static let others = Speaker(rawValue: "others")
        public static func remote(_ number: Int) -> Speaker { Speaker(rawValue: "S\(number)") }

        public var isMe: Bool { self == .me }

        public var name: String {
            switch rawValue {
            case "me": "You"
            case "others": "Others"
            default: "Speaker " + rawValue.dropFirst()
            }
        }

        /// The name you gave this speaker in `names` (by ``rawValue``), or ``name``.
        public func name(in names: [String: String]) -> String {
            let given = names[rawValue]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return given.isEmpty ? name : given
        }

        /// Names you gave speakers in earlier meetings that start with what is typed (any word of
        /// them, ignoring case), most recent first, without the names already used in this meeting.
        ///
        /// - Parameter earlier: The names of each earlier meeting, most recent meeting first.
        public static func suggestions(
            from earlier: [[String: String]], typed: String, taken: Set<String>, limit: Int = 5
        ) -> [String] {
            let typed = typed.trimmingCharacters(in: .whitespaces).lowercased()
            let taken = Set(taken.map { $0.lowercased() })
            var seen: Set<String> = []
            var result: [String] = []
            for names in earlier {
                // Within a meeting, in speaker order, so the order doesn't change between runs.
                for key in names.keys.sorted() {
                    let name = names[key]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    let lowered = name.lowercased()
                    guard !name.isEmpty, !taken.contains(lowered), seen.insert(lowered).inserted else { continue }
                    let words = lowered.split(separator: " ")
                    guard typed.isEmpty || lowered.hasPrefix(typed) || words.contains(where: { $0.hasPrefix(typed) })
                    else { continue }
                    result.append(name)
                    if result.count == limit { return result }
                }
            }
            return result
        }

        public init(from decoder: any Decoder) throws {
            rawValue = try decoder.singleValueContainer().decode(String.self)
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.singleValueContainer()
            try container.encode(rawValue)
        }
    }

    public struct Line: Sendable, Codable, Equatable, Identifiable {
        public var start: Double
        public var end: Double
        public var speaker: Speaker
        public var text: String

        public var id: String { "\(start)-\(speaker.rawValue)" }

        public init(start: Double, end: Double, speaker: Speaker, text: String) {
            self.start = start
            self.end = end
            self.speaker = speaker
            self.text = text
        }
    }

    public static let currentVersion = 2

    public var version = MeetingTranscript.currentVersion
    public var createdAt: Date
    /// The speech model that made it.
    public var model: String
    public var language: String?
    public var lines: [Line]
    /// Microphone lines dropped because they repeated the other side.
    public var echoLinesDropped: Int
    /// What Whisper returned for each whole track, before echo filtering, speakers and cleanup.
    /// Nil in transcripts made before it was kept.
    public var whisper: [TrackText]?

    /// Whisper's text of one track, on the meeting's timeline.
    public struct TrackText: Sendable, Codable, Equatable {
        /// "system" for the call, "microphone" (and "microphone-2"… after device changes) for you.
        public var track: String
        public var lines: [TimedText]

        public init(track: String, lines: [TimedText]) {
            self.track = track
            self.lines = lines
        }

        /// Whisper's words joined into readable lines at pauses, without speakers.
        public init(track: String, words: [TimedText]) {
            self.track = track
            lines = MeetingTranscript.lines(words: words, speakers: words.map { _ in .others })
                .map { TimedText(start: $0.start, end: $0.end, text: $0.text) }
        }
    }

    public init(
        createdAt: Date, model: String, language: String?, lines: [Line], echoLinesDropped: Int,
        whisper: [TrackText]? = nil
    ) {
        self.createdAt = createdAt
        self.model = model
        self.language = language
        self.lines = lines
        self.echoLinesDropped = echoLinesDropped
        self.whisper = whisper
    }

    /// Builds a transcript from both tracks: echo removed, lines in time order. Lines of the other
    /// side are all `.others`; ``merge(lines:echoDropped:createdAt:model:language:)`` takes lines
    /// already split by person.
    public static func merge(
        me: [TimedText], others: [TimedText], echoDropped: Int = 0, createdAt: Date = Date(), model: String,
        language: String?
    ) -> MeetingTranscript {
        merge(
            lines: me.map { Line(start: $0.start, end: $0.end, speaker: .me, text: $0.text) }
                + others.map { Line(start: $0.start, end: $0.end, speaker: .others, text: $0.text) },
            echoDropped: echoDropped, createdAt: createdAt, model: model, language: language)
    }

    /// - Parameter echoDropped: Microphone words or lines already dropped as echo by their sound
    ///   (``MeetingEcho``), added to ``echoLinesDropped``.
    /// - Parameter echoShare: The share of a line's words repeated by the other side nearby that
    ///   makes it echo; 1.1 turns the check off.
    public static func merge(
        lines: [Line], echoDropped: Int = 0, echoShare: Double = 0.6, whisper: [TrackText]? = nil,
        createdAt: Date = Date(), model: String, language: String?
    ) -> MeetingTranscript {
        let lines = lines.filter { !$0.text.isEmpty }
        let others = lines.filter { !$0.speaker.isMe }.map { TimedText(start: $0.start, end: $0.end, text: $0.text) }
        let mine = lines.filter(\.speaker.isMe)
        // Lines found by loudness (``MeetingEcho/userRegions``) are yours even when they share
        // words with the other side; only whole lines that repeat the call are echo.
        let kept = mine.filter {
            !isEcho(TimedText(start: $0.start, end: $0.end, text: $0.text), of: others, share: echoShare)
        }
        let cleaned = (kept + lines.filter { !$0.speaker.isMe })
            .map { line -> Line in
                var line = line
                line.text = removingDialogueDashes(collapsingRepeats(line.text))
                return line
            }
            .sorted { ($0.start, $0.speaker.isMe ? 0 : 1) < ($1.start, $1.speaker.isMe ? 0 : 1) }
        return MeetingTranscript(
            createdAt: createdAt, model: model, language: language, lines: removingRepeatedLines(cleaned),
            echoLinesDropped: echoDropped + mine.count - kept.count, whisper: whisper)
    }

    /// Groups words into lines: a new line starts when the speaker changes, after a pause longer
    /// than `gap` seconds, or once a line has run `longest` seconds and its sentence ends (`longest`
    /// plus 10 s at most).
    public static func lines(
        words: [TimedText], speakers: [Speaker], gap: Double = 1.5, longest: Double = 25
    ) -> [Line] {
        var lines: [Line] = []
        for (word, speaker) in zip(words, speakers) where !word.text.trimmingCharacters(in: .whitespaces).isEmpty {
            if var last = lines.last, last.speaker == speaker, word.start - last.end <= gap {
                let length = word.end - last.start
                let ended = [".", "!", "?", "…"].contains { last.text.hasSuffix($0) }
                if length <= longest || (!ended && length <= longest + 10) {
                    // Whisper's words carry their own leading space; pieces like "-school" in
                    // "online-school" have none and attach to the previous word.
                    last.text += word.text
                    last.end = word.end
                    lines[lines.count - 1] = last
                    continue
                }
            }
            lines.append(
                Line(
                    start: word.start, end: word.end, speaker: speaker,
                    text: word.text.trimmingCharacters(in: .whitespaces)))
        }
        return lines.map { line in
            var line = line
            line.text = line.text.trimmingCharacters(in: .whitespaces)
            return line
        }
    }

    /// The speaker of each word: the turn it overlaps most, or the nearest turn within a second,
    /// or the previous word's. Speakers are numbered by when they first speak.
    public static func assignSpeakers(words: [TimedText], turns: [SpeakerTurn]) -> [Speaker] {
        var numbers: [String: Int] = [:]
        var previous: Speaker?
        let assigned = words.map { word -> Speaker? in
            let overlaps = turns.map { min($0.end, word.end) - max($0.start, word.start) }
            var best = overlaps.indices.max { overlaps[$0] < overlaps[$1] }
            if let index = best, overlaps[index] <= 0 {
                let middle = (word.start + word.end) / 2
                let distances = turns.map { max($0.start - middle, middle - $0.end, 0) }
                best = distances.indices.min { distances[$0] < distances[$1] }.flatMap { distances[$0] <= 1 ? $0 : nil }
            }
            guard let index = best else { return previous }
            let id = turns[index].speaker
            let number = numbers[id] ?? (numbers.count + 1)
            numbers[id] = number
            previous = .remote(number)
            return previous
        }
        // Words before the first turn belong to whoever speaks first.
        let first = assigned.compactMap { $0 }.first ?? .others
        return assigned.map { $0 ?? first }
    }

    /// How far apart in time the same words may appear on both tracks: the speakers' delay plus
    /// the difference in where Whisper cuts its segments.
    static let echoWindow = 2.0

    /// Whether most of a microphone line's words were said by the other side around the same time.
    static func isEcho(_ line: TimedText, of others: [TimedText], share: Double = 0.6) -> Bool {
        let words = Self.words(line.text)
        guard !words.isEmpty else { return false }
        let nearby = others.filter {
            $0.end >= line.start - echoWindow && $0.start <= line.end + echoWindow
        }
        let heard = Set(nearby.flatMap { Self.words($0.text) })
        let repeated = words.filter(heard.contains).count
        return Double(repeated) / Double(words.count) >= share
    }

    static func words(_ text: String) -> [String] {
        text.lowercased().split { !($0.isLetter || $0.isNumber) }.map(String.init)
    }

    /// Plain text with times and speakers, for copying, with the names you gave speakers.
    public func plainText(names: [String: String] = [:]) -> String {
        lines.map { "[\(Self.timestamp($0.start))] \($0.speaker.name(in: names)): \($0.text)" }
            .joined(separator: "\n")
    }

    /// The people on the other side, in order of first words.
    public var remoteSpeakers: [Speaker] {
        var seen: Set<Speaker> = []
        return lines.map(\.speaker).filter { !$0.isMe && seen.insert($0).inserted }
    }

    public static func timestamp(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}
