// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import AppKit
import SwiftUI

/// Renders every overlay state to PNG files, for reviewing the design without a screen capture:
///
///     open Typist.app --args --overlay-snapshots <directory>
@MainActor
enum OverlaySnapshots {
    static func runIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--overlay-snapshots"), arguments.indices.contains(index + 1)
        else { return }
        let directory = URL(filePath: arguments[index + 1], directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let states: [(String, OverlayModel.Phase, Bool, Bool, String?)] = [
            ("1-listening", .listening, false, false, "Release fn to insert · esc to cancel"),
            ("2-hands-free", .listening, true, false, "fn to finish · stops after 3 s of silence"),
            ("3-processing", .processing, false, false, "Transcribing on this Mac"),
            ("4-inserted", .inserted, false, false, "Inserted into Team chat"),
            ("5-cancelled", .cancelled, false, false, nil),
            ("6-remote", .listening, false, true, "Transcribing on home-whisper (192.168.1.10)"),
            ("7-copied", .copied, false, false, nil),
            ("8-fallback", .fallback, false, false, "home-whisper didn’t answer"),
            ("9-needs-microphone", .needsMicrophone, false, false, nil),
        ]
        let sample: [Float] = [0.1, 0.35, 0.8, 0.55, 0.2, 0.65, 0.95, 0.5, 0.15, 0.3, 0.6, 0.05]
        for (name, phase, handsFree, remote, hint) in states {
            let model = OverlayModel()
            for level in sample { model.push(level: level) }
            model.phase = phase
            model.isHandsFree = handsFree
            model.isRemote = remote
            model.startedAt = Date().addingTimeInterval(-84)
            model.hint = hint
            let view = OverlayView(model: model)
                .frame(width: OverlayPanel.size.width, height: OverlayPanel.size.height)
                .background(Color(red: 0.17, green: 0.2, blue: 0.27))
                .environment(\.colorScheme, .dark)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            guard let image = renderer.cgImage else { continue }
            let rep = NSBitmapImageRep(cgImage: image)
            try? rep.representation(using: .png, properties: [:])?.write(to: directory.appending(path: "\(name).png"))
        }
        NSApplication.shared.terminate(nil)
    }
}
