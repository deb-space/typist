// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import AppKit
import Carbon.HIToolbox
import CoreGraphics

/// Turns the fn key into the dictation trigger, using a session event tap.
///
/// - Hold fn (longer than ``holdDelay``): ``Event/holdStarted``; release: ``Event/holdEnded``.
///   A release before ``minimumHold`` counts as an accidental press: ``Event/aborted``.
/// - fn+Space: ``Event/handsFreeStarted`` (also from an ongoing hold); fn again: ``Event/handsFreeEnded``.
/// - fn together with another key (fn+arrow, fn+F-key) is not dictation: ``Event/aborted``.
/// - Esc while recording: ``Event/cancelled``. Esc is swallowed only then.
///
/// A short tap of fn is left alone: macOS runs the 🌐 key action on it (switch layout by default)
/// before the tap sees it, so taps cannot be a trigger unless that action is "Do Nothing".
/// ``doublePressStartsHandsFree`` enables a double press for that case.
///
/// Needs the Accessibility permission, because the tap can swallow events.
@MainActor
public final class HotkeyService {
    public enum Event: Sendable {
        /// fn went down and may become a hold. Start the microphone now so the first word is not
        /// cut off; ``aborted`` follows if it turns out to be a tap or a shortcut.
        case pressed
        case holdStarted, holdEnded, handsFreeStarted, handsFreeEnded, cancelled, aborted
    }

    public enum Status: Equatable, Sendable {
        case stopped, running, failed(String)
    }

    /// How long fn must be held before recording starts, so a tap does not flash the overlay.
    public var holdDelay: Duration = .milliseconds(250)
    /// Shorter holds are treated as accidental and do not insert anything.
    public var minimumHold: TimeInterval = 0.4
    /// Off by default: with the 🌐 key set to switch layouts, every tap also switches the layout.
    public var doublePressStartsHandsFree = false
    /// Maximum time between two taps of a double press.
    public var doublePressWindow: TimeInterval = 0.35
    /// Stop fn from reaching the system, so the 🌐 key action (switch layout, emoji) does not fire.
    public var swallowsFn = true

    public var onEvent: ((Event) -> Void)?
    public private(set) var status: Status = .stopped

    private enum State { case idle, pending, holding, handsFree }
    private var state: State = .idle
    private var fnIsDown = false
    private var ignoreNextFnUp = false
    private var lastTapUp: Date?
    private var fnDownAt: Date?
    private var holdTimer: Task<Void, Never>?
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    public init() {}

    public static var hasInputMonitoring: Bool { CGPreflightListenEventAccess() }

    /// Shows the system prompt for Input Monitoring and adds the app to its list.
    @discardableResult
    public static func requestInputMonitoring() -> Bool { CGRequestListenEventAccess() }

    public func start() {
        guard tap == nil else { return }
        let mask =
            (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: CGEventMask(mask), callback: hotkeyTapCallback,
                userInfo: Unmanaged.passUnretained(self).toOpaque())
        else {
            status = .failed("could not create the event tap: Accessibility or Input Monitoring is missing")
            return
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        runLoopSource = source
        CGEvent.tapEnable(tap: tap, enable: true)
        status = .running
    }

    public func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil
        runLoopSource = nil
        reset()
        status = .stopped
    }

    /// The consumer gave up on a recording on its own (an error, for example).
    public func reset() {
        holdTimer?.cancel()
        state = .idle
        ignoreNextFnUp = fnIsDown
        lastTapUp = nil
    }

    // MARK: - Events

    /// Returns true to swallow the event.
    fileprivate func handle(type: CGEventType, keyCode: Int64, flags: CGEventFlags) -> Bool {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        case .flagsChanged where keyCode == Int64(kVK_Function):
            let down = flags.contains(.maskSecondaryFn)
            guard down != fnIsDown else { return swallowsFn }
            fnIsDown = down
            down ? fnPressed() : fnReleased()
            return swallowsFn
        case .keyDown:
            return otherKeyPressed(keyCode: keyCode)
        default:
            return false
        }
    }

    private func fnPressed() {
        switch state {
        case .handsFree:
            state = .idle
            ignoreNextFnUp = true
            onEvent?(.handsFreeEnded)
        case .idle:
            fnDownAt = Date()
            if doublePressStartsHandsFree, let lastTapUp, Date().timeIntervalSince(lastTapUp) < doublePressWindow {
                self.lastTapUp = nil
                state = .handsFree
                ignoreNextFnUp = true
                onEvent?(.handsFreeStarted)
            } else {
                state = .pending
                onEvent?(.pressed)
                holdTimer?.cancel()
                holdTimer = Task { [weak self, holdDelay] in
                    try? await Task.sleep(for: holdDelay)
                    guard let self, !Task.isCancelled, state == .pending else { return }
                    state = .holding
                    onEvent?(.holdStarted)
                }
            }
        case .pending, .holding:
            break
        }
    }

    private func fnReleased() {
        if ignoreNextFnUp {
            ignoreNextFnUp = false
            return
        }
        switch state {
        case .pending:
            holdTimer?.cancel()
            state = .idle
            lastTapUp = Date()
            onEvent?(.aborted)
        case .holding:
            state = .idle
            let held = fnDownAt.map { Date().timeIntervalSince($0) } ?? .infinity
            if held < minimumHold {
                lastTapUp = Date()
                onEvent?(.aborted)
            } else {
                onEvent?(.holdEnded)
            }
        case .idle, .handsFree:
            break
        }
    }

    private func otherKeyPressed(keyCode: Int64) -> Bool {
        if keyCode == Int64(kVK_Escape), state == .holding || state == .handsFree {
            state = .idle
            ignoreNextFnUp = fnIsDown
            onEvent?(.cancelled)
            return true
        }
        if keyCode == Int64(kVK_Space), fnIsDown, state == .pending || state == .holding {
            holdTimer?.cancel()
            state = .handsFree
            ignoreNextFnUp = true
            onEvent?(.handsFreeStarted)
            return true
        }
        switch state {
        case .pending:
            // fn used as a modifier (fn+arrow): not dictation.
            holdTimer?.cancel()
            state = .idle
            ignoreNextFnUp = true
            onEvent?(.aborted)
        case .holding where fnIsDown:
            state = .idle
            ignoreNextFnUp = true
            onEvent?(.aborted)
        default:
            break
        }
        lastTapUp = nil
        return false
    }
}

private func hotkeyTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let service = Unmanaged<HotkeyService>.fromOpaque(refcon).takeUnretainedValue()
    let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
    let flags = event.flags
    // The tap's run loop source is on the main run loop.
    let swallow = MainActor.assumeIsolated {
        service.handle(type: type, keyCode: keyCode, flags: flags)
    }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
