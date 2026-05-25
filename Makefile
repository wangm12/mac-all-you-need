SHELL := /bin/bash

PROJECT := MacAllYouNeed.xcodeproj
SCHEME := MacAllYouNeed
DESTINATION := platform=macOS,arch=arm64
PKG_CONFIG_PATH := /opt/homebrew/opt/libarchive/lib/pkgconfig
# Stable path for `make build` / `make run` (avoids globbing ~/Library/Developer/Xcode/DerivedData).
DERIVED_DATA ?= $(CURDIR)/.build/DerivedData
DEBUG_APP := $(DERIVED_DATA)/Build/Products/Debug/MacAllYouNeed.app

.PHONY: help bootstrap generate test build run open-app release dmg clean clean-cache clean-dist

help:
	@echo "Targets:"
	@echo "  make bootstrap   Fetch downloader binaries and regenerate the Xcode project"
	@echo "  make generate    Regenerate MacAllYouNeed.xcodeproj from project.yml"
	@echo "  make test        Run Shared Swift package tests"
	@echo "  make build       Build the Debug app (DerivedData: .build/DerivedData)"
	@echo "  make run         Build Debug, then open the built app"
	@echo "  make open-app    Open last make-built Debug app without rebuilding"
	@echo "  make release     Build Release and create dist/MacAllYouNeed.dmg"
	@echo "  make dmg         Alias for make release"
	@echo "  make clean       Remove local build caches and dist output"
	@echo "  make clean-cache Remove local build caches only"
	@echo "  make clean-dist  Remove dist output only"

bootstrap: generate
	./scripts/fetch-binaries.sh

generate:
	xcodegen generate

test:
	cd Shared && PKG_CONFIG_PATH="$(PKG_CONFIG_PATH)" swift test

build:
	xcodebuild -project "$(PROJECT)" \
		-scheme "$(SCHEME)" \
		-configuration Debug \
		-destination "$(DESTINATION)" \
		-derivedDataPath "$(DERIVED_DATA)" \
		build

run: build
	@test -d "$(DEBUG_APP)" || { echo "error: expected app at $(DEBUG_APP)" >&2; exit 1; }
	open "$(DEBUG_APP)"

open-app:
	@test -d "$(DEBUG_APP)" || { echo "error: no app at $(DEBUG_APP) — run make build first" >&2; exit 1; }
	open "$(DEBUG_APP)"

release:
	./scripts/package-dmg.sh

dmg: release

clean: clean-cache clean-dist

clean-cache:
	rm -rf .build Shared/.build Shared/.swiftpm build
	rm -rf MacAllYouNeed.xcodeproj/xcuserdata MacAllYouNeed.xcworkspace/xcuserdata
	rm -rf "$$HOME"/Library/Developer/Xcode/DerivedData/MacAllYouNeed-*
	rm -f default.profraw Shared/default.profraw

clean-dist:
	rm -rf dist
