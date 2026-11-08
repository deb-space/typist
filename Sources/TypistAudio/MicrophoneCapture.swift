// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import AVFoundation
import Synchronization

/// Records the default input device with AVAudioEngine.
///
/// AVAudioEngine stops when the input device or its format changes (for example when AirPods
/// connect). Then the capture creates a new engine on the new device and writes a new segment
/// file, `microphone.2.caf` and so on, because the format may differ.
public final class MicrophoneCapture: @unchecked Sendable {
    public typealias EventHandler = @Sendable (String) -> Void

    private let url: URL
    private let voiceProcessing: Bool
    private let onEvent: EventHandler
    private let queue = DispatchQueue(label: "space.deb.typist.mic.control")
    /// Only touched on `queue`.
    private var engine = AVAudioEngine()
    private var observer: (any NSObjectProtocol)?
    private let state = Mutex<(segments: [TrackWriter], stopped: Bool)>(([], false))

    /// The segment being written now.
    public var writer: TrackWriter? { state.withLock { $0.segments.last } }

    /// All segments, in order.
    public var segments: [TrackWriter] { state.withLock { $0.segments } }

    /// - Parameter voiceProcessing: Apple's voice processing (echo cancellation, noise
    ///   suppression). Other apps' audio is not ducked.
    public init(url: URL, voiceProcessing: Bool, onEvent: @escaping EventHandler) {
        self.url = url
        self.voiceProcessing = voiceProcessing
        self.onEvent = onEvent
    }

    public static func requestPermission() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    public func start() throws -> TrackWriter {
        try queue.sync {
            guard let writer = try startSegment() else {
                throw CaptureError("microphone has no valid input format")
            }
            return writer
        }
    }

    public func stop() {
        queue.sync {
            state.withLock { $0.stopped = true }
            stopEngine()
            for segment in segments { segment.close() }
        }
    }

    // MARK: - Engine, on `queue`

    /// Starts the engine and a new segment. Returns nil while the input format is not valid yet,
    /// which happens for a moment after a device switch.
    private func startSegment() throws -> TrackWriter? {
        let input = engine.inputNode
        if voiceProcessing {
            try input.setVoiceProcessingEnabled(true)
            input.voiceProcessingOtherAudioDuckingConfiguration = AVAudioVoiceProcessingOtherAudioDuckingConfiguration(
                enableAdvancedDucking: false, duckingLevel: .min)
        }
        // installTap raises an Objective-C exception, which Swift cannot catch, when the format
        // does not match the hardware. Check it first.
        let format = input.outputFormat(forBus: 0)
        let hardware = input.inputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0, format.sampleRate == hardware.sampleRate else {
            return nil
        }

        let index = segments.count + 1
        let segmentURL =
            index == 1
            ? url
            : url.deletingPathExtension().appendingPathExtension("\(index)").appendingPathExtension(url.pathExtension)
        let writer = try TrackWriter(
            name: index == 1 ? "microphone" : "microphone-\(index)", url: segmentURL, format: format)
        state.withLock { $0.segments.append(writer) }

        input.installTap(onBus: 0, bufferSize: 4096, format: format) { buffer, time in
            writer.write(buffer, hostTime: time.isHostTimeValid ? time.hostTime : nil)
        }
        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            let changedAt = HostTime.now()
            self?.queue.async { self?.restart(changedAt: changedAt) }
        }
        try engine.start()
        onEvent(
            "mic: segment \(index), \(AudioDevices.defaultInputName()), voice processing \(voiceProcessing ? "on" : "off"), format \(format)"
        )
        return writer
    }

    private func stopEngine() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    /// Called after AVAudioEngine stopped because of a configuration change.
    private func restart(changedAt: UInt64) {
        guard !state.withLock({ $0.stopped }), observer != nil else { return }
        let previous = writer?.stats
        onEvent("event: microphone configuration changed (now \(AudioDevices.defaultInputName())), restarting")
        stopEngine()
        attemptRestart(changedAt: changedAt, previous: previous, attempt: 1)
    }

    private func attemptRestart(changedAt: UInt64, previous: TrackStats?, attempt: Int) {
        guard !state.withLock({ $0.stopped }) else { return }
        engine = AVAudioEngine()
        do {
            guard let newWriter = try startSegment() else {
                guard attempt < 25 else {
                    onEvent("mic: gave up, input format still invalid after \(attempt) attempts")
                    return
                }
                queue.asyncAfter(deadline: .now() + 0.2) { [weak self] in
                    self?.attemptRestart(changedAt: changedAt, previous: previous, attempt: attempt + 1)
                }
                return
            }
            let elapsed = HostTime.seconds(from: changedAt, to: HostTime.now()) * 1000
            onEvent(String(format: "mic: restarted %.0f ms after the change (attempt %d)", elapsed, attempt))
            reportLostAudio(previous: previous, next: newWriter)
        } catch {
            onEvent("mic: restart failed: \(error)")
        }
    }

    /// Logs the time between the end of the previous segment and the start of the next one.
    private func reportLostAudio(previous: TrackStats?, next: TrackWriter) {
        guard let previous, let last = previous.lastHostTime, previous.sampleRate > 0 else { return }
        let end = last + HostTime.ticks(seconds: Double(previous.lastBufferFrames) / previous.sampleRate)
        queue.asyncAfter(deadline: .now() + 2) { [onEvent] in
            guard let first = next.stats.firstHostTime else {
                onEvent("mic: no audio in the new segment 2 s after restart")
                return
            }
            onEvent(
                String(
                    format: "mic: %.0f ms of microphone audio lost in the switch",
                    HostTime.seconds(from: end, to: first) * 1000))
        }
    }
}
