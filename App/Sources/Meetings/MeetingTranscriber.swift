// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import Foundation
import OSLog
import Observation
import TypistAudio
import TypistCore
import TypistProviders

/// Transcribes recorded meetings on this Mac, one at a time, and keeps `transcript.json` next to
/// the tracks.
@MainActor @Observable
final class MeetingTranscriber {
    static let shared = MeetingTranscriber()

    enum Status: Equatable {
        case queued
        case loadingModel
        /// Overall share done, over both tracks.
        case transcribing(Double)
        case findingSpeakers
        case failed(String)
    }

    /// Meetings being transcribed or waiting, by meeting id. Done meetings are not listed.
    private(set) var status: [String: Status] = [:]
    private(set) var transcripts: [String: MeetingTranscript] = [:]

    /// Its running meeting is the one being transcribed now. Progress reports arrive
    /// asynchronously and can come in after the work is done; only the running meeting's status
    /// is updated.
    @ObservationIgnored private var queue = SerialQueue()
    @ObservationIgnored private let logger = Logger(subsystem: "space.deb.typist", category: "meetings")
    private var settings: AppSettings { .shared }
    private var recorder: MeetingRecorder { .shared }

    /// The saved transcript of a meeting, if it has one.
    func transcript(of record: MeetingRecord) -> MeetingTranscript? {
        if let cached = transcripts[record.id] { return cached }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: url(of: record)),
            let transcript = try? decoder.decode(MeetingTranscript.self, from: data)
        else { return nil }
        transcripts[record.id] = transcript
        return transcript
    }

    func transcribe(_ record: MeetingRecord) {
        guard !recorder.finishingIDs.contains(record.id) else { return }
        guard status[record.id] == nil || status[record.id].map(isFailed) == true else { return }
        status[record.id] = .queued
        queue.enqueue(record.id)
        runQueue()
    }

    /// Throws away a meeting's transcript and makes it again, for example after changing the
    /// language or the speech model.
    func retranscribe(_ record: MeetingRecord) {
        guard queue.running != record.id, status[record.id] != .queued else { return }
        transcripts[record.id] = nil
        try? FileManager.default.removeItem(at: url(of: record))
        status[record.id] = nil
        transcribe(record)
    }

    private func reportProgress(_ fraction: Double, for id: String) {
        guard queue.running == id, status[id] != nil else { return }
        status[id] = .transcribing(fraction)
    }

    private func isFailed(_ status: Status) -> Bool {
        if case .failed = status { return true }
        return false
    }

    private func url(of record: MeetingRecord) -> URL {
        recorder.folder(of: record).appending(path: "transcript.json")
    }

    private func runQueue() {
        guard let recordID = queue.start() else { return }
        guard let record = recorder.recordings.first(where: { $0.id == recordID }) else {
            status[recordID] = .failed("Meeting record not found")
            queue.finish()
            runQueue()
            return
        }
        Task {
            defer {
                queue.finish()
                runQueue()
            }
            do {
                let transcript = try await run(record)
                save(transcript, for: record)
                transcripts[record.id] = transcript
                status[record.id] = nil
            } catch {
                logger.error("meeting transcription failed: \(String(describing: error), privacy: .public)")
                status[record.id] = .failed(String(describing: error))
            }
        }
    }

    /// Transcribes the other side's track and each microphone segment, placing the segments on
    /// the other side's timeline by their host-clock start.
    private func run(_ record: MeetingRecord) async throws -> MeetingTranscript {
        let id = record.id
        status[id] = .loadingModel
        // Its own copy of the model, so dictation keeps working while a long meeting is transcribed.
        let variant = settings.modelVariant
        let transcriber = WhisperKitTranscriber(variant: variant, modelsDirectory: SpeechModel.directory)
        try await transcriber.prepare { _ in }

        let folder = recorder.folder(of: record)
        // The call app's track, or the whole sound of an imported file.
        let system = record.tracks.first { !$0.name.hasPrefix("microphone") }
        let microphone = record.tracks.filter { $0.name.hasPrefix("microphone") }
        let tracks = [system].compactMap { $0 } + microphone
        let total = max(1, tracks.reduce(0) { $0 + $1.secondsByFrames })
        let language = settings.language
        // No dictionary prompt for meetings: on long tracks it made Whisper skip the first chunk
        // and translate the echo into English. The dictionary is still applied to the text.
        let cleanup = settings.cleanup

        var lines: [MeetingTranscript.Line] = []
        var whisper: [MeetingTranscript.TrackText] = []
        /// Kept to tell your voice from the call's echo on the microphone track.
        var systemSamples: [Float]?
        var detected: String?
        var done = 0.0
        for track in tracks {
            let samples = try await Task.detached(priority: .utility) {
                try AudioFileSamples.load(folder.appending(path: track.file))
            }.value
            let before = done
            let share = track.secondsByFrames / total
            status[id] = .transcribing(before)
            let report: @Sendable (Double) -> Void = { fraction in
                Task { @MainActor in MeetingTranscriber.shared.reportProgress(before + share * fraction, for: id) }
            }
            let offset = Self.offset(of: track, from: system)
            var words: [TimedText] = []
            let speakers: [MeetingTranscript.Speaker]
            let isOtherSide = track.name == system?.name
            if isOtherSide || systemSamples == nil {
                let result = try await transcriber.transcribeTimed(
                    samples, language: language, prompt: nil, words: true, onProgress: report)
                detected = detected ?? result.language
                words = await Task.detached(priority: .utility) {
                    SpeechOnsets(samples: samples).aligning(result.segments)
                }.value
                whisper.append(.init(track: track.name, words: words.map { $0.shifted(by: offset) }))
                if isOtherSide {
                    systemSamples = samples
                    status[id] = .findingSpeakers
                    speakers = await self.speakers(of: words, samples: samples)
                } else {
                    speakers = words.map { _ in .me }
                }
            } else if let systemSamples {
                // The whole track as Whisper hears it, echo included, to compare with what is kept.
                let full = try await transcriber.transcribeTimed(
                    samples, language: language ?? detected, prompt: nil, words: true
                ) { fraction in report(fraction * 0.6) }
                let aligned = await Task.detached(priority: .utility) {
                    SpeechOnsets(samples: samples).aligning(full.segments)
                }.value
                whisper.append(.init(track: track.name, words: aligned.map { $0.shifted(by: offset) }))
                // Without headphones the microphone also hears the call. Find where you speak by
                // loudness, and transcribe only those stretches: the echo never reaches Whisper, and
                // the times come from the audio, not from Whisper's word alignment, which was off by
                // seconds in tests.
                let echo = await Task.detached(priority: .utility) {
                    MeetingEcho(microphone: samples, system: systemSamples, offset: offset)
                }.value
                // Pauses inside a phrase are often over a second; keep the phrase together.
                let regions = echo.userRegions(mergeGap: 1.5, minimumVoiced: 0.5, padding: 0.4)
                for (index, region) in regions.enumerated() {
                    let low = Int(region.lowerBound * 16_000)
                    let high = min(samples.count, Int(region.upperBound * 16_000))
                    guard high > low else { continue }
                    // Short stretches transcribe best the way dictation does; their time is the
                    // stretch's, so no word alignment is needed.
                    // No dictionary prompt: on a short stretch with echo underneath, Whisper either
                    // repeated the prompt or switched to translating it.
                    let transcript = try await transcriber.transcribe(
                        Array(samples[low..<high]), language: language ?? detected, prompt: nil)
                    let text = transcript.text.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !text.isEmpty {
                        words.append(TimedText(start: region.lowerBound, end: region.upperBound, text: " " + text))
                    }
                    report(0.6 + 0.4 * Double(index + 1) / Double(regions.count))
                }
                speakers = words.map { _ in .me }
            } else {
                speakers = []
            }
            done += share
            lines += MeetingTranscript.lines(words: words.map { $0.shifted(by: offset) }, speakers: speakers)
                .map { line in
                    var line = line
                    line.text = cleanup.applyDictionary(to: cleanup.applyRules(to: line.text)).text
                    return line
                }
        }
        return MeetingTranscript.merge(
            // Your lines come from where the microphone is louder than the echo; checking their words
            // against the call only threw away phrases that merely share words with it.
            lines: lines, echoShare: 1.1, whisper: whisper, model: SpeechModel.named(variant).name,
            language: language ?? detected)
    }

    /// Who said each word on the call track. Without the diarization models (offline on first
    /// use) everyone is "Others".
    private func speakers(of words: [TimedText], samples: [Float]) async -> [MeetingTranscript.Speaker] {
        let directory = SpeechModel.directory.appending(path: "diarization", directoryHint: .isDirectory)
        do {
            let turns = try await FluidDiarizer.diarize(samples, modelsDirectory: directory) { _ in }
            return MeetingTranscript.assignSpeakers(words: words, turns: turns)
        } catch {
            logger.error("diarization failed: \(String(describing: error), privacy: .public)")
            return words.map { _ in .others }
        }
    }

    /// Where a track starts on the other side's timeline, in seconds.
    static func offset(of track: TrackStats, from system: TrackStats?) -> Double {
        guard let system, track.name != system.name, let start = system.firstHostTime, let first = track.firstHostTime
        else { return 0 }
        return HostTime.seconds(from: start, to: first)
    }

    private func save(_ transcript: MeetingTranscript, for record: MeetingRecord) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            try encoder.encode(transcript).write(to: url(of: record), options: .atomic)
        } catch {
            logger.error("couldn't save transcript.json: \(String(describing: error), privacy: .public)")
        }
    }
}
