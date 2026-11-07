# ADR 0002: Minimum macOS version is 15

- **Status:** accepted
- **Date:** 2026-11-07

## Context

Meeting recording needs system audio capture. Core Audio process taps, the main candidate, are available since macOS 14.4. Supporting older versions costs testing effort and keeps us on older APIs.

Homebrew Analytics for the 30 days to 2026-11-07, counting macOS installs only: macOS 26 ≈ 46%, macOS 27 ≈ 31%, macOS 15 ≈ 18%, macOS 14 ≈ 2%, older ≈ 3%. Apple ended support for macOS 14 in September 2026. Most Macs still on 14 cannot upgrade to 15, so they are old Intel models that would run local speech models poorly anyway.

## Decision

- The deployment target is **macOS 15.0**.
- Features that need macOS 26 or later, such as Apple's SpeechAnalyzer, are optional and guarded with `if #available`.
- Spikes and manual QA cover macOS 15, 26 and 27.

## Consequences

- Typist reaches about 95% of Macs, measured by Homebrew users.
- Process taps and ScreenCaptureKit audio capture are both available on every supported version.
- We will review the minimum version once a year, after each major macOS release.
