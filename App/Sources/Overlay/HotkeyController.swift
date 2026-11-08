// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import AppKit
import OSLog
import Observation
import TypistInput

/// Connects the fn hotkey to the dictation overlay. There is no transcription yet: the overlay
/// shows the live microphone level and pretends to insert.
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
        let overlay = OverlayController.shared
        switch event {
        case .holdStarted:
            overlay.startTestDictation(handsFree: false, hint: "Release fn to insert · esc to cancel")
        case .handsFreeStarted:
            if overlay.isTestDictating {
                overlay.switchToHandsFree(hint: "fn to finish · esc to cancel")
            } else {
                overlay.startTestDictation(handsFree: true, hint: "fn to finish · esc to cancel")
            }
        case .holdEnded, .handsFreeEnded:
            overlay.finishTestDictation()
        case .cancelled:
            overlay.cancelTestDictation()
        case .aborted:
            overlay.cancelTestDictation(quietly: true)
        }
    }
}
