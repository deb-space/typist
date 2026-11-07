# ADR 0003: Swift package for libraries, XcodeGen for the app

- **Status:** accepted
- **Date:** 2026-11-07

## Context

The app needs a real `.app` bundle with Info.plist, entitlements and code signing, so that macOS privacy permissions work. Checked-in `.xcodeproj` files are hard to review and often cause merge conflicts.

## Decision

- Library code is a Swift package at the repository root (`Package.swift`) with the modules `TypistCore`, `TypistAudio`, `TypistProviders` and `TypistStorage`. `swift build` and `swift test` work without Xcode.
- The app target lives in `App/` and is described in `project.yml`. XcodeGen generates `Typist.xcodeproj`, which is not checked in.
- Build settings live in `Config/Base.xcconfig`. Personal signing settings go in `Config/Local.xcconfig`, which git ignores.
- Formatting uses `swift format`, which ships with the Swift toolchain, so contributors need no extra linter.
- Tests use Swift Testing.

## Consequences

- Contributors need XcodeGen (`brew install xcodegen`) to build the app, but not to work on the libraries.
- Project settings must be changed in `project.yml`, not in Xcode. Changes made in Xcode are lost when the project is regenerated.
