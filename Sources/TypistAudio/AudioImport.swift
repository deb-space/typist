// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import AVFoundation
import UniformTypeIdentifiers

/// Brings an audio or video file into a meeting folder as an AAC track, so it goes through the
/// same transcription, speakers and player as a recorded meeting.
public enum AudioImport {
    /// Files Typist offers to import. Anything AVFoundation can read with a sound track works.
    public static let types: [UTType] = [.audio, .movie, .mpeg4Movie, .quickTimeMovie, .mp3, .mpeg4Audio, .wav, .aiff]

    public struct Result: Sendable {
        public var track: TrackStats
        /// When the file was recorded, from its metadata, or nil if it doesn't say.
        public var recordedAt: Date?
    }

    /// Writes the sound of `source` to `destination`, an `.m4a` file, as a track called `name`.
    public static func extract(_ source: URL, to destination: URL, name: String) async throws -> Result {
        let asset = AVURLAsset(url: source)
        guard (try? await asset.loadTracks(withMediaType: .audio))?.isEmpty == false else {
            throw CaptureError("\(source.lastPathComponent) has no sound to transcribe")
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
            throw CaptureError("can't convert \(source.lastPathComponent)")
        }
        try await session.export(to: destination, as: .m4a)

        let file = try AVAudioFile(forReading: destination)
        let format = file.fileFormat
        var track = TrackStats(
            name: name, file: destination.lastPathComponent, format: "aac", sampleRate: format.sampleRate,
            channelCount: Int(format.channelCount))
        track.framesWritten = file.length
        let recordedAt = try? await asset.load(.creationDate)?.load(.dateValue)
        return Result(track: track, recordedAt: recordedAt)
    }
}
