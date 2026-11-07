// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import Testing

@testable import TypistCore

@Suite struct PermissionTests {
    @Test func dictationNeedsMicrophoneAccessibilityAndInputMonitoring() {
        #expect(Permission.required(for: .dictation) == [.microphone, .accessibility, .inputMonitoring])
    }

    @Test func meetingsNeedMicrophoneAndSystemAudio() {
        #expect(Permission.required(for: .meetings) == [.microphone, .systemAudio])
    }

    @Test func calendarIsNeverRequired() {
        for feature in Feature.allCases {
            #expect(!Permission.required(for: feature).contains(.calendar))
        }
    }
}
