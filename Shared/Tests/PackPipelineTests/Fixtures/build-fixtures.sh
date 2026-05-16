#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$DIR"

rm -rf happy-pack zipslip-pack symlink-pack unexpected-file-pack zipbomb-pack
mkdir -p happy-pack symlink-pack unexpected-file-pack zipbomb-pack

# 1. Happy pack: a manifest + two tiny "binaries"
cat > happy-pack/yt-dlp <<'EOF'
#!/bin/sh
echo "fake yt-dlp"
EOF
chmod +x happy-pack/yt-dlp

cat > happy-pack/ffmpeg <<'EOF'
#!/bin/sh
echo "fake ffmpeg"
EOF
chmod +x happy-pack/ffmpeg

cat > happy-pack/manifest.json <<'EOF'
{ "version": "1.0.0", "files": ["yt-dlp", "ffmpeg"] }
EOF
(cd happy-pack && zip -X -r ../happy-pack.zip yt-dlp ffmpeg manifest.json) > /dev/null

# 2. Zip-slip pack: archive with a stored entry path of "../escape.txt"
# The zip CLI refuses paths with ".." — use Python's zipfile instead.
python3 - <<'PYEOF'
import zipfile, os, tempfile
os.chdir(os.path.dirname(os.path.abspath(__file__)) if '__file__' in dir() else '.')
tmpfile = 'escape_src.txt'
with open(tmpfile, 'w') as f:
    f.write('should not write\n')
with zipfile.ZipFile('zipslip-pack.zip', 'w') as zf:
    zf.write(tmpfile, arcname='../escape.txt')
os.remove(tmpfile)
PYEOF

# 3. Symlink pack
ln -s /etc/passwd symlink-pack/yt-dlp
(cd symlink-pack && zip --symlinks ../symlink-pack.zip yt-dlp) > /dev/null
rm -rf symlink-pack

# 4. Unexpected file pack: contains a 'malware' entry not in allowlist
echo "harmless" > unexpected-file-pack/yt-dlp
echo "MALWARE" > unexpected-file-pack/malware.bin
(cd unexpected-file-pack && zip -X ../unexpected-file-pack.zip yt-dlp malware.bin) > /dev/null
rm -rf unexpected-file-pack

# 5. Zip bomb: one large file
mkdir -p zipbomb-pack
dd if=/dev/zero of=zipbomb-pack/yt-dlp bs=1m count=10 2>/dev/null
(cd zipbomb-pack && zip -X ../zipbomb-pack.zip yt-dlp) > /dev/null
rm -rf zipbomb-pack

echo "fixtures regenerated."
