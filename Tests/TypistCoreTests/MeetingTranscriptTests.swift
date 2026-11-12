// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import Foundation
import Testing

@testable import TypistCore

@Suite struct MeetingTranscriptTests {
    let others = [
        TimedText(start: 5.0, end: 9.5, text: "Let's start with the budget for next quarter."),
        TimedText(start: 20.0, end: 24.0, text: "Any questions about the plan?"),
    ]

    @Test func dropsTheOtherSideHeardThroughTheSpeakers() {
        let me = [TimedText(start: 5.1, end: 9.0, text: "let's start with the budget for next quarter")]
        let transcript = MeetingTranscript.merge(me: me, others: others, model: "test", language: "en")
        #expect(transcript.echoLinesDropped == 1)
        #expect(transcript.lines.allSatisfy { $0.speaker == .others })
    }

    @Test func keepsWhatYouSaid() {
        let me = [
            TimedText(start: 12.0, end: 15.0, text: "I think we should cut the travel costs."),
            // Same time as the other side, different words: you talking over them.
            TimedText(start: 21.0, end: 23.0, text: "Yes, one about hiring."),
        ]
        let transcript = MeetingTranscript.merge(me: me, others: others, model: "test", language: "en")
        #expect(transcript.echoLinesDropped == 0)
        #expect(transcript.lines.map(\.speaker) == [.others, .me, .others, .me])
    }

    @Test func dropsEmptyLines() {
        let transcript = MeetingTranscript.merge(
            me: [TimedText(start: 1, end: 2, text: "")], others: [], model: "test", language: nil)
        #expect(transcript.lines.isEmpty)
        #expect(transcript.echoLinesDropped == 0)
    }

    @Test func formatsPlainText() {
        let transcript = MeetingTranscript.merge(
            me: [TimedText(start: 65, end: 70, text: "Sounds good.")],
            others: [TimedText(start: 3725, end: 3730, text: "Thanks, bye.")], model: "test", language: "en")
        #expect(transcript.plainText() == "[1:05] You: Sounds good.\n[1:02:05] Others: Thanks, bye.")
    }

    @Test func shiftsSegmentsOntoTheTimeline() {
        #expect(TimedText(start: 1, end: 2, text: "a").shifted(by: 10) == TimedText(start: 11, end: 12, text: "a"))
    }

    @Test func roundTripsThroughJSON() throws {
        let transcript = MeetingTranscript.merge(
            me: [TimedText(start: 1, end: 2, text: "Hi.")], others: [],
            createdAt: Date(timeIntervalSince1970: 1_800_000_000), model: "test", language: "en")
        let data = try JSONEncoder().encode(transcript)
        #expect(try JSONDecoder().decode(MeetingTranscript.self, from: data) == transcript)
    }
}

@Suite struct MeetingEchoTests {
    /// Speech-like noise bursts: on for `on` seconds, off for `off`.
    func bursts(seconds: Double, on: Double, off: Double, level: Float, seed: UInt64) -> [Float] {
        var generator = SplitMix(seed: seed)
        let count = Int(seconds * 16_000)
        let period = on + off
        return (0..<count).map { index in
            let t = Double(index) / 16_000
            guard t.truncatingRemainder(dividingBy: period) < on else { return 0 }
            return level * (Float(generator.next() % 2000) / 1000 - 1)
        }
    }

    @Test func echoAloneIsNotYou() {
        let call = bursts(seconds: 30, on: 2, off: 1, level: 0.5, seed: 1)
        // The call through the speakers, 33 dB down and 50 ms late, plus a little room noise.
        var noise = SplitMix(seed: 2)
        let mic = (0..<call.count).map { index in
            (index >= 800 ? call[index - 800] * 0.022 : 0) + 0.0005 * (Float(noise.next() % 2000) / 1000 - 1)
        }
        let echo = MeetingEcho(microphone: mic, system: call, offset: 0)
        #expect(echo.userShare(from: 0, to: 30) < 0.05)
    }

