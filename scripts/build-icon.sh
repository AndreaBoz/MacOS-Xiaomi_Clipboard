#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ICONSET="$PWD/.build/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    /usr/bin/sips -z "$size" "$size" Assets/AppIcon.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    /usr/bin/sips -z "$double" "$double" Assets/AppIcon.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
if ! /usr/bin/iconutil -c icns "$ICONSET" -o Assets/AppIcon.icns; then
    # Some Command Line Tools installations reject otherwise valid iconsets.
    # Keep the checked-in, prebuilt icon so packaging remains reproducible.
    if [[ -s Assets/AppIcon.icns ]]; then
        echo "Warning: iconutil rejected the generated iconset; using Assets/AppIcon.icns." >&2
    else
        exit 1
    fi
fi
