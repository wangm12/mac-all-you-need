#!/usr/bin/env bash
set -euo pipefail

WORKSPACE="MacAllYouNeed.xcworkspace"
SCHEME="MacAllYouNeed"

echo "==> SwiftLint"
swiftlint --strict

echo "==> SwiftFormat lint"
swiftformat --lint .

echo "==> Swift package tests"
(cd Shared && swift test)

echo "==> Xcode build"
xcodebuild \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "platform=macOS" \
  CODE_SIGNING_ALLOWED=NO \
  build

echo "==> Xcode tests"
xcodebuild \
  -workspace "$WORKSPACE" \
  -scheme "$SCHEME" \
  -configuration Debug \
  -destination "platform=macOS" \
  CODE_SIGNING_ALLOWED=NO \
  test
