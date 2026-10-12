#!/usr/bin/env python3
"""Run packaging with temporary CI signing material; never log secrets."""
import base64
import os
from pathlib import Path
import secrets
import shlex
import subprocess
import sys
import tempfile


def security(*args):
    result = subprocess.run(['security', *args], capture_output=True, text=True)
    if result.returncode:
        raise RuntimeError('Signing keychain operation failed (credential details suppressed)')
    return result.stdout


def decode_file(env, name, path):
    value = env.get(name, '')
    if not value:
        raise ValueError(f'{name} is required')
    try:
        data = base64.b64decode(''.join(value.split()), validate=True)
    except ValueError:
        raise ValueError(f'{name} must contain valid Base64') from None
    if not data:
        raise ValueError(f'{name} is empty')
    path.write_bytes(data)
    path.chmod(0o600)


def main():
    if len(sys.argv) < 2:
        raise ValueError('Usage: with-ios-signing.py <packaging command> [arguments]')
    env = os.environ.copy()
    for name in ['CMUX_REMOTE_IOS_API_KEY_ID', 'CMUX_REMOTE_IOS_API_ISSUER', 'CMUX_REMOTE_IOS_CERT_PASSWORD']:
        if not env.get(name):
            raise ValueError(f'{name} is required')
    with tempfile.TemporaryDirectory(prefix='cmux-remote-signing-') as directory:
        root = Path(directory)
        key, cert, keychain = root / 'AuthKey.p8', root / 'distribution.p12', root / 'release.keychain-db'
        decode_file(env, 'CMUX_REMOTE_IOS_API_KEY_B64', key)
        decode_file(env, 'CMUX_REMOTE_IOS_CERT_P12_B64', cert)
        previous = shlex.split(security('list-keychains', '-d', 'user'))
        password = secrets.token_urlsafe(32)
        created = False
        try:
            security('create-keychain', '-p', password, str(keychain))
            created = True
            security('set-keychain-settings', '-lut', '21600', str(keychain))
            security('unlock-keychain', '-p', password, str(keychain))
            security('import', str(cert), '-k', str(keychain), '-P', env['CMUX_REMOTE_IOS_CERT_PASSWORD'],
                     '-T', '/usr/bin/codesign', '-T', '/usr/bin/security')
            security('set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:', '-s', '-k', password, str(keychain))
            security('list-keychains', '-d', 'user', '-s', str(keychain), *previous)
            env['CMUX_REMOTE_IOS_API_KEY_PATH'] = str(key)
            env['CMUX_REMOTE_IOS_KEYCHAIN_PATH'] = str(keychain)
            for name in ['CMUX_REMOTE_IOS_API_KEY_B64', 'CMUX_REMOTE_IOS_CERT_P12_B64', 'CMUX_REMOTE_IOS_CERT_PASSWORD']:
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
