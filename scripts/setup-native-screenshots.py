#!/usr/bin/env python3
"""Install/remove the screenshot forwarding job and restore the previous location."""
from pathlib import Path
import json
import os
import plistlib
import subprocess
import sys
import signal
import configparser

resource_root = Path(__file__).resolve().parent
home = Path.home()
support = home / 'Library/Application Support/XiaomiClipboard'
label = 'it.andrea.screenshot-to-tablet'
domain = f'gui/{os.getuid()}'
service = domain + '/' + label
plist = home / 'Library/LaunchAgents' / (label + '.plist')
incoming = home / 'Library/Caches/XiaomiScreenshot/Incoming'
backup = support / 'screenshot-settings.json'

def call(args, check=True):
    return subprocess.run(args, check=check, capture_output=True, text=True)

def close_kde():
    prefix = str(home / 'Applications/KDE Connect.app/Contents/MacOS') + '/'
    rows = call(['/bin/ps', '-axo', 'pid=,command=']).stdout.splitlines()
    for row in rows:
        pid, _, command = row.strip().partition(' ')
        command = command.lstrip()
        if command.startswith(prefix) and command[len(prefix):].split(' --', 1)[0] in ['KDE Connect', 'kdeconnectd', 'kdeconnect-app', 'dbus-daemon']:
            try:
                os.kill(int(pid), signal.SIGTERM)
            except ProcessLookupError:
                pass

mode = sys.argv[1] if len(sys.argv) == 2 else 'status'
if mode == 'on':
    device_file = resource_root / 'screenshot-device-id'
    if not device_file.is_file() or not device_file.read_text().strip():
        raise SystemExit('Missing screenshot-device-id in the application resources.')
    device = device_file.read_text().strip()
    config_path = home / 'Library/Preferences/kdeconnect' / device / 'config'
    config_path.parent.mkdir(parents=True, exist_ok=True)
    config = configparser.RawConfigParser()
    config.optionxform = str
    if config_path.exists(): config.read(config_path)
    if not config.has_section('Plugins'): config.add_section('Plugins')
    if config.get('Plugins', 'kdeconnect_clipboardEnabled', fallback='true') != 'true':
        close_kde()
        config.set('Plugins', 'kdeconnect_clipboardEnabled', 'true')
        with config_path.open('w') as stream: config.write(stream, space_around_delimiters=False)
    call(['/usr/bin/open', str(home / 'Applications/KDE Connect.app')])
    cleanup_label = 'it.andrea.screenshot-cleanup'
    cleanup_plist = home / 'Library/LaunchAgents' / (cleanup_label + '.plist')
    cleanup_job = {'Label': cleanup_label, 'ProgramArguments': ['/usr/bin/python3', str(resource_root / 'send-screenshots.py'), '--cleanup-only'], 'RunAtLoad': True, 'StartInterval': 60, 'ProcessType': 'Background'}
    cleanup_plist.parent.mkdir(parents=True, exist_ok=True)
    cleanup_plist.write_bytes(plistlib.dumps(cleanup_job))
    cleanup_plist.chmod(0o600)
    if call(['/bin/launchctl', 'print', domain + '/' + cleanup_label], False).returncode != 0:
        call(['/bin/launchctl', 'bootstrap', domain, str(cleanup_plist)])
    incoming.mkdir(mode=0o700, parents=True, exist_ok=True)
    backup.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    if not backup.exists():
        old = call(['/usr/bin/defaults', 'read', 'com.apple.screencapture', 'location'], False)
        backup.write_text(json.dumps({'location': old.stdout.strip() if old.returncode == 0 else None}))
    saved = json.loads(backup.read_text())
    if 'target' not in saved:
        old = call(['/usr/bin/defaults', 'read', 'com.apple.screencapture', 'target'], False)
        saved['target'] = old.stdout.strip() if old.returncode == 0 else None
        backup.write_text(json.dumps(saved))
    if 'thumbnail' not in saved:
        old = call(['/usr/bin/defaults', 'read', 'com.apple.screencapture', 'show-thumbnail'], False)
        saved['thumbnail'] = old.stdout.strip() if old.returncode == 0 else None
        backup.write_text(json.dumps(saved))
    job = {'Label': label, 'ProgramArguments': ['/usr/bin/python3', str(resource_root / 'send-screenshots.py')],
           'RunAtLoad': True, 'WatchPaths': [str(incoming)], 'StartInterval': 5, 'ThrottleInterval': 1,
           'ProcessType': 'Background', 'LimitLoadToSessionType': 'Aqua', 'Umask': 0o077}
    plist.parent.mkdir(parents=True, exist_ok=True)
    call(['/bin/launchctl', 'bootout', service], False)
    plist.unlink(missing_ok=True)
    session_plist = support / 'screenshot-session.plist'
    session_plist.write_bytes(plistlib.dumps(job))
    session_plist.chmod(0o600)
    call(['/bin/launchctl', 'enable', service])
    call(['/bin/launchctl', 'bootstrap', domain, str(session_plist)])
    session_plist.unlink()
    call(['/usr/bin/defaults', 'write', 'com.apple.screencapture', 'location', '-string', str(incoming)])
    call(['/usr/bin/defaults', 'delete', 'com.apple.screencapture', 'target'], False)
    call(['/usr/bin/defaults', 'write', 'com.apple.screencapture', 'show-thumbnail', '-bool', 'false'])
    call(['/usr/bin/killall', 'screencaptureui'], False)
    call(['/usr/bin/killall', 'SystemUIServer'], False)
    print('Invio automatico attivato per gli screenshot normali del Mac.')
elif mode == 'off':
    close_kde()
    call(['/bin/launchctl', 'bootout', service], False)
    plist.unlink(missing_ok=True)
    if backup.exists():
        thumbnail = json.loads(backup.read_text()).get('thumbnail')
        if thumbnail is None:
            call(['/usr/bin/defaults', 'delete', 'com.apple.screencapture', 'show-thumbnail'], False)
        else:
            call(['/usr/bin/defaults', 'write', 'com.apple.screencapture', 'show-thumbnail', '-bool', 'true' if thumbnail in ['1', 'true', 'YES'] else 'false'])
        backup.unlink()
        call(['/usr/bin/killall', 'screencaptureui'], False)
        call(['/usr/bin/killall', 'SystemUIServer'], False)
    call(['/usr/bin/defaults', 'write', 'com.apple.screencapture', 'location', '-string', str(home / 'Desktop')])
    call(['/usr/bin/defaults', 'delete', 'com.apple.screencapture', 'target'], False)
    call(['/usr/bin/killall', 'screencaptureui'], False)
    call(['/usr/bin/killall', 'SystemUIServer'], False)
    print('Invio disattivato; i nuovi screenshot vengono salvati sulla Scrivania.')
elif mode == 'status':
    print('Attivo' if call(['/bin/launchctl', 'print', service], False).returncode == 0 else 'Disattivato')
else:
    raise SystemExit('Uso: setup-native-screenshots.py on|off|status')
