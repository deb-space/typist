// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import Darwin

/// Conversions for the host clock (`mach_absolute_time`), which Core Audio,
/// AVAudioEngine and ScreenCaptureKit all use for buffer timestamps.
public enum HostTime {
    private static let nanosecondsPerTick: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom)
    }()

    public static func now() -> UInt64 { mach_absolute_time() }

    public static func seconds(_ ticks: UInt64) -> Double {
        Double(ticks) * nanosecondsPerTick / 1e9
    }

    /// Signed difference `a - b` in seconds.
    public static func seconds(from b: UInt64, to a: UInt64) -> Double {
        a >= b ? seconds(a - b) : -seconds(b - a)
    }

    public static func ticks(seconds: Double) -> UInt64 {
        UInt64(max(0, seconds) * 1e9 / nanosecondsPerTick)
    }
}
