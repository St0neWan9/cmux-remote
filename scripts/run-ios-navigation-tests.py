#!/usr/bin/env python3
"""Run native iOS tests on one explicit existing Simulator, preserving its pairing."""
from pathlib import Path
import argparse
import json
import plistlib
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('device')
parser.add_argument('arch', choices=['arm64', 'x86_64'])
parser.add_argument('--fixture', type=Path)
parser.add_argument('--env', action='append', default=[], metavar='KEY=VALUE',
                    help='Extra test-process environment, for example the id of a real session to open.')
parser.add_argument('--only-testing', action='append', default=[], metavar='TARGET/TEST',
                    help='Run only these tests, so a real-backend run does not drag in every fixture test.')
args = parser.parse_args()
extra = {}
for item in args.env:
    key, separator, value = item.partition('=')
    if not separator or not key:
        parser.error(f'--env expects KEY=VALUE, got {item!r}')
    extra[key] = value
devices = json.loads(subprocess.check_output(['xcrun', 'simctl', 'list', 'devices', '-j']))['devices']
device = next((d for items in devices.values() for d in items if d['udid'] == args.device), None)
if not device or not device['name'].startswith('cmux-remote-') or device['state'] != 'Booted':
    parser.error('Use an already booted, task-owned cmux-remote Simulator')
root = Path(__file__).resolve().parents[1]
derived = root / '.build/ios-navigation-tests'
command = ['xcodebuild', '-project', 'ios/CmuxRemote.xcodeproj', '-scheme', 'CmuxRemote',
           '-configuration', 'Debug', '-destination', f'platform=iOS Simulator,id={args.device},arch={args.arch}',
           '-derivedDataPath', str(derived), '-parallel-testing-enabled', 'NO', 'ONLY_ACTIVE_ARCH=YES',
           f'ARCHS={args.arch}', 'CODE_SIGNING_ALLOWED=NO']
subprocess.run(command + ['build-for-testing'], cwd=root, check=True)
run_file = max((derived / 'Build/Products').glob('*.xctestrun'), key=lambda p: p.stat().st_mtime)
configuration = plistlib.loads(run_file.read_bytes())
if args.fixture:
    fixture = args.fixture.resolve(strict=True)
    configuration['CmuxRemoteUITests'].setdefault('EnvironmentVariables', {})['CMUX_REMOTE_TEST_PAIRING_PATH'] = str(fixture)
else:
    # UI tests need a deterministic backend; never substitute the user's live agent.
    configuration['CmuxRemoteUITests']['SkipTestIdentifiers'] = ['MobileGestureUITests']
if extra:
    configuration['CmuxRemoteUITests'].setdefault('EnvironmentVariables', {}).update(extra)
run_file.write_bytes(plistlib.dumps(configuration))
container_result = subprocess.run(['xcrun', 'simctl', 'get_app_container', args.device,
                                   'cmux-remote.mobile', 'data'], capture_output=True, text=True)
container = Path(container_result.stdout.strip()) if container_result.returncode == 0 else None
names = ('ProtectedConnection', 'SimulatorPairing')
with tempfile.TemporaryDirectory(prefix='ios-test-pairing-', dir=root / '.build') as temporary:
    backup = Path(temporary)
    if container:
        for name in names:
            source = container / 'Library/Application Support' / name
            if source.exists():
                shutil.copytree(source, backup / name)
    try:
        subprocess.run(['xcodebuild', '-xctestrun', str(run_file), '-destination',
                        f'platform=iOS Simulator,id={args.device},arch={args.arch}',
                        '-parallel-testing-enabled', 'NO', '-derivedDataPath', str(derived),
                        *[f'-only-testing:{test}' for test in args.only_testing],
                        'test-without-building'], cwd=root, check=True)
    finally:
        if args.fixture:
            current = subprocess.run(['xcrun', 'simctl', 'get_app_container', args.device,
                                      'cmux-remote.mobile', 'data'], capture_output=True, text=True)
            if current.returncode == 0:
                support = Path(current.stdout.strip()) / 'Library/Application Support'
                for name in names:
                    target = support / name
                    if target.exists():
                        shutil.rmtree(target)
                    if (backup / name).exists():
                        shutil.copytree(backup / name, target)
