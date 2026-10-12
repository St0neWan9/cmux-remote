#!/usr/bin/env python3
"""Compile the actual iOS state models with controlled enrollment/tick seams on macOS."""
from pathlib import Path
import json, subprocess
root = Path(__file__).resolve().parents[1]
info = json.loads(subprocess.check_output(['swift', '-print-target-info']))
triple = info['target']['unversionedTriple']
build = root / '.build' / triple / 'debug'
args = ['swiftc', '-parse-as-library', '-swift-version', '6', '-I', str(build / 'Modules')]
for name in ['AppModel', 'ConversationModel', 'ImageDraftModel', 'ImageSelection', 'ImageAttachmentEncoder', 'ImageFileLoader', 'PendingSendStore', 'PairingStore', 'DeviceIdentityStore', 'SecureDeviceStore', 'ErrorPresentation', 'RefreshTicker', 'MarkdownBlock', 'ProjectModel', 'FeedModel']:
    args.append(str(root / 'ios' / 'Sources' / (name + '.swift')))
args.append(str(root / 'scripts/fixtures/PhoneStateChecks.swift'))
for module in ['CmuxRemoteCore', 'CmuxRemoteClient', 'CmuxAgentChat']:
    mapping = json.loads((build / (module + '.build/output-file-map.json')).read_text())
    args += [entry['object'] for entry in mapping.values() if 'object' in entry]
executable = root / '.build/phone-state-checks'
subprocess.run(args + ['-o', str(executable)], cwd=root, check=True)
subprocess.run([str(executable)], cwd=root, check=True)