    @Test func yourVoiceIsYou() {
        let call = bursts(seconds: 30, on: 2, off: 1, level: 0.5, seed: 1)
        let voice = bursts(seconds: 30, on: 1, off: 4, level: 0.1, seed: 3)
        let mic = (0..<call.count).map { index in (index >= 800 ? call[index - 800] * 0.022 : 0) + voice[index] }
        let echo = MeetingEcho(microphone: mic, system: call, offset: 0)
        // The voice speaks during the first second of every five.
        #expect(echo.userShare(from: 0, to: 1) > 0.8)
        #expect(echo.userShare(from: 1.5, to: 4.5) < 0.1)
    }

    @Test func collapsesLoops() {
        #expect(
            MeetingTranscript.collapsingRepeats(
                "They can be blamed for that, they can be blamed for that, they can be blamed for that end.")
                == "They can be blamed for that, end.")
        #expect(MeetingTranscript.collapsingRepeats("Very very good.") == "Very very good.")
    }

    @Test func dropsRepeatedLines() {
        let me = (0..<4).map { TimedText(start: 268 + Double($0), end: 270 + Double($0), text: "...back to this.") }
        let transcript = MeetingTranscript.merge(me: me, others: [], model: "test", language: "en")
        #expect(transcript.lines.count == 1)
    }
}

/// A seeded generator, so the tests are the same every run.
struct SplitMix: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

@Suite struct MeetingTranscriptCleanupTests {
    @Test func dropsAStretchTranscribedTwice() {
        let others = [
            TimedText(start: 0, end: 8, text: "Friends, hello everyone! A few facts about today's guest."),
            TimedText(start: 8, end: 12, text: "He founded the largest online school."),
            TimedText(
                start: 12, end: 20, text: "- Friends, hello everyone! A few facts about today's guest. - He founded"),
            TimedText(start: 20, end: 25, text: "Today the school has fifteen thousand teachers."),
        ]
        let transcript = MeetingTranscript.merge(me: [], others: others, model: "test", language: "en")
        #expect(transcript.lines.map(\.start) == [0, 8, 20])
    }

    @Test func keepsShortRepliesThatRepeatAWord() {
        let others = [
            TimedText(start: 0, end: 3, text: "Do you agree with the plan?"),
            TimedText(start: 4, end: 5, text: "Yes."),
            TimedText(start: 6, end: 7, text: "The plan, yes, I agree."),
        ]
        #expect(MeetingTranscript.merge(me: [], others: others, model: "test", language: "en").lines.count == 3)
    }

    @Test func removesDialogueDashes() {
        #expect(
            MeetingTranscript.removingDialogueDashes("- Hello there. - Thanks for coming. Well-known co-founder.")
                == "Hello there. Thanks for coming. Well-known co-founder.")
    }
}

@Suite struct RepeatedLineTests {
    @Test func keepsNewLinesOnTheSameTopic() {
        let others = [
            TimedText(
                start: 0, end: 20,
                text: "Education is very important and it builds the foundation, especially in our country."),
            TimedText(
                start: 22, end: 40,
                text: "And if we look at education today, it is not the foundation it was, especially for us."),
        ]
        #expect(MeetingTranscript.merge(me: [], others: others, model: "test", language: "en").lines.count == 2)
    }
}

@Suite struct SpeakerTests {
    let words = [
        TimedText(start: 0.0, end: 0.4, text: " Hello"),
        TimedText(start: 0.5, end: 0.9, text: " everyone."),
        TimedText(start: 1.2, end: 1.6, text: " Thanks"),
        TimedText(start: 1.7, end: 2.0, text: " for"),
        TimedText(start: 2.1, end: 2.6, text: " coming."),
        TimedText(start: 3.0, end: 3.4, text: " Sure."),
    ]
    let turns = [
        SpeakerTurn(start: 0, end: 1.0, speaker: "B"),
        SpeakerTurn(start: 1.1, end: 2.7, speaker: "A"),
        SpeakerTurn(start: 2.9, end: 3.5, speaker: "B"),
    ]

