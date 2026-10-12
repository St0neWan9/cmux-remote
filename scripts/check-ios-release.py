#!/usr/bin/env python3
"""Portable release guards; no Apple account or signing credentials needed."""
from datetime import datetime, timedelta
import importlib.util
import io
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

ROOT = Path(__file__).resolve().parent.parent

def module(name, filename):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'scripts' / filename)
    result = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(result)
    return result

PACKAGE = module('ios_package', 'check-ios-package.py')
SIGNING = module('ios_signing', 'with-ios-signing.py')
DEFAULTS = json.loads((ROOT / 'ios/Release.json').read_text())
BUNDLE = DEFAULTS['bundle_id']
TEAM = DEFAULTS['team_id']

class ReleaseChecks(unittest.TestCase):
    def dry_run(self, *arguments):
        env = {k: v for k, v in os.environ.items() if not k.startswith('CMUX_REMOTE_IOS_')}
        # GitHub passes an empty optional variable when no override is configured.
        env['CMUX_REMOTE_IOS_APP_STORE_APP_ID'] = ''
        return subprocess.run([str(ROOT / 'scripts/package-ios.sh'), '--dry-run', *arguments], cwd=ROOT,
                              env=env, capture_output=True, text=True)

    def test_release_defaults_and_overrides(self):
        result = self.dry_run('--build-number=23', '--version=0.2.1')
        self.assertEqual(result.returncode, 0, result.stderr)
        metadata = json.loads(result.stdout)
        self.assertEqual(metadata['app_store_app_id'], DEFAULTS['app_store_app_id'])
        self.assertEqual((metadata['bundle'], metadata['team'], metadata['version'], metadata['build']), (BUNDLE, TEAM, '0.2.1', '23'))

    def test_missing_or_invalid_metadata_never_packages(self):
        for args in [(), ('--build-number=0',), ('--build-number=1;echo bad',), ('--build-number=1', '--version=bad')]:
            self.assertNotEqual(self.dry_run(*args).returncode, 0)

    def test_unsigned_cannot_upload(self):
        self.assertNotEqual(self.dry_run('--build-number=1', '--unsigned', '--upload').returncode, 0)

    def payload(self, signed=True, bundle=BUNDLE, extra=None):
        stream = io.BytesIO()
        with zipfile.ZipFile(stream, 'w') as z:
            root = 'Payload/CmuxRemote.app/'
            z.writestr(root + 'Info.plist', plistlib.dumps({'CFBundleIdentifier': bundle, 'CFBundleShortVersionString': '0.1.0', 'CFBundleVersion': '23'}))
            if signed:
                z.writestr(root + 'embedded.mobileprovision', b'fixture')
                z.writestr(root + '_CodeSignature/CodeResources', b'fixture')
            if extra:
                z.writestr(extra, b'fixture')
        stream.seek(0)
        return zipfile.ZipFile(stream)

    def test_upload_rejects_wrong_app_unsigned_and_traversal(self):
        for options in [{'bundle': 'io.valuz'}, {'signed': False}, {'extra': '../outside'}]:
            with self.payload(**options) as z, self.assertRaises(ValueError):
                PACKAGE.inspect_payload(z, BUNDLE, '0.1.0', '23')
        with self.payload() as z:
            self.assertEqual(PACKAGE.inspect_payload(z, BUNDLE, '0.1.0', '23'), 'Payload/CmuxRemote.app/')
            with self.assertRaises(ValueError):
                PACKAGE.inspect_payload(z, BUNDLE, '0.1.0', '24')

    def test_profile_rejects_development_wrong_team_and_expiry(self):
        profile = {'TeamIdentifier': [TEAM], 'ApplicationIdentifierPrefix': [TEAM],
                   'Entitlements': {'com.apple.developer.team-identifier': TEAM, 'application-identifier': f'{TEAM}.{BUNDLE}', 'get-task-allow': False},
                   'ExpirationDate': datetime.now() + timedelta(days=1)}
        PACKAGE.inspect_profile(profile, BUNDLE, TEAM)
        for changed in [{'ProvisionedDevices': ['device']}, {'TeamIdentifier': ['OTHERTEAM00']},
                        {'ExpirationDate': datetime.now() - timedelta(days=1)}, {'ProvisionsAllDevices': True}]:
            with self.assertRaises(ValueError):
                PACKAGE.inspect_profile({**profile, **changed}, BUNDLE, TEAM)

    def test_signing_cleanup_on_packaging_failure(self):
        # Synthetic data only. No certificate/private key is included in this fixture.
        env = {'CMUX_REMOTE_IOS_API_KEY_ID': 'fixture', 'CMUX_REMOTE_IOS_API_ISSUER': 'fixture',
               'CMUX_REMOTE_IOS_CERT_PASSWORD': 'fixture', 'CMUX_REMOTE_IOS_API_KEY_B64': 'Zml4dHVyZQ==',
               'CMUX_REMOTE_IOS_CERT_P12_B64': 'Zml4dHVyZQ=='}
        calls = []
        paths = []
        def fake_security(*args):
            calls.append(args)
            return '"/original/login.keychain-db"' if len(args) == 3 else ''
        def fake_run(command, env):
            paths.extend([env['CMUX_REMOTE_IOS_API_KEY_PATH'], env['CMUX_REMOTE_IOS_KEYCHAIN_PATH']])
            self.assertTrue(Path(paths[0]).exists())
            self.assertEqual(Path(paths[0]).stat().st_mode & 0o777, 0o600)
            self.assertNotIn('CMUX_REMOTE_IOS_CERT_PASSWORD', env)
            self.assertNotIn('CMUX_REMOTE_IOS_API_KEY_B64', env)
            return subprocess.CompletedProcess(command, 9)
        with patch.dict(os.environ, env, clear=True), patch('sys.argv', ['signing', 'package']), \
             patch.object(SIGNING, 'security', fake_security), patch.object(SIGNING.subprocess, 'run', fake_run):
            self.assertEqual(SIGNING.main(), 9)
        self.assertEqual(calls[-2], ('list-keychains', '-d', 'user', '-s', '/original/login.keychain-db'))
        self.assertEqual(calls[-1][0], 'delete-keychain')
        self.assertTrue(all(not Path(path).exists() for path in paths))

    def test_rejected_signature_never_passes_upload_validation(self):
        profile = {'TeamIdentifier': [TEAM], 'ApplicationIdentifierPrefix': [TEAM],
                   'Entitlements': {'com.apple.developer.team-identifier': TEAM, 'application-identifier': f'{TEAM}.{BUNDLE}', 'get-task-allow': False},
                   'ExpirationDate': datetime.now() + timedelta(days=1)}
        def fake_run(command, capture_output):
            if command[0] == 'security':
                return subprocess.CompletedProcess(command, 0, plistlib.dumps(profile))
            return subprocess.CompletedProcess(command, 1 if command[0] == 'codesign' else 0)
        with tempfile.TemporaryDirectory() as directory:
            ipa = Path(directory) / 'fixture.ipa'
            with self.payload() as z:
                ipa.write_bytes(z.fp.getvalue())
            with patch.object(PACKAGE.subprocess, 'run', fake_run), self.assertRaisesRegex(ValueError, 'code signature'):
                PACKAGE.verify(ipa, BUNDLE, '0.1.0', '23', TEAM)

if __name__ == '__main__':
    unittest.main(verbosity=2)
