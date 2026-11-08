// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import AVFoundation
import Accelerate
import Synchronization

/// Records the microphone into memory as 16 kHz mono, the format speech models expect, and
/// reports the level for the overlay. Nothing is written to disk.
public final class DictationRecorder: @unchecked Sendable {
    public static let sampleRate: Double = 16_000

    private let engine = AVAudioEngine()
    private let samples = Mutex<[Float]>([])

    public init() {}

    /// - Parameter onLevel: Called on an audio thread, 0 (silence) to 1 (loud speech).
    public func start(onLevel: @escaping @Sendable (Float) -> Void) throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0,
            let target = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: Self.sampleRate, channels: 1, interleaved: false),
            let converter = AVAudioConverter(from: inputFormat, to: target)
        else {
            throw CaptureError("microphone has no usable input format")
        }
        let box = ConverterBox(converter: converter, target: target, inputRate: inputFormat.sampleRate)
        let chunk = max(1, Int(inputFormat.sampleRate * MicrophoneMeter.interval))
        samples.withLock { $0.removeAll(keepingCapacity: true) }

        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(chunk), format: inputFormat) { [weak self] buffer, _ in
            Self.reportLevels(buffer, chunk: chunk, onLevel: onLevel)
            if let converted = box.convert(buffer) {
                self?.samples.withLock { $0.append(contentsOf: converted) }
            }
        }
        try engine.start()
    }

    /// Stops recording and returns everything recorded.
    public func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        return samples.withLock { recorded in
            defer { recorded = [] }
            return recorded
        }
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
