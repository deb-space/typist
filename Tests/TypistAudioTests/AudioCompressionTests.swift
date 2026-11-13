// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import AVFoundation
import Foundation
import Testing

@testable import TypistAudio

@Suite struct AudioCompressionTests {
    @Test(arguments: [(48_000.0, 2), (24_000.0, 1)])
    func compressesATrackToAAC(sampleRate: Double, channels: Int) throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appending(path: "system.caf")
        let format = try #require(
            AVAudioFormat(
                commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: AVAudioChannelCount(channels),
                interleaved: false))
        let seconds = 3.0
        let frames = AVAudioFrameCount(sampleRate * seconds)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        for channel in 0..<channels {
            for frame in 0..<Int(frames) {
                buffer.floatChannelData?[channel][frame] = 0.5 * sin(2 * .pi * 440 * Float(frame) / Float(sampleRate))
            }
        }
        let writer = try TrackWriter(name: "system", url: source, format: format)
        writer.write(buffer, hostTime: nil)
        writer.close()

        let target = folder.appending(path: "system.m4a")
        try AudioCompression.compress(source, to: target)

        let compressed = try AVAudioFile(forReading: target)
        #expect(compressed.fileFormat.sampleRate == sampleRate)
        #expect(Int(compressed.fileFormat.channelCount) == channels)
        #expect(abs(Double(compressed.length) / sampleRate - seconds) < 0.1)
        let original = try #require(FileManager.default.attributesOfItem(atPath: source.path)[.size] as? Int)
        let small = try #require(FileManager.default.attributesOfItem(atPath: target.path)[.size] as? Int)
        #expect(small * 5 < original)
    }

    @Test func refusesWhatAACCantHold() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appending(path: "microphone.caf")
        let format = try #require(
            AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 96_000, channels: 2, interleaved: false))
        let writer = try TrackWriter(name: "microphone", url: source, format: format)
        writer.close()
        #expect(throws: CaptureError.self) {
            try AudioCompression.compress(source, to: folder.appending(path: "microphone.m4a"))
        }
    }
}

@Suite struct AudioFileSamplesTests {
    @Test func convertsALongStereoFileTo16kMono() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appending(path: "system.caf")
        let format = try #require(
            AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: false))
        let writer = try TrackWriter(name: "system", url: url, format: format)
        // 10 s in 1 s buffers: several of the loader's pieces.
        for _ in 0..<10 {
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 48_000))
            buffer.frameLength = 48_000
            for channel in 0..<2 {
                for frame in 0..<48_000 {
                    buffer.floatChannelData?[channel][frame] = 0.3 * sin(2 * .pi * 300 * Float(frame) / 48_000)
                }
            }
            writer.write(buffer, hostTime: nil)
        }
        writer.close()

        let samples = try AudioFileSamples.load(url)
        #expect(abs(samples.count - 160_000) < 1_600)
        #expect((samples.map(abs).max() ?? 0) > 0.2)
    }
}

@Suite struct AudioImportTests {
    @Test func importsAnAudioFile() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appending(path: "interview.wav")
        let sampleRate = 44_100.0
        let format = try #require(
            AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate, channels: 2, interleaved: false))
        let frames = AVAudioFrameCount(sampleRate * 4)
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames))
        buffer.frameLength = frames
        for channel in 0..<2 {
            for frame in 0..<Int(frames) {
                buffer.floatChannelData?[channel][frame] = 0.3 * sin(2 * .pi * 220 * Float(frame) / Float(sampleRate))
            }
        }
        do {
            let file = try AVAudioFile(forWriting: source, settings: format.settings)
            try file.write(from: buffer)
        }

        let result = try await AudioImport.extract(source, to: folder.appending(path: "audio.m4a"), name: "file")
        #expect(result.track.name == "file")
        #expect(result.track.file == "audio.m4a")
        #expect(abs(result.track.secondsByFrames - 4) < 0.1)
        #expect(abs(Double(try AudioFileSamples.load(folder.appending(path: "audio.m4a")).count) / 16_000 - 4) < 0.1)
    }

    @Test func refusesAFileWithoutSound() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appending(path: "notes.txt")
        try Data("not audio".utf8).write(to: source)
        await #expect(throws: (any Error).self) {
            try await AudioImport.extract(source, to: folder.appending(path: "audio.m4a"), name: "file")
        }
    }
}
