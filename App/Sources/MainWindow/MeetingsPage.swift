// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import AppKit
import SwiftUI
import TypistAudio
import UniformTypeIdentifiers

struct MeetingsPage: View {
    @Environment(\.palette) private var palette
    @Bindable private var recorder = MeetingRecorder.shared
    @State private var askingConsent = false
    @State private var error: String?
    /// The meeting shown in full, by id.
    @State private var opened: String?
    @State private var choosingFiles = false
    /// A file is being dragged over the list.
    @State private var dropTargeted = false
    private var transcriber: MeetingTranscriber { .shared }

    var body: some View {
        if let record = recorder.recordings.first(where: { $0.id == opened }) {
            MeetingDetailView(record: record) { opened = nil }
        } else {
            list
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 10) {
                CardSection("Record a meeting") {
                    if recorder.isRecording {
                        recordingRows
                    } else {
                        setupRows
                    }
                }
                Text(
                    "Two tracks: your microphone, and the call app’s sound. No bot joins the call, and recordings stay on this Mac. Let everyone on the call know you’re recording."
                )
                .font(.system(size: 12))
                .foregroundStyle(palette.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Recordings")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(palette.secondaryText)
                    Spacer()
                    Button("Import Audio or Video…") { choosingFiles = true }
                        .buttonStyle(.themedSmall)
                        .help("Transcribe a recording made elsewhere: mp3, m4a, wav, mp4, mov and more")
                }
                CardSection {
                    ForEach(recorder.importing.indices, id: \.self) { index in
                        CardRow(recorder.importing[index], index == 0 ? "Importing…" : "Waiting to import") {
                            if index == 0 { ProgressView().controlSize(.small) }
                        }
                    }
                    if recorder.recordings.isEmpty && recorder.importing.isEmpty {
                        Text("No meetings yet. Record one above, or drop an audio or video file here.")
                            .foregroundStyle(palette.secondaryText)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    }
                    ForEach(recorder.recordings) { record in
                        recordingRow(record, last: record.id == recorder.recordings.last?.id)
                    }
                }
                .overlay {
                    if dropTargeted {
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(palette.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                            .allowsHitTesting(false)
                    }
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                let files = urls.filter(Self.isImportable)
                guard !files.isEmpty else { return false }
                importFiles(files)
                return true
            } isTargeted: {
                dropTargeted = $0
            }
        }
        .fileImporter(
            isPresented: $choosingFiles, allowedContentTypes: AudioImport.types, allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result { importFiles(urls) }
        }
        .alert(
            "Couldn’t import the file",
            isPresented: Binding(
                get: { recorder.importError != nil }, set: { if !$0 { recorder.dismissImportError() } })
        ) {
            Button("OK") { recorder.dismissImportError() }
        } message: {
            Text(recorder.importError ?? "")
        }
        .onAppear {
            recorder.reload()
        }
        .alert("Let everyone know you’re recording", isPresented: $askingConsent) {
            Button("Start Recording") {
                recorder.consentShown = true
                Task { await recorder.start() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "In many places it’s illegal to record a call without the consent of everyone on it. Typist doesn’t notify the other side."
            )
        }
        .alert("Couldn’t delete the recording", isPresented: .constant(error != nil)) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    /// Imports the files and, for a single file, opens it to follow the transcription.
    private func importFiles(_ urls: [URL]) {
        Task {
            let id = await recorder.importFiles(urls)
            if urls.count == 1, let id { opened = id }
        }
    }

    /// Audio and video files; folders and documents dropped by mistake are ignored.
    static func isImportable(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .audiovisualContent)
    }

    // MARK: - Recording card

    @ViewBuilder
    private var setupRows: some View {
        CardRow("Other side", "The app your call runs in, with its helper processes") {
            ThemedMenu(
                options: [(String?.none, "All system audio")]
                    + AudioApp.running().map { (Optional($0.bundleID), $0.name) },
                selection: $recorder.sourceBundleID, label: "Other side")
        }
        CardRow("You", "The microphone selected in macOS, on its own track") {
            Text(AudioDevices.defaultInputName()).foregroundStyle(palette.secondaryText)
        }
        CardRow(
            recorder.isFinishing ? "Compressing the last recording…" : "Ready",
            recorder.error ?? "Recording starts at once; stop it here or from the menu bar", divider: false
        ) {
            Button("Start Recording") {
                if recorder.consentShown {
                    Task { await recorder.start() }
                } else {
                    askingConsent = true
                }
            }
            .buttonStyle(.themedPrimary)
        }
    }

    @ViewBuilder
    private var recordingRows: some View {
        CardRow(recorder.sourceName, "Other side") {
            LevelMeter(level: recorder.otherSideLevel)
        }
        CardRow("You", "Microphone") {
            LevelMeter(level: recorder.microphoneLevel)
        }
        CardRow(
            "Recording",
            recorder.heardOtherSide || elapsed < 20
                ? "Stop when the call ends"
                : "No sound from the other side yet. Check System Settings › Privacy & Security › System Audio Recording",
            divider: false
        ) {
            HStack(spacing: 12) {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    HStack(spacing: 6) {
                        Circle().fill(palette.danger).frame(width: 8, height: 8)
                        Text(Self.duration(elapsed)).monospacedDigit()
                    }
                }
                Button("Stop") { recorder.stop() }.buttonStyle(.themed)
            }
        }
    }

    private var elapsed: Double {
        recorder.startedAt.map { Date().timeIntervalSince($0) } ?? 0
    }

    // MARK: - Recordings

    private func recordingRow(_ record: MeetingRecord, last: Bool) -> some View {
        let size = recorder.sizeOnDisk(of: record).map {
            ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
        }
        let detail = [
            Self.duration(record.seconds), record.sourceDescription, size,
            record.endedAt == nil && record.id != MeetingRecorder.shared.currentID ? "interrupted" : nil,
            transcriptionNote(record),
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
        return CardRow(record.startedAt.formatted(date: .abbreviated, time: .shortened), detail, divider: !last) {
            HStack(spacing: 8) {
                if record.id != MeetingRecorder.shared.currentID {
                    Button("Open") { opened = record.id }
                        .buttonStyle(.themed)
                }
                Button {
                    NSWorkspace.shared.activateFileViewerSelecting([recorder.folder(of: record)])
                } label: {
                    Image(systemName: "folder").font(.system(size: 12))
                }
                .buttonStyle(.themed)
                .help("Show in Finder")
                .accessibilityLabel("Show in Finder")
                Button {
                    do {
                        try recorder.delete(record)
                    } catch {
                        self.error = error.localizedDescription
                    }
                } label: {
                    Image(systemName: "trash").font(.system(size: 12))
                }
                .buttonStyle(.themed)
                .help("Delete")
                .accessibilityLabel("Delete")
                .disabled(record.id == MeetingRecorder.shared.currentID)
            }
        }
    }

    private func transcriptionNote(_ record: MeetingRecord) -> String? {
        switch transcriber.status[record.id] {
        case .queued, .loadingModel: return "waiting to transcribe"
        case .transcribing(let fraction): return "transcribing \(Int(fraction * 100))%"
        case .findingSpeakers: return "finding speakers"
        case .failed: return "transcription failed"
        case nil: return transcriber.transcript(of: record) == nil ? nil : "transcribed"
        }
    }

    static func duration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds))
        return total >= 3600
            ? String(format: "%d:%02d:%02d", total / 3600, total / 60 % 60, total % 60)
            : String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// A horizontal level bar for a track.
private struct LevelMeter: View {
    @Environment(\.palette) private var palette
    let level: Float

    var body: some View {
        // Square root, so quiet speech still moves the bar.
        let fraction = CGFloat(min(1, sqrt(max(0, level))))
        ZStack(alignment: .leading) {
            Capsule().fill(palette.control)
            Capsule().fill(palette.accent).frame(width: 160 * fraction)
        }
        .frame(width: 160, height: 6)
        .animation(.linear(duration: 0.1), value: fraction)
        .accessibilityHidden(true)
    }
}

#Preview("Meetings · Dark Blue") {
    ScrollView {
        MeetingsPage().padding(44)
    }
    .frame(width: 860, height: 640)
    .background(ThemePalette.darkBlue.window)
    .foregroundStyle(ThemePalette.darkBlue.text)
    .environment(\.palette, .darkBlue)
}
