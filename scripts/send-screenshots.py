#!/usr/bin/env python3
"""Send only files saved by macOS into the dedicated screenshot destination."""
import fcntl
import json
import sys
import os
from pathlib import Path
import shutil
import subprocess
import time
import uuid

resource_root = Path(__file__).resolve().parent
home = Path.home()
cache = home / 'Library/Caches/XiaomiScreenshot'
incoming = cache / 'Incoming'
sent = cache / 'Sent'
cli = home / 'Applications/KDE Connect.app/Contents/MacOS/kdeconnect-cli'
device_file = resource_root / 'screenshot-device-id'
# Only accepted queue entries have receipts; pending/uncertain files are kept.
if sent.is_dir():
    for receipt in sent.glob('*.queued.json'):
        try:
            entry = json.loads(receipt.read_text())
            name = entry['name']
            if Path(name).name != name or time.time() - entry['queued_at'] < 300:
                continue
            (sent / name).unlink(missing_ok=True)
            receipt.unlink()
        except (OSError, ValueError, KeyError, TypeError):
            pass
if '--cleanup-only' in sys.argv:
    raise SystemExit(0)
if not incoming.is_dir() or not cli.is_file() or not device_file.is_file():
    raise SystemExit(0)
if subprocess.run(['/bin/launchctl', 'print', f'gui/{os.getuid()}/it.andrea.xiaomi-clipboard'], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL).returncode != 0:
    raise SystemExit(0)
lock = (cache / 'send.lock').open('a')
try:
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError:
    raise SystemExit(0)
pending = [p for p in incoming.iterdir() if p.is_file() and not p.is_symlink()
           and not p.name.startswith('.') and p.suffix.lower() in {'.png', '.jpg', '.jpeg', '.heic', '.tiff'}]
if not pending:
    raise SystemExit(0)
device = device_file.read_text().strip()
try:
    available = subprocess.run([str(cli), '--list-available', '--id-only'],
                               capture_output=True, text=True, timeout=15)
    if available.returncode or device not in available.stdout.splitlines():
        raise SystemExit(0)  # Keep pending files and retry on the next timer/event.
    sent.mkdir(mode=0o700, parents=True, exist_ok=True)
    for path in sorted(pending):
        try:
            before = path.stat()
            time.sleep(0.15)
            after = path.stat()
            if not after.st_size or (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
                continue
            destination = sent / (uuid.uuid4().hex[:8] + '-' + path.name)
            shutil.copy2(path, destination)
            current = path.stat()
            if (current.st_size, current.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
                destination.unlink()
                continue
            result = subprocess.run([str(cli), '--device', device, '--share', str(destination)],
                                    capture_output=True, timeout=20)
            if result.returncode == 0:
                (sent / (destination.name + '.queued.json')).write_text(json.dumps({'name': destination.name, 'queued_at': time.time()}))
                path.unlink()
            else:
                destination.unlink()
        except (OSError, subprocess.TimeoutExpired):
            # Leave pending input intact; a timeout may already have queued a send.
            break
except subprocess.TimeoutExpired:
    pass
# Receipts allow a separate lightweight cleanup job to expire queued copies after 5 minutes.
