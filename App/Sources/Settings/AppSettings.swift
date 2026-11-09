// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import Foundation
import Observation
import TypistProviders

/// User preferences, stored in UserDefaults. The main window edits them, dictation reads them.
@MainActor @Observable
final class AppSettings {
    static let shared = AppSettings()

    enum OverlayPosition: String, CaseIterable, Identifiable {
        case bottom, top
        var id: Self { self }
        var title: String { self == .bottom ? "Above the Dock" : "Below the menu bar" }
    }

    enum Theme: String, CaseIterable, Identifiable {
        /// The system's dark appearance.
        case dark
        /// Ink-navy surfaces from the deb.space palette.
        case darkBlue
        case light

        var id: Self { self }
        var title: String {
            switch self {
            case .dark: "Dark"
            case .darkBlue: "Dark Blue"
            case .light: "Light"
            }
        }
    }

    enum HistoryRetention: String, CaseIterable, Identifiable {
        case forever, month, week, never
        var id: Self { self }
        var title: String {
            switch self {
            case .forever: "Forever"
            case .month: "For 30 days"
            case .week: "For 7 days"
            case .never: "Don’t keep"
            }
        }
        /// nil keeps entries forever; 0 keeps none.
        var days: Int? {
            switch self {
            case .forever: nil
            case .month: 30
            case .week: 7
            case .never: 0
            }
        }
    }

    /// Languages offered in the picker. Whisper knows many more; detection covers the rest.
    static let languages: [(code: String?, name: String)] = [
        (nil, "Detect automatically"), ("en", "English"), ("ru", "Русский"), ("de", "Deutsch"),
        ("es", "Español"), ("fr", "Français"), ("pt", "Português"), ("it", "Italiano"), ("uk", "Українська"),
    ]

    var autostopSeconds: Double { didSet { store(autostopSeconds, "autostopSeconds") } }
    var restoreClipboard: Bool { didSet { store(restoreClipboard, "restoreClipboard") } }
    var showHints: Bool { didSet { store(showHints, "showHints") } }
    var playSounds: Bool { didSet { store(playSounds, "playSounds") } }
    var overlayPosition: OverlayPosition { didSet { store(overlayPosition.rawValue, "overlayPosition") } }
    /// nil detects the language.
    var language: String? { didSet { store(language ?? "", "language") } }
    var historyRetention: HistoryRetention { didSet { store(historyRetention.rawValue, "historyRetention") } }
    var modelVariant: String { didSet { store(modelVariant, "modelVariant") } }
    var dismissedGlobeTip: Bool { didSet { store(dismissedGlobeTip, "dismissedGlobeTip") } }
    var theme: Theme { didSet { store(theme.rawValue, "theme") } }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        autostopSeconds = defaults.object(forKey: "autostopSeconds") as? Double ?? 5
        restoreClipboard = defaults.object(forKey: "restoreClipboard") as? Bool ?? true
        showHints = defaults.object(forKey: "showHints") as? Bool ?? true
        playSounds = defaults.object(forKey: "playSounds") as? Bool ?? false
        overlayPosition = defaults.string(forKey: "overlayPosition").flatMap(OverlayPosition.init) ?? .bottom
        let storedLanguage = defaults.string(forKey: "language") ?? ""
        language = storedLanguage.isEmpty ? nil : storedLanguage
        historyRetention = defaults.string(forKey: "historyRetention").flatMap(HistoryRetention.init) ?? .month
        modelVariant = defaults.string(forKey: "modelVariant") ?? WhisperKitTranscriber.defaultVariant
        dismissedGlobeTip = defaults.bool(forKey: "dismissedGlobeTip")
        theme = defaults.string(forKey: "theme").flatMap(Theme.init) ?? .dark
    }

    private func store(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
