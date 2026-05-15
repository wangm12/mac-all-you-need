SHELL := /bin/bash

PROJECT := MacAllYouNeed.xcodeproj
SCHEME := MacAllYouNeed
DESTINATION := platform=macOS,arch=arm64
PKG_CONFIG_PATH := /opt/homebrew/opt/libarchive/lib/pkgconfig

.PHONY: help bootstrap generate test build release dmg clean clean-cache clean-dist

help:
	@echo "Targets:"
	@echo "  make bootstrap   Fetch downloader binaries and regenerate the Xcode project"
	@echo "  make generate    Regenerate MacAllYouNeed.xcodeproj from project.yml"
	@echo "  make test        Run Shared Swift package tests"
	@echo "  make build       Build the Debug app"
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
		build

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
