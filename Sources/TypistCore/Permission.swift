// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

/// A macOS privacy permission that typist asks the user for.
public enum Permission: String, CaseIterable, Sendable, Identifiable {
    /// Recording the user's voice.
    case microphone
    /// Inserting text into other apps.
    case accessibility
    /// Global hotkeys, including Fn and push-to-talk.
    case inputMonitoring
    /// Recording the other side of a call.
    case systemAudio
    /// Matching recordings to calendar events. Optional.
    case calendar

    public var id: String { rawValue }

    /// Features that a permission is needed for.
    public var features: Set<Feature> {
        switch self {
        case .microphone: [.dictation, .meetings]
        case .accessibility, .inputMonitoring: [.dictation]
        case .systemAudio: [.meetings]
        case .calendar: []
        }
    }

    /// Permissions required for a feature to work.
    public static func required(for feature: Feature) -> [Permission] {
        allCases.filter { $0.features.contains(feature) }
    }
}

/// A user-facing feature of typist.
public enum Feature: String, CaseIterable, Sendable {
    case dictation
    case meetings
}
