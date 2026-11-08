// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import AppKit
import CoreAudio
import Darwin

/// A process that is connected to the Core Audio server.
public struct AudioProcess: Sendable, Hashable, Identifiable {
    public let objectID: AudioObjectID
    public let pid: pid_t
    public let bundleID: String?
    public let name: String
    public let isRunningOutput: Bool
    public let isRunningInput: Bool

    public var id: AudioObjectID { objectID }
}

/// An app whose audio can be captured, together with its helper processes.
public struct AudioApp: Sendable, Hashable, Identifiable {
    public let bundleID: String
    public let pid: pid_t
    public let name: String

    public var id: String { bundleID }

    public init(bundleID: String, pid: pid_t, name: String) {
        self.bundleID = bundleID
        self.pid = pid
        self.name = name
    }

    /// Regular (Dock) apps that are running now, sorted by name.
    @MainActor public static func running() -> [AudioApp] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() }
            .compactMap { app in
                app.bundleIdentifier.map {
                    AudioApp(bundleID: $0, pid: app.processIdentifier, name: app.localizedName ?? $0)
                }
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

public enum AudioProcessList {
    /// All processes currently connected to the Core Audio server.
    public static func current() -> [AudioProcess] {
        let ids = (try? CAProperty.objectIDs(CAProperty.system, kAudioHardwarePropertyProcessObjectList)) ?? []
        return ids.compactMap(process(objectID:))
    }

    /// Processes that belong to `app`: the app itself, processes whose bundle ID starts with
    /// the app's (Chrome's `com.google.Chrome.helper`), and processes the app launched.
    public static func processes(of app: AudioApp, in list: [AudioProcess] = current()) -> [AudioProcess] {
        list.filter { process in
            if let bundleID = process.bundleID,
                bundleID == app.bundleID || bundleID.hasPrefix(app.bundleID + ".")
            {
                return true
            }
            return ancestors(of: process.pid).contains(app.pid)
        }
    }

    /// The Core Audio process object for a PID, if the process has connected to the audio server.
    public static func processObject(for pid: pid_t) -> AudioObjectID? {
        var address = CAProperty.address(kAudioHardwarePropertyTranslatePIDToProcessObject)
        var pid = pid
        var objectID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        let status = AudioObjectGetPropertyData(
            CAProperty.system, &address, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &objectID)
        return status == noErr && objectID != kAudioObjectUnknown ? objectID : nil
    }

    static func process(objectID: AudioObjectID) -> AudioProcess? {
        guard let pid = try? CAProperty.scalar(objectID, kAudioProcessPropertyPID, initial: pid_t(-1)), pid > 0
        else { return nil }
        let bundleID = (try? CAProperty.string(objectID, kAudioProcessPropertyBundleID)).flatMap { $0 }
        let output = (try? CAProperty.scalar(objectID, kAudioProcessPropertyIsRunningOutput, initial: UInt32(0))) ?? 0
        let input = (try? CAProperty.scalar(objectID, kAudioProcessPropertyIsRunningInput, initial: UInt32(0))) ?? 0
        return AudioProcess(
            objectID: objectID,
            pid: pid,
            bundleID: bundleID?.isEmpty == false ? bundleID : nil,
            name: name(of: pid) ?? bundleID ?? "pid \(pid)",
            isRunningOutput: output != 0,
            isRunningInput: input != 0)
    }

    static func name(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 1024)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    /// Parent, grandparent and so on, up to launchd.
    static func ancestors(of pid: pid_t) -> [pid_t] {
        var result: [pid_t] = []
        var current = pid
        for _ in 0..<16 {
            guard let parent = parentPID(of: current), parent > 1 else { break }
            result.append(parent)
            current = parent
        }
        return result
    }

    static func parentPID(of pid: pid_t) -> pid_t? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        return info.kp_eproc.e_ppid
    }
}
