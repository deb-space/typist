// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import CoreAudio
import Foundation

/// A failed Core Audio call.
public struct CoreAudioError: Error, CustomStringConvertible {
    public let operation: String
    public let status: OSStatus

    public var description: String { "\(operation) failed: \(fourCharCode(UInt32(bitPattern: status)))" }
}

func check(_ status: OSStatus, _ operation: @autoclosure () -> String) throws {
    guard status == noErr else { throw CoreAudioError(operation: operation(), status: status) }
}

/// Formats an OSStatus or selector as `'abcd'` when it is printable, otherwise as a number.
func fourCharCode(_ value: UInt32) -> String {
    let bytes = [24, 16, 8, 0].map { UInt8((value >> UInt32($0)) & 0xFF) }
    if bytes.allSatisfy({ (0x20...0x7E).contains($0) }) {
        return "'\(String(decoding: bytes, as: UTF8.self))'"
    }
    return String(Int32(bitPattern: value))
}

/// Typed access to Core Audio object properties.
enum CAProperty {
    static let system = AudioObjectID(kAudioObjectSystemObject)

    static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    static func scalar<T>(
        _ object: AudioObjectID,
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
        initial: T
    ) throws -> T {
        var address = address(selector, scope: scope)
        var value = initial
        var size = UInt32(MemoryLayout<T>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(object, &address, 0, nil, &size, $0)
        }
        try check(status, "get \(fourCharCode(selector))")
        return value
    }

    static func objectIDs(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> [AudioObjectID] {
        var address = address(selector)
        var size: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size), "size \(fourCharCode(selector))")
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.stride)
        guard !ids.isEmpty else { return [] }
        try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids), "get \(fourCharCode(selector))")
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.stride))
    }

    static func string(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) throws -> String? {
        var address = address(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check(AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value), "get \(fourCharCode(selector))")
        return value?.takeRetainedValue() as String?
    }

    static func defaultDevice(output: Bool) throws -> AudioObjectID {
        let selector = output ? kAudioHardwarePropertyDefaultOutputDevice : kAudioHardwarePropertyDefaultInputDevice
        return try scalar(system, selector, initial: AudioObjectID(kAudioObjectUnknown))
    }

    static func deviceName(_ device: AudioObjectID) -> String {
        (try? string(device, kAudioObjectPropertyName)) ?? "device \(device)"
    }
}

/// The current default audio devices, for logging.
public enum AudioDevices {
    public static func defaultOutputName() -> String {
        (try? CAProperty.defaultDevice(output: true)).map(CAProperty.deviceName) ?? "unknown"
    }

    public static func defaultInputName() -> String {
        (try? CAProperty.defaultDevice(output: false)).map(CAProperty.deviceName) ?? "unknown"
    }
}