    @Test func numbersSpeakersByFirstWords() {
        let speakers = MeetingTranscript.assignSpeakers(words: words, turns: turns)
        #expect(speakers == [.remote(1), .remote(1), .remote(2), .remote(2), .remote(2), .remote(1)])
    }

    @Test func groupsWordsIntoLinesBySpeaker() {
        let speakers = MeetingTranscript.assignSpeakers(words: words, turns: turns)
        let lines = MeetingTranscript.lines(words: words, speakers: speakers)
        #expect(lines.map(\.text) == ["Hello everyone.", "Thanks for coming.", "Sure."])
        #expect(lines.map(\.speaker.name) == ["Speaker 1", "Speaker 2", "Speaker 1"])
        #expect(lines[1].start == 1.2 && lines[1].end == 2.6)
    }

    @Test func wordsOutsideTurnsKeepTheLastSpeaker() {
        let speakers = MeetingTranscript.assignSpeakers(
            words: [TimedText(start: 0, end: 0.5, text: "a"), TimedText(start: 9, end: 9.5, text: "b")],
            turns: [SpeakerTurn(start: 0, end: 1, speaker: "X")])
        #expect(speakers == [.remote(1), .remote(1)])
    }

    @Test func storesSpeakersAsPlainStrings() throws {
        let line = MeetingTranscript.Line(start: 0, end: 1, speaker: .remote(2), text: "Hi")
        let json = String(decoding: try JSONEncoder().encode(line), as: UTF8.self)
        #expect(json.contains("\"speaker\":\"S2\""))
        #expect(try JSONDecoder().decode(MeetingTranscript.Line.self, from: Data(json.utf8)) == line)
    }
}

@Suite struct WordJoiningTests {
    @Test func attachesHyphenatedPieces() {
        let words = [
            TimedText(start: 0, end: 0.3, text: " the"), TimedText(start: 0.3, end: 0.6, text: " online"),
            TimedText(start: 0.6, end: 0.9, text: "-school"), TimedText(start: 0.9, end: 1.2, text: " grew."),
        ]
        let lines = MeetingTranscript.lines(words: words, speakers: words.map { _ in .remote(1) })
        #expect(lines.map(\.text) == ["the online-school grew."])
    }

    @Test func givesWordsBeforeTheFirstTurnToTheFirstSpeaker() {
        let speakers = MeetingTranscript.assignSpeakers(
            words: [TimedText(start: 0, end: 0.2, text: "a"), TimedText(start: 5, end: 5.5, text: "b")],
            turns: [SpeakerTurn(start: 4.8, end: 6, speaker: "X")])
        #expect(speakers == [.remote(1), .remote(1)])
    }
}

@Suite struct StackedWordTests {
    @Test func spreadsWordsGivenTheSameInstant() {
        let words = [
            TimedText(start: 0.4, end: 0.4, text: " Hello"), TimedText(start: 0.4, end: 0.4, text: " there."),
            TimedText(start: 1.5, end: 1.9, text: " Next"),
        ]
        let spread = TimedText.spreadingStackedWords(words)
        #expect(spread[0].start == 0.4)
        #expect(spread[0].end > 0.4 && spread[0].end == spread[1].start)
        #expect(spread[1].end <= 1.5)
        #expect(spread[2] == words[2])
    }
}

@Suite struct UserRegionTests {
    @Test func findsWhereYouSpeak() {
        let call = MeetingEchoTests().bursts(seconds: 30, on: 2, off: 1, level: 0.5, seed: 1)
        // You speak 10–12 s and 20.0–21.5 s, over the call's echo.
        var voice = [Float](repeating: 0, count: call.count)
        var generator = SplitMix(seed: 9)
        for range in [160_000..<192_000, 320_000..<344_000] {
            for index in range { voice[index] = 0.1 * (Float(generator.next() % 2000) / 1000 - 1) }
        }
        let mic = (0..<call.count).map { index in (index >= 800 ? call[index - 800] * 0.022 : 0) + voice[index] }
        let regions = MeetingEcho(microphone: mic, system: call, offset: 0).userRegions()
        #expect(regions.count == 2)
        #expect(abs(regions[0].lowerBound - 9.7) < 0.15 && abs(regions[0].upperBound - 12.3) < 0.15)
        #expect(abs(regions[1].lowerBound - 19.7) < 0.15 && abs(regions[1].upperBound - 21.8) < 0.15)
    }
}

