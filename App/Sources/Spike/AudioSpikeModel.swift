// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import AppKit
import Observation
import TypistAudio

/// State of the system audio spike (M0, task 0.2): records system audio and the microphone
/// with a chosen method and saves the tracks with measurements to a session folder.
@MainActor @Observable
final class AudioSpikeModel {
    static let shared = AudioSpikeModel()

    enum Method: String, CaseIterable, Identifiable, Codable {
        case processTap = "tap"
        case screenCaptureKit = "sck"

        var id: Self { self }
        var title: String { self == .processTap ? "Process tap" : "ScreenCaptureKit" }
    }

    enum MicMode: String, CaseIterable, Identifiable, Codable {
        case off
        case engine
        case screenCaptureKit = "sck"

        var id: Self { self }
        var title: String {
            switch self {
            case .off: "Off"
            case .engine: "AVAudioEngine"
            case .screenCaptureKit: "ScreenCaptureKit stream"
            }
        }
    }

    var method: Method = .processTap {
        didSet { if method == .processTap, micMode == .screenCaptureKit { micMode = .engine } }
    }
    var micMode: MicMode = .engine
    var voiceProcessing = false
    var tracking: ProcessTapCapture.Tracking = .updateDescription
    /// nil records all system audio.
    var targetBundleID: String?

    private(set) var apps: [AudioApp] = []
    private(set) var audioProcesses: [AudioProcess] = []
    private(set) var isRecording = false
    private(set) var isBusy = false
    private(set) var startedAt: Date?
    private(set) var systemLevel: Float = 0
    private(set) var microphoneLevel: Float = 0
    private(set) var log: [String] = []
    private(set) var summary = ""
    private(set) var lastSession: URL?

    private var tap: ProcessTapCapture?
    private var screenCapture: ScreenCaptureAudioCapture?
    private var microphone: MicrophoneCapture?
    private var meterTask: Task<Void, Never>?
    private var sessionDirectory: URL?
    private var startHostTime: UInt64 = 0
    private var startDevices = (output: "", input: "")

    var micModes: [MicMode] { method == .processTap ? [.off, .engine] : MicMode.allCases }

    static var spikesDirectory: URL {
        URL.applicationSupportDirectory.appending(path: "Typist/Spikes", directoryHint: .isDirectory)
    }

    func refresh() {
        apps = AudioApp.running()
        audioProcesses = AudioProcessList.current().sorted {
            ($0.isRunningOutput ? 0 : 1, $0.name) < ($1.isRunningOutput ? 0 : 1, $1.name)
        }
        if let targetBundleID, !apps.contains(where: { $0.bundleID == targetBundleID }) {
            self.targetBundleID = nil
        }
    }

    // MARK: - Recording

    func start() async {
        guard !isRecording, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }

        log = []
        summary = ""
        startHostTime = HostTime.now()
        startedAt = Date()
        startDevices = (AudioDevices.defaultOutputName(), AudioDevices.defaultInputName())
        let app = apps.first { $0.bundleID == targetBundleID }
        append("session: \(method.title), source \(app?.name ?? "all system audio"), mic \(micMode.title)")
        append("devices: output \(startDevices.output), input \(startDevices.input)")

