// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import AVFoundation
import AppKit
import OSLog
import Observation
import TypistAudio

/// One recorded meeting: a folder with the other side's track, the microphone track (in
/// segments when the input device changed) and `meeting.json`.
struct MeetingRecord: Codable, Identifiable, Equatable {
    var startedAt: Date
    /// Nil while recording, or when Typist quit before the meeting was stopped.
    var endedAt: Date?
    /// The app recorded as the other side, or nil for all system audio.
    var sourceName: String?
    var sourceBundleID: String?
    var outputDevice: String
    var inputDevice: String
    var tracks: [TrackStats]
    /// Whether the tracks were compressed to AAC after the meeting.
    var compressed = false
    var log: [String] = []

    /// The folder name, set when loading.
    var id = ""

    var seconds: Double {
        if let endedAt { return endedAt.timeIntervalSince(startedAt) }
        return tracks.map(\.secondsByFrames).max() ?? 0
    }

    enum CodingKeys: String, CodingKey {
        case startedAt, endedAt, sourceName, sourceBundleID, outputDevice, inputDevice, tracks, compressed, log
    }

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id && lhs.endedAt == rhs.endedAt }
}

/// Records meetings: the call app's audio and the microphone, as separate tracks, on this Mac.
@MainActor @Observable
final class MeetingRecorder {
    static let shared = MeetingRecorder()

    static let directory = URL.applicationSupportDirectory.appending(
        path: "Typist/Meetings", directoryHint: .isDirectory)

    private(set) var isRecording = false
    /// Compressing the tracks after a meeting.
    private(set) var isFinishing = false
    private(set) var startedAt: Date?
    private(set) var otherSideLevel: Float = 0
    private(set) var microphoneLevel: Float = 0
    /// Whether the other side's track has had any sound. A denied permission records silence.
    private(set) var heardOtherSide = false
    private(set) var error: String?
    private(set) var recordings: [MeetingRecord] = []

    /// The app to record as the other side; nil records all system audio.
    var sourceBundleID: String? {
        didSet { UserDefaults.standard.set(sourceBundleID ?? "", forKey: "meetingSource") }
    }
    var consentShown: Bool {
        didSet { UserDefaults.standard.set(consentShown, forKey: "meetingConsentShown") }
    }

    @ObservationIgnored private var tap: ProcessTapCapture?
    @ObservationIgnored private var microphone: MicrophoneCapture?
    @ObservationIgnored private var meters: Task<Void, Never>?
    @ObservationIgnored private var folder: URL?
    @ObservationIgnored private var record: MeetingRecord?
    @ObservationIgnored private let logger = Logger(subsystem: "space.deb.typist", category: "meetings")

    init() {
        let stored = UserDefaults.standard.string(forKey: "meetingSource") ?? ""
        sourceBundleID = stored.isEmpty ? nil : stored
        consentShown = UserDefaults.standard.bool(forKey: "meetingConsentShown")
        reload()
    }

    /// The folder name of the meeting being recorded.
    var currentID: String? { isRecording ? folder?.lastPathComponent : nil }

    /// What is being recorded as the other side.
    var sourceName: String { record?.sourceName ?? "All system audio" }

    // MARK: - Recording