@Suite struct WhisperTextTests {
    @Test func keepsWhisperTextPerTrack() throws {
        let words = [
            TimedText(start: 0, end: 0.5, text: " Hello"), TimedText(start: 0.5, end: 1, text: " there."),
            TimedText(start: 5, end: 5.5, text: " Later."),
        ]
        let track = MeetingTranscript.TrackText(track: "system", words: words)
        #expect(track.lines.map(\.text) == ["Hello there.", "Later."])
        let transcript = MeetingTranscript.merge(lines: [], whisper: [track], model: "test", language: "en")
        let decoded = try JSONDecoder().decode(MeetingTranscript.self, from: JSONEncoder().encode(transcript))
        #expect(decoded.whisper == [track])
    }

    @Test func readsTranscriptsWithoutWhisperText() throws {
        let json = #"{"version":2,"createdAt":0,"model":"m","lines":[],"echoLinesDropped":0}"#
        #expect(try JSONDecoder().decode(MeetingTranscript.self, from: Data(json.utf8)).whisper == nil)
    }
}

@Suite struct SpeechOnsetTests {
    /// Silence, then speech-like noise from 14 s.
    let samples: [Float] = {
        var generator = SplitMix(seed: 4)
        return (0..<(20 * 16_000)).map { index in
            index < 14 * 16_000 ? 0 : 0.2 * (Float(generator.next() % 2000) / 1000 - 1)
        }
    }()

    @Test func findsWhereSpeechStarts() throws {
        let onset = try #require(SpeechOnsets(samples: samples).onset(near: 11.3))
        #expect(abs(onset - 14) < 0.05)
    }

    @Test func movesEarlyWordsToTheSpeech() {
        let words = [
            TimedText(start: 11.3, end: 11.8, text: " Hello"), TimedText(start: 11.9, end: 12.3, text: " there."),
        ]
        let aligned = SpeechOnsets(samples: samples).aligning(words)
        #expect(abs(aligned[0].start - 14) < 0.05)
        #expect(abs((aligned[1].start - aligned[0].start) - 0.6) < 0.01)
    }
}

@Suite struct SpeakerNameTests {
    @Test func usesGivenNames() {
        let names = ["S2": "Anna", "me": "  ", "S1": " Bob "]
        #expect(MeetingTranscript.Speaker.remote(2).name(in: names) == "Anna")
        #expect(MeetingTranscript.Speaker.remote(1).name(in: names) == "Bob")
        #expect(MeetingTranscript.Speaker.me.name(in: names) == "You")
        #expect(MeetingTranscript.Speaker.remote(3).name(in: names) == "Speaker 3")
    }

    @Test func plainTextUsesNames() {
        let transcript = MeetingTranscript.merge(
            me: [TimedText(start: 1, end: 2, text: "Hi.")],
            others: [TimedText(start: 3, end: 4, text: "Hello.")], model: "m", language: nil)
        #expect(transcript.plainText(names: ["me": "Leo"]) == "[0:01] Leo: Hi.\n[0:03] Others: Hello.")
    }

    @Test func suggestsEarlierNames() {
        let earlier = [["S1": "Anna Smith", "S2": "Bob"], ["S1": "anna smith", "S2": "Alex"]]
        let suggestions = MeetingTranscript.Speaker.suggestions
        #expect(suggestions(earlier, "", [], 5) == ["Anna Smith", "Bob", "Alex"])
        #expect(suggestions(earlier, "a", [], 5) == ["Anna Smith", "Alex"])
        #expect(suggestions(earlier, "sm", [], 5) == ["Anna Smith"])
        #expect(suggestions(earlier, "", ["BOB"], 5) == ["Anna Smith", "Alex"])
        #expect(suggestions(earlier, "", [], 1) == ["Anna Smith"])
    }
}
