// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import AVFoundation
import CoreMedia
import ScreenCaptureKit
import Synchronization

/// Records system audio, and optionally the microphone, with ScreenCaptureKit.
///
/// ScreenCaptureKit always captures video too, so the stream asks for a 2×2 picture once a second
/// and drops it.
public final class ScreenCaptureAudioCapture: NSObject, SCStreamOutput, SCStreamDelegate, @unchecked Sendable {
    public enum Target: Sendable, Hashable {
        case allSystemAudio
        case app(AudioApp)
    }

    public typealias EventHandler = @Sendable (String) -> Void

    private let target: Target
    private let systemURL: URL
    private let microphoneURL: URL?
    private let onEvent: EventHandler

    private let audioQueue = DispatchQueue(label: "space.deb.typist.sck.audio", qos: .userInteractive)
    private let microphoneQueue = DispatchQueue(label: "space.deb.typist.sck.mic", qos: .userInteractive)
    private let screenQueue = DispatchQueue(label: "space.deb.typist.sck.screen")
    private let writers = Mutex<(system: TrackWriter?, microphone: TrackWriter?)>((nil, nil))
    /// Only touched by `start()` and `stop()`, which callers do not run concurrently.
    nonisolated(unsafe) private var stream: SCStream?

    /// Pass `microphoneURL` to record the microphone in the same stream (macOS 15+).
    public init(target: Target, systemURL: URL, microphoneURL: URL?, onEvent: @escaping EventHandler) {
        self.target = target
        self.systemURL = systemURL
        self.microphoneURL = microphoneURL
        self.onEvent = onEvent
    }

    /// Created when the first buffer of each track arrives, because only then is its format known.
    public var systemWriter: TrackWriter? { writers.withLock { $0.system } }
    public var microphoneWriter: TrackWriter? { writers.withLock { $0.microphone } }

    public func start() async throws {
        onEvent("sck: screen recording preflight \(CGPreflightScreenCaptureAccess() ? "granted" : "not granted")")
        let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false)
        guard let display = content.displays.first else {
            throw CaptureError("ScreenCaptureKit returned no displays")
        }

        let filter: SCContentFilter
        switch target {
        case .allSystemAudio:
            let own = content.applications.filter { $0.processID == getpid() }
            filter = SCContentFilter(display: display, excludingApplications: own, exceptingWindows: [])
            onEvent("sck: all system audio")
        case .app(let app):
            // Several instances of an app can run with the same bundle ID (Chrome profiles).
            let scApps = content.applications.filter { $0.bundleIdentifier == app.bundleID }
            guard !scApps.isEmpty else {
                throw CaptureError("ScreenCaptureKit does not list \(app.bundleID)")
            }
            filter = SCContentFilter(display: display, including: scApps, exceptingWindows: [])
            onEvent("sck: \(app.name), pids \(scApps.map { String($0.processID) }.joined(separator: ", "))")
        }

        let configuration = SCStreamConfiguration()
        configuration.capturesAudio = true
        configuration.excludesCurrentProcessAudio = true
        configuration.sampleRate = 48_000
        configuration.channelCount = 2
        configuration.width = 2
        configuration.height = 2
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
        configuration.captureMicrophone = microphoneURL != nil

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: screenQueue)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: audioQueue)
        if microphoneURL != nil {
            try stream.addStreamOutput(self, type: .microphone, sampleHandlerQueue: microphoneQueue)
        }
        try await stream.startCapture()
        self.stream = stream
        onEvent("sck: capture started")
    }

    public func stop() async {
        let stream = self.stream
        self.stream = nil
        do {
            try await stream?.stopCapture()
        } catch {
            onEvent("sck: stopCapture failed: \(error)")
        }
        let (system, microphone) = writers.withLock { ($0.system, $0.microphone) }
        system?.close()
        microphone?.close()
    }

    // MARK: - SCStreamOutput

    public func stream(
        _ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType
    ) {
        guard type != .screen, sampleBuffer.isValid,
            var description = sampleBuffer.formatDescription?.audioStreamBasicDescription,
            let format = AVAudioFormat(streamDescription: &description),
            let writer = writer(for: type, format: format)
        else { return }

        let hostTime = HostTime.ticks(seconds: sampleBuffer.presentationTimeStamp.seconds)
        do {
            try sampleBuffer.withAudioBufferList { list, _ in
                guard let pcm = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: list.unsafePointer) else {
                    return
                }
                writer.write(pcm, hostTime: hostTime)
            }
        } catch {
            onEvent("sck: could not read \(type == .audio ? "system" : "microphone") buffer: \(error)")
        }
    }

    public func stream(_ stream: SCStream, didStopWithError error: any Error) {
        onEvent("event: stream stopped with error: \(error)")
    }

    private func writer(for type: SCStreamOutputType, format: AVAudioFormat) -> TrackWriter? {
        let isSystem = type == .audio
        guard let url = isSystem ? systemURL : microphoneURL else { return nil }
        return writers.withLock { writers in
            if let existing = isSystem ? writers.system : writers.microphone { return existing }
            do {
                let writer = try TrackWriter(name: isSystem ? "system" : "microphone", url: url, format: format)
                if isSystem { writers.system = writer } else { writers.microphone = writer }
                onEvent("sck: \(isSystem ? "system" : "microphone") format \(format)")
                return writer
            } catch {
                onEvent("sck: could not create \(url.lastPathComponent): \(error)")
                return nil
            }
        }
    }
}

public struct CaptureError: Error, CustomStringConvertible {
    public let description: String
    public init(_ description: String) { self.description = description }
}
