// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import AVFoundation
import CoreAudio
import Foundation

/// Records system audio with a Core Audio process tap (macOS 14.4+).
///
/// The tap is added to a private aggregate device whose clock comes from the default output
/// device, and an IO proc on that aggregate device writes the tapped audio to a file.
public final class ProcessTapCapture: @unchecked Sendable {
    public enum Target: Sendable, Hashable {
        case allSystemAudio
        case app(AudioApp)
    }

    /// How the tap keeps up with an app's processes that start after recording has started,
    /// such as a browser's audio helper when a call begins.
    public enum Tracking: String, Sendable, CaseIterable, Codable {
        /// Tap the processes that exist at the start and nothing else.
        case fixed
        /// Watch the process list and update the tap description when a matching process appears.
        case updateDescription
        /// Also give Core Audio the bundle IDs and enable process restore (macOS 26+).
        /// In the spike on macOS 27 this did not capture new processes.
        case bundleIDs
    }

    public typealias EventHandler = @Sendable (String) -> Void

    private let target: Target
    private let tracking: Tracking
    private let outputURL: URL
    private let onEvent: EventHandler

    private let ioQueue = DispatchQueue(label: "space.deb.typist.tap.io", qos: .userInteractive)
    private let controlQueue = DispatchQueue(label: "space.deb.typist.tap.control")

    private var tapDescription: CATapDescription?
    private var tapID = AudioObjectID(kAudioObjectUnknown)
    private var aggregateID = AudioObjectID(kAudioObjectUnknown)
    private var ioProcID: AudioDeviceIOProcID?
    private var listeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []
    private var tappedProcesses: Set<AudioObjectID> = []
    private var loggedBufferLayout = false

    public private(set) var writer: TrackWriter?

    public init(target: Target, tracking: Tracking, outputURL: URL, onEvent: @escaping EventHandler) {
        self.target = target
        self.tracking = tracking
        self.outputURL = outputURL
        self.onEvent = onEvent
    }

    public func start() throws -> TrackWriter {
        try controlQueue.sync {
            do {
                return try startLocked()
            } catch {
                teardownLocked()
                throw error
            }
        }
    }

    public func stop() {
        controlQueue.sync { teardownLocked() }
    }

    // MARK: - Setup

    private func startLocked() throws -> TrackWriter {
        let description = try makeDescription()
        var tap = AudioObjectID(kAudioObjectUnknown)
        try check(AudioHardwareCreateProcessTap(description, &tap), "AudioHardwareCreateProcessTap")
        tapID = tap
        tapDescription = description

        var streamDescription = try CAProperty.scalar(
            tapID, kAudioTapPropertyFormat, initial: AudioStreamBasicDescription())
        guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
            throw CoreAudioError(operation: "AVAudioFormat from tap format", status: kAudio_ParamError)
        }
        onEvent("tap: format \(format)")

        let outputDevice = try CAProperty.defaultDevice(output: true)
        let outputUID = try CAProperty.string(outputDevice, kAudioDevicePropertyDeviceUID) ?? ""
        let composition: [String: Any] = [
            kAudioAggregateDeviceNameKey: "Typist system audio",
            kAudioAggregateDeviceUIDKey: UUID().uuidString,
            kAudioAggregateDeviceMainSubDeviceKey: outputUID,
            kAudioAggregateDeviceIsPrivateKey: true,
            kAudioAggregateDeviceIsStackedKey: false,
            kAudioAggregateDeviceTapAutoStartKey: false,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
            kAudioAggregateDeviceTapListKey: [
                [kAudioSubTapDriftCompensationKey: true, kAudioSubTapUIDKey: description.uuid.uuidString]
            ],
        ]
        var aggregate = AudioObjectID(kAudioObjectUnknown)
        try check(
            AudioHardwareCreateAggregateDevice(composition as CFDictionary, &aggregate),
            "AudioHardwareCreateAggregateDevice")
        aggregateID = aggregate
        onEvent("tap: aggregate device clocked by \(CAProperty.deviceName(outputDevice))")

        let writer = try TrackWriter(name: "system", url: outputURL, format: format)
        self.writer = writer

