// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import AVFoundation
import Accelerate

/// Reports the microphone level for level meters, without recording anything.
public final class MicrophoneMeter: @unchecked Sendable {
    /// Length of audio that each reported level covers.
    public static let interval = 0.05

    private let engine = AVAudioEngine()

    public init() {}

    /// - Parameter onLevel: Called on an audio thread with a level from 0 (silence) to 1 (loud speech).
    public func start(onLevel: @escaping @Sendable (Float) -> Void) throws {
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0, format.commonFormat == .pcmFormatFloat32 else {
            throw CaptureError("microphone has no usable input format")
        }
        let chunk = max(1, Int(format.sampleRate * Self.interval))
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(chunk), format: format) { buffer, _ in
            guard let samples = buffer.floatChannelData?[0] else { return }
            let frames = Int(buffer.frameLength)
            let stride = format.isInterleaved ? Int(format.channelCount) : 1
            var offset = 0
            while offset < frames {
                let count = min(chunk, frames - offset)
                var rms: Float = 0
                vDSP_rmsqv(samples + offset * stride, vDSP_Stride(stride), &rms, vDSP_Length(count))
                onLevel(Self.normalized(rms))
                offset += count
            }
        }
        try engine.start()
    }

    public func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    /// Maps RMS to 0...1 on a -55...-15 dBFS scale, which covers quiet to loud speech.
    static func normalized(_ rms: Float) -> Float {
        guard rms > 0 else { return 0 }
        let decibels = 20 * log10(rms)
        return min(1, max(0, (decibels + 55) / 40))
    }
}
