// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import SwiftUI
import TypistAudio

struct AudioSpikeView: View {
    @Bindable private var model = AudioSpikeModel.shared

    var body: some View {
        Form {
            Section("Setup") {
                Picker("Method", selection: $model.method) {
                    ForEach(AudioSpikeModel.Method.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)

                Picker("Source", selection: $model.targetBundleID) {
                    Text("All system audio").tag(String?.none)
                    Divider()
                    ForEach(model.apps) { app in
                        Text(app.name).tag(Optional(app.bundleID))
                    }
                }

                if model.method == .processTap, model.targetBundleID != nil {
                    Picker("New app processes", selection: $model.tracking) {
                        Text("Ignore").tag(ProcessTapCapture.Tracking.fixed)
                        Text("Add to tap").tag(ProcessTapCapture.Tracking.updateDescription)
                        if #available(macOS 26.0, *) {
                            Text("Match by bundle ID (macOS 26)").tag(ProcessTapCapture.Tracking.bundleIDs)
                        }
                    }
                }

                Picker("Microphone", selection: $model.micMode) {
                    ForEach(model.micModes) { Text($0.title).tag($0) }
                }
                Toggle("Voice processing (echo cancellation)", isOn: $model.voiceProcessing)
                    .disabled(model.micMode != .engine)
            }
            .disabled(model.isRecording || model.isBusy)

            Section("Recording") {
                HStack {
                    Button(model.isRecording ? "Stop" : "Record") {
                        Task { model.isRecording ? await model.stop() : await model.start() }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(model.isBusy)

                    if model.isRecording, let startedAt = model.startedAt {
                        Text(startedAt, style: .timer).monospacedDigit()
                    }
                    Spacer()
                    Button("Show Recordings") { model.showRecordings() }
                }
                LevelRow(title: "System", peak: model.systemLevel)
                LevelRow(title: "Microphone", peak: model.microphoneLevel)
                if !model.summary.isEmpty {
                    Text(model.summary)
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                }
            }

            Section {
                ForEach(model.audioProcesses) { process in
                    HStack {
                        Image(systemName: "speaker.wave.2.fill")
                            .opacity(process.isRunningOutput ? 1 : 0.15)
                        Image(systemName: "mic.fill")
                            .opacity(process.isRunningInput ? 1 : 0.15)
                        Text(process.name)
                        Spacer()
                        Text("\(process.bundleID ?? "-") · \(String(process.pid))")
                            .foregroundStyle(.secondary)
                    }
                    .font(.callout)
                }
            } header: {
                HStack {
                    Text("Audio processes")
                    Spacer()
                    Button("Refresh") { model.refresh() }
                        .buttonStyle(.borderless)
                }
            }

            Section("Log") {
                ScrollView {
                    Text(model.log.joined(separator: "\n"))
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 200)
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 600, minHeight: 720)
        .onAppear { model.refresh() }
    }
}

private struct LevelRow: View {
    let title: String
    let peak: Float

    var body: some View {
        LabeledContent(title) {
            ProgressView(value: Self.meterValue(peak))
                .frame(width: 260)
        }
    }

    /// Maps a peak to 0...1 on a -60...0 dBFS scale.
    static func meterValue(_ peak: Float) -> Double {
        guard peak > 0 else { return 0 }
        let decibels = 20 * log10(Double(peak))
        return min(1, max(0, (decibels + 60) / 60))
    }
}