        do {
            let directory = try makeSessionDirectory()
            sessionDirectory = directory
            if micMode != .off {
                let granted = await MicrophoneCapture.requestPermission()
                append("mic: permission \(granted ? "granted" : "denied")")
            }

            switch method {
            case .processTap:
                let capture = ProcessTapCapture(
                    target: app.map { .app($0) } ?? .allSystemAudio, tracking: tracking,
                    outputURL: directory.appending(path: "system.caf"), onEvent: eventHandler())
                tap = capture
                _ = try capture.start()
            case .screenCaptureKit:
                let capture = ScreenCaptureAudioCapture(
                    target: app.map { .app($0) } ?? .allSystemAudio,
                    systemURL: directory.appending(path: "system.caf"),
                    microphoneURL: micMode == .screenCaptureKit ? directory.appending(path: "microphone.caf") : nil,
                    onEvent: eventHandler())
                screenCapture = capture
                try await capture.start()
            }
            if micMode == .engine {
                let capture = MicrophoneCapture(
                    url: directory.appending(path: "microphone.caf"), voiceProcessing: voiceProcessing,
                    onEvent: eventHandler())
                microphone = capture
                _ = try capture.start()
            }
            isRecording = true
            startMeters()
        } catch {
            append("error: \(error)")
            await stopCaptures()
            finishSession()
        }
    }

    func stop() async {
        guard isRecording, !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        await stopCaptures()
        finishSession()
        refresh()
    }

    private func stopCaptures() async {
        meterTask?.cancel()
        meterTask = nil
        tap?.stop()
        await screenCapture?.stop()
        microphone?.stop()
        isRecording = false
        systemLevel = 0
        microphoneLevel = 0
    }

    private var systemWriter: TrackWriter? { tap?.writer ?? screenCapture?.systemWriter }
    private var microphoneWriter: TrackWriter? { microphone?.writer ?? screenCapture?.microphoneWriter }

    private func startMeters() {
        meterTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                systemLevel = systemWriter?.takeRecentPeak() ?? 0
                microphoneLevel = microphoneWriter?.takeRecentPeak() ?? 0
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    // MARK: - Session report

    private func finishSession() {
        let microphoneSegments = microphone?.segments ?? [screenCapture?.microphoneWriter].compactMap { $0 }
        let tracks = ([systemWriter].compactMap { $0 } + microphoneSegments).map(\.stats)
        let system = tracks.first { $0.name == "system" }
        let mic = tracks.first { $0.name == "microphone" }
        var microphoneLead: Double?
        if let s = system?.firstHostTime, let m = mic?.firstHostTime {
            microphoneLead = HostTime.seconds(from: m, to: s)
        }

        var lines = tracks.map(Self.describe)
        if let microphoneLead {
            lines.append(String(format: "first mic buffer %+.1f ms before first system buffer", microphoneLead * 1000))
        }
        summary = lines.joined(separator: "\n")
        for line in lines { append("result: \(line)") }

        guard let sessionDirectory else { return }
        let report = SessionReport(
            method: method.rawValue, source: targetBundleID ?? "all", microphone: micMode.rawValue,
            voiceProcessing: micMode == .engine ? voiceProcessing : nil,
            tracking: method == .processTap && targetBundleID != nil ? tracking.rawValue : nil,
            macOS: ProcessInfo.processInfo.operatingSystemVersionString,
            outputDevice: startDevices.output, inputDevice: startDevices.input,
            startedAt: startedAt ?? Date(), wallSeconds: HostTime.seconds(from: startHostTime, to: HostTime.now()),
            tracks: tracks.map(TrackReport.init), microphoneLeadSeconds: microphoneLead, log: log)
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            try encoder.encode(report).write(to: sessionDirectory.appending(path: "session.json"))
            try sessionDirectory.path.write(
                to: Self.spikesDirectory.appending(path: "latest.txt"), atomically: true, encoding: .utf8)
        } catch {
            append("error: could not write session.json: \(error)")
        }
        lastSession = sessionDirectory
        self.sessionDirectory = nil
        tap = nil
        screenCapture = nil
        microphone = nil
    }

    private static func describe(_ track: TrackStats) -> String {
        var parts = [String(format: "%@: %.2f s", track.name, track.secondsByFrames)]
        if let clock = track.secondsByClock {
            parts.append(String(format: "clock %.2f s (drift %+.1f ms)", clock, (track.secondsByFrames - clock) * 1000))
        }
        parts.append(String(format: "peak %.3f", track.maxPeak))
        parts.append("silent \(track.silentBuffers)/\(track.buffers) buffers")
        parts.append(
            "gaps \(track.gaps)"
                + (track.gaps > 0 ? String(format: " (max %.0f ms)", track.longestGapSeconds * 1000) : ""))
        if track.writeErrors > 0 { parts.append("write errors \(track.writeErrors): \(track.lastError ?? "")") }
        if track.buffers > 0, track.silentBuffers == track.buffers { parts.append("ALL SILENT") }
        return parts.joined(separator: ", ")
    }

    // MARK: - Helpers

    func append(_ message: String, at hostTime: UInt64 = HostTime.now()) {
        let offset = HostTime.seconds(from: startHostTime, to: hostTime)
        log.append(String(format: "[%7.3f] ", offset) + message)
    }

    private func eventHandler() -> @Sendable (String) -> Void {
        { message in
            let hostTime = HostTime.now()
            Task { @MainActor in AudioSpikeModel.shared.append(message, at: hostTime) }
        }
    }

    private func makeSessionDirectory() throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let name = "\(formatter.string(from: Date()))_\(method.rawValue)"
        let directory = Self.spikesDirectory.appending(path: name, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    func showRecordings() {
        try? FileManager.default.createDirectory(at: Self.spikesDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.open(lastSession ?? Self.spikesDirectory)
    }
}

private struct SessionReport: Codable {
    var method: String
    var source: String
    var microphone: String
    var voiceProcessing: Bool?
    var tracking: String?
    var macOS: String
    var outputDevice: String
    var inputDevice: String
    var startedAt: Date
    var wallSeconds: Double
    var tracks: [TrackReport]
    /// Positive when the first microphone buffer came before the first system buffer.
    var microphoneLeadSeconds: Double?
    var log: [String]
}

private struct TrackReport: Codable {
    var stats: TrackStats
    var secondsByFrames: Double
    var secondsByClock: Double?
    var driftMilliseconds: Double?

    init(_ stats: TrackStats) {
        self.stats = stats
        secondsByFrames = stats.secondsByFrames
        secondsByClock = stats.secondsByClock
        driftMilliseconds = stats.secondsByClock.map { (stats.secondsByFrames - $0) * 1000 }
    }
}
