// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import AppKit
import ScreenCaptureKit
import SwiftUI

/// Captures every page of the main window to PNG files with ScreenCaptureKit (needs the Screen
/// Recording permission), for reviewing the layout. The window shows on screen for a few seconds:
///
///     open Typist.app --args --window-snapshots <directory> [--light] [--theme dark|darkBlue]
@MainActor
enum MainWindowSnapshots {
    static func runIfRequested() {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "--window-snapshots"), arguments.indices.contains(index + 1)
        else { return }
        let directory = URL(filePath: arguments[index + 1], directoryHint: .isDirectory)
        let appearance = NSAppearance(named: arguments.contains("--light") ? .aqua : .darkAqua)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // Applied for the snapshots only, then put back.
        let savedTheme = AppSettings.shared.theme
        if let name = arguments.firstIndex(of: "--theme").flatMap({
            arguments.indices.contains($0 + 1) ? arguments[$0 + 1] : nil
        }),
            let theme = AppSettings.Theme(rawValue: name)
        {
            AppSettings.shared.theme = theme
        }

        // Built like the SwiftUI Window scene builds it, so the toolbar and safe areas match.
        let window = NSWindow(contentViewController: NSHostingController(rootView: MainWindowView()))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.setFrame(NSRect(x: 80, y: 80, width: 980, height: 700), display: true)
        window.appearance = appearance
        window.orderFrontRegardless()

        Task {
            for section in MainSection.allCases {
                MainWindowRouter.shared.selection = section
                // Let SwiftUI lay out and the permission and size checks finish.
                try? await Task.sleep(for: .milliseconds(900))
                guard let image = await capture(window) else { continue }
                try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?
                    .write(to: directory.appending(path: "\(section.rawValue).png"))
            }
            AppSettings.shared.theme = savedTheme
            NSApplication.shared.terminate(nil)
        }
    }

    private static func capture(_ window: NSWindow) async -> CGImage? {
        guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false),
            let scWindow = content.windows.first(where: { $0.windowID == CGWindowID(window.windowNumber) })
        else { return nil }
        let configuration = SCStreamConfiguration()
        configuration.width = Int(window.frame.width * 2)
        configuration.height = Int(window.frame.height * 2)
        configuration.showsCursor = false
        return try? await SCScreenshotManager.captureImage(
            contentFilter: SCContentFilter(desktopIndependentWindow: scWindow), configuration: configuration)
    }
}
