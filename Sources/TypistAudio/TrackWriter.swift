// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import AVFoundation
import Accelerate
import Synchronization

/// Measurements of one recorded track.
public struct TrackStats: Sendable, Codable {
    public var name: String
    public var file: String
    public var format: String
    public var sampleRate: Double
    public var channelCount: Int
    public var buffers = 0
    public var framesWritten: Int64 = 0
    public var firstHostTime: UInt64?
    public var lastHostTime: UInt64?
    public var lastBufferFrames = 0
    public var maxPeak: Float = 0
    /// Buffers with only zero samples. A track of silent buffers usually means a missing permission.
    public var silentBuffers = 0
    /// Breaks of more than 50 ms between where a buffer should start and where it starts.
    public var gaps = 0
    public var longestGapSeconds = 0.0
    public var writeErrors = 0
    public var lastError: String?

    /// Track length according to the number of samples.
    public var secondsByFrames: Double { sampleRate > 0 ? Double(framesWritten) / sampleRate : 0 }

    /// Track length according to buffer timestamps.
    public var secondsByClock: Double? {
        guard let first = firstHostTime, let last = lastHostTime, sampleRate > 0 else { return nil }
        return HostTime.seconds(from: first, to: last) + Double(lastBufferFrames) / sampleRate
    }
}

/// Writes PCM buffers of one track to a file and collects ``TrackStats``.
///
/// `write` must be called from one thread at a time. Stats can be read from any thread.
public final class TrackWriter: @unchecked Sendable {
    public let url: URL
    private let file: AVAudioFile
    private let state: Mutex<(stats: TrackStats, recentPeak: Float)>

    public init(name: String, url: URL, format: AVAudioFormat) throws {
        self.url = url
        file = try AVAudioFile(
            forWriting: url, settings: format.settings, commonFormat: format.commonFormat,
            interleaved: format.isInterleaved)
        let stats = TrackStats(
            name: name, file: url.lastPathComponent, format: String(describing: format),
            sampleRate: format.sampleRate, channelCount: Int(format.channelCount))
        state = Mutex((stats, 0))
    }

    public var stats: TrackStats { state.withLock { $0.stats } }

    /// The highest peak since the previous call, for level meters.
    public func takeRecentPeak() -> Float {
        state.withLock { value in
            defer { value.recentPeak = 0 }
            return value.recentPeak
        }
    }

    public func write(_ buffer: AVAudioPCMBuffer, hostTime: UInt64?) {
        let peak = buffer.peak
        let writeError: String?
        do {
            try file.write(from: buffer)
            writeError = nil
        } catch {
            writeError = String(describing: error)
        }

        state.withLock { value in
            if let writeError {
                value.stats.writeErrors += 1
                value.stats.lastError = writeError
                return
            }
            var stats = value.stats
            if let hostTime, let last = stats.lastHostTime, stats.sampleRate > 0 {
                let expected = last + HostTime.ticks(seconds: Double(stats.lastBufferFrames) / stats.sampleRate)
                let gap = HostTime.seconds(from: expected, to: hostTime)
                if gap > 0.05 {
                    stats.gaps += 1
                    stats.longestGapSeconds = max(stats.longestGapSeconds, gap)
                }
            }
            if stats.firstHostTime == nil { stats.firstHostTime = hostTime }
            if let hostTime { stats.lastHostTime = hostTime }
            stats.buffers += 1
            stats.framesWritten += Int64(buffer.frameLength)
            stats.lastBufferFrames = Int(buffer.frameLength)
            if let peak {
                stats.maxPeak = max(stats.maxPeak, peak)
                if peak == 0 { stats.silentBuffers += 1 }
                value.recentPeak = max(value.recentPeak, peak)
            }
            value.stats = stats
        }
    }

    public func close() {
        file.close()
    }
}

extension AVAudioPCMBuffer {
    /// The largest absolute sample value, or nil for non-float formats.
    var peak: Float? {
        guard format.commonFormat == .pcmFormatFloat32, let data = floatChannelData else { return nil }
        let frames = Int(frameLength)
        let channels = Int(format.channelCount)
        guard frames > 0 else { return 0 }
        var peak: Float = 0
        if format.isInterleaved {
            vDSP_maxmgv(data[0], 1, &peak, vDSP_Length(frames * channels))
        } else {
            for channel in 0..<channels {
                var channelPeak: Float = 0
                vDSP_maxmgv(data[channel], 1, &channelPeak, vDSP_Length(frames))
                peak = max(peak, channelPeak)
            }
        }
        return peak
    }
}
