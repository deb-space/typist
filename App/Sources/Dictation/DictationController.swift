// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import AVFoundation
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

    @ObservationIgnored private var transcriber = WhisperKitTranscriber(
        variant: AppSettings.shared.modelVariant, modelsDirectory: SpeechModel.directory)
    /// Increases when the model changes, so late state updates from the old one are ignored.
    @ObservationIgnored private var modelGeneration = 0
    @ObservationIgnored private var recorder: DictationRecorder?
    @ObservationIgnored private var flow: Task<Void, Never>?
    @ObservationIgnored private var silenceWatch: Task<Void, Never>?
    @ObservationIgnored private let logger = Logger(subsystem: "space.deb.typist", category: "dictation")
    @ObservationIgnored private var isOverlayShown = false
    @ObservationIgnored private var isHandsFree = false
    /// Whether the microphone heard anything louder than ``voiceLevel`` in this recording.
    @ObservationIgnored private var heardVoice = false
    @ObservationIgnored private var lastVoiceAt = Date()
    private var overlay: OverlayController { .shared }
    private var history: DictationHistory { .shared }
    private var settings: AppSettings { .shared }

    /// Recordings shorter than this are treated as accidental.
    private let minimumSeconds = 0.3
    /// A normalized level above this counts as voice (about -43 dBFS).
    private let voiceLevel: Float = 0.3
    /// Hands-free stops after this much silence following speech.
    private var silenceToStop: TimeInterval { settings.autostopSeconds }
    /// The microphone is switching devices: no audio, so silence does not count.
    @ObservationIgnored private var isSwitchingMicrophone = false

    var modelName: String { "Whisper large-v3-turbo" }
    var currentModel: SpeechModel { SpeechModel.named(settings.modelVariant) }

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
        let transcriber = transcriber
        let generation = modelGeneration
        Task {
            try? await transcriber.prepare { state in
                Task { @MainActor in DictationController.shared.update(state, generation: generation) }
            }
        }
    }

    /// Switches to another speech model, downloading it if needed.
    func selectModel(_ model: SpeechModel) {
        guard model.variant != settings.modelVariant else { return }
        settings.modelVariant = model.variant
        modelGeneration += 1
        transcriber = WhisperKitTranscriber(variant: model.variant, modelsDirectory: SpeechModel.directory)
        modelStatus = .idle
        prepareModel()
    }

    /// Deletes a downloaded model that is not in use.
    func deleteModel(_ model: SpeechModel) throws {
        guard model.variant != settings.modelVariant else { return }
        try FileManager.default.removeItem(at: model.folder)
    }

    private func update(_ state: WhisperKitTranscriber.State, generation: Int) {
        guard generation == modelGeneration else { return }
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

    /// fn went down. Start the microphone without showing anything, so the first word is kept
    /// if this turns into a hold. Only when the permission is already granted: a prompt on a tap
    /// would be confusing.
    func prepareRecording() {
        guard recorder == nil, AVAudioApplication.shared.recordPermission == .granted else { return }
        flow?.cancel()
        startRecorder()
    }

    func start(handsFree: Bool) {
        isHandsFree = handsFree
        if recorder != nil {
            showListening()
            return
        }
        flow?.cancel()
        flow = Task {
            let granted = await MicrophoneCapture.requestPermission()
            // fn may already be released while the permission check was running.
            guard !Task.isCancelled else { return }
            guard granted, startRecorder() else {
                overlay.show(.needsMicrophone)
                return
            }
            showListening()
        }
    }

    func switchToHandsFree() {
        isHandsFree = true
        guard recorder != nil else { return start(handsFree: true) }
        if isOverlayShown {
            overlay.model.isHandsFree = true
            overlay.model.hint = handsFreeHint
        } else {
            showListening()
        }
        watchForSilence()
    }

    private var handsFreeHint: String { "fn to finish · stops after \(Int(silenceToStop)) s of silence" }

    @discardableResult
    private func startRecorder() -> Bool {
        let recorder = DictationRecorder()
        let model = overlay.model
        model.resetLevels()
        heardVoice = false
        lastVoiceAt = Date()
        isSwitchingMicrophone = false
        let voiceLevel = voiceLevel
        do {
            try recorder.start(
                onLevel: { level in
                    Task { @MainActor in
                        model.push(level: level)
                        if level > voiceLevel { DictationController.shared.noteVoice() }
                    }
                },
                onEvent: { event in
                    Task { @MainActor in DictationController.shared.handle(event) }
                })
        } catch {
            logger.error("recorder failed: \(String(describing: error), privacy: .public)")
            return false
        }
        self.recorder = recorder
        isRecording = true
        return true
    }

    private func handle(_ event: DictationRecorder.Event) {
        switch event {
        case .switching:
            logger.info("microphone switching")
            isSwitchingMicrophone = true
            if isOverlayShown { overlay.model.hint = "Switching microphone…" }
        case .restarted(let attempts):
            logger.info("microphone restarted after \(attempts) attempt(s)")
            isSwitchingMicrophone = false
            // Start counting silence again from now.
            lastVoiceAt = Date()
            if isOverlayShown {
                overlay.model.hint = isHandsFree ? handsFreeHint : "Release fn to insert · esc to cancel"
            }
        case .failed(let message):
            logger.error("microphone restart failed: \(message, privacy: .public)")
            isSwitchingMicrophone = false
        }
    }

    private func noteVoice() {
        heardVoice = true
        lastVoiceAt = Date()
    }

    private func showListening() {
        let model = overlay.model
        model.isHandsFree = isHandsFree
        model.isRemote = false
        model.startedAt = Date()
        // How to finish and cancel is shown during the first few dictations only.
        let routineHints = settings.showHints && settings.hintsShown < AppSettings.hintLimit
        model.showsHints = routineHints
        if routineHints { settings.hintsShown += 1 }
        isOverlayShown = true
        if settings.playSounds { NSSound(named: "Tink")?.play() }
        overlay.show(.listening, hint: isHandsFree ? handsFreeHint : "Release fn to insert · esc to cancel")
        if isHandsFree { watchForSilence() }
    }

    private func watchForSilence() {
        silenceWatch?.cancel()
        silenceWatch = Task {
            while !Task.isCancelled, isRecording, isHandsFree {
                try? await Task.sleep(for: .milliseconds(250))
                if heardVoice, !isSwitchingMicrophone, Date().timeIntervalSince(lastVoiceAt) > silenceToStop {
                    logger.info("hands-free stopped after silence")
                    finish()
                    return
                }
            }
        }
    }

    func finish() {
        silenceWatch?.cancel()
        guard let recorder else {
            // fn released before the microphone started.
            flow?.cancel()
            hideOverlay()
            return
        }
        let samples = recorder.stop()
        self.recorder = nil
        isRecording = false
        let seconds = Double(samples.count) / DictationRecorder.sampleRate
        guard seconds >= minimumSeconds else {
            hideOverlay()
            return
        }
        // Whisper invents text on silence ("Thank you."), so skip it entirely.
        guard heardVoice else {
            flow = Task {
                showException(.cancelled, hint: "Didn’t hear anything")
                try? await Task.sleep(for: .milliseconds(1300))
                guard !Task.isCancelled else { return }
                hideOverlay()
            }
            return
        }

        flow?.cancel()
        flow = Task {
            overlay.show(
                .processing, hint: modelStatus == .ready ? "Transcribing on this Mac" : "Loading \(modelName)…")
            do {
                let transcriber = transcriber
                let generation = modelGeneration
                try await transcriber.prepare { state in
                    Task { @MainActor in DictationController.shared.update(state, generation: generation) }
                }
                overlay.model.hint = "Transcribing on this Mac"
                var transcript = try await transcriber.transcribe(
                    samples, language: settings.language, prompt: settings.recognitionPrompt)
                let raw = transcript.text
                let cleaned = settings.cleanup.applyCountingUses(to: raw)
                transcript.text = cleaned.text
                settings.recordUses(cleaned.uses)
                guard !Task.isCancelled else { return }
                logger.info(
                    "transcribed \(transcript.audioSeconds, format: .fixed(precision: 1)) s in \(transcript.processingSeconds, format: .fixed(precision: 2)) s, \(transcript.wordCount) words, \(transcript.language ?? "?", privacy: .public)"
                )
                await insert(transcript, raw: raw)
            } catch {
                logger.error("transcription failed: \(String(describing: error), privacy: .public)")
                showException(.cancelled, hint: "Couldn’t transcribe — \(String(describing: error))")
                try? await Task.sleep(for: .seconds(3))
                hideOverlay()
            }
        }
    }

    func cancel(quietly: Bool = false) {
        flow?.cancel()
        silenceWatch?.cancel()
        stopRecorder()
        guard !quietly else {
            hideOverlay()
            return
        }
        flow = Task {
            overlay.show(.cancelled, hint: "Cancelled — nothing inserted")
            try? await Task.sleep(for: .milliseconds(1300))
            guard !Task.isCancelled else { return }
            hideOverlay()
        }
    }

    private func stopRecorder() {
        _ = recorder?.stop()
        recorder = nil
        isRecording = false
    }

    /// Something unusual happened: always explain it, even after routine hints stopped.
    private func showException(_ phase: OverlayModel.Phase, hint: String) {
        overlay.model.showsHints = true
        overlay.show(phase, hint: hint)
    }

    private func hideOverlay() {
        isOverlayShown = false
        overlay.hide()
    }

    // MARK: - Insertion

    private func insert(_ transcript: Transcript, raw: String) async {
        guard !transcript.text.isEmpty else {
            showException(.cancelled, hint: "Nothing recognized")
            try? await Task.sleep(for: .milliseconds(1500))
            hideOverlay()
            return
        }
        let app = NSWorkspace.shared.frontmostApplication?.localizedName
        history.add(
            .init(
                date: Date(), text: transcript.text, rawText: raw == transcript.text ? nil : raw, app: app,
                language: transcript.language))
        let timing = String(format: "%.1f s", transcript.processingSeconds)

        if FocusInspector.isSecureInputEnabled {
            // A password field: typing is blocked, so leave the text where the user can get it.
            copyToClipboard(transcript.text)
            showException(.copied, hint: "Password field — typing is blocked")
            try? await Task.sleep(for: .seconds(3))
        } else {
            _ = await TextInserter.insert(
                transcript.text, method: .pasteboard, restoreClipboard: settings.restoreClipboard)
            if settings.playSounds { NSSound(named: "Pop")?.play() }
            overlay.show(
                .inserted,
                hint: "Inserted into \(app ?? "the app in front") · \(transcript.wordCount) words · \(timing)")
            try? await Task.sleep(for: .milliseconds(1800))
        }
        guard !Task.isCancelled else { return }
        hideOverlay()
    }

    /// Inserts an earlier dictation again into the app in front, from the menu.
    func reinsert(_ entry: DictationHistory.Entry) {
        Task {
            // Let the menu close and focus return to the app.
            try? await Task.sleep(for: .milliseconds(250))
            if FocusInspector.isSecureInputEnabled {
                copyToClipboard(entry.text)
            } else {
                _ = await TextInserter.insert(
                    entry.text, method: .pasteboard, restoreClipboard: settings.restoreClipboard)
            }
        }
    }

    func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
