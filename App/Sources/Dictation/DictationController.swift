// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import AppKit
import OSLog
import Observation
import TypistAudio
import TypistCore
import TypistInput
import TypistProviders

/// Dictation from fn to inserted text: record, transcribe on this Mac, paste into the app in front.
@MainActor @Observable
final class DictationController {
    static let shared = DictationController()

    enum ModelStatus: Equatable {
        case idle, downloading(Double), loading, ready, failed(String)
    }

    private(set) var modelStatus: ModelStatus = .idle
    private(set) var isRecording = false
    /// The last result, for the menu.
    private(set) var lastTranscript: Transcript?

    @ObservationIgnored private let transcriber = WhisperKitTranscriber(
        modelsDirectory: URL.applicationSupportDirectory.appending(path: "Typist/Models", directoryHint: .isDirectory))
    @ObservationIgnored private var recorder: DictationRecorder?
    @ObservationIgnored private var flow: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "space.deb.typist", category: "dictation")
    private var overlay: OverlayController { .shared }

    /// Recordings shorter than this are treated as accidental.
    private let minimumSeconds = 0.3

    var modelName: String { "Whisper large-v3-turbo" }

    var modelStatusText: String {
        switch modelStatus {
        case .idle: "\(modelName): not loaded"
        case .downloading(let fraction): "\(modelName): downloading \(Int(fraction * 100))%"
        case .loading: "\(modelName): loading…"
        case .ready: "\(modelName): ready"
        case .failed: "\(modelName): failed"
        }
    }

    // MARK: - Model

    func prepareModel() {
        Task {
            try? await transcriber.prepare { state in
                Task { @MainActor in DictationController.shared.update(state) }
            }
        }
    }

    private func update(_ state: WhisperKitTranscriber.State) {
        switch state {
        case .idle: modelStatus = .idle
        case .downloading(let fraction): modelStatus = .downloading(fraction)
        case .loading: modelStatus = .loading
        case .ready: modelStatus = .ready
        case .failed(let message):
            modelStatus = .failed(message)
            logger.error("model failed: \(message, privacy: .public)")
        }
    }

    // MARK: - Recording

    func start(handsFree: Bool) {
        flow?.cancel()
        stopRecorder()
        flow = Task {
            let granted = await MicrophoneCapture.requestPermission()
            guard !Task.isCancelled else { return }
            guard granted else {
                overlay.show(.needsMicrophone)
                return
            }
            let recorder = DictationRecorder()
            let model = overlay.model
            do {
                try recorder.start { level in
                    Task { @MainActor in model.push(level: level) }
                }
            } catch {
                logger.error("recorder failed: \(String(describing: error), privacy: .public)")
                overlay.show(.needsMicrophone)
                return
            }
            self.recorder = recorder
            isRecording = true
            model.resetLevels()
            model.isHandsFree = handsFree
            model.isRemote = false
            model.startedAt = Date()
            overlay.show(
                .listening, hint: handsFree ? "fn to finish · esc to cancel" : "Release fn to insert · esc to cancel")
        }
    }

    func switchToHandsFree() {
        guard isRecording else { return start(handsFree: true) }
        overlay.model.isHandsFree = true
        overlay.model.hint = "fn to finish · esc to cancel"
    }

    func finish() {
        guard let recorder else {
            // fn released before the microphone started.
            flow?.cancel()
            overlay.hide()
            return
        }
        let samples = recorder.stop()
        self.recorder = nil
        isRecording = false
        let seconds = Double(samples.count) / DictationRecorder.sampleRate
        guard seconds >= minimumSeconds else {
            overlay.hide()
            return
        }

        flow?.cancel()
        flow = Task {
            overlay.show(
                .processing, hint: modelStatus == .ready ? "Transcribing on this Mac" : "Loading \(modelName)…")
            do {
                try await transcriber.prepare { state in
                    Task { @MainActor in DictationController.shared.update(state) }
                }
                overlay.model.hint = "Transcribing on this Mac"
                let transcript = try await transcriber.transcribe(samples)
                guard !Task.isCancelled else { return }
                lastTranscript = transcript
                logger.info(
                    "transcribed \(transcript.audioSeconds, format: .fixed(precision: 1)) s in \(transcript.processingSeconds, format: .fixed(precision: 2)) s, \(transcript.wordCount) words, \(transcript.language ?? "?", privacy: .public)"
                )
                await insert(transcript)
            } catch {
                logger.error("transcription failed: \(String(describing: error), privacy: .public)")
                overlay.show(.cancelled, hint: "Couldn’t transcribe — \(String(describing: error))")
                try? await Task.sleep(for: .seconds(3))
                overlay.hide()
            }
        }
    }

    func cancel(quietly: Bool = false) {
        flow?.cancel()
        stopRecorder()
        guard !quietly else {
            overlay.hide()
            return
        }
        flow = Task {
            overlay.show(.cancelled, hint: "Cancelled — nothing inserted")
            try? await Task.sleep(for: .milliseconds(1300))
            guard !Task.isCancelled else { return }
            overlay.hide()
        }
    }

    private func stopRecorder() {
        _ = recorder?.stop()
        recorder = nil
        isRecording = false
    }

    // MARK: - Insertion

    private func insert(_ transcript: Transcript) async {
        guard !transcript.text.isEmpty else {
            overlay.show(.cancelled, hint: "Nothing recognized")
            try? await Task.sleep(for: .milliseconds(1500))
            overlay.hide()
            return
        }
        let app = NSWorkspace.shared.frontmostApplication?.localizedName ?? "the app in front"
        let timing = String(format: "%.1f s", transcript.processingSeconds)

        if FocusInspector.isSecureInputEnabled {
            // A password field: typing is blocked, so leave the text where the user can get it.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(transcript.text, forType: .string)
            overlay.show(.copied, hint: "Secure field — not typed")
            try? await Task.sleep(for: .seconds(3))
        } else {
            _ = await TextInserter.insert(transcript.text, method: .pasteboard)
            overlay.show(.inserted, hint: "Inserted into \(app) · \(transcript.wordCount) words · \(timing)")
            try? await Task.sleep(for: .milliseconds(1800))
        }
        guard !Task.isCancelled else { return }
        overlay.hide()
    }
}
