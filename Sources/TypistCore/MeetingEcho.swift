// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import Accelerate
import Foundation

/// Tells your voice on the microphone track from the other side coming out of the speakers.
///
/// Without headphones the microphone records the call too, at a level that stays the same
/// fraction of the call app's track for the whole meeting (about −33 dB on a MacBook). Your own
/// voice is much louder than that echo. So a stretch of the microphone track counts as you when
/// it is well above what the echo alone would give.
public struct MeetingEcho: Sendable {
    /// 20 ms frames at 16 kHz.
    static let frameLength = 320
    public static let frameSeconds = 0.02

    /// Per frame of the microphone track: whether it sounds like you rather than echo.
    public let userFrames: [Bool]
    /// The microphone's level relative to the call app's track, measured where the call is loud.
    public let echoGain: Float

    /// - Parameters:
    ///   - microphone: 16 kHz samples of one microphone segment.
    ///   - system: 16 kHz samples of the call app's track.
    ///   - offset: Where the microphone segment starts on the call track's timeline, in seconds.
    public init(microphone: [Float], system: [Float], offset: Double) {
        let mic = Self.envelope(microphone)
        let shift = Int((offset / Self.frameSeconds).rounded())
        let call = Self.envelope(system)
        // The call track's level around each microphone frame (±200 ms): the echo lags and rings on.
        let spread = 10
        let callNear: [Float] = mic.indices.map { index in
            let center = index + shift
            let low = max(0, center - spread)
            let high = min(call.count - 1, center + spread)
            return low <= high ? call[low...high].max() ?? 0 : 0
        }
        // Echo gain: the typical mic/call ratio where the call is loud.
        let loud = Self.percentile(callNear, 0.6)
        let ratios = zip(mic, callNear).compactMap { pair -> Float? in
            pair.1 > loud && pair.1 > 0 ? pair.0 / pair.1 : nil
        }.sorted()
        let gain = ratios.isEmpty ? 0 : ratios[ratios.count / 2]
        let floor = Self.percentile(mic, 0.1)
        echoGain = gain
        // Well above the expected echo (about +10 dB) and the room's noise (+14 dB). Single frames
        // are dropped: echo has stray loud frames, a voice holds for at least 40 ms. Tuned on three
        // calls through MacBook speakers.
        let loudEnough = zip(mic, callNear).map { level, call in level > 3 * gain * call && level > 5 * floor }
        userFrames = loudEnough.indices.map { index in
            loudEnough[index]
                && ((index > 0 && loudEnough[index - 1]) || (index + 1 < loudEnough.count && loudEnough[index + 1]))
        }
    }

    /// The share of a stretch of the microphone segment (seconds from its own start) that sounds
    /// like you.
    public func userShare(from start: Double, to end: Double) -> Double {
        let low = max(0, Int(start / Self.frameSeconds))
        let high = min(userFrames.count, Int((end / Self.frameSeconds).rounded(.up)))
        guard low < high else { return 0 }
        return Double(userFrames[low..<high].filter { $0 }.count) / Double(high - low)
    }

    /// The value below which `share` of the values lie; 0 for no values.
    static func percentile(_ values: [Float], _ share: Double) -> Float {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        return sorted[min(sorted.count - 1, Int(Double(sorted.count) * share))]
    }

    /// Stretches of the microphone segment where you speak, in seconds from its start: voiced
    /// frames closer than `mergeGap` joined, stretches with less than `minimumVoiced` seconds of
    /// voice dropped, each widened by `padding` to keep the soft starts and ends of words.
    public func userRegions(
        mergeGap: Double = 0.6, minimumVoiced: Double = 0.3, padding: Double = 0.3
    ) -> [ClosedRange<Double>] {
        var regions: [(start: Int, end: Int, voiced: Int)] = []
        let gapFrames = Int(mergeGap / Self.frameSeconds)
        for (index, voiced) in userFrames.enumerated() where voiced {
            if let last = regions.last, index - last.end <= gapFrames {
                regions[regions.count - 1].end = index
                regions[regions.count - 1].voiced += 1
            } else {
                regions.append((index, index, 1))
            }
        }
        let total = Double(userFrames.count) * Self.frameSeconds
        var result: [ClosedRange<Double>] = []
        for region in regions where Double(region.voiced) * Self.frameSeconds >= minimumVoiced {
            let start = max(0, Double(region.start) * Self.frameSeconds - padding)
            let end = min(total, Double(region.end + 1) * Self.frameSeconds + padding)
            // Padding can make neighbours touch.
            if let last = result.last, start <= last.upperBound {
                result[result.count - 1] = last.lowerBound...end
            } else {
                result.append(start...end)
            }
        }
        return result
    }

    /// RMS level per frame.
    static func envelope(_ samples: [Float]) -> [Float] {
        let count = samples.count / frameLength
        guard count > 0 else { return [] }
        return samples.withUnsafeBufferPointer { buffer in
            guard let base = buffer.baseAddress else { return [] }
            return (0..<count).map { index in
                var rms: Float = 0
                vDSP_rmsqv(base + index * frameLength, 1, &rms, vDSP_Length(frameLength))
                return rms
            }
        }
    }
}