        var procID: AudioDeviceIOProcID?
        try check(
            AudioDeviceCreateIOProcIDWithBlock(&procID, aggregateID, ioQueue) {
                [weak self] _, inputData, inputTime, _, _ in
                self?.handleInput(inputData, time: inputTime.pointee, format: format, writer: writer)
            },
            "AudioDeviceCreateIOProcIDWithBlock")
        ioProcID = procID
        try check(AudioDeviceStart(aggregateID, procID), "AudioDeviceStart")
        addListeners()
        return writer
    }

    private func makeDescription() throws -> CATapDescription {
        let description: CATapDescription
        switch target {
        case .allSystemAudio:
            let ownProcess = AudioProcessList.processObject(for: getpid()).map { [$0] } ?? []
            description = CATapDescription(stereoGlobalTapButExcludeProcesses: ownProcess)
            onEvent("tap: all system audio")
        case .app(let app):
            let processes = AudioProcessList.processes(of: app)
            tappedProcesses = Set(processes.map(\.objectID))
            description = CATapDescription(stereoMixdownOfProcesses: processes.map(\.objectID))
            onEvent("tap: \(app.name), processes: \(Self.describe(processes))")
            if tracking == .bundleIDs {
                guard #available(macOS 26.0, *) else {
                    throw CoreAudioError(
                        operation: "bundle ID tracking needs macOS 26", status: kAudio_UnimplementedError)
                }
                let bundleIDs = Set([app.bundleID] + processes.compactMap(\.bundleID)).sorted()
                description.bundleIDs = bundleIDs
                description.isProcessRestoreEnabled = true
                onEvent("tap: following bundle IDs \(bundleIDs.joined(separator: ", "))")
            }
        }
        description.uuid = UUID()
        description.name = "Typist"
        description.isPrivate = true
        description.muteBehavior = .unmuted
        return description
    }

    // MARK: - IO

    private func handleInput(
        _ inputData: UnsafePointer<AudioBufferList>, time: AudioTimeStamp, format: AVAudioFormat, writer: TrackWriter
    ) {
        let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: inputData))
        if !loggedBufferLayout {
            loggedBufferLayout = true
            let layout = buffers.map { "\($0.mNumberChannels)ch/\($0.mDataByteSize)B" }.joined(separator: ", ")
            onEvent("tap: first input has \(buffers.count) buffer(s): \(layout)")
        }

        // The aggregate device also exposes the input streams of its sub-device (for example a
        // headset's microphone), so pick the tap's buffers: they come after the sub-device's.
        let channels = Int(format.channelCount)
        let needed = format.isInterleaved ? 1 : channels
        guard buffers.count >= needed else { return }
        let tapBuffers = Array(buffers.suffix(needed))
        if format.isInterleaved, tapBuffers[0].mNumberChannels != UInt32(channels) { return }

        let list = AudioBufferList.allocate(maximumBuffers: needed)
        defer { free(list.unsafeMutablePointer) }
        for (index, buffer) in tapBuffers.enumerated() { list[index] = buffer }
        guard let pcm = AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: list.unsafePointer) else { return }
        let hostTime = time.mFlags.contains(.hostTimeValid) ? time.mHostTime : nil
        writer.write(pcm, hostTime: hostTime)
    }

    // MARK: - Listeners

    private func addListeners() {
        addListener(CAProperty.system, kAudioHardwarePropertyDefaultOutputDevice) { [weak self] in
            self?.onEvent("event: default output changed to \(AudioDevices.defaultOutputName())")
        }
        addListener(CAProperty.system, kAudioHardwarePropertyServiceRestarted) { [weak self] in
            self?.onEvent("event: coreaudiod restarted")
        }
        addListener(CAProperty.system, kAudioHardwarePropertyProcessObjectList) { [weak self] in
            self?.processListChanged()
        }
        addListener(aggregateID, kAudioDevicePropertyDeviceIsAlive) { [weak self] in
            self?.onEvent("event: aggregate device is no longer alive")
        }
    }

    private func addListener(
        _ object: AudioObjectID, _ selector: AudioObjectPropertySelector, _ handler: @escaping @Sendable () -> Void
    ) {
        var address = CAProperty.address(selector)
        let block: AudioObjectPropertyListenerBlock = { _, _ in handler() }
        if AudioObjectAddPropertyListenerBlock(object, &address, controlQueue, block) == noErr {
            listeners.append((object, address, block))
        }
    }

    /// Runs on `controlQueue`.
    private func processListChanged() {
        guard case .app(let app) = target, let description = tapDescription else { return }
        let matching = AudioProcessList.processes(of: app)
        let new = matching.filter { !tappedProcesses.contains($0.objectID) }
        guard !new.isEmpty else { return }

        switch tracking {
        case .fixed:
            onEvent("event: new \(app.name) process not captured (fixed): \(Self.describe(new))")
        case .bundleIDs:
            onEvent("event: new \(app.name) process, expecting Core Audio to add it: \(Self.describe(new))")
            tappedProcesses.formUnion(new.map(\.objectID))
        case .updateDescription:
            tappedProcesses.formUnion(new.map(\.objectID))
            description.processes = Array(tappedProcesses)
            var address = CAProperty.address(kAudioTapPropertyDescription)
            var reference: CATapDescription = description
            let status = withUnsafeMutablePointer(to: &reference) {
                AudioObjectSetPropertyData(tapID, &address, 0, nil, UInt32(MemoryLayout<CATapDescription>.size), $0)
            }
            let result = status == noErr ? "ok" : fourCharCode(UInt32(bitPattern: status))
            onEvent("event: added \(app.name) process to tap (\(result)): \(Self.describe(new))")
        }
    }

    // MARK: - Teardown

    private func teardownLocked() {
        for (object, address, block) in listeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(object, &address, controlQueue, block)
        }
        listeners = []
        if aggregateID != kAudioObjectUnknown {
            if let ioProcID {
                AudioDeviceStop(aggregateID, ioProcID)
                AudioDeviceDestroyIOProcID(aggregateID, ioProcID)
            }
            AudioHardwareDestroyAggregateDevice(aggregateID)
        }
        if tapID != kAudioObjectUnknown {
            AudioHardwareDestroyProcessTap(tapID)
        }
        ioProcID = nil
        aggregateID = AudioObjectID(kAudioObjectUnknown)
        tapID = AudioObjectID(kAudioObjectUnknown)
        tapDescription = nil
        writer?.close()
    }

    private static func describe(_ processes: [AudioProcess]) -> String {
        guard !processes.isEmpty else { return "none" }
        return processes.map { "\($0.name) [\($0.bundleID ?? "-"), pid \($0.pid)]" }.joined(separator: "; ")
    }
}
