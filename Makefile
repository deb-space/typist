# SPDX-License-Identifier: GPL-3.0-only
# Copyright (C) 2026 typist contributors

SWIFT_DIRS := Package.swift Sources Tests App/Sources

.PHONY: project build test app lint format check clean

project: ## Generate Typist.xcodeproj (needs XcodeGen)
	xcodegen generate

build: ## Build the Swift package
	swift build

test: ## Run unit tests
	swift test

app: project ## Build Typist.app (Debug) into build/
	xcodebuild -project Typist.xcodeproj -scheme Typist -configuration Debug \
		-derivedDataPath build/DerivedData build
	@echo "App: build/DerivedData/Build/Products/Debug/Typist.app"

lint: ## Check formatting
	swift format lint --strict --recursive $(SWIFT_DIRS)

format: ## Fix formatting
	swift format --in-place --recursive $(SWIFT_DIRS)

check: lint test ## Everything CI runs, except the app build
	scripts/check-spdx.sh

clean:
	rm -rf .build build Typist.xcodeproj
