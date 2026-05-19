#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/Vendored/binaries"
mkdir -p "$DEST"

YTDLP_VERSION="2026.03.17"

echo "==> Downloading yt-dlp ${YTDLP_VERSION}…"
curl -L -o "$DEST/yt-dlp" "https://github.com/yt-dlp/yt-dlp/releases/download/${YTDLP_VERSION}/yt-dlp_macos"
chmod +x "$DEST/yt-dlp"

echo "==> Downloading ffmpeg (arm64 + x86_64)…"
curl -L -o "$DEST/ffmpeg-arm64.zip" "https://ffmpeg.martin-riedl.de/redirect/latest/macos/arm64/release/ffmpeg.zip"
curl -L -o "$DEST/ffmpeg-x86_64.zip" "https://ffmpeg.martin-riedl.de/redirect/latest/macos/amd64/release/ffmpeg.zip"
unzip -o "$DEST/ffmpeg-arm64.zip" -d "$DEST/ffmpeg-arm64"
unzip -o "$DEST/ffmpeg-x86_64.zip" -d "$DEST/ffmpeg-x86_64"
lipo -create "$DEST/ffmpeg-arm64/ffmpeg" "$DEST/ffmpeg-x86_64/ffmpeg" -output "$DEST/ffmpeg"
rm -rf "$DEST/ffmpeg-arm64" "$DEST/ffmpeg-x86_64" "$DEST/ffmpeg-arm64.zip" "$DEST/ffmpeg-x86_64.zip"
chmod +x "$DEST/ffmpeg"

echo "==> Verifying SHA-256…"
expected_ytdlp="$(python3 -c "import json,sys; d=json.load(open('$DEST/manifest.json')); print(d['yt-dlp']['sha256'])")"
expected_ffmpeg="$(python3 -c "import json,sys; d=json.load(open('$DEST/manifest.json')); print(d['ffmpeg']['sha256'])")"
actual_ytdlp="$(shasum -a 256 "$DEST/yt-dlp" | awk '{print $1}')"
actual_ffmpeg="$(shasum -a 256 "$DEST/ffmpeg" | awk '{print $1}')"
test "$actual_ytdlp" = "$expected_ytdlp" || { echo "yt-dlp SHA mismatch"; exit 1; }
test "$actual_ffmpeg" = "$expected_ffmpeg" || { echo "ffmpeg SHA mismatch"; exit 1; }

echo "==> Verifying architectures…"
lipo -archs "$DEST/yt-dlp" | grep -q arm64
lipo -archs "$DEST/yt-dlp" | grep -q x86_64
lipo -archs "$DEST/ffmpeg" | grep -q arm64
lipo -archs "$DEST/ffmpeg" | grep -q x86_64

echo "==> All checks passed."
