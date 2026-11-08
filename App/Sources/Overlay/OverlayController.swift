// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import AppKit
import SwiftUI
import TypistAudio

/// A borderless panel that floats above other apps without taking focus, so text keeps going
/// to the app the user is typing in.
final class OverlayPanel: NSPanel {
    static let size = NSSize(width: 420, height: 116)

    init(contentView: NSView) {
        super.init(
            contentRect: NSRect(origin: .zero, size: Self.size), styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered, defer: true)
        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        animationBehavior = .none
        ignoresMouseEvents = true
        self.contentView = contentView
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Shows the dictation overlay and runs the test flows from the menu bar.
@MainActor
final class OverlayController {
    static let shared = OverlayController()

    let model = OverlayModel()
    private lazy var panel: OverlayPanel = {
        let hosting = NSHostingView(rootView: OverlayView(model: model))
        hosting.sizingOptions = []
        return OverlayPanel(contentView: hosting)
    }()
    private var meter: MicrophoneMeter?
    private var flow: Task<Void, Never>?

    var isTestDictating: Bool { model.isLiveTest }

    // MARK: - Showing

    func show(_ phase: OverlayModel.Phase, hint: String? = nil) {
        if model.phase == .hidden { position() }
        model.hint = hint
        model.phase = phase
        // Only the permission state has a button; everywhere else clicks go through.
        panel.ignoresMouseEvents = phase != .needsMicrophone
        panel.orderFrontRegardless()
    }

    func hide() {
        model.phase = .hidden
        model.hint = nil
        Task {
            try? await Task.sleep(for: .milliseconds(250))
            if model.phase == .hidden { panel.orderOut(nil) }
        }
    }

    /// Bottom center of the screen under the mouse pointer, just above the Dock.
    private func position() {
        let mouse = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main
        else { return }
        let frame = screen.visibleFrame
        panel.setFrameOrigin(NSPoint(x: frame.midX - OverlayPanel.size.width / 2, y: frame.minY - 12))
    }

    // MARK: - Test dictation with the real microphone

    func toggleTestDictation() {
        if isTestDictating {
            finishTestDictation()
        } else {
            startTestDictation(handsFree: true, hint: "Choose Stop Test Dictation in the menu bar")
        }
    }

    /// Shows the listening capsule driven by the real microphone. Nothing is recorded.
    func startTestDictation(handsFree: Bool, hint: String) {
        stopMeter()
        flow?.cancel()
        flow = Task {
            let granted = await MicrophoneCapture.requestPermission()
            // fn may already be released while the permission check was running.
            guard !Task.isCancelled else { return }
            guard granted else {
                show(.needsMicrophone)
                try? await Task.sleep(for: .seconds(4))
                if model.phase == .needsMicrophone { hide() }
                return
            }
            let meter = MicrophoneMeter()
            let model = model
            do {
                try meter.start { level in
                    Task { @MainActor in model.push(level: level) }
                }
            } catch {
                show(.needsMicrophone)
                return
            }
            self.meter = meter
            model.isLiveTest = true
            model.resetLevels()
            model.isHandsFree = handsFree
            model.isRemote = false
            model.startedAt = Date()
            show(.listening, hint: hint)
        }
    }

    /// A hold turned into hands-free (fn+Space): keep listening, add the timer.
    func switchToHandsFree(hint: String) {
        model.isHandsFree = true
        model.hint = hint
    }

    func finishTestDictation() {
        stopMeter()
        flow?.cancel()
        flow = Task {
            show(.processing, hint: "Transcribing on this Mac")
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            show(.inserted, hint: "Inserted into the app in front")
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            hide()
        }
    }

    /// - Parameter quietly: hide without the ✕, for an aborted hold such as fn+arrow.
    func cancelTestDictation(quietly: Bool = false) {
        stopMeter()
        flow?.cancel()
        if quietly {
            hide()
            return
        }
        flow = Task {
            show(.cancelled, hint: "Cancelled — nothing inserted")
            try? await Task.sleep(for: .milliseconds(1300))
            guard !Task.isCancelled else { return }
            hide()
        }
    }

    private func stopMeter() {
        meter?.stop()
        meter = nil
        model.isLiveTest = false
    }

    // MARK: - Tour of all states

    func showAllStates() {
        stopMeter()
        flow?.cancel()
        flow = Task {
            let fakeLevels = Task {
                var t = 0.0
                while !Task.isCancelled {
                    t += 1
                    let envelope = 0.5 + 0.5 * abs(sin(t * 0.13))
                    model.push(level: Float(envelope * abs(sin(t * 0.9) * cos(t * 0.37))))
                    try? await Task.sleep(for: .milliseconds(50))
                }
            }
            defer { fakeLevels.cancel() }

            let steps: [(OverlayModel.Phase, Bool, Bool, String)] = [
                (.listening, false, false, "1/9 · Listening — release fn to insert"),
                (.listening, true, false, "2/9 · Hands-free — fn to finish"),
                (.processing, false, false, "3/9 · Processing on this Mac"),
                (.inserted, false, false, "4/9 · Inserted"),
                (.cancelled, false, false, "5/9 · Cancelled"),
                (.listening, false, true, "6/9 · Audio leaves the Mac"),
                (.copied, false, false, "7/9 · Couldn’t type here"),
                (.fallback, false, false, "8/9 · Endpoint didn’t answer"),
                (.needsMicrophone, false, false, "9/9 · Needs a permission"),
            ]
            for (phase, handsFree, remote, hint) in steps {
                model.isHandsFree = handsFree
                model.isRemote = remote
                model.startedAt = Date().addingTimeInterval(-84)
                show(phase, hint: hint)
                try? await Task.sleep(for: .milliseconds(2200))
                if Task.isCancelled { return }
            }
            model.isRemote = false
            hide()
        }
    }
}
