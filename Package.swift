// swift-tools-version: 6.2
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
        .library(name: "TypistInput", targets: ["TypistInput"]),
    ],
    dependencies: [
        // Exact versions: dependencies are reviewed for license and behavior before each upgrade.
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", exact: "1.1.1"),
        // Local language models for text cleanup (MIT), and their tokenizers (Apache-2.0).
        .package(url: "https://github.com/ml-explore/mlx-swift-lm.git", exact: "3.32.3"),
        .package(url: "https://github.com/huggingface/swift-transformers.git", exact: "1.4.0"),
        // Speaker diarization (Apache-2.0) with pyannote models on the Neural Engine. Only the
        // Diarizer trait: no text-processing binary, no speech synthesis.
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.18.3", traits: ["Diarizer"]),
    ],
    targets: [
        // Domain types and service protocols. No dependencies on other modules.
        .target(name: "TypistCore"),
        // Microphone and system audio capture.
        .target(name: "TypistAudio", dependencies: ["TypistCore"]),
        // STT, LLM and diarization providers: local engines and external endpoints.
        .target(
            name: "TypistProviders",
            dependencies: [
                "TypistCore",
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Tokenizers", package: "swift-transformers"),
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]),
        // SQLite storage, audio files, Keychain.
        .target(name: "TypistStorage", dependencies: ["TypistCore"]),
        // Text insertion into other apps and global hotkeys.
        .target(name: "TypistInput", dependencies: ["TypistCore"]),

        .testTarget(name: "TypistCoreTests", dependencies: ["TypistCore"]),
        .testTarget(name: "TypistAudioTests", dependencies: ["TypistAudio"]),
    ],
    swiftLanguageModes: [.v6]
)
