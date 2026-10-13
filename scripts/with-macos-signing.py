#!/usr/bin/env python3
"""Run Mac packaging with a temporary Developer ID keychain; never log secrets.

Inputs (environment):
  CMUX_REMOTE_MAC_CERT_P12_B64 or CMUX_REMOTE_MAC_CERT_P12_PATH  Developer ID Application P12
  CMUX_REMOTE_MAC_CERT_PASSWORD or CMUX_REMOTE_MAC_CERT_PASSWORD_PATH
  CMUX_REMOTE_NOTARY_KEY_B64 or CMUX_REMOTE_NOTARY_KEY_PATH       App Store Connect API key (.p8)
  CMUX_REMOTE_NOTARY_KEY_ID, CMUX_REMOTE_NOTARY_ISSUER

The wrapped command receives CMUX_REMOTE_MAC_SIGNING_IDENTITY (certificate SHA-1),
CMUX_REMOTE_MAC_KEYCHAIN and CMUX_REMOTE_NOTARY_KEY_PATH.
"""
import base64
import os
from pathlib import Path
import re
import secrets
import shlex
import subprocess
import sys
import tempfile

IDENTITY = re.compile(r'^\s*\d+\)\s+([0-9A-F]{40})\s+"Developer ID Application: .+"$', re.MULTILINE)


def security(*args):
    result = subprocess.run(['security', *args], capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError('Signing keychain operation failed (credential details suppressed)')
    return result.stdout


def material(env, name, path):
    """Write Base64 secret material to path, or return an existing local file."""
    local = env.get(name + '_PATH', '')
    if local:
        if not Path(local).expanduser().is_file():
            raise ValueError(f'{name}_PATH does not name a file')
        return Path(local).expanduser()
    value = env.get(name + '_B64', '')
    if not value:
        raise ValueError(f'{name}_B64 or {name}_PATH is required')
    try:
        data = base64.b64decode(''.join(value.split()), validate=True)
    except ValueError:
        raise ValueError(f'{name}_B64 must contain valid Base64') from None
    if not data:
        raise ValueError(f'{name}_B64 is empty')
    path.write_bytes(data)
    path.chmod(0o600)
    return path


def password(env):
    if env.get('CMUX_REMOTE_MAC_CERT_PASSWORD'):
        return env['CMUX_REMOTE_MAC_CERT_PASSWORD']
    local = env.get('CMUX_REMOTE_MAC_CERT_PASSWORD_PATH', '')
    if local and Path(local).expanduser().is_file():
        return Path(local).expanduser().read_text().strip()
    raise ValueError('CMUX_REMOTE_MAC_CERT_PASSWORD or CMUX_REMOTE_MAC_CERT_PASSWORD_PATH is required')


def main():
    if len(sys.argv) < 2:
        raise ValueError('Usage: with-macos-signing.py <packaging command> [arguments]')
    env = os.environ.copy()
    for name in ['CMUX_REMOTE_NOTARY_KEY_ID', 'CMUX_REMOTE_NOTARY_ISSUER']:
        if not env.get(name):
            raise ValueError(f'{name} is required')
    with tempfile.TemporaryDirectory(prefix='cmux-remote-mac-signing-') as directory:
        root = Path(directory)
        cert = material(env, 'CMUX_REMOTE_MAC_CERT_P12', root / 'developer-id.p12')
        key = material(env, 'CMUX_REMOTE_NOTARY_KEY', root / 'AuthKey.p8')
        cert_password = password(env)
        keychain = root / 'release.keychain-db'
        previous = shlex.split(security('list-keychains', '-d', 'user'))
        keychain_password = secrets.token_urlsafe(32)
        created = False
        try:
            security('create-keychain', '-p', keychain_password, str(keychain))
            created = True
            security('set-keychain-settings', '-lut', '21600', str(keychain))
            security('unlock-keychain', '-p', keychain_password, str(keychain))
            security('import', str(cert), '-k', str(keychain), '-P', cert_password,
                     '-T', '/usr/bin/codesign', '-T', '/usr/bin/security')
            security('set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:', '-s', '-k', keychain_password, str(keychain))
            security('list-keychains', '-d', 'user', '-s', str(keychain), *previous)
            # Only the temporary keychain is searched, so an older certificate with the same
            # common name elsewhere cannot be chosen; sign by SHA-1, never by name.
            identities = IDENTITY.findall(security('find-identity', '-v', '-p', 'codesigning', str(keychain)))
            if len(identities) != 1:
                raise RuntimeError(f'Expected one valid Developer ID Application identity, found {len(identities)}')
            env['CMUX_REMOTE_MAC_SIGNING_IDENTITY'] = identities[0]
            env['CMUX_REMOTE_MAC_KEYCHAIN'] = str(keychain)
            env['CMUX_REMOTE_NOTARY_KEY_PATH'] = str(key)
            for name in ['CMUX_REMOTE_MAC_CERT_P12_B64', 'CMUX_REMOTE_MAC_CERT_PASSWORD', 'CMUX_REMOTE_NOTARY_KEY_B64']:
                env.pop(name, None)
            return subprocess.run(sys.argv[1:], env=env).returncode
        finally:
            if created:
                try:
                    security('list-keychains', '-d', 'user', '-s', *previous)
                finally:
                    security('delete-keychain', str(keychain))


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, RuntimeError) as error:
        print(str(error), file=sys.stderr)
        sys.exit(1)
