// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import AVFoundation

public enum AudioFileSamples {
    /// Reads an audio file and converts it to 16 kHz mono Float samples.
    ///
    /// The file is read in pieces, so an hour-long 48 kHz stereo meeting needs memory only for its
    /// 16 kHz result (about 230 MB), not for the whole original.
    public static func load(_ url: URL) throws -> [Float] {
        let file = try AVAudioFile(forReading: url)
        let source = file.processingFormat
        guard
            let target = AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: DictationRecorder.sampleRate, channels: 1,
                interleaved: false),
            let converter = AVAudioConverter(from: source, to: target),
            let input = AVAudioPCMBuffer(pcmFormat: source, frameCapacity: 1 << 16),
            let output = AVAudioPCMBuffer(
                pcmFormat: target,
                frameCapacity: AVAudioFrameCount(Double(1 << 16) * target.sampleRate / source.sampleRate) + 1024)
        else { throw CaptureError("cannot convert \(url.lastPathComponent)") }

        var samples: [Float] = []
        samples.reserveCapacity(Int(Double(file.length) * target.sampleRate / source.sampleRate) + 1024)
        var readError: Error?
        var finished = false
        while !finished {
            output.frameLength = 0
            var error: NSError?
            let status = converter.convert(to: output, error: &error) { _, status in
                do {
                    try file.read(into: input)
                } catch {
                    readError = error
                    status.pointee = .endOfStream
                    return nil
                }
                guard input.frameLength > 0 else {
                    status.pointee = .endOfStream
                    return nil
                }
                status.pointee = .haveData
                return input
            }
            if let error { throw error }
            if let readError, file.framePosition < file.length { throw readError }
            if let data = output.floatChannelData?[0], output.frameLength > 0 {
                samples.append(contentsOf: UnsafeBufferPointer(start: data, count: Int(output.frameLength)))
            }
            finished = status == .endOfStream || status == .error || (output.frameLength == 0 && status != .haveData)
        }
        return samples
    }
}
