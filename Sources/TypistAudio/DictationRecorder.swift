// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import AVFoundation
import Accelerate
import Synchronization

/// Records the microphone into memory as 16 kHz mono, the format speech models expect, and
/// reports the level for the overlay. Nothing is written to disk.
///
/// When the input device changes mid-recording (AirPods connect), AVAudioEngine stops. The
/// recorder then starts a new engine on the new device and keeps appending to the same samples;
/// the audio during the switch is lost.
public final class DictationRecorder: @unchecked Sendable {
    public static let sampleRate: Double = 16_000

    public enum Event: Sendable {
        /// The input device changed and the microphone is restarting; no audio until `restarted`.
        case switching
        case restarted(attempts: Int)
        case failed(String)
    }

    public typealias EventHandler = @Sendable (Event) -> Void

    private let samples = Mutex<[Float]>([])
    private let queue = DispatchQueue(label: "space.deb.typist.dictation.recorder")
    /// Only touched on `queue`.
    private var engine = AVAudioEngine()
    private var observer: (any NSObjectProtocol)?
    private var onLevel: (@Sendable (Float) -> Void)?
    private var onEvent: EventHandler?
    private var isRunning = false

    public init() {}

    /// - Parameters:
    ///   - onLevel: Called on an audio thread, 0 (silence) to 1 (loud speech).
    ///   - onEvent: Device changes and restarts, for logging.
    public func start(onLevel: @escaping @Sendable (Float) -> Void, onEvent: EventHandler? = nil) throws {
        try queue.sync {
            self.onLevel = onLevel
            self.onEvent = onEvent
            samples.withLock { $0.removeAll(keepingCapacity: true) }
            isRunning = true
            guard try startEngine() else {
                isRunning = false
                throw CaptureError("microphone has no usable input format")
            }
        }
    }

    /// Stops recording and returns everything recorded.
    public func stop() -> [Float] {
        queue.sync {
            isRunning = false
            stopEngine()
        }
        return samples.withLock { recorded in
            defer { recorded = [] }
            return recorded
        }
    }

    // MARK: - Engine, on `queue`

    /// Returns false while the input format is not valid yet, which happens for a moment after a
    /// device switch.
    private func startEngine() throws -> Bool {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        // installTap raises an Objective-C exception, which Swift cannot catch, when the format
        // does not match the hardware. Check it first.
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
            inputFormat.sampleRate == input.inputFormat(forBus: 0).sampleRate,
            let target = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate, channels: 1, interleaved: false),
            let converter = AVAudioConverter(from: inputFormat, to: target)
        else { return false }

        let box = ConverterBox(converter: converter, target: target, inputRate: inputFormat.sampleRate)
        let chunk = max(1, Int(inputFormat.sampleRate * MicrophoneMeter.interval))
        let onLevel = onLevel
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(chunk), format: inputFormat) { [weak self] buffer, _ in
            if let onLevel { Self.reportLevels(buffer, chunk: chunk, onLevel: onLevel) }
            if let converted = box.convert(buffer) {
                self?.samples.withLock { $0.append(contentsOf: converted) }
            }
        }
        observer = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            self?.queue.async { self?.restart(attempt: 1) }
        }
        try engine.start()
        return true
    }

    private func stopEngine() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    private func restart(attempt: Int) {
        guard isRunning else { return }
        if attempt == 1 {
            onEvent?(.switching)
            stopEngine()
        }
        engine = AVAudioEngine()
        do {
            if try startEngine() {
                onEvent?(.restarted(attempts: attempt))
                return
            }
        } catch {
            onEvent?(.failed(String(describing: error)))
            return
        }
        guard attempt < 25 else {
            onEvent?(.failed("input format still invalid after \(attempt) attempts"))
            return
        }
        queue.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.restart(attempt: attempt + 1) }
    }

    private static func reportLevels(_ buffer: AVAudioPCMBuffer, chunk: Int, onLevel: @Sendable (Float) -> Void) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let frames = Int(buffer.frameLength)
        let stride = buffer.format.isInterleaved ? Int(buffer.format.channelCount) : 1
        var offset = 0
        while offset < frames {
            let count = min(chunk, frames - offset)
            var rms: Float = 0
            vDSP_rmsqv(data + offset * stride, vDSP_Stride(stride), &rms, vDSP_Length(count))
            onLevel(MicrophoneMeter.normalized(rms))
            offset += count
        }
    }
}

/// AVAudioConverter is used from the audio thread only, one buffer at a time.
private final class ConverterBox: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let target: AVAudioFormat
    private let ratio: Double

    init(converter: AVAudioConverter, target: AVAudioFormat, inputRate: Double) {
        self.converter = converter
        self.target = target
        ratio = target.sampleRate / inputRate
    }

    func convert(_ buffer: AVAudioPCMBuffer) -> [Float]? {
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else { return nil }
        var supplied = false
        var error: NSError?
        let status = converter.convert(to: output, error: &error) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .noDataNow
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return buffer
        }
        guard status != .error, let data = output.floatChannelData?[0] else { return nil }
        return Array(UnsafeBufferPointer(start: data, count: Int(output.frameLength)))
    }
}
