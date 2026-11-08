// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import Foundation
import Observation

/// What the dictation overlay shows.
@MainActor @Observable
final class OverlayModel {
    enum Phase: Equatable {
        case hidden
        case listening
        case processing
        case inserted
        case cancelled
        /// The text could not be typed and is on the clipboard instead.
        case copied
        /// The user's endpoint did not answer, the on-device model was used.
        case fallback
        case needsMicrophone
    }

    static let barCount = 12

    var phase: Phase = .hidden
    /// Hands-free mode shows a timer.
    var isHandsFree = false
    /// Audio or text goes to an external endpoint.
    var isRemote = false
    var startedAt = Date()
    /// The most recent levels, 0...1, oldest first.
    private(set) var levels = [Float](repeating: 0, count: OverlayModel.barCount)
    /// One line under the capsule, for the first few uses.
    var hint: String?
    var showsHints = true
    /// A test dictation from the menu bar is recording.
    var isLiveTest = false

    func push(level: Float) {
        levels.removeFirst()
        levels.append(level)
    }

    func resetLevels() {
        levels = [Float](repeating: 0, count: Self.barCount)
    }
}
