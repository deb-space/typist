// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import AppKit
import OSLog
import Observation
import TypistInput

/// Connects the fn hotkey to dictation.
@MainActor @Observable
final class HotkeyController {
    static let shared = HotkeyController()

    private let service = HotkeyService()
    private let logger = Logger(subsystem: "space.deb.typist", category: "hotkey")
    private(set) var status: HotkeyService.Status = .stopped

    var isRunning: Bool { status == .running }

    func start() {
        guard !isRunning else { return }
        service.onEvent = { [weak self] event in self?.handle(event) }
        service.start()
        status = service.status
        logger.info(
            "hotkey: \(String(describing: self.status), privacy: .public), accessibility \(FocusInspector.isTrusted), input monitoring \(HotkeyService.hasInputMonitoring)"
        )
    }

    /// Asks for the permissions the event tap needs, then tries again.
    func enable() {
        if !FocusInspector.isTrusted { FocusInspector.requestTrust() }
        if !HotkeyService.hasInputMonitoring { HotkeyService.requestInputMonitoring() }
        start()
    }

    private func handle(_ event: HotkeyService.Event) {
        logger.info("hotkey event: \(String(describing: event), privacy: .public)")
        let dictation = DictationController.shared
        switch event {
        case .pressed:
            dictation.prepareRecording()
        case .holdStarted:
            dictation.start(handsFree: false)
        case .handsFreeStarted:
            dictation.switchToHandsFree()
        case .holdEnded, .handsFreeEnded:
            dictation.finish()
        case .cancelled:
            dictation.cancel()
        case .aborted:
            dictation.cancel(quietly: true)
        }
    }
}
