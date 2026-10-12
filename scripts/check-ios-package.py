#!/usr/bin/env python3
"""Validate the IPA identity, App Store profile and signature before upload."""
import argparse
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath
import plistlib
import subprocess
import tempfile
import zipfile


def inspect_payload(z, bundle_id, version, build_number):
    names = z.namelist()
    if len(names) != len(set(names)):
        raise ValueError('IPA contains duplicate payload entries')
    for name in names:
        if name.startswith('/') or '..' in PurePosixPath(name).parts:
            raise ValueError('IPA contains an unsafe path')
    candidates = [n for n in names if n.startswith('Payload/') and n.count('/') == 2 and n.endswith('.app/Info.plist')]
    if len(candidates) != 1:
        raise ValueError('IPA must contain exactly one application')
    path = candidates[0]
    root = path.removesuffix('Info.plist')
    metadata = plistlib.loads(z.read(path))
    for key, expected in [('CFBundleIdentifier', bundle_id), ('CFBundleShortVersionString', version), ('CFBundleVersion', build_number)]:
        if metadata.get(key) != expected:
            raise ValueError('IPA release identity/version differs from requested build')
    if root + 'embedded.mobileprovision' not in names or root + '_CodeSignature/CodeResources' not in names:
        raise ValueError('IPA lacks its distribution profile or code signature')
    return root


def inspect_profile(profile, bundle_id, team_id):
    entitlements = profile.get('Entitlements', {})
    prefixes = profile.get('ApplicationIdentifierPrefix', [])
    app_ids = [f'{prefix}.{bundle_id}' for prefix in prefixes]
    if team_id not in profile.get('TeamIdentifier', []) or entitlements.get('com.apple.developer.team-identifier') != team_id:
        raise ValueError('IPA provisioning team differs from release configuration')
    if entitlements.get('application-identifier') not in app_ids:
        raise ValueError('IPA provisioning profile does not authorize this app')
    if entitlements.get('get-task-allow') is not False or 'ProvisionedDevices' in profile or profile.get('ProvisionsAllDevices'):
        raise ValueError('IPA requires an App Store distribution profile')
    expiry = profile.get('ExpirationDate')
    if not isinstance(expiry, datetime) or expiry.replace(tzinfo=timezone.utc) <= datetime.now(timezone.utc):
        raise ValueError('IPA provisioning profile is expired')


def verify(ipa, bundle_id, version, build_number, team_id):
    with zipfile.ZipFile(ipa) as z, tempfile.TemporaryDirectory(prefix='cmux-remote-ipa-') as directory:
        root = inspect_payload(z, bundle_id, version, build_number)
        # ditto retains executable modes and framework symlinks from Apple's IPA.
        extracted = subprocess.run(['ditto', '-x', '-k', str(Path(ipa).resolve()), directory], capture_output=True)
        if extracted.returncode:
            raise ValueError('Cannot extract the IPA for signature verification')
        app = Path(directory) / root
        decoded = subprocess.run(['security', 'cms', '-D', '-i', str(app / 'embedded.mobileprovision')], capture_output=True)
        if decoded.returncode:
            raise ValueError('Cannot verify the IPA provisioning profile')
        inspect_profile(plistlib.loads(decoded.stdout), bundle_id, team_id)
        signature = subprocess.run(['codesign', '--verify', '--deep', '--strict', str(app)], capture_output=True)
        if signature.returncode:
            raise ValueError('IPA code signature verification failed')


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('ipa')
    p.add_argument('--bundle-id', required=True)
    p.add_argument('--version', required=True)
    p.add_argument('--build-number', required=True)
    p.add_argument('--team-id', required=True)
    a = p.parse_args()
    try:
        verify(a.ipa, a.bundle_id, a.version, a.build_number, a.team_id)
    except (ValueError, OSError, zipfile.BadZipFile) as error:
        raise SystemExit(str(error)) from None
    print('IPA identity, version, App Store profile and code signature verified')
