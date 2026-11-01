#!/usr/bin/env python3
"""Compile the isolated enrollment fixture against the actual Bridge modules."""
from pathlib import Path
import json, shlex, subprocess

root = Path(__file__).resolve().parents[1]
info = json.loads(subprocess.check_output(['swift', '-print-target-info']))
build = root / '.build' / info['target']['unversionedTriple'] / 'debug'
args = ['swiftc', '-parse-as-library', '-swift-version', '6',
        '-I', str(build / 'Modules'),
        str(root / 'scripts/fixtures/EnrollmentFixture.swift')]
description = json.loads((build / 'description.json').read_text())
command = next(value for key, value in description['swiftCommands'].items() if 'CmuxRemoteBridge-' in key)
flags = command['otherArguments']
for index, flag in enumerate(flags[:-1]):
    if flag == '-Xcc':
        args += ['-Xcc', flags[index + 1]]
link = build / 'cmux-remote.product/Objects.LinkFileList'
args += [line for line in shlex.split(link.read_text())
         if '/CmuxRemoteCLI.build/' not in line and '/Modules/CmuxRemoteCLI.o' not in line]
result = subprocess.run(args + ['-o', str(root / '.build/enrollment-fixture')], cwd=root)
raise SystemExit(result.returncode)
