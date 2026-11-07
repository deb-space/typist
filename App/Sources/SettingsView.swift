// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import SwiftUI
import TypistCore

struct SettingsView: View {
    var body: some View {
        Form {
            Section("Permissions") {
                ForEach(Permission.allCases) { permission in
                    LabeledContent(permission.title, value: permission.purpose)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .fixedSize()
    }
}

extension Permission {
    fileprivate var title: String {
        switch self {
        case .microphone: "Microphone"
        case .accessibility: "Accessibility"
        case .inputMonitoring: "Input Monitoring"
        case .systemAudio: "System Audio"
        case .calendar: "Calendar"
        }
    }

    fileprivate var purpose: String {
        switch self {
        case .microphone: "Records your voice"
        case .accessibility: "Inserts text into other apps"
        case .inputMonitoring: "Global hotkeys"
        case .systemAudio: "Records the other side of a call"
        case .calendar: "Optional: names meetings"
        }
    }
}

#Preview {
    SettingsView()
}
