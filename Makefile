SHELL := /bin/bash

PROJECT := MacAllYouNeed.xcodeproj
SCHEME := MacAllYouNeed
DESTINATION := platform=macOS,arch=arm64
PKG_CONFIG_PATH := /opt/homebrew/opt/libarchive/lib/pkgconfig
# Stable path for `make build` / `make run` (avoids globbing ~/Library/Developer/Xcode/DerivedData).
DERIVED_DATA ?= $(CURDIR)/.build/DerivedData
DEBUG_APP := $(DERIVED_DATA)/Build/Products/Debug/MacAllYouNeed.app

VOICE_EXPORT_DIR ?= $(CURDIR)/.build/voice-export
VOICE_EXPORT_TAR ?= $(VOICE_EXPORT_DIR)/mayn-voice-training.tar.gz
VOICE_FINETUNE_DIR ?= $(CURDIR)/.build/voice-finetune-pilot
VOICE_TRAIN_MAX_STEPS ?= 12
VOICE_PYTHON ?= python3.12

.PHONY: help bootstrap generate test build run open-app release dmg clean clean-cache clean-dist import-typeless
.PHONY: voice-training-stats voice-training-export voice-training-extract
.PHONY: voice-training-venv voice-training-prepare voice-training-train-smoke
.PHONY: voice-training-pilot voice-training-clean
.PHONY: voice-clone-curate voice-clone-chatterbox-smoke

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
	@echo "  make import-typeless  Import Typeless voice history (quit the app first)"
	@echo ""
	@echo "Voice offline training (see docs/voice-training/README.md):"
	@echo "  make voice-training-stats        Corpus counts from App Group DB"
	@echo "  make voice-training-export       Export training archive (quit app first)"
	@echo "  make voice-training-extract      Untar export to .build/voice-export/extracted"
	@echo "  make voice-training-venv         Python venv for mlx-tune pilot"
	@echo "  make voice-training-prepare      Build HF dataset from export"
	@echo "  make voice-training-train-smoke  Whisper-tiny LoRA smoke ($(VOICE_TRAIN_MAX_STEPS) steps)"
	@echo "  make voice-training-pilot        Full smoke: stats → export → train"
	@echo "  make voice-training-clean        Remove voice-training build dirs"
	@echo ""
	@echo "Voice cloning reference (see docs/voice-cloning/README.md):"
	@echo "  make voice-clone-curate          Build instant reference pack from export"
	@echo "  make voice-clone-chatterbox-smoke  Local Chatterbox TTS smoke (optional)"

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
		-allowProvisioningUpdates \
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

import-typeless:
	./scripts/import-typeless-history.sh

voice-training-stats:
	./scripts/voice-training/stats.sh

voice-training-export:
	VOICE_EXPORT_TAR="$(VOICE_EXPORT_TAR)" ./scripts/voice-training/export.sh

voice-training-extract:
	./scripts/voice-training/extract.sh

voice-training-venv:
	VOICE_PYTHON="$(VOICE_PYTHON)" ./scripts/voice-training/venv.sh

voice-training-prepare:
	./scripts/voice-training/prepare.sh

voice-training-train-smoke:
	VOICE_TRAIN_MAX_STEPS="$(VOICE_TRAIN_MAX_STEPS)" ./scripts/voice-training/train-whisper-smoke.sh

voice-training-pilot:
	./scripts/voice-training/pilot.sh

voice-training-clean:
	./scripts/voice-training/clean.sh

voice-clone-curate:
	./scripts/voice-cloning/curate-reference-pack.sh

voice-clone-chatterbox-smoke:
	PIP_INDEX_URL=https://pypi.org/simple PIP_EXTRA_INDEX_URL= ./scripts/voice-cloning/run-chatterbox-smoke.sh

clean: clean-cache clean-dist

clean-cache:
	rm -rf .build Shared/.build Shared/.swiftpm build
	rm -rf MacAllYouNeed.xcodeproj/xcuserdata MacAllYouNeed.xcworkspace/xcuserdata
	rm -rf "$$HOME"/Library/Developer/Xcode/DerivedData/MacAllYouNeed-*
	rm -f default.profraw Shared/default.profraw

clean-dist:
	rm -rf dist
