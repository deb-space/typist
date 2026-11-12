// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import AVFoundation
import Observation
import TypistAudio

/// Plays a meeting's tracks together, each at its place on the timeline.
@MainActor @Observable
final class MeetingPlayer {
    private(set) var isPlaying = false
    private(set) var currentTime: Double = 0
    private(set) var duration: Double = 0
    private(set) var isReady = false

    @ObservationIgnored private let player = AVPlayer()
    @ObservationIgnored private var observer: Any?
    @ObservationIgnored private var endObserver: (any NSObjectProtocol)?

    /// Builds one composition from the other side's track and the microphone segments.
    func load(_ record: MeetingRecord, folder: URL) async {
        let composition = AVMutableComposition()
        let system = record.tracks.first { $0.name == "system" }
        for track in record.tracks {
            let asset = AVURLAsset(url: folder.appending(path: track.file))
            guard let source = try? await asset.loadTracks(withMediaType: .audio).first,
                let range = try? await source.load(.timeRange),
                let target = composition.addMutableTrack(
                    withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)
            else { continue }
            let offset = MeetingTranscriber.offset(of: track, from: system)
            // A track that started before the other side's is trimmed to the shared timeline.
            let skip = CMTime(seconds: max(0, -offset), preferredTimescale: 48_000)
            let start = CMTime(seconds: max(0, offset), preferredTimescale: 48_000)
            let trimmed = CMTimeRange(start: range.start + skip, duration: range.duration - skip)
            try? target.insertTimeRange(trimmed, of: source, at: start)
        }
        player.replaceCurrentItem(with: AVPlayerItem(asset: composition))
        duration = composition.duration.seconds.isFinite ? composition.duration.seconds : record.seconds
        isReady = true
        observer = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 0.2, preferredTimescale: 600), queue: .main
        ) { [weak self] time in
            MainActor.assumeIsolated { self?.currentTime = time.seconds }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime, object: player.currentItem, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.isPlaying = false }
        }
    }

    func toggle() {
        if isPlaying {
            player.pause()
        } else {
            if currentTime >= duration - 0.3 { seek(to: 0) }
            player.play()
        }
        isPlaying.toggle()
    }

    func seek(to seconds: Double) {
        currentTime = seconds
        player.seek(
            to: CMTime(seconds: seconds, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    /// Jumps to a moment and plays from there.
    func play(from seconds: Double) {
        seek(to: seconds)
        player.play()
        isPlaying = true
    }

    func stop() {
        player.pause()
        isPlaying = false
        if let observer { player.removeTimeObserver(observer) }
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        observer = nil
        endObserver = nil
    }
}
