// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import AppKit
import SwiftUI
import TypistCore

/// One meeting: a player for both tracks and the transcript. Clicking a line plays from there.
struct MeetingDetailView: View {
    @Environment(\.palette) private var palette
    let record: MeetingRecord
    let onBack: () -> Void
    @State private var player = MeetingPlayer()
    @State private var copied = false
    /// Whisper's own text of each track instead of the lines by speaker.
    @State private var showsWhisper = false
    /// The line whose speaker is being named, by position.
    @State private var renaming: Int?
    @State private var draftName = ""
    private var transcriber: MeetingTranscriber { .shared }
    private var recorder: MeetingRecorder { .shared }

    /// The names you gave this meeting's speakers; the library's copy changes as you rename.
    private var names: [String: String] {
        (recorder.recordings.first { $0.id == record.id } ?? record).speakerNames ?? [:]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Button(action: onBack) {
                Label("Meetings", systemImage: "chevron.left").font(.system(size: 13))
            }
            .buttonStyle(.themedQuiet)

            VStack(alignment: .leading, spacing: 4) {
                Text(record.startedAt.formatted(date: .complete, time: .shortened))
                    .font(.system(size: 17, weight: .semibold))
                Text(
                    [MeetingsPage.duration(record.seconds), record.sourceName ?? "All system audio"]
                        .joined(separator: " · ")
                )
                .font(.system(size: 13))
                .foregroundStyle(palette.secondaryText)
            }

            playerBar
            transcriptSection
        }
        .task {
            await player.load(record, folder: recorder.folder(of: record))
            if transcriber.transcript(of: record) == nil, transcriber.status[record.id] == nil {
                transcriber.transcribe(record)
            }
        }
        .onDisappear { player.stop() }
    }

    // MARK: - Player

    private var playerBar: some View {
        HStack(spacing: 14) {
            Button {
                player.toggle()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 13))
                    .frame(width: 18)
            }
            .buttonStyle(.themedPrimary)
            .keyboardShortcut(.space, modifiers: [])
            .disabled(!player.isReady)
            .accessibilityLabel(player.isPlaying ? "Pause" : "Play")

            Text(MeetingTranscript.timestamp(player.currentTime))
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)
            Slider(
                value: Binding(get: { player.currentTime }, set: { player.seek(to: $0) }),
                in: 0...max(1, player.duration)
            )
            .accessibilityLabel("Position")
            Text(MeetingTranscript.timestamp(player.duration))
                .monospacedDigit()
                .foregroundStyle(palette.secondaryText)
                .frame(width: 52, alignment: .leading)
        }
        .font(.system(size: 13))
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .card()
    }

    // MARK: - Transcript

    @ViewBuilder
    private var transcriptSection: some View {
        if let transcript = transcriber.transcript(of: record) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    ThemedSegments(
                        options: [(false, "By speaker"), (true, "Whisper")], selection: $showsWhisper)
                    Spacer()
                    Button("Retranscribe") { transcriber.retranscribe(record) }
                        .buttonStyle(.themedSmall)
                        .help("Make the transcript again, for example after changing the language")
                    Button(copied ? "Copied" : "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(
                            showsWhisper ? whisperText(transcript) : transcript.plainText(names: names),
                            forType: .string)
                        copied = true
                    }
                    .buttonStyle(.themedSmall)
                }
                if showsWhisper {
                    whisperSection(transcript)
                } else {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if transcript.lines.isEmpty {
                            Text("No speech was recognized.")
                                .foregroundStyle(palette.secondaryText)
                                .padding(20)
                        }
                        // By position: two lines can start at the same moment.
                        ForEach(Array(transcript.lines.enumerated()), id: \.offset) { index, line in
                            lineRow(line, index: index, current: isCurrent(line, in: transcript), in: transcript)
                        }
                    }
                    .card()
                }
                if transcript.echoLinesDropped > 0 {
                    Text(
                        "Your microphone also picked up the call from your speakers; \(transcript.echoLinesDropped) such phrases were left out of your lines. Headphones avoid this."
                    )
                    .font(.system(size: 12))
                    .foregroundStyle(palette.secondaryText)
                    .padding(.horizontal, 4)
                }
            }
        } else {
            statusCard
        }
    }

    // MARK: - Whisper's text

    private static func trackTitle(_ track: String) -> String {
        track == "system" ? "Call audio" : track == "microphone" ? "Your microphone" : "Your microphone (\(track))"
    }

    /// Each track in full, as Whisper heard it: the echo on the microphone, no speakers, no cleanup.
    @ViewBuilder
    private func whisperSection(_ transcript: MeetingTranscript) -> some View {
        if let tracks = transcript.whisper {
            ForEach(Array(tracks.enumerated()), id: \.offset) { _, track in
                VStack(alignment: .leading, spacing: 6) {
                    Text(Self.trackTitle(track.track))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(palette.secondaryText)
                        .padding(.horizontal, 4)
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if track.lines.isEmpty {
                            Text("Whisper returned nothing for this track.")
                                .foregroundStyle(palette.secondaryText)
                                .padding(20)
                        }
                        ForEach(Array(track.lines.enumerated()), id: \.offset) { _, line in
                            whisperRow(line)
                        }
                    }
                    .card()
                }
            }
        } else {
            Text("This transcript was made before Whisper’s own text was kept. Retranscribe to see it.")
                .font(.system(size: 13))
                .foregroundStyle(palette.secondaryText)
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card()
        }
    }

    private func whisperRow(_ line: TimedText) -> some View {
        Button {
            player.play(from: line.start)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Text(MeetingTranscript.timestamp(line.start))
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(palette.secondaryText)
                    .frame(width: 44, alignment: .trailing)
                Text(line.text)
                    .font(.system(size: 14))
                    .foregroundStyle(palette.text)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 9)
            .background(
                player.currentTime > 0 && line.start <= player.currentTime && player.currentTime < line.end
                    ? palette.selection : .clear
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(MeetingTranscript.timestamp(line.start)): \(line.text)")
        .accessibilityHint("Plays from here")
    }

    private func whisperText(_ transcript: MeetingTranscript) -> String {
        (transcript.whisper ?? []).map { track in
            Self.trackTitle(track.track) + "\n"
                + track.lines.map { "[\(MeetingTranscript.timestamp($0.start))] \($0.text)" }.joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }

    /// You in the accent colour; the other side in a few distinct colours by order of first words.
    private func color(of speaker: MeetingTranscript.Speaker, in transcript: MeetingTranscript) -> Color {
        guard !speaker.isMe else { return palette.accentText }
        let colors = [
            palette.outside, Color(red: 0.35, green: 0.72, blue: 0.62), Color(red: 0.80, green: 0.45, blue: 0.70),
        ]
        let index = transcript.remoteSpeakers.firstIndex(of: speaker) ?? 0
        return speaker == .others ? palette.secondaryText : colors[index % colors.count]
    }

    private func lineRow(
        _ line: MeetingTranscript.Line, index: Int, current: Bool, in transcript: MeetingTranscript
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(MeetingTranscript.timestamp(line.start))
                .font(.system(size: 12).monospacedDigit())
                .foregroundStyle(palette.secondaryText)
                .frame(width: 44, alignment: .trailing)
            speakerButton(line, index: index, in: transcript)
            Text(line.text)
                .font(.system(size: 14))
                .foregroundStyle(palette.text)
                .lineSpacing(2)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("\(MeetingTranscript.timestamp(line.start)): \(line.text)")
                .accessibilityAddTraits(.isButton)
                .accessibilityHint("Plays from here")
                .accessibilityAction { player.play(from: line.start) }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .background(current ? palette.selection : .clear)
        .contentShape(Rectangle())
        // A tap anywhere but the speaker's name plays from the line.
        .onTapGesture { player.play(from: line.start) }
        .accessibilityElement(children: .contain)
    }

    /// The speaker's name; clicking it names the speaker in every line of the meeting.
    private func speakerButton(_ line: MeetingTranscript.Line, index: Int, in transcript: MeetingTranscript)
        -> some View
    {
        let speaker = line.speaker
        let name = speaker.name(in: names)
        return Button {
            draftName = names[speaker.rawValue] ?? ""
            renaming = index
        } label: {
            Text(name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color(of: speaker, in: transcript))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: 96, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Rename \(name)")
        .accessibilityLabel(name)
        .accessibilityHint("Renames this speaker in the whole meeting")
        .popover(
            isPresented: Binding(get: { renaming == index }, set: { if !$0 { renaming = nil } }),
            arrowEdge: .bottom
        ) {
            SpeakerNameEditor(
                speaker: speaker, name: $draftName, isNamed: names[speaker.rawValue] != nil,
                suggestions: { typed in
                    MeetingTranscript.Speaker.suggestions(
                        from: recorder.earlierSpeakerNames(excluding: record.id), typed: typed,
                        taken: Set(names.filter { $0.key != speaker.rawValue }.values))
                },
                onSave: { newName in
                    recorder.rename(speaker, to: newName, in: record.id)
                    renaming = nil
                }
            )
            .environment(\.palette, palette)
        }
    }

    private func isCurrent(_ line: MeetingTranscript.Line, in transcript: MeetingTranscript) -> Bool {
        guard player.currentTime > 0 else { return false }
        return line.start <= player.currentTime && player.currentTime < max(line.end, line.start + 0.5)
    }

    @ViewBuilder
    private var statusCard: some View {
        HStack(spacing: 12) {
            switch transcriber.status[record.id] {
            case .queued:
                ProgressView().controlSize(.small)
                Text("Waiting to transcribe…")
            case .loadingModel:
                ProgressView().controlSize(.small)
                Text("Loading the speech model…")
            case .transcribing(let fraction):
                ProgressView(value: fraction).frame(width: 160)
                Text("Transcribing on this Mac · \(Int(fraction * 100))%").monospacedDigit()
            case .findingSpeakers:
                ProgressView().controlSize(.small)
                Text("Telling the speakers apart…")
            case .failed(let message):
                Text("Couldn’t transcribe: \(message)").foregroundStyle(palette.danger)
                Spacer()
                Button("Try Again") { transcriber.transcribe(record) }.buttonStyle(.themed)
            case nil:
                Text("Not transcribed yet.")
                Spacer()
                Button("Transcribe") { transcriber.transcribe(record) }.buttonStyle(.themed)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(palette.text.opacity(0.85))
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
    }
}

/// Names a speaker: a field, the names you used in earlier meetings, and a way back to the
/// default name.
private struct SpeakerNameEditor: View {
    @Environment(\.palette) private var palette
    let speaker: MeetingTranscript.Speaker
    @Binding var name: String
    let isNamed: Bool
    let suggestions: (String) -> [String]
    let onSave: (String) -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Rename \(speaker.name)")
                .font(.system(size: 13, weight: .semibold))
            TextField(speaker.name, text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .padding(.horizontal, 10)
                .frame(height: 32)
                .background(RoundedRectangle(cornerRadius: 8).fill(palette.input))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(palette.inputBorder))
                .focused($focused)
                .onSubmit { onSave(name) }
                .accessibilityLabel("Name")
            let names = suggestions(name).filter { $0.caseInsensitiveCompare(name) != .orderedSame }
            if !names.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("From earlier meetings")
                        .font(.system(size: 11))
                        .foregroundStyle(palette.secondaryText)
                    ForEach(names, id: \.self) { suggestion in
                        Button(suggestion) { onSave(suggestion) }
                            .buttonStyle(.themedQuiet)
                    }
                }
            }
            HStack {
                if isNamed {
                    Button("Use “\(speaker.name)”") { onSave("") }
                        .buttonStyle(.themedSmall)
                }
                Spacer()
                Button("Save") { onSave(name) }
                    .buttonStyle(.themedPrimary)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(palette.text)
        .padding(16)
        .frame(width: 260)
        .presentationBackground(palette.card)
        .onAppear { focused = true }
    }
}

#Preview("Rename speaker · Dark Blue") {
    SpeakerNameEditor(
        speaker: .remote(2), name: .constant("An"), isNamed: true,
        suggestions: { _ in ["Anna Smith", "Andrew"] }, onSave: { _ in }
    )
    .background(ThemePalette.darkBlue.card)
    .environment(\.palette, .darkBlue)
}

#Preview("Meeting · Dark Blue") {
    ScrollView {
        if let record = MeetingRecorder.shared.recordings.first {
            MeetingDetailView(record: record) {}.padding(44)
        } else {
            Text("Record a meeting to preview this page.").padding(44)
        }
    }
    .frame(width: 860, height: 760)
    .background(ThemePalette.darkBlue.window)
    .foregroundStyle(ThemePalette.darkBlue.text)
    .environment(\.palette, .darkBlue)
}