    func start() async {
        guard !isRecording else { return }
        error = nil
        heardOtherSide = false
        let app = AudioApp.running().first { $0.bundleID == sourceBundleID }
        let start = Date()
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let folder = Self.directory.appending(path: formatter.string(from: start), directoryHint: .isDirectory)
        var record = MeetingRecord(
            startedAt: start, sourceName: app?.name, sourceBundleID: app?.bundleID,
            outputDevice: AudioDevices.defaultOutputName(), inputDevice: AudioDevices.defaultInputName(), tracks: [])
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let tap = ProcessTapCapture(
                target: app.map { .app($0) } ?? .allSystemAudio, tracking: .updateDescription,
                outputURL: folder.appending(path: "system.caf"), onEvent: Self.log)
            _ = try tap.start()
            self.tap = tap
        } catch {
            self.error = "Couldn’t record \(app?.name ?? "system audio"): \(error)"
            logger.error("meeting start failed: \(String(describing: error), privacy: .public)")
            try? FileManager.default.removeItem(at: folder)
            return
        }
        if await MicrophoneCapture.requestPermission() {
            let microphone = MicrophoneCapture(
                url: folder.appending(path: "microphone.caf"), voiceProcessing: false, onEvent: Self.log)
            do {
                _ = try microphone.start()
                self.microphone = microphone
            } catch {
                record.log.append("microphone failed: \(error)")
            }
        } else {
            record.log.append("microphone permission denied")
        }
        self.folder = folder
        self.record = record
        // Written now too, so a meeting cut short by a crash is still listed.
        save(record, in: folder)
        startedAt = start
        isRecording = true
        startMeters()
        reload()
    }

    func stop() {
        guard isRecording, let folder, var record else { return }
        meters?.cancel()
        tap?.stop()
        microphone?.stop()
        record.endedAt = Date()
        record.tracks = ([tap?.writer].compactMap { $0 } + (microphone?.segments ?? [])).map(\.stats)
        record.log += pendingLog
        pendingLog = []
        save(record, in: folder)
        tap = nil
        microphone = nil
        self.record = nil
        self.folder = nil
        isRecording = false
        startedAt = nil
        otherSideLevel = 0
        microphoneLevel = 0
        reload()
        compress(record, in: folder)
    }

    /// Stops without compressing, when Typist quits mid-meeting. The CAF tracks stay as they are.
    func stopForQuit() {
        guard isRecording, let folder, var record else { return }
        tap?.stop()
        microphone?.stop()
        record.endedAt = Date()
        record.tracks = ([tap?.writer].compactMap { $0 } + (microphone?.segments ?? [])).map(\.stats)
        save(record, in: folder)
    }

    private func startMeters() {
        meters = Task {
            while !Task.isCancelled {
                otherSideLevel = tap?.writer?.takeRecentPeak() ?? 0
                microphoneLevel = microphone?.writer?.takeRecentPeak() ?? 0
                if otherSideLevel > 0 { heardOtherSide = true }
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    /// Compresses each CAF track to AAC off the main thread, keeping any track that fails.
    private func compress(_ record: MeetingRecord, in folder: URL) {
        isFinishing = true
        let tracks = record.tracks
        Task {
            let compressed = await Task.detached(priority: .utility) {
                tracks.map { track -> TrackStats in
                    let source = folder.appending(path: track.file)
                    let target = source.deletingPathExtension().appendingPathExtension("m4a")
                    do {
                        try AudioCompression.compress(source, to: target)
                        try FileManager.default.removeItem(at: source)
                        var track = track
                        track.file = target.lastPathComponent
                        return track
                    } catch {
                        try? FileManager.default.removeItem(at: target)
                        return track
                    }
                }
            }.value
            var record = record
            record.tracks = compressed
            record.compressed = compressed.allSatisfy { $0.file.hasSuffix(".m4a") }
            save(record, in: folder)
            isFinishing = false
            reload()
        }
    }

    // MARK: - Library

    func reload() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let folders =
            (try? FileManager.default.contentsOfDirectory(
                at: Self.directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        recordings =
            folders.compactMap { folder in
                guard let data = try? Data(contentsOf: folder.appending(path: "meeting.json")),
                    var record = try? decoder.decode(MeetingRecord.self, from: data)
                else { return nil }
                record.id = folder.lastPathComponent
                return record
            }
            .sorted { $0.startedAt > $1.startedAt }
    }

    func folder(of record: MeetingRecord) -> URL {
        Self.directory.appending(path: record.id, directoryHint: .isDirectory)
    }

    /// The other side's track, or the first track there is.
    func mainTrack(of record: MeetingRecord) -> URL? {
        let track = record.tracks.first { $0.name == "system" } ?? record.tracks.first
        return track.map { folder(of: record).appending(path: $0.file) }
    }

    func delete(_ record: MeetingRecord) throws {
        guard record.id != folder?.lastPathComponent else { return }
        try FileManager.default.removeItem(at: folder(of: record))
        reload()
    }

    func sizeOnDisk(of record: MeetingRecord) -> Int64? {
        SpeechModel.allocatedSize(of: folder(of: record))
    }

    // MARK: - Helpers

    private func save(_ record: MeetingRecord, in folder: URL) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        do {
            try encoder.encode(record).write(to: folder.appending(path: "meeting.json"), options: .atomic)
        } catch {
            logger.error("couldn't save meeting.json: \(String(describing: error), privacy: .public)")
        }
    }

    /// Capture events, kept in `meeting.json` for checking device switches and gaps.
    @ObservationIgnored private var pendingLog: [String] = []

    private nonisolated static func log(_ message: String) {
        let time = Date().formatted(.dateTime.hour().minute().second())
        Task { @MainActor in MeetingRecorder.shared.pendingLog.append("[\(time)] \(message)") }
    }
}
