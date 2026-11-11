// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import Foundation
import Observation
import TypistCore
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
    /// How many dictations have shown the routine hints; they stop after ``hintLimit``.
    var hintsShown: Int { didSet { store(hintsShown, "hintsShown") } }
    static let hintLimit = 5
    var playSounds: Bool { didSet { store(playSounds, "playSounds") } }
    var overlayPosition: OverlayPosition { didSet { store(overlayPosition.rawValue, "overlayPosition") } }
    /// nil detects the language.
    var language: String? { didSet { store(language ?? "", "language") } }
    var historyRetention: HistoryRetention { didSet { store(historyRetention.rawValue, "historyRetention") } }
    var modelVariant: String { didSet { store(modelVariant, "modelVariant") } }
    var dismissedGlobeTip: Bool { didSet { store(dismissedGlobeTip, "dismissedGlobeTip") } }
    var theme: Theme { didSet { store(theme.rawValue, "theme") } }
    /// Rule-based cleanup: fillers, stutters and phrases Whisper invents.
    var cleanupEnabled: Bool { didSet { store(cleanupEnabled, "cleanupEnabled") } }
    /// The personal dictionary.
    var replacements: [Replacement] {
        didSet { store((try? JSONEncoder().encode(replacements)) ?? Data(), "replacements") }
    }

    /// How many times each dictionary entry was applied, by entry id.
    var dictionaryUses: [UUID: Int] {
        didSet { store((try? JSONEncoder().encode(dictionaryUses)) ?? Data(), "dictionaryUses") }
    }

    func recordUses(_ uses: [UUID: Int]) {
        guard !uses.isEmpty else { return }
        dictionaryUses.merge(uses, uniquingKeysWith: +)
    }

    /// Dictionary terms (not snippets) as a hint for speech recognition.
    var recognitionPrompt: String? {
        // Most used first: Whisper's prompt has room for about 200 tokens, the rest is cut off.
        var seen: Set<String> = []
        let terms = replacements.filter { $0.kind == .term }
            .sorted { (dictionaryUses[$0.id] ?? 0, $1.to) > (dictionaryUses[$1.id] ?? 0, $0.to) }
            .map { $0.to.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && seen.insert($0.lowercased()).inserted }
        return terms.isEmpty ? nil : terms.joined(separator: ", ")
    }

    var cleanup: TextCleanup {
        TextCleanup(
            removesFillers: cleanupEnabled, removesStutters: cleanupEnabled, removesPhantomPhrases: cleanupEnabled,
            replacements: replacements)
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        autostopSeconds = defaults.object(forKey: "autostopSeconds") as? Double ?? 5
        restoreClipboard = defaults.object(forKey: "restoreClipboard") as? Bool ?? true
        showHints = defaults.object(forKey: "showHints") as? Bool ?? true
        hintsShown = defaults.integer(forKey: "hintsShown")
        playSounds = defaults.object(forKey: "playSounds") as? Bool ?? false
        overlayPosition = defaults.string(forKey: "overlayPosition").flatMap(OverlayPosition.init) ?? .bottom
        let storedLanguage = defaults.string(forKey: "language") ?? ""
        language = storedLanguage.isEmpty ? nil : storedLanguage
        historyRetention = defaults.string(forKey: "historyRetention").flatMap(HistoryRetention.init) ?? .month
        modelVariant = defaults.string(forKey: "modelVariant") ?? WhisperKitTranscriber.defaultVariant
        dismissedGlobeTip = defaults.bool(forKey: "dismissedGlobeTip")
        theme = defaults.string(forKey: "theme").flatMap(Theme.init) ?? .dark
        cleanupEnabled = defaults.object(forKey: "cleanupEnabled") as? Bool ?? true
        replacements =
            defaults.data(forKey: "replacements").flatMap { try? JSONDecoder().decode([Replacement].self, from: $0) }
            ?? []
        dictionaryUses =
            defaults.data(forKey: "dictionaryUses").flatMap { try? JSONDecoder().decode([UUID: Int].self, from: $0) }
            ?? [:]
    }

    private func store(_ value: Any, _ key: String) {
        defaults.set(value, forKey: key)
    }
}