/// Where speech starts on a track, to correct Whisper's word times.
///
/// With chunking at pauses, Whisper often puts the first words of a chunk seconds before the
/// speech actually starts (2.7 s on a test call), which puts lines at the wrong time and words on
/// the wrong speaker. The audio itself says where the speech is.
public struct SpeechOnsets: Sendable {
    let levels: [Float]
    let threshold: Float

    public init(samples: [Float]) {
        levels = MeetingEcho.envelope(samples)
        let floor = MeetingEcho.percentile(levels, 0.1)
        let typical = MeetingEcho.percentile(levels, 0.5)
        // About 15 dB over the quiet parts, but under a third of the typical level (a track with
        // little silence), and never below −55 dBFS.
        threshold = max(min(floor * 5.6, typical * 0.3), 0.0018)
    }

    /// The first moment from `start - before` to `start + after` where speech holds for 60 ms.
    public func onset(near start: Double, before: Double = 0.5, after: Double = 4) -> Double? {
        let frame = MeetingEcho.frameSeconds
        let low = max(0, Int((start - before) / frame))
        let high = min(levels.count - 3, Int((start + after) / frame))
        guard low <= high else { return nil }
        for index in low...high where levels[index...index + 2].allSatisfy({ $0 > threshold }) {
            return Double(index) * frame
        }
        return nil
    }

    /// Moves each run of words (split at pauses over `gap` seconds) so that it starts where the
    /// speech does, without moving a run past the next one.
    public func aligning(_ words: [TimedText], gap: Double = 1.0) -> [TimedText] {
        var runs: [[TimedText]] = []
        for word in words {
            if let last = runs.last?.last, word.start - last.end <= gap {
                runs[runs.count - 1].append(word)
            } else {
                runs.append([word])
            }
        }
        var result: [TimedText] = []
        for (index, run) in runs.enumerated() {
            guard let first = run.first, let onset = onset(near: first.start) else {
                result += run
                continue
            }
            var shift = onset - first.start
            if index + 1 < runs.count, let next = runs[index + 1].first, let last = run.last {
                shift = min(shift, next.start - last.end + max(0, shift))
            }
            result += run.map { $0.shifted(by: shift) }
        }
        return result
    }
}

extension MeetingTranscript {
    /// Whisper sometimes loops on a phrase ("…they can be blamed for, that they can be blamed
    /// for…"). Keeps the first of any run of three or more words repeated back to back.
    public static func collapsingRepeats(_ text: String) -> String {
        var tokens = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        func key(_ token: String) -> String { token.lowercased().filter { $0.isLetter || $0.isNumber } }
        var changed = true
        while changed {
            changed = false
            for length in stride(from: min(12, tokens.count / 2), through: 3, by: -1) {
                var index = 0
                while index + 2 * length <= tokens.count {
                    let first = tokens[index..<index + length].map(key)
                    let second = tokens[index + length..<index + 2 * length].map(key)
                    if first == second, first.contains(where: { !$0.isEmpty }) {
                        tokens.removeSubrange(index + length..<index + 2 * length)
                        changed = true
                    } else {
                        index += 1
                    }
                }
            }
        }
        return tokens.joined(separator: " ")
    }

    /// Drops a line that was nearly all said by the same speaker in the minute before: Whisper
    /// repeats itself on quiet audio and re-transcribes stretches at its window boundaries.
    ///
    /// Lines are compared by runs of three words, not single words: neighbouring lines of the same
    /// person share many words ("and", "that", the topic), but a repeat shares whole phrases.
    static func removingRepeatedLines(_ lines: [Line]) -> [Line] {
        var result: [Line] = []
        for line in lines {
            let words = MeetingTranscript.words(line.text)
            let previous = result.last { $0.speaker == line.speaker && line.start - $0.start <= 30 }
            if !words.isEmpty, previous.map({ MeetingTranscript.words($0.text) == words }) == true {
                continue
            }
            let runs = Self.runs(of: words)
            if runs.count >= 4 {
                let recent = Set(
                    result.filter { $0.speaker == line.speaker && line.start - $0.start <= 60 }
                        .flatMap { Self.runs(of: MeetingTranscript.words($0.text)) })
                if Double(runs.filter(recent.contains).count) / Double(runs.count) >= 0.6 { continue }
            }
            result.append(line)
        }
        return result
    }

    private static func runs(of words: [String]) -> [String] {
        guard words.count >= 3 else { return [] }
        return (0...(words.count - 3)).map { words[$0..<$0 + 3].joined(separator: " ") }
    }

    /// Removes the dashes Whisper puts before lines of dialogue, as in subtitles.
    public static func removingDialogueDashes(_ text: String) -> String {
        text.replacingOccurrences(of: #"(^|(?<=[.!?…])\s)[-–—]\s+"#, with: "$1", options: .regularExpression)
    }
}
