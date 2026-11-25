# Xiaomi Clipboard

Xiaomi Clipboard is a small macOS companion app for a focused study workflow: when a session is enabled, KDE Connect shares copied text with a paired Xiaomi tablet and forwards ordinary macOS screenshots to its gallery. Turning the session off restores the normal desktop screenshot destination and stops the local forwarding service.

The project was created because the author needed a single, deliberate switch for moving notes and screenshots from a Mac to a Xiaomi Pad while studying. It does not depend on Xiaomi Interconnectivity; KDE Connect is the transport layer.

## Compatibility

- **macOS 12 Monterey or later** on Apple Silicon. The app is developed and packaged on Apple Silicon; Intel Macs have not been tested.
- **KDE Connect** installed on the Mac and Android tablet.
- A paired, reachable Android device on the same network. It was tested with a Xiaomi Pad 7 running HyperOS.
- Apple Command Line Tools and Swift 5.9 or newer for building from source.

The screenshot forwarding feature needs the KDE Connect command-line tool found inside the macOS app bundle. Clipboard and rich-text behaviour ultimately depends on KDE Connect and the receiving Android app.

## How it works

1. Pair the Mac and tablet in KDE Connect and keep KDE Connect available in the background on the tablet.
2. Save the tablet ID (one line) in `.local/screenshot-device-id`. This local configuration is intentionally not committed.
3. Build a self-contained local app bundle with `./clipboardctl package`.
4. Open `dist/Xiaomi Clipboard.app` and confirm the dialog to start a session.
5. Copy text normally, or take screenshots with `Command-Shift-3`, `Command-Shift-4`, or `Command-Shift-5`.
6. Open the app again and confirm the dialog to stop the session.

When active, macOS saves screenshots into a private cache. A small local job detects stable image files, asks KDE Connect to share them, then removes accepted local copies after roughly five minutes. This is an acknowledgement of hand-off to KDE Connect, not proof that the tablet received the file. Pending and uncertain files are preserved for a later retry.

Only screenshots saved as files are forwarded. Screenshots copied only to the clipboard, ordinary images copied from other apps, and screen recordings are excluded.

## Setup

Install KDE Connect from the [official download page](https://kdeconnect.kde.org/download.html), pair the devices, then retrieve the tablet ID:

```bash
"$HOME/Applications/KDE Connect.app/Contents/MacOS/kdeconnect-cli" --list-available --id-only
```

Create the local configuration and package the app:

```bash
mkdir -p .local
printf '%s\n' 'YOUR_TABLET_ID' > .local/screenshot-device-id
./clipboardctl package
open "dist/Xiaomi Clipboard.app"
```

`clipboardctl package` embeds the configured device ID and the required scripts in the generated app bundle. The resulting bundle contains no path back to the cloned repository, so it can be moved after packaging. Do not publish a generated bundle containing a real device ID.

## Development

```bash
./clipboardctl build
./clipboardctl test
./clipboardctl package
```

The app is ad-hoc signed for local use. It is not notarized or prepared for third-party distribution.

## Repository layout

| Path | Purpose |
| --- | --- |
| `Sources/` | Swift application and clipboard core. |
| `Tests/` | Swift tests for the clipboard core. |
| `scripts/` | Build, packaging, icon, and screenshot-forwarding helpers. |
| `Assets/` | Source icon assets. |
| `docs/` | Operational notes and archived prototypes. |
| `clipboardctl` | Main developer command for building, testing, and packaging. |

Generated output (`.build/`, `dist/`, the local app bundle), user configuration (`.local/`), Python caches, and Finder metadata are excluded through `.gitignore`.

## Privacy and safety

The app changes the macOS screenshot destination only while a session is enabled. It stores screenshots temporarily under `~/Library/Caches/XiaomiScreenshot/` and stores the previous screenshot settings under `~/Library/Application Support/XiaomiClipboard/`. It opens and configures KDE Connect locally; it does not provide a cloud service.

Before sharing sensitive screenshots, verify that the intended tablet is paired and reachable. The project does not guarantee immediate delivery, and it does not delete files already received on the tablet.
