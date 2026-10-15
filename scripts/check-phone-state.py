#!/usr/bin/env python3
"""Compile the actual iOS state models with controlled enrollment/tick seams on macOS."""
from pathlib import Path
import json, subprocess
root = Path(__file__).resolve().parents[1]
build = Path(subprocess.check_output(['swift', 'build', '--show-bin-path'], cwd=root, text=True).strip())
modules = build / 'Modules' if (build / 'Modules').is_dir() else build
args = ['swiftc', '-parse-as-library', '-swift-version', '6', '-I', str(modules)]
for name in ['SpeechDraftModel', 'SpeechInputServing', 'SpeechInputResult', 'UnavailableSpeechInput', 'HistoricalImageModel', 'ReadRequestOwner', 'AppModel', 'HostLink', 'HostedSession', 'ConversationModel', 'ImageDraftModel', 'ImageSelection', 'ImageAttachmentEncoder', 'ImageFileLoader', 'PendingSendStore', 'ToolDetailModel', 'ToolDetailReference', 'PairingStore', 'DeviceIdentityStore', 'SecureDeviceStore', 'ErrorPresentation', 'DiagnosticLog', 'EdgeBackSwipe', 'ConversationCache', 'RunningSessionSync', 'BackgroundSync', 'RefreshTicker', 'ReconnectSchedule', 'MarkdownBlock', 'ProjectModel', 'FeedModel']:
    args.append(str(root / 'ios' / 'Sources' / (name + '.swift')))
args.append(str(root / 'scripts/fixtures/PhoneStateChecks.swift'))
args.append(str(root / 'scripts/fixtures/ConversationReadChecks.swift'))
args.append(str(root / 'scripts/fixtures/ConversationCacheChecks.swift'))
args.append(str(root / 'scripts/fixtures/RunningSyncChecks.swift'))
args.append(str(root / 'scripts/fixtures/HistoricalImageChecks.swift'))
args.append(str(root / 'scripts/fixtures/SpeechStateChecks.swift'))
args.append(str(root / 'scripts/fixtures/EdgeBackChecks.swift'))
args.append(str(root / 'scripts/fixtures/MultiHostChecks.swift'))
args.append(str(root / 'scripts/fixtures/ReconnectChecks.swift'))
for module in ['CmuxRemoteCore', 'CmuxRemoteClient', 'CmuxAgentChat']:
    mapping_file = build / (module + '.build/output-file-map.json')
    if mapping_file.is_file():
        mapping = json.loads(mapping_file.read_text())
        args += [entry['object'] for entry in mapping.values() if 'object' in entry]
    else:
        # SwiftPM's Swift Build backend emits one combined object per module.
        args.append(str(build / (module + '.o')))
executable = root / '.build/phone-state-checks'
subprocess.run(args + ['-o', str(executable)], cwd=root, check=True)
subprocess.run([str(executable)], cwd=root, check=True)
