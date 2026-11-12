// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import AVFoundation

/// Re-encodes recorded tracks as AAC.
///
/// Meetings are recorded as uncompressed CAF, which survives a crash: everything written so far
/// stays readable. Once a meeting ends, each track is compressed to about 1/30 of its size.
public enum AudioCompression {
    /// Writes `source` as AAC to `destination`, an `.m4a` file. AAC takes one or two channels at
    /// up to 48 kHz; other tracks throw and should be kept as they are.
    public static func compress(_ source: URL, to destination: URL) throws {
        let input = try AVAudioFile(forReading: source)
        let format = input.processingFormat
        guard format.channelCount <= 2, format.sampleRate <= 48_000 else {
            throw CaptureError("AAC can't hold \(format.channelCount) channels at \(Int(format.sampleRate)) Hz")
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: format.sampleRate,
            AVNumberOfChannelsKey: format.channelCount,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        let output = try AVAudioFile(
            forWriting: destination, settings: settings, commonFormat: format.commonFormat,
            interleaved: format.isInterleaved)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1 << 16) else {
            throw CaptureError("no buffer for \(format)")
        }
        while input.framePosition < input.length {
            try input.read(into: buffer)
            guard buffer.frameLength > 0 else { break }
            try output.write(from: buffer)
        }
        output.close()
    }
}
