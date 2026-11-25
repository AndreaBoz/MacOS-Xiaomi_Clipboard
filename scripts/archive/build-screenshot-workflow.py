#!/usr/bin/env python3
"""Build a no-input Automator Quick Action using only macOS's shell action."""
from pathlib import Path
import plistlib
import shlex
import uuid

root = Path(__file__).resolve().parent.parent
contents = root / 'dist/Screenshot al tablet.workflow/Contents'
contents.mkdir(parents=True, exist_ok=True)
parameters = {
    'COMMAND_STRING': '/bin/bash ' + shlex.quote(str(root / 'scripts/screenshot-to-tablet.sh')),
    'CheckedForUserDefaultShell': True, 'inputMethod': 0, 'shell': '/bin/bash', 'source': ''
}
action = {
    'AMAccepts': {'Container': 'List', 'Optional': True, 'Types': ['com.apple.cocoa.string']},
    'AMProvides': {'Container': 'List', 'Types': ['com.apple.cocoa.string']},
    'AMActionVersion': '2.0.3', 'AMApplication': ['Automator'],
    'AMParameterProperties': {k: {} for k in parameters},
    'ActionBundlePath': '/System/Library/Automator/Run Shell Script.action',
    'ActionName': 'Run Shell Script', 'ActionParameters': parameters,
    'BundleIdentifier': 'com.apple.RunShellScript', 'CFBundleVersion': '2.0.3',
    'Class Name': 'RunShellScriptAction', 'UUID': str(uuid.uuid4()),
    'InputUUID': str(uuid.uuid4()), 'OutputUUID': str(uuid.uuid4())
}
workflow = {
    'AMDocumentVersion': '2', 'actions': [{'action': action}], 'connectors': {},
    'workflowMetaData': {
        'workflowTypeIdentifier': 'com.apple.Automator.servicesMenu',
        'serviceInputTypeIdentifier': 'com.apple.Automator.nothing',
        'serviceOutputTypeIdentifier': 'com.apple.Automator.nothing',
        'inputTypeIdentifier': 'com.apple.Automator.nothing',
        'outputTypeIdentifier': 'com.apple.Automator.nothing',
        'serviceProcessesInput': False, 'processesInput': False,
        'applicationBundleIDsByPath': {}, 'applicationPaths': [],
        'useAutomaticInputType': False, 'presentationMode': 11,
        'systemImageName': 'NSActionTemplate'
    }
}
info = {'NSServices': [{
    'NSMenuItem': {'default': 'Screenshot al tablet'},
    'NSMessage': 'runWorkflowAsService',
    'NSIconName': 'NSActionTemplate',
    'NSKeyEquivalent': {'default': '^~@4'}
}]}
for name, data in [('document.wflow', workflow), ('Info.plist', info)]:
    (contents / name).write_bytes(plistlib.dumps(data))
print(contents.parent)
