#!/bin/bash
# Dedicated screenshot action: does not read or monitor the clipboard.
set -euo pipefail
umask 077
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CLI="$HOME/Applications/KDE Connect.app/Contents/MacOS/kdeconnect-cli"
DEVICE_FILE="$ROOT/.local/screenshot-device-id"
CACHE="$HOME/Library/Caches/XiaomiScreenshot"

show_error() {
    /usr/bin/osascript -e 'display alert "Screenshot al tablet" message "Invio non riuscito. Verifica che KDE Connect sia aperto sui due dispositivi e che il tablet sia collegato alla stessa rete Wi-Fi." as warning' >/dev/null
}

if [[ ! -x "$CLI" || ! -s "$DEVICE_FILE" ]]; then
    show_error
    exit 1
fi
DEVICE_ID="$(cat "$DEVICE_FILE")"
if ! AVAILABLE="$("$CLI" --list-available --id-only 2>/dev/null)" ||
   ! /usr/bin/grep -Fxq "$DEVICE_ID" <<< "$AVAILABLE"; then
    show_error
    exit 1
fi
if [[ "${1:-}" == --check ]]; then
    echo 'Tablet associato e raggiungibile.'
    exit 0
fi

mkdir -p "$CACHE"
# Only this action's temporary screenshots, never the user's screenshot folders.
/usr/bin/find "$CACHE" -type f -name 'Screenshot-Mac-*.png' -mtime +1 -delete
SHOT="$CACHE/Screenshot-Mac-$(date +%Y%m%d-%H%M%S)-$(/usr/bin/uuidgen).png"
# Allow time to release the hotkey modifiers (Control changes screencapture mode).
/bin/sleep 0.4
if ! /usr/sbin/screencapture -i -s -x -t png "$SHOT"; then
    rm -f "$SHOT"
    exit 0
fi
# Escape cancels without sending anything.
[[ -s "$SHOT" ]] || exit 0
if ! "$CLI" --device "$DEVICE_ID" --share "$SHOT" >/dev/null 2>&1; then
    show_error
    exit 1
fi
# KDE Connect queues the upload asynchronously: keep the source available.
# Old temporary files are removed on a later invocation, after at least 24h.
