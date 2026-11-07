// swift-tools-version: 6.0
// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 typist contributors

import PackageDescription

let package = Package(
    name: "TypistKit",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "TypistCore", targets: ["TypistCore"]),
        .library(name: "TypistAudio", targets: ["TypistAudio"]),
        .library(name: "TypistProviders", targets: ["TypistProviders"]),
        .library(name: "TypistStorage", targets: ["TypistStorage"]),
    ],
    targets: [
        // Domain types and service protocols. No dependencies on other modules.
        .target(name: "TypistCore"),
        // Microphone and system audio capture.
        .target(name: "TypistAudio", dependencies: ["TypistCore"]),
        // STT, LLM and diarization providers: local engines and external endpoints.
        .target(name: "TypistProviders", dependencies: ["TypistCore"]),
        // SQLite storage, audio files, Keychain.
        .target(name: "TypistStorage", dependencies: ["TypistCore"]),

        .testTarget(name: "TypistCoreTests", dependencies: ["TypistCore"]),
    ],
    swiftLanguageModes: [.v6]
)
